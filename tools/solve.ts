/**
 * 关卡检查：每层每种布局/配置的最优解 vs 贪心玩家，再检查所有选图组合能不能通关。
 * 用法：npm run solve            全部
 *       npm run solve -- 2       只看第 2 层
 *       npm run solve -- 2 -v    加上最优路线
 */
import { CHARACTERS, Hero, MONSTERS } from '../src/core/config';
import { parseFloor } from '../src/core/floor';
import { DEMO_POOLS, allChoices, buildFloor, buildFloors } from '../src/core/levels';
import { greedyFloor, solveFromStart, solveRun } from '../src/core/solver';

const ch = CHARACTERS.digger;
const onlyFloor = Number(process.argv[2]) || 0;
const verbose = process.argv.includes('-v');
const fmt = (h: Hero | null | undefined) => (h ? `${String(h.hp).padStart(4)} 血 ${h.atk}/${h.def} 钥${h.keys}` : '  走不到出口   ');

// 每层的"典型入场属性"：上一层所有配置最优解结果的中位数
let entries: Hero[] = [{ ...ch.base }];
for (let fi = 0; fi < DEMO_POOLS.length; fi++) {
    const pool = DEMO_POOLS[fi];
    const sorted = [...entries].sort((a, b) => a.hp - b.hp);
    const entry = sorted[Math.floor(sorted.length / 2)];
    const outs: Hero[] = [];
    if (!onlyFloor || onlyFloor === fi + 1) {
        console.log(`\n== ${pool.params.name}（典型入场 ${fmt(entry)}）==`);
    }
    pool.layouts.forEach((layout, li) => layout.variants.forEach((v, vi) => {
        const f = buildFloor(pool, { layout: li, variant: vi });
        const p = parseFloor(f);
        const t0 = Date.now();
        const r = solveFromStart(f, entry, ch);
        const ms = Date.now() - t0;
        const g = greedyFloor(f, entry, ch);
        const gc = greedyFloor(f, entry, ch, 'clear');
        if (r.best) outs.push(r.best.hero);
        if (onlyFloor && onlyFloor !== fi + 1) return;
        // 开局不用战斗就能拿到的奖励（应该尽量没有）
        const free: string[] = [];
        {
            const seen = new Set([p.start]);
            const st = [p.start];
            while (st.length) {
                const cur = st.pop()!;
                for (const n of [cur - p.w, cur + p.w, cur % p.w ? cur - 1 : -1, (cur + 1) % p.w ? cur + 1 : -1]) {
                    if (n < 0 || n >= p.cells.length || seen.has(n)) continue;
                    seen.add(n);
                    const c = p.cells[n];
                    if (c.kind === 'floor') st.push(n);
                    if (c.kind === 'item') { free.push(`${c.id}(${n % p.w},${Math.floor(n / p.w)})`); st.push(n); }
                }
            }
        }
        const ents = p.cells.filter(c => c.kind === 'monster' || c.kind === 'item' || c.kind === 'door').length;
        const gap = r.best && g ? r.best.hero.hp - g.hp : NaN;
        const gapC = r.best && gc ? r.best.hero.hp - gc.hp : NaN;
        const fought = r.best ? r.best.plan.map(i => p.cells[i]).filter(c => c.kind === 'monster').map(c => (c.kind === 'monster' ? MONSTERS[c.id].name : '')).join(' ') : '';
        console.log(`  ${layout.name}${vi + 1}  最优 ${fmt(r.best?.hero)}  赶路 ${fmt(g)} 差${String(gap).padStart(4)}  清图差${String(gapC).padStart(4)}  格子 ${ents}  状态 ${r.statesVisited} ${ms}ms  打：${fought}`);
        if (free.length) console.log(`      ⚠ 开局白拿：${free.join(' ')}`);
        if (verbose && r.best) {
            const names = r.best.plan.map(i => {
                const c = p.cells[i];
                const xy = `${i % p.w},${Math.floor(i / p.w)}`;
                if (c.kind === 'monster') return `${MONSTERS[c.id].name}(${xy})`;
                if (c.kind === 'door') return `${c.door === 'bone' ? '骨门' : '血门'}(${xy})`;
                return c.kind === 'item' ? `${c.id}(${xy})` : xy;
            });
            console.log(`      ${names.join(' → ')}`);
        }
    }));
    entries = outs;
}

if (!onlyFloor) {
    const combos = allChoices();
    const finals: number[] = [];
    let failed = 0;
    for (const c of combos) {
        const r = solveRun(buildFloors(c), ch);
        if (r.bestHp < 0) failed++;
        else finals.push(r.bestHp);
    }
    finals.sort((a, b) => a - b);
    console.log(`\n所有 ${combos.length} 种选图组合：${failed} 种无法通关；最优解通关剩余生命 最少 ${finals[0]} / 中位 ${finals[Math.floor(finals.length / 2)]} / 最多 ${finals[finals.length - 1]}`);
}
