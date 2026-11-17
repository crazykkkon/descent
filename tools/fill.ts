/**
 * 关卡内容搜索：设计者手画墙壁和"内容格"（?），工具在内容格里摆怪物和奖励，
 * 搜索满足目标的组合（能通关、剩余生命在目标范围、最优解明显好于乱打）。
 * 结果需要人再看一遍、写上设计意图后放进 levels.ts。
 *
 * 用法：npx tsx tools/fill.ts <配置名> [迭代次数] [种子]
 */
import { CHARACTERS, Hero } from '../src/core/config';
import { FloorDef, neighbors, parseFloor } from '../src/core/floor';
import { DEMO_POOLS, rng } from '../src/core/levels';
import { greedyFloor, solveFromStart } from '../src/core/solver';

interface Job {
    floor: number; // 1-based
    geometry: string[];
    monsters: string; // 可选怪物字符
    items: string; // 必须放下的道具/门（每个字符一个）
    entries: Hero[];
    /** 目标：出口剩余生命 = 入场生命 + delta（取中位数入场属性） */
    delta: number;
    avoidFights?: number[]; // 另一套配置的最优解打过的格子，尽量不同
}

const H = (hp: number, atk: number, def: number): Hero => ({ hp, atk, def, keys: 0, gold: 0 });

// 第 1 层各配置最优解出口属性的大致范围
const F1_OUT = [H(160, 13, 10), H(179, 10, 13), H(196, 13, 13), H(155, 10, 10), H(175, 13, 10)];
// 第 2 层出口的大致范围（按第 1、2 层所有组合的最优解结果挑的代表）
const F2_OUT = [{ ...H(157, 16, 16), keys: 1 }, H(90, 16, 13), H(135, 19, 13), H(150, 19, 13), H(157, 16, 16), H(157, 13, 16), H(195, 19, 16)];

const GEO: Record<string, string[]> = {
    fork: [
        '@..?.#?..?.',
        '.###.#.###.',
        '.#?.?....#>',
        '.#.###?#.#.',
        '...#?..#...',
        '##?#.###.#.',
        '?..?.....??',
    ],
    ring: [
        '@...?...?..',
        '.###.#.###.',
        '.#?..?..?#.',
        '.#.###.##..',
        '.#..?..?#.>',
        '.##.###.#?.',
        '..?.?...?.?',
    ],
    rooms: [
        '#?#.?.#?#.?',
        '#?#.#.#?#.#',
        '#.#.#.#.#.#',
        '@....?...?>',
        '#.#.#.#.#.#',
        '#?#.?.#?#?#',
        '#?#.#.#?#.#',
    ],
};

function parseArgs(): { job: Job; iters: number; seed: number; name: string } {
    const name = process.argv[2] ?? 'f2-fork';
    const iters = Number(process.argv[3] ?? 3000);
    const seed = Number(process.argv[4] ?? 1);
    const [f, g] = name.split('-');
    const floor = Number(f.slice(1));
    const job: Job = floor === 2
        ? { floor, geometry: GEO[g], monsters: 'meeffcv', items: 'rrbhkD', entries: F1_OUT, delta: -25 }
        : { floor, geometry: GEO[g], monsters: 'effcvvgx', items: 'rbbhhkDB', entries: F2_OUT, delta: -35 };
    return { job, iters, seed, name };
}

function slotsOf(geo: string[]): [number, number][] {
    const out: [number, number][] = [];
    geo.forEach((row, y) => [...row].forEach((ch, x) => { if (ch === '?') out.push([x, y]); }));
    return out;
}

function render(geo: string[], slots: [number, number][], fill: string[]): string[] {
    const rows = geo.map(r => [...r]);
    slots.forEach(([x, y], i) => { rows[y][x] = fill[i]; });
    return rows.map(r => r.join(''));
}

interface Eval { score: number; endMed: number; gapR: number; gapC: number; fights: number; ok: boolean; fought: number[] }

