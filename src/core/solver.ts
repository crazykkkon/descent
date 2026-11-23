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
import { keepVersion } from './contract';

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
    /** 拿到本层所有道具（宝石、血瓶、钥匙、金币）后再走出口、剩余生命最多的打法；做不到时为空 */
    bestAll?: ExitOption;
    /** 所有"不被其他结果完全压制"的出口结果（用于多层连续求解） */
    pareto: ExitOption[];
    statesVisited: number;
}

const MAX_ENTITIES = 30;

interface Node { hp: number; parent: number; via: number[] }

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
        // 先算道具，再扣骨门用掉的钥匙，和处理顺序无关
        let hh: Hero = { ...hero, hp: Number.MAX_SAFE_INTEGER };
        let doors = 0;
        for (let k = 0; k < entities.length; k++) {
            if (!(mask & (1 << k))) continue;
            const c = cells[entities[k]];
            if (c.kind === 'item') { const r = interact(c, hh, floor, ch); if (r.ok) hh = r.hero; }
            else if (c.kind === 'door' && c.door === 'bone') doors++;
        }
        return { ...hh, hp: hero.hp, keys: hh.keys - doors };
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
                if (c.kind === 'wall' || c.kind === 'slot') continue;
                if (c.kind === 'exit') { atExit = true; continue; }
                if (c.kind === 'floor') { stack.push(n); continue; }
                const k = bit.get(n)!;
                if (mask & (1 << k)) stack.push(n);
                else next.push(k);
            }
        }
        return { next, atExit };
    };

    // 捡道具永远不亏（只加不减），所以能走到的道具立刻全部捡掉，大幅减少状态数
    const close = (mask: number, stats: Hero): { mask: number; stats: Hero; picked: number[] } => {
        const picked: number[] = [];
        for (;;) {
            const items = frontier(mask).next.filter(k => cells[entities[k]].kind === 'item');
            if (!items.length) return { mask, stats, picked };
            for (const k of items) {
                const r = interact(cells[entities[k]], stats, floor, ch);
                if (r.ok) stats = r.hero;
                mask |= 1 << k;
                picked.push(entities[k]);
            }
        }
    };

    const nodes = new Map<number, Node>();
    const start = close(0, { ...hero });
    nodes.set(start.mask, { hp: start.stats.hp, parent: -1, via: start.picked });
    // 已处理集合只会变大，所以按"已处理格子数"从少到多处理，保证一个状态被处理时它的所有来路都已经算过
    const buckets: Set<number>[] = Array.from({ length: entities.length + 1 }, () => new Set<number>());
    buckets[popcount(start.mask)].add(start.mask);
    const exits: { mask: number; hero: Hero }[] = [];

    for (let p = 0; p <= entities.length; p++) {
        for (const mask of buckets[p]) {
            const node = nodes.get(mask)!;
            const stats = { ...statsOf(mask), hp: node.hp };
            const { next, atExit } = frontier(mask);
            if (atExit && (mask & eliteMask) === eliteMask) exits.push({ mask, hero: stats });
            for (const k of next) {
                const r = interact(cells[entities[k]], stats, floor, ch);
                if (!r.ok) continue;
                const c = close(mask | (1 << k), r.hero);
                const old = nodes.get(c.mask);
                if (!old || old.hp < c.stats.hp) nodes.set(c.mask, { hp: c.stats.hp, parent: mask, via: [entities[k], ...c.picked] });
                buckets[popcount(c.mask)].add(c.mask);
            }
        }
    }

    const planOf = (mask: number): number[] => {
        const plan: number[] = [];
        let m = mask;
        for (;;) { const n = nodes.get(m)!; plan.unshift(...n.via); if (n.parent < 0) break; m = n.parent; }
        return plan;
    };

    const pareto = paretoFilter(exits.map(e => e.hero)).map(hh => {
        const e = exits.find(x => x.hero === hh)!;
        return { hero: hh, plan: planOf(e.mask) };
    });
    const best = pareto.length ? pareto.reduce((a, b) => (b.hero.hp > a.hero.hp ? b : a)) : undefined;
    const itemMask = entities.reduce((m, cell, k) => (cells[cell].kind === 'item' ? m | (1 << k) : m), 0);
    const all = exits.filter(e => (e.mask & itemMask) === itemMask);
    const allBest = all.length ? all.reduce((a, b) => (b.hero.hp > a.hero.hp ? b : a)) : undefined;
    const bestAll = allBest ? { hero: allBest.hero, plan: planOf(allBest.mask) } : undefined;
    return { solvable: exits.length > 0, best, bestAll, pareto, statesVisited: nodes.size };
}

