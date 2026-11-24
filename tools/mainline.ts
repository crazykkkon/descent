/**
 * 路线检查（断臂转轮版）：按种子生成一局的路线，沿几种选法连续求解。
 * 保守下限：不算断臂转轮的武器、大转盘、当铺、骨坛、补给摊、诏令（它们大多只会让结果更好）。
 * 用法：npx tsx tools/mainline.ts [种子个数，默认 20]
 */
import { buildRoute } from '../src/core/route';
import { solveChain } from '../src/core/solver';
import { FloorDef } from '../src/core/floor';

const seeds = Number(process.argv[2] ?? 20);
const ways: [string, (opts: FloorDef[], d: number) => number][] = [
    ['总走第一条', () => 0],
    ['总走第二条', opts => opts.length - 1],
    ['专挑打架层', opts => Math.max(0, opts.findIndex(f => f.kind === 'normal' || f.kind === 'elite'))],
    ['专挑设施层', opts => Math.max(0, opts.findIndex(f => f.kind !== 'normal' && f.kind !== 'elite'))],
];
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
        const chain = solveChain(floors, undefined, 40, exits);
        const last = chain[chain.length - 1];
        const ok = chain.length === floors.length && last.best;
        if (!ok) fails++;
        worst[name] = Math.min(worst[name] ?? Infinity, ok ? last.best!.hp : -chain.length);
        row.push(ok ? `${name} ${last.best!.hp}` : `${name} 卡在第 ${chain.length} 层`);
    }
    console.log(`种子 ${String(seed).padStart(3)}：${row.join('　')}`);
}
console.log('最差：', Object.entries(worst).map(([k, v]) => `${k} ${v < 0 ? `卡在第 ${-v} 层` : v}`).join('　'));
if (fails) { console.log(`有 ${fails} 条路线走不通`); process.exit(1); }
