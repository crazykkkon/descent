/**
 * 20 层主线检查：每层的保守最优（不算补给摊、井中轮、武器）、和"赶路"玩家的对比。
 * 用法：npx tsx tools/mainline.ts [种子]
 */
import { buildMainline, pickMainline } from '../src/core/mainline';
import { greedyFloor, solveChain } from '../src/core/solver';
import { parseFloor } from '../src/core/floor';
import { CHARACTERS } from '../src/core/config';

const seed = Number(process.argv[2] ?? 1);
const floors = buildMainline(pickMainline(seed));
const chain = solveChain(floors);
console.log('层  名称                     结果数  最优：生命 攻 防 钥 金    赶路（从最优入场）   实体数');
let prev = null as null | import('../src/core/config').Hero;
chain.forEach((c, i) => {
    const f = floors[i];
    const ents = parseFloor(f).cells.filter(x => x.kind === 'monster' || x.kind === 'item' || x.kind === 'door').length;
    const rush = prev ? greedyFloor(f, prev, undefined, 'rush') : null;
    const b = c.best;
    console.log(`${String(i + 1).padStart(2)}  ${f.name.padEnd(16, '　')}  ${String(c.outcomes).padStart(3)}   ${b ? `${b.hp} ${b.atk} ${b.def} ${b.keys} ${b.gold}` : '走不通'}    ${rush ? `${rush.hp} ${rush.atk}/${rush.def}` : prev ? '赶路会卡住/死' : '-'}   ${ents}`);
    prev = b;
});
// 只看眼前的玩家：每层都走"这一层剩血最多"的路线，不为后面留攻防和金币
{
    let h: import('../src/core/config').Hero | null = { ...CHARACTERS.digger.base };
    let died = 0;
    for (let i = 0; i < floors.length && h; i++) {
        const one = solveChain([floors[i]], { ...CHARACTERS.digger, base: h });
        h = one[0]?.best ?? null;
        if (!h) died = i + 1;
    }
    console.log(`只看眼前（每层剩血最多）：${h ? `通关，剩 ${h.hp} 生命（攻 ${h.atk} 防 ${h.def}）` : `第 ${died} 层走不通`}`);
}
// 一路"赶路"的玩家：每层都只捡顺手的、打最便宜的，能出去就走；井租金币不够就用攻击抵
for (const mode of ['rush', 'clear'] as const) {
    let h: import('../src/core/config').Hero | null = { ...CHARACTERS.digger.base };
    let died = 0;
    for (let i = 0; i < floors.length && h; i++) {
        h = greedyFloor(floors[i], h, undefined, mode);
        if (!h) { died = i + 1; break; }
        const rent = floors[i].rent;
        if (rent) h = h.gold >= rent ? { ...h, gold: h.gold - rent } : { ...h, atk: h.atk - 3 };
    }
    console.log(`${mode === 'rush' ? '一路赶路' : '一路清图'}：${h ? `通关，剩 ${h.hp} 生命（攻 ${h.atk} 防 ${h.def}）` : `第 ${died} 层卡住或死亡`}`);
}
if (chain.length < floors.length || !chain[chain.length - 1].best) { console.log(`第 ${chain.length} 层走不通`); process.exit(1); }
