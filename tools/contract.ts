/**
 * 契约验算：对每张带契约的图，列出"拒签 / 签约守约 / 签约毁约"三条路的结果。
 * 价格是手调的，这个工具只负责把账算清楚，帮设计者判断三种选择是不是都有道理。
 *
 * 用法：npx tsx tools/contract.ts
 */
import { CHARACTERS, Hero } from '../src/core/config';
import { ContractDef, contractText, keepVersion } from '../src/core/contract';
import { FloorDef, parseFloor } from '../src/core/floor';
import { DEMO_POOLS, buildFloor } from '../src/core/levels';
import { solveFromStart } from '../src/core/solver';

const ch = CHARACTERS.digger;
const H = (hp: number, atk: number, def: number): Hero => ({ hp, atk, def, keys: 0, gold: 0 });
// 第 1 层出口的典型状态：拿全宝石的、只拿赤晶的、不拿宝石只保血的
const ENTRIES = [H(150, 13, 13), H(175, 13, 10), H(200, 10, 13), H(235, 10, 10), H(120, 13, 13)];

const f3Floors: FloorDef[] = [];
DEMO_POOLS[2].layouts.forEach((l, li) => l.variants.forEach((_, vi) => f3Floors.push(buildFloor(DEMO_POOLS[2], { layout: li, variant: vi }))));

/** 带着这个状态进第 3 层：能活着通过的图有几张，平均出口生命 */
function f3(h: Hero): string {
    const res = f3Floors.map(f => solveFromStart(f, h, ch).best?.hero.hp ?? -1);
    const ok = res.filter(x => x > 0);
    const avg = ok.length ? Math.round(ok.reduce((a, b) => a + b, 0) / ok.length) : 0;
    return `第3层 ${ok.length}/${res.length} 张能过，平均剩 ${avg}`;
}

const fmt = (h?: Hero) => (h ? `${String(h.hp).padStart(3)} 血 攻${h.atk}/防${h.def} 钥${h.keys}` : '  —— 过不去 ——  ');

function drinks(f: FloorDef, plan: number[]): boolean {
    const p = parseFloor(f);
    return plan.some(i => { const c = p.cells[i]; return c.kind === 'item' && (c.id === 'smallPotion' || c.id === 'bigPotion'); });
}

const pool = DEMO_POOLS[1];
pool.layouts.forEach((l, li) => l.variants.forEach((v, vi) => {
    const f = buildFloor(pool, { layout: li, variant: vi });
    const c: ContractDef | undefined = f.contract;
    if (!c) return;
    const t = contractText(c);
    console.log(`\n== ${l.name}${l.variants.length > 1 ? vi + 1 : ''}：${t.pay}，${t.get}；${t.cond}，${t.reward}`);
    console.log(`   情报："${f.intel ?? '（自动）'}"   设计意图：${v.note}`);
    for (const e of ENTRIES) {
        const refuse = solveFromStart(f, e, ch).best;
        const signed: Hero = { ...e, hp: e.hp - c.deposit, atk: e.atk + c.atk, def: e.def + c.def };
        const keepR = signed.hp > 0 ? solveFromStart(keepVersion(f), signed, ch).best : undefined;
        const keep = keepR ? { ...keepR.hero, hp: keepR.hero.hp + c.refund, gold: keepR.hero.gold + c.gold } : undefined;
        const anyR = signed.hp > 0 ? solveFromStart(f, signed, ch).best : undefined;
        const brk = anyR && drinks(f, anyR.plan) ? anyR.hero : undefined;
        const best = [['拒签', refuse?.hero], ['守约', keep], ['毁约', brk]]
            .filter(([, h]) => h).sort((a, b) => (b[1] as Hero).hp - (a[1] as Hero).hp)[0]?.[0];
        console.log(`  入场 ${fmt(e)} | 拒签 ${fmt(refuse?.hero)} | 守约 ${fmt(keep)} | 毁约 ${fmt(brk)} | 本层血最多：${best}`);
        console.log(`  ${''.padStart(30)} | ${refuse ? f3(refuse.hero) : ''.padEnd(22)} | ${keep ? f3(keep) : ''.padEnd(22)} | ${brk ? f3(brk) : ''}`);
    }
}));
