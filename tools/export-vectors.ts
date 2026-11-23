/**
 * 从 TypeScript 原型导出"标准算例"：同一组输入在原型里算出的结果。
 * LÖVE + Lua 版用这些算例逐条对账，保证移植后战损、扣血、押金、退还、毁约完全一致。
 *
 * 用法：npx tsx tools/export-vectors.ts   → 写出 love/tests/vectors.lua
 */
import { writeFileSync, mkdirSync } from 'node:fs';
import { CHARACTERS, Hero, MONSTERS, MonsterId, WEAPONS, WeaponId } from '../src/core/config';
import { simulateCombat } from '../src/core/combat';
import { FloorDef } from '../src/core/floor';
import { Run } from '../src/core/game';
import { DEMO_POOLS, buildFloor } from '../src/core/levels';
import { keepVersion } from '../src/core/contract';
import { solveFromStart } from '../src/core/solver';

// ---------- 把 JS 值写成 Lua 表 ----------
function lua(v: unknown, indent = ''): string {
    const next = indent + '  ';
    if (v === null || v === undefined) return 'nil';
    if (typeof v === 'number' || typeof v === 'boolean') return String(v);
    if (typeof v === 'string') return JSON.stringify(v); // JSON 字符串转义在 Lua 里也成立（不含 \u 时）
    if (Array.isArray(v)) {
        if (!v.length) return '{}';
        const simple = v.every(x => typeof x !== 'object' || x === null);
        if (simple) return `{ ${v.map(x => lua(x)).join(', ')} }`;
        return `{\n${v.map(x => next + lua(x, next)).join(',\n')}\n${indent}}`;
    }
    const entries = Object.entries(v as Record<string, unknown>).filter(([, x]) => x !== undefined);
    if (!entries.length) return '{}';
    return `{\n${entries.map(([k, x]) => `${next}${/^[A-Za-z_]\w*$/.test(k) ? k : `[${JSON.stringify(k)}]`} = ${lua(x, next)}`).join(',\n')}\n${indent}}`;
}

// ---------- 1. 战斗算例 ----------
const STATS: [number, number][] = [[10, 10], [13, 10], [10, 13], [13, 13], [16, 13], [16, 16], [19, 16], [19, 19], [22, 19], [22, 22], [25, 22]];
const weapons: (WeaponId | null)[] = [null, ...(Object.keys(WEAPONS) as WeaponId[])];
const combat: unknown[] = [];
for (const id of Object.keys(MONSTERS) as MonsterId[]) {
    for (const [atk, def] of STATS) {
        for (const w of weapons) {
            const r = simulateCombat({ atk, def, weapon: w ?? undefined }, MONSTERS[id]);
            combat.push({ monster: id, atk, def, weapon: w ?? undefined, canAttack: r.canAttack, canWin: r.canWin, damage: r.damage, hits: r.hits });
        }
    }
}

// ---------- 2. 楼层逐步算例 ----------
type Step = { cell: number; ok: boolean; hp: number; atk: number; def: number; keys: number; gold: number; pos: number; status: string; contractActive: boolean };

function floorParams(f: FloorDef) {
    return { name: f.name, map: f.map, bloodCost: f.bloodCost, gem: f.gem, smallPotion: f.smallPotion, bigPotion: f.bigPotion, gold: f.gold, rent: f.rent };
}

