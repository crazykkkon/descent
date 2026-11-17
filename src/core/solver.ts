/**
 * 求解器：找出走到出口时剩余生命最多的打法。
 *
 * 关键观察：在一层里，"已经处理掉哪些格子"决定了攻击、防御、钥匙和能走到的区域，
 * 只有生命会因为处理顺序不同而不同。所以状态 = 已处理格子的集合（位掩码），
 * 每个状态只保留生命最高的那条路线。主角在已打通区域里可以随便走（M1 不计步数）。
 */
import { CharacterDef, CHARACTERS, Hero } from './config';
import { Cell, FloorDef, neighbors, parseFloor } from './floor';
import { interact, isElite, isEntity } from './rules';

export interface FloorState {
    w: number;
    h: number;
    cells: Cell[];
    pos: number;
}

export interface ExitOption {
    hero: Hero;
    /** 按顺序处理的格子 */
    plan: number[];
}

export interface SolveResult {
    /** 能否走到出口 */
    solvable: boolean;
    /** 剩余生命最多的打法 */
    best?: ExitOption;
    /** 所有"不被其他结果完全压制"的出口结果（用于多层连续求解） */
    pareto: ExitOption[];
    statesVisited: number;
}

const MAX_ENTITIES = 30;

interface Node { hp: number; parent: number; via: number }

export function solveFloor(state: FloorState, hero: Hero, floor: FloorDef, ch: CharacterDef): SolveResult {
    const { w, h, cells, pos } = state;
    const entities: number[] = [];
    cells.forEach((c, i) => { if (isEntity(c)) entities.push(i); });
    if (entities.length > MAX_ENTITIES) throw new Error(`可交互格子太多（${entities.length}），求解器上限 ${MAX_ENTITIES}`);
    const bit = new Map<number, number>();
    entities.forEach((cell, k) => bit.set(cell, k));
    const exit = cells.findIndex(c => c.kind === 'exit');
    const eliteMask = entities.reduce((m, cell, k) => (isElite(cells[cell]) ? m | (1 << k) : m), 0);

    // 已处理集合下的属性（生命除外）
    const statsOf = (mask: number): Hero => {
        let hh: Hero = { ...hero };
        for (let k = 0; k < entities.length; k++) {
            if (!(mask & (1 << k))) continue;
            const c = cells[entities[k]];
            if (c.kind === 'monster') continue;
            if (c.kind === 'door' && c.door === 'blood') continue;
            const r = interact(c, { ...hh, hp: Number.MAX_SAFE_INTEGER }, floor, ch);
            if (r.ok) hh = { ...r.hero, hp: hh.hp };
        }
        return hh;
    };

    // 从起点出发，经过空地和已处理格子能到的区域；返回区域边上的未处理格子，以及出口是否相邻
    const frontier = (mask: number): { next: number[]; atExit: boolean } => {
        const seen = new Uint8Array(cells.length);
        const stack = [pos];
        seen[pos] = 1;
        const next: number[] = [];
        let atExit = false;
        while (stack.length) {
            const cur = stack.pop()!;
            for (const n of neighbors(cur, w, h)) {
                if (seen[n]) continue;
                seen[n] = 1;
                const c = cells[n];
                if (c.kind === 'wall') continue;
                if (c.kind === 'exit') { atExit = true; continue; }
                if (c.kind === 'floor') { stack.push(n); continue; }
                const k = bit.get(n)!;
                if (mask & (1 << k)) stack.push(n);
                else next.push(k);
            }
        }
        return { next, atExit };
    };

    const nodes = new Map<number, Node>();
    nodes.set(0, { hp: hero.hp, parent: -1, via: -1 });
    let layer = [0];
    const exits: { mask: number; hero: Hero }[] = [];

    while (layer.length) {
        const nextLayer = new Map<number, true>();
        for (const mask of layer) {
            const node = nodes.get(mask)!;
            const stats = { ...statsOf(mask), hp: node.hp };
            const { next, atExit } = frontier(mask);
            if (atExit && (mask & eliteMask) === eliteMask) exits.push({ mask, hero: stats });
            for (const k of next) {
                const r = interact(cells[entities[k]], stats, floor, ch);
                if (!r.ok) continue;
                const nm = mask | (1 << k);
                const old = nodes.get(nm);
                if (!old || old.hp < r.hero.hp) nodes.set(nm, { hp: r.hero.hp, parent: mask, via: entities[k] });
                nextLayer.set(nm, true);
            }
        }
        layer = [...nextLayer.keys()];
    }

    const planOf = (mask: number): number[] => {
        const plan: number[] = [];
        let m = mask;
        while (m !== 0) { const n = nodes.get(m)!; plan.unshift(n.via); m = n.parent; }
        return plan;
    };

    const pareto = paretoFilter(exits.map(e => e.hero)).map(hh => {
        const e = exits.find(x => x.hero === hh)!;
        return { hero: hh, plan: planOf(e.mask) };
    });
    const best = pareto.length ? pareto.reduce((a, b) => (b.hero.hp > a.hero.hp ? b : a)) : undefined;
    return { solvable: exits.length > 0, best, pareto, statesVisited: nodes.size };
}

