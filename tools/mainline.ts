/**
 * 路线检查（断臂转轮版）：按种子生成一局的路线，沿几种选法连续求解。
 * 保守下限：不算断臂转轮的武器、大转盘、当铺、骨坛、补给摊、诏令（它们大多只会让结果更好）。
 * 用法：npx tsx tools/mainline.ts [种子个数，默认 20] [quick = 只算前两种选法] [perks = 碎片强化买满]
 * 制作人定：第一次玩大约 10% 通关、强化买满大约一半，所以不加强化时有路线走不通是正常的；这里报告能走通的比例。
 */
import { buildRoute } from '../src/core/route';
import { solveChain } from '../src/core/solver';
import { FloorDef } from '../src/core/floor';
import { CHARACTERS } from '../src/core/config';
import { PERKS, perkValue } from '../src/core/meta';

const seeds = Number(process.argv[2] ?? 20);
const ALL_WAYS: [string, (opts: FloorDef[], d: number) => number][] = [
    ['总走第一条', () => 0],
    ['总走第二条', opts => opts.length - 1],
    ['专挑打架层', opts => Math.max(0, opts.findIndex(f => f.kind === 'normal' || f.kind === 'elite'))],
    ['专挑设施层', opts => Math.max(0, opts.findIndex(f => f.kind !== 'normal' && f.kind !== 'elite'))],
];
// 第二个参数 quick：只算前两种选法（调数值时用，快一半）
const ways = process.argv[3] === 'quick' ? ALL_WAYS.slice(0, 2) : ALL_WAYS;
const top = (id: string) => perkValue(id, PERKS.find(p => p.id === id)!.costs.length);
const b = CHARACTERS.digger.base;
const ch = process.argv.includes('perks')
    ? { ...CHARACTERS.digger, base: { hp: b.hp + top('hp'), atk: b.atk + top('atk'), def: b.def + top('def'), keys: b.keys + top('keys'), gold: b.gold + top('gold') } }
    : CHARACTERS.digger;
const finals: number[] = [];
let fails = 0;
const worst: Record<string, number> = {};
for (let seed = 1; seed <= seeds; seed++) {
    const plan = buildRoute(seed);
    const row: string[] = [];
    for (const [name, way] of ways) {
        const picks = plan.map((opts, d) => way(opts, d));
        const floors = plan.map((opts, d) => opts[picks[d]]);
        // 第 d 层走哪个出口，决定第 d+1 层是哪个候选
        const exits = plan.map((_, d) => (plan[d + 1]?.length === 2 ? picks[d + 1] : 0));
        const chain = solveChain(floors, ch, 40, exits);
        const last = chain[chain.length - 1];
        const ok = chain.length === floors.length && last.best;
        if (!ok) fails++;
        worst[name] = Math.min(worst[name] ?? Infinity, ok ? last.best!.hp : -chain.length);
        if (ok) finals.push(last.best!.hp);
        row.push(ok ? `${name} ${last.best!.hp}` : `${name} 卡在第 ${chain.length} 层`);
    }
    console.log(`种子 ${String(seed).padStart(3)}：${row.join('　')}`);
}
console.log('最差：', Object.entries(worst).map(([k, v]) => `${k} ${v < 0 ? `卡在第 ${-v} 层` : v}`).join('　'));
finals.sort((a, b) => a - b);
if (finals.length) console.log(`通关时剩余生命：最少 ${finals[0]}，四分之一 ${finals[finals.length >> 2]}，中位 ${finals[finals.length >> 1]}，最多 ${finals[finals.length - 1]}`);
const total = seeds * ways.length;
console.log(`${process.argv.includes('perks') ? '碎片强化买满' : '不加强化'}：保守求解（每层算最优打法，不算武器、转盘、当铺、骨坛）${total} 条路线走通 ${total - fails} 条（${Math.round(((total - fails) / total) * 100)}%）`);