function scenario(name: string, f: FloorDef, entry: Hero, mode: 'refuse' | 'keep' | 'break' | 'any') {
    const c = f.contract;
    const sign = mode === 'keep' || mode === 'break';
    // 第 0 层只是一个"入口 → 出口"的空层，用来在它的楼梯口签约
    const run = new Run([{ ...f, contract: undefined, intel: undefined, rent: undefined, map: ['@>'] }, f]);
    run.hero = { ...entry };
    run.move(1, 0);
    run.finishFloor(false, sign);
    const start = { ...run.hero };
    // 求解器给出这条路线，再一步一步走
    const signedHero = { ...run.hero };
    const plan = (mode === 'keep' && c ? solveFromStart(keepVersion(f), signedHero) : solveFromStart(f, signedHero)).best;
    if (!plan) return null;
    if (run.floorIndex !== 1) throw new Error(`${name}：没能进入要测的楼层`);
    const targets = [...plan.plan, run.cells.findIndex(x => x.kind === 'exit')];
    const steps: Step[] = [];
    for (const t of targets) {
        const path = run.findPath(t);
        if (!path) break;
        for (const cell of path) {
            const r = run.step(cell);
            steps.push({ cell, ok: r.ok, hp: run.hero.hp, atk: run.hero.atk, def: run.hero.def, keys: run.hero.keys, gold: run.hero.gold, pos: run.pos, status: run.status, contractActive: run.contractActive() });
            if (!r.ok) break;
        }
    }
    if (mode === 'break' && !steps.some(s => !s.contractActive)) return null; // 这条路线没有喝药，算不上毁约
    const summary = run.exitSummary();
    // 有井租先交：金币够就交金币，不够就用攻击抵
    const rentMethod = run.rentDue() ? (run.hero.gold >= run.rentDue() ? 'gold' : 'atk') : undefined;
    if (rentMethod) run.payRent(rentMethod);
    run.finishFloor(false);
    return {
        name, mode, floor: floorParams(f), contract: c, sign, entry, start, steps, rentMethod,
        exit: { kept: summary.contract?.kept, leftoverPotions: summary.leftoverPotions, potionGold: summary.potionGold },
        final: { hp: run.hero.hp, atk: run.hero.atk, def: run.hero.def, keys: run.hero.keys, gold: run.hero.gold, status: run.status },
    };
}

const scenarios: unknown[] = [];
const entries: Hero[] = [
    { hp: 150, atk: 13, def: 13, keys: 0, gold: 0 },
    { hp: 200, atk: 10, def: 13, keys: 0, gold: 5 },
    { hp: 175, atk: 13, def: 10, keys: 1, gold: 12 },
];
DEMO_POOLS[1].layouts.forEach((l, li) => {
    const f = buildFloor(DEMO_POOLS[1], { layout: li, variant: 0 });
    entries.forEach((e, ei) => {
        for (const mode of ['refuse', 'keep', 'break'] as const) {
            const sc = scenario(`${l.name}·入场${ei + 1}·${mode}`, f, e, mode);
            if (sc) scenarios.push(sc);
        }
    });
});
// 第 1 层（宝石、骨钥、骨门、血门）和第 3 层的若干张图，不签约，验证基本规则
for (const fi of [0, 2]) {
    DEMO_POOLS[fi].layouts.forEach((l, li) => l.variants.forEach((_, vi) => {
        const f = buildFloor(DEMO_POOLS[fi], { layout: li, variant: vi });
        const e = fi === 0 ? { ...CHARACTERS.digger.base } : { hp: 170, atk: 16, def: 16, keys: 1, gold: 20 };
        const sc = scenario(`第${fi + 1}层·${l.name}${vi + 1}`, f, e, 'any');
        if (sc) scenarios.push(sc);
    }));
}

// ---------- 3. 硬打致死 ----------
const deaths = (['frog', 'beetle', 'wraith'] as MonsterId[]).map(id => {
    const f: FloorDef = { name: 't', map: ['@' + Object.entries({ frog: 'f', beetle: 'c', wraith: 'g' }).find(([k]) => k === id)![1] + '>'], bloodCost: 40, gem: 2, smallPotion: 50, bigPotion: 150, gold: 20 };
    const run = new Run([f]);
    run.hero.hp = 30;
    const r = run.step(1);
    return { monster: id, map: f.map, hp: 30, ok: r.ok, status: run.status, heroHp: run.hero.hp };
});

const out = `-- 由 tools/export-vectors.ts 自动生成，不要手改。
-- 来源：TypeScript 原型（src/core）。LÖVE + Lua 版必须逐条算出同样的结果。
return ${lua({ character: CHARACTERS.digger, combat, scenarios, deaths })}
`;
mkdirSync('love/tests', { recursive: true });
writeFileSync('love/tests/vectors.lua', out);
console.log(`战斗算例 ${combat.length} 条；楼层算例 ${scenarios.length} 条（共 ${scenarios.reduce((n: number, s) => n + (s as { steps: unknown[] }).steps.length, 0)} 步）；致死算例 ${deaths.length} 条`);