function evaluate(job: Job, map: string[]): Eval {
    const params = DEMO_POOLS[job.floor - 1].params;
    const f: FloorDef = { ...params, map };
    const ch = CHARACTERS.digger;
    const ends: number[] = [];
    let gapR = 0;
    let gapC = 0;
    let fights = 99;
    let fought: number[] = [];
    for (const e of job.entries) {
        const r = solveFromStart(f, e, ch);
        if (!r.best) return { score: -1e9, endMed: 0, gapR: 0, gapC: 0, fights: 0, ok: false, fought: [] };
        ends.push(r.best.hero.hp - e.hp);
        const g = greedyFloor(f, e, ch);
        const gc = greedyFloor(f, e, ch, 'clear');
        gapR += g ? r.best.hero.hp - g.hp : 120;
        gapC += gc ? r.best.hero.hp - gc.hp : 120;
        const p = r.best.plan.filter(i => {
            const [x, y] = [i % map[0].length, Math.floor(i / map[0].length)];
            return /[a-zA-Z]/.test(map[y][x]) && 'meffcvgxG'.includes(map[y][x]);
        });
        fights = Math.min(fights, p.length);
        if (e === job.entries[Math.floor(job.entries.length / 2)]) fought = p;
    }
    // 开局不打怪就能拿到的奖励（金币除外）要扣分：奖励应该放在怪物身后
    const p0 = parseFloor(f);
    let freeItems = 0;
    {
        const seen = new Set([p0.start]);
        const st = [p0.start];
        while (st.length) {
            const cur = st.pop()!;
            for (const n of neighbors(cur, p0.w, p0.h)) {
                if (seen.has(n)) continue;
                seen.add(n);
                const c = p0.cells[n];
                if (c.kind === 'floor') st.push(n);
                if (c.kind === 'item') { if (c.id !== 'gold') freeItems++; st.push(n); }
            }
        }
    }
    ends.sort((a, b) => a - b);
    const endMed = ends[Math.floor(ends.length / 2)];
    const n = job.entries.length;
    gapR /= n;
    gapC /= n;
    let score = Math.min(gapR, 60) + 0.5 * Math.min(gapC, 120) - 2 * Math.abs(endMed - job.delta) + 20 * Math.min(fights, 4) - (fights < 2 ? 60 : 0);
    if (ends[0] < job.delta - 60) score -= 3 * (job.delta - 60 - ends[0]);
    score -= 50 * freeItems;
    if (job.avoidFights) score -= 15 * fought.filter(c => job.avoidFights!.includes(c)).length;
    return { score, endMed, gapR, gapC, fights, ok: true, fought };
}

function search(job: Job, iters: number, seed: number) {
    const rand = rng(seed);
    const pick = <T>(arr: ArrayLike<T>) => arr[Math.floor(rand() * arr.length)];
    const slots = slotsOf(job.geometry);
    const randomFill = (): string[] => {
        const fill = slots.map(() => pick(job.monsters));
        const idx = slots.map((_, i) => i).sort(() => rand() - 0.5);
        [...job.items].forEach((it, k) => { fill[idx[k]] = it; });
        return fill;
    };
    const mutate = (fill: string[]): string[] => {
        const f = [...fill];
        if (rand() < 0.5) {
            const i = Math.floor(rand() * f.length);
            const j = Math.floor(rand() * f.length);
            [f[i], f[j]] = [f[j], f[i]];
        } else {
            const mon = f.map((c, i) => (job.monsters.includes(c) || c === '.' ? i : -1)).filter(i => i >= 0);
            if (mon.length) f[pick(mon)] = rand() < 0.15 ? '.' : pick(job.monsters);
        }
        return f;
    };
    let best = randomFill();
    let bestE = evaluate(job, render(job.geometry, slots, best));
    let cur = best;
    let curE = bestE;
    for (let it = 0; it < iters; it++) {
        const cand = it % 200 === 0 && it > 0 ? randomFill() : mutate(cur);
        const e = evaluate(job, render(job.geometry, slots, cand));
        const temp = 20 * (1 - it / iters) + 1;
        if (e.score > curE.score || rand() < Math.exp((e.score - curE.score) / temp)) { cur = cand; curE = e; }
        if (e.score > bestE.score) { best = cand; bestE = e; }
    }
    return { map: render(job.geometry, slots, best), e: bestE };
}

const { job, iters, seed, name } = parseArgs();
const avoidArg = process.argv[5];
if (avoidArg) job.avoidFights = avoidArg.split(',').map(Number);
const t0 = Date.now();
const r = search(job, iters, seed);
console.log(`${name} seed ${seed}  ${Date.now() - t0}ms  score ${r.e.score.toFixed(1)}  出口生命变化(中位) ${r.e.endMed}  赶路差 ${r.e.gapR.toFixed(0)}  清图差 ${r.e.gapC.toFixed(0)}  最少战斗 ${r.e.fights}`);
console.log(`  fought: ${r.e.fought.join(',')}`);
console.log(r.map.map(l => `'${l}',`).join('\n'));
