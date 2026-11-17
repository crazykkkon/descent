/**
 * 关卡检查：对每一层算出最优解和"不怎么算的玩家"的结果，用来调关卡和数值。
 * 用法：npm run solve
 */
import { CHARACTERS, Hero, MONSTERS } from '../src/core/config';
import { parseFloor } from '../src/core/floor';
import { M1_FLOORS } from '../src/core/levels';
import { greedyFloor, solveFromStart, solveRun } from '../src/core/solver';

const ch = CHARACTERS.digger;
const fmt = (h: Hero | null | undefined) => (h ? `生命 ${h.hp}  攻 ${h.atk}  防 ${h.def}  钥 ${h.keys}` : '走不到出口');

let hero: Hero = { ...ch.base };
let greedy: Hero | null = { ...ch.base };
for (const f of M1_FLOORS) {
    const t0 = Date.now();
    const r = solveFromStart(f, hero, ch);
    const ms = Date.now() - t0;
    const p = parseFloor(f);
    console.log(`\n== ${f.name} ==`);
    console.log(`  入场        ${fmt(hero)}`);
    console.log(`  最优解      ${fmt(r.best?.hero)}   （${r.statesVisited} 个状态，${ms} ms）`);
    if (r.best) {
        const names = r.best.plan.map(i => {
            const c = p.cells[i];
            const xy = `${i % p.w},${Math.floor(i / p.w)}`;
            if (c.kind === 'monster') return `${MONSTERS[c.id].name}(${xy})`;
            if (c.kind === 'door') return `${c.door === 'bone' ? '骨门' : '血门'}(${xy})`;
            return `${c.kind === 'item' ? c.id : c.kind}(${xy})`;
        });
        console.log(`  路线        ${names.join(' → ')}`);
    }
    const g: Hero | null = greedy ? greedyFloor(f, greedy, ch) : null;
    console.log(`  贪心玩家    ${fmt(greedyFloor(f, hero, ch))}   （和最优解同样属性入场）`);
    console.log(`  贪心连续玩  ${fmt(g)}   （从第 1 层一直贪心）`);
    console.log(`  不被压制的出口结果 ${r.pareto.length} 种`);
    greedy = g;
    if (!r.best) break;
    hero = r.best.hero;
}

const run = solveRun(M1_FLOORS, ch);
console.log(`\n连续 3 层的全局最优（考虑带属性进下一层）：每层结束最高生命 ${run.perFloor.join(' / ')}`);