/** 去掉被完全压制的结果（生命、攻击、防御、钥匙都不比别人高） */
export function paretoFilter(list: Hero[]): Hero[] {
    const dominated = (a: Hero, b: Hero) =>
        b.hp >= a.hp && b.atk >= a.atk && b.def >= a.def && b.keys >= a.keys &&
        (b.hp > a.hp || b.atk > a.atk || b.def > a.def || b.keys > a.keys);
    const uniq: Hero[] = [];
    for (const x of list) {
        if (!uniq.some(u => u.hp === x.hp && u.atk === x.atk && u.def === x.def && u.keys === x.keys)) uniq.push(x);
    }
    return uniq.filter(a => !uniq.some(b => dominated(a, b)));
}

export function solveFromStart(floor: FloorDef, hero: Hero, ch: CharacterDef = CHARACTERS.digger): SolveResult {
    const p = parseFloor(floor);
    return solveFloor({ w: p.w, h: p.h, cells: p.cells, pos: p.start }, hero, floor, ch);
}

/** 连续多层求解：每层把所有不被压制的结果带到下一层，返回最后一层的最高剩余生命 */
export function solveRun(floors: FloorDef[], ch: CharacterDef = CHARACTERS.digger): { bestHp: number; perFloor: number[] } {
    let heroes: Hero[] = [{ ...ch.base }];
    const perFloor: number[] = [];
    for (const f of floors) {
        const outs: Hero[] = [];
        for (const hh of heroes) outs.push(...solveFromStart(f, hh, ch).pareto.map(o => o.hero));
        heroes = paretoFilter(outs);
        if (!heroes.length) { perFloor.push(-1); return { bestHp: -1, perFloor }; }
        perFloor.push(Math.max(...heroes.map(x => x.hp)));
    }
    return { bestHp: perFloor[perFloor.length - 1], perFloor };
}

/**
 * 一个"不怎么算"的玩家：先捡所有道具和开门，然后每次打掉血最少的怪，
 * 直到能走到出口就离开。用来和最优解比较，差距越大说明这层越有解谜空间。
 */
export function greedyFloor(floor: FloorDef, hero: Hero, ch: CharacterDef = CHARACTERS.digger): Hero | null {
    const p = parseFloor(floor);
    const cells = p.cells.map(c => ({ ...c })) as Cell[];
    let hh = { ...hero };
    for (;;) {
        const reach = reachable(cells, p.w, p.h, p.start);
        const free = reach.next.filter(i => {
            const c = cells[i];
            return c.kind === 'item' || (c.kind === 'door' && c.door === 'bone' && hh.keys > 0);
        });
        if (free.length) {
            const r = interact(cells[free[0]], hh, floor, ch);
            if (r.ok) { hh = r.hero; cells[free[0]] = { kind: 'floor' }; continue; }
        }
        const eliteAlive = cells.some(isElite);
        if (reach.atExit && !eliteAlive) return hh;
        let bestI = -1;
        let bestHero: Hero | null = null;
        for (const i of reach.next) {
            const r = interact(cells[i], hh, floor, ch);
            if (r.ok && (!bestHero || r.hero.hp > bestHero.hp)) { bestI = i; bestHero = r.hero; }
        }
        if (!bestHero) return null;
        hh = bestHero;
        cells[bestI] = { kind: 'floor' };
    }
}

function reachable(cells: Cell[], w: number, h: number, pos: number): { next: number[]; atExit: boolean } {
    const seen = new Uint8Array(cells.length);
    const stack = [pos];
    seen[pos] = 1;
    const next: number[] = [];
    let atExit = false;
    while (stack.length) {
        const cur = stack.pop()!;
        for (const n of neighbors(cur, w, h)) {
            if (seen[n]) continue;
            seen[n] = 1;
            const c = cells[n];
            if (c.kind === 'wall') continue;
            if (c.kind === 'exit') atExit = true;
            else if (c.kind === 'floor') stack.push(n);
            else next.push(n);
        }
    }
    return { next, atExit };
}