/** 去掉被完全压制的结果（生命、攻击、防御、钥匙都不比别人高） */
export function paretoFilter(list: Hero[]): Hero[] {
    // 武器不同的结果互不压制（没法简单比较哪把更好）
    const dominated = (a: Hero, b: Hero) => a.weapon === b.weapon &&
        b.hp >= a.hp && b.atk >= a.atk && b.def >= a.def && b.keys >= a.keys &&
        (b.hp > a.hp || b.atk > a.atk || b.def > a.def || b.keys > a.keys);
    const uniq: Hero[] = [];
    for (const x of list) {
        if (!uniq.some(u => u.hp === x.hp && u.atk === x.atk && u.def === x.def && u.keys === x.keys && u.weapon === x.weapon)) uniq.push(x);
    }
    return uniq.filter(a => !uniq.some(b => dominated(a, b)));
}

export function solveFromStart(floor: FloorDef, hero: Hero, ch: CharacterDef = CHARACTERS.digger): SolveResult {
    const p = parseFloor(floor);
    return solveFloor({ w: p.w, h: p.h, cells: p.cells, pos: p.start }, hero, floor, ch);
}

/** 连续多层求解：每层把所有不被压制的结果带到下一层（有契约的层把签约 / 不签都算上），返回最后一层的最高剩余生命 */
export function solveRun(floors: FloorDef[], ch: CharacterDef = CHARACTERS.digger): { bestHp: number; perFloor: number[] } {
    let heroes: Hero[] = [{ ...ch.base }];
    const perFloor: number[] = [];
    for (const f of floors) {
        const outs: Hero[] = [];
        for (const hh of heroes) {
            outs.push(...solveFromStart(f, hh, ch).pareto.map(o => o.hero));
            // 这一层有契约：再算"签约后守约"和"签约后毁约（或不碰血瓶但没守到）"两条分支
            const c = f.contract;
            if (c && hh.hp > c.deposit) {
                const signed = { ...hh, hp: hh.hp - c.deposit, atk: hh.atk + c.atk, def: hh.def + c.def };
                outs.push(...solveFromStart(f, signed, ch).pareto.map(o => o.hero));
                outs.push(...solveFromStart(keepVersion(f), signed, ch).pareto.map(o => ({ ...o.hero, hp: o.hero.hp + c.refund, gold: o.hero.gold + c.gold })));
            }
        }
        heroes = paretoFilter(outs);
        if (!heroes.length) { perFloor.push(-1); return { bestHp: -1, perFloor }; }
        perFloor.push(Math.max(...heroes.map(x => x.hp)));
    }
    return { bestHp: perFloor[perFloor.length - 1], perFloor };
}

/**
 * 两种"不怎么算"的玩家，用来和最优解比较，差距越大说明这层越有解谜空间：
 * - rush（赶路）：捡所有能捡的，每次打掉血最少的怪，能走到出口就离开
 * - clear（清图）：同样每次打最便宜的，但要把打得过的怪全打完才走
 */
export function greedyFloor(floor: FloorDef, hero: Hero, ch: CharacterDef = CHARACTERS.digger, mode: 'rush' | 'clear' = 'rush'): Hero | null {
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
        const canLeave = reach.atExit && !eliteAlive;
        if (canLeave && mode === 'rush') return hh;
        let bestI = -1;
        let bestHero: Hero | null = null;
        for (const i of reach.next) {
            if (mode === 'clear' && canLeave && cells[i].kind !== 'monster') continue;
            const r = interact(cells[i], hh, floor, ch);
            if (r.ok && (!bestHero || r.hero.hp > bestHero.hp)) { bestI = i; bestHero = r.hero; }
        }
        if (!bestHero) return canLeave ? hh : null;
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
            if (c.kind === 'wall' || c.kind === 'slot') continue;
            if (c.kind === 'exit') atExit = true;
            else if (c.kind === 'floor') stack.push(n);
            else next.push(n);
        }
    }
    return { next, atExit };
}

function popcount(n: number): number {
    let c = 0;
    while (n) { n &= n - 1; c++; }
    return c;
}
