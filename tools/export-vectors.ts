/**
 * 从 TypeScript 原型导出"标准算例"：同一组输入在原型里算出的结果。
 * LÖVE + Lua 版用这些算例逐条对账，保证移植后战损、扣血、押金、退还、毁约完全一致。
 *
 * 用法：npx tsx tools/export-vectors.ts   → 写出 love/tests/vectors.lua
 */
import { writeFileSync, mkdirSync } from 'node:fs';
import { CHARACTERS, Hero, MONSTERS, MonsterId, WEAPONS, WeaponId } from '../src/core/config';
import { simulateCombat } from '../src/core/combat';
import { FloorDef, parseFloor } from '../src/core/floor';
const parseFloorCells = (f: FloorDef) => parseFloor(f).cells;
import { Run } from '../src/core/game';
import { DEMO_POOLS, buildFloor } from '../src/core/levels';
import { keepVersion } from '../src/core/contract';
import { solveFromStart } from '../src/core/solver';
import { SLOTS, SlotId, newSlotState, roll } from '../src/core/slot';
import { choosePick, stairIntel } from '../src/core/intel';
import { MAINLINE, buildMainline, pickMainline } from '../src/core/mainline';
import { solveChain } from '../src/core/solver';
import { pickChoices, FloorChoice } from '../src/core/levels';

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
const STATS: [number, number][] = [[10, 10], [13, 10], [10, 13], [13, 13], [16, 13], [16, 16], [19, 16], [19, 19], [22, 19], [22, 22], [25, 22], [30, 25], [36, 28], [44, 34]];
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
    return { name: f.name, map: f.map, bloodCost: f.bloodCost, gem: f.gem, smallPotion: f.smallPotion, bigPotion: f.bigPotion, gold: f.gold, rent: f.rent, eliteReward: f.eliteReward };
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

// 新怪（群居、腐蚀、庇护、守门人）：伤害要按周围还活着的怪算
const AURA_MAPS: string[][] = [
    ['@.www..', '.#####.', '...u..>'],
    ['@..p...', '.#.K.#.', '.#.p.#>'],
    ['@.wpw..', '.#.w.#.', 'u...pK>'],
    ['@ppp...', '..w#...', '.www..>'],
];
const auraEntries: Hero[] = [{ hp: 1500, atk: 40, def: 30, keys: 0, gold: 0 }, { hp: 2500, atk: 33, def: 26, keys: 0, gold: 0, weapon: 'hammer' }];
const monsterViews: unknown[] = [];
AURA_MAPS.forEach((map, mi) => {
    const f: FloorDef = { name: `新怪${mi + 1}`, map, bloodCost: 40, gem: 2, smallPotion: 50, bigPotion: 150, gold: 20 };
    auraEntries.forEach((e, ei) => {
        const sc = scenario(`新怪${mi + 1}·入场${ei + 1}`, f, e, 'any');
        if (!sc) throw new Error(`新怪${mi + 1}·入场${ei + 1}：走不通`);
        scenarios.push(sc);
    });
    const run = new Run([f]);
    run.cells.forEach((c, i) => {
        if (c.kind === 'monster') { const m = run.monsterAt(i); monsterViews.push({ map, cell: i, atk: m.atk, def: m.def }); }
    });
});

// ---------- 3. 硬打致死 ----------
const deaths = (['frog', 'beetle', 'wraith'] as MonsterId[]).map(id => {
    const f: FloorDef = { name: 't', map: ['@' + Object.entries({ frog: 'f', beetle: 'c', wraith: 'g' }).find(([k]) => k === id)![1] + '>'], bloodCost: 40, gem: 2, smallPotion: 50, bigPotion: 150, gold: 20 };
    const run = new Run([f]);
    run.hero.hp = 30;
    const r = run.step(1);
    return { monster: id, map: f.map, hp: 30, ok: r.ok, status: run.status, heroHp: run.hero.hp };
});

// ---------- 4. 井中轮 ----------
// 4a. 纯转轮：同一个种子、同一台机器，连续转 40 次的图案（验证随机数完全一致）
const rolls: unknown[] = [];
for (const seed of [1, 7, 12345, 2147483647, 987654321]) {
    for (const key of [0, 1003, 4021]) {
        for (const id of ['risky', 'steady'] as SlotId[]) {
            const st = newSlotState();
            const seq: string[] = [];
            for (let k = 0; k < 40; k++) seq.push(roll(SLOTS[id], st, seed, key).result.join(','));
            rolls.push({ seed, key, machine: id, seq });
        }
    }
}
// 4b. 完整操作：转、锁轴重转、收下、血注，每一步之后的属性和机器状态
type SlotAct = { kind: 'spin'; pay: 'gold' | 'blood'; held?: boolean[] } | { kind: 'collect' };
const slotSessions: unknown[] = [];
const sessionScripts: SlotAct[][] = [
    [{ kind: 'spin', pay: 'gold' }, { kind: 'collect' }, { kind: 'spin', pay: 'gold' }, { kind: 'spin', pay: 'gold', held: [true, false, false] }, { kind: 'collect' }, { kind: 'spin', pay: 'blood' }, { kind: 'collect' }],
    [{ kind: 'spin', pay: 'blood' }, { kind: 'spin', pay: 'gold', held: [true, true, false] }, { kind: 'spin', pay: 'gold', held: [false, true, true] }, { kind: 'collect' }, { kind: 'spin', pay: 'gold' }, { kind: 'spin', pay: 'gold' }, { kind: 'collect' }],
];
for (const seed of [3, 11, 2024, 99991]) {
    for (const [mi, map] of [['S', ['@.>', '.S.']], ['T', ['@.>', '.T.']]] as const) {
        sessionScripts.forEach((script, si) => {
            const f: FloorDef = { name: 't', map: [...map], bloodCost: 40, gem: 2, smallPotion: 50, bigPotion: 150, gold: 20 };
            const run = new Run([f], 'digger', seed);
            run.move(0, 1);
            run.hero = { hp: 400, atk: 13, def: 13, keys: 0, gold: 300 };
            const steps: unknown[] = [];
            for (const a of script) {
                if (a.kind === 'spin') {
                    const r = run.slotSpin(4, a.pay, a.held);
                    steps.push({ act: 'spin', pay: a.pay, held: a.held, ok: r.ok, result: r.result?.join(','), bite: r.bite, hero: { ...run.hero }, spins: run.slotState(4).spins, status: run.status });
                } else {
                    const lines = run.slotCollect(4);
                    steps.push({ act: 'collect', lines, hero: { ...run.hero }, status: run.status });
                }
            }
            slotSessions.push({ seed, machine: mi, script: si, map, steps });
        });
    }
}

// ---------- 5. 精英倒下后三选一的武器 ----------
const weaponChoices: unknown[] = [];
for (const seed of [1, 5, 77, 31337, 2147483647]) {
    for (const floors of [1, 4, 10]) {
        for (const current of [undefined, 'boneKnife', 'hammer'] as (WeaponId | undefined)[]) {
            const fs: FloorDef[] = [];
            for (let k = 0; k < floors; k++) fs.push({ name: 't', map: ['@>'], bloodCost: 40, gem: 2, smallPotion: 50, bigPotion: 150, gold: 20 });
            fs[floors - 1] = { ...fs[floors - 1], map: ['@G>'], eliteReward: true };
            const run = new Run(fs, 'digger', seed);
            for (let k = 0; k < floors - 1; k++) { run.move(1, 0); run.finishFloor(false); }
            run.hero = { hp: 999, atk: 60, def: 60, keys: 0, gold: 0, weapon: current };
            run.move(1, 0);
            weaponChoices.push({ seed, floorIndex: floors, current, choices: run.pendingWeapons });
        }
    }
}

// ---------- 6. 楼梯口情报（情报怪事先选好，写进关卡数据） ----------
const intels: unknown[] = [];
const intelHeroes: Hero[] = [{ hp: 150, atk: 13, def: 13, keys: 0, gold: 0 }, { hp: 120, atk: 19, def: 16, keys: 0, gold: 0 }, { hp: 200, atk: 10, def: 10, keys: 0, gold: 0, weapon: 'hammer' }];
for (const fi of [1, 2, 4]) {
    DEMO_POOLS[fi].layouts.forEach((l, li) => l.variants.forEach((_, vi) => {
        const base = buildFloor(DEMO_POOLS[fi], { layout: li, variant: vi });
        const next: FloorDef = { ...base, intel: undefined, intelPick: choosePick(base, intelHeroes[0], CHARACTERS.digger) };
        const cur = buildFloor(DEMO_POOLS[0], { layout: 0, variant: 0 });
        const curCells = parseFloorCells(cur);
        for (const h of intelHeroes) {
            const it = stairIntel(next, h, CHARACTERS.digger, { floor: cur, cells: curCells })!;
            intels.push({ floor: floorParams(next), intelPick: next.intelPick, current: floorParams(cur), hero: h, headline: it.headline, lines: it.lines, mustFight: it.mustFight });
        }
    }));
}

// ---------- 7. 补给摊 ----------
const stallFloor: FloorDef = { name: 't', map: ['@.M>'], bloodCost: 40, gem: 2, smallPotion: 50, bigPotion: 150, gold: 20, stall: [{ id: 'atk', amount: 2, price: 40 }, { id: 'hp', amount: 80, price: 25 }, { id: 'key', amount: 1, price: 30 }] };
const stalls: unknown[] = [];
for (const [gold, buys] of [[100, [0, 0, 1, 2]], [50, [2, 1, 0]], [200, [1, 2, 0, 1]]] as [number, number[]][]) {
    const run = new Run([stallFloor]);
    run.hero.gold = gold;
    const pre = run.stallBuy(2, 0).ok; // 还没走到旁边
    run.move(1, 0);
    const steps = buys.map(k => { const r = run.stallBuy(2, k); return { k, ok: r.ok, msg: r.msg, hero: { ...run.hero } }; });
    stalls.push({ floor: floorParams(stallFloor), stall: stallFloor.stall, gold, pre, steps });
}

// ---------- 8. 主线：选图 + 每层按求解器路线走一遍 ----------
const picks: unknown[] = [];
let prevChoice: FloorChoice[] | undefined;
for (const seed of [1, 2, 3, 99, 12345, 4000000000]) {
    const c = pickMainline(seed, prevChoice);
    picks.push({ seed, avoid: prevChoice, choices: c });
    prevChoice = c;
}
const mainScenarios: unknown[] = [];
{
    const floors = buildMainline(pickMainline(1));
    const chain = solveChain(floors);
    floors.forEach((f, i) => {
        if (i === 0) return; // 第 1 层已经在上面的楼层算例里
        const entry = chain[i - 1].best!;
        const sc = scenario(`主线第${i + 1}层`, f, entry, f.contract ? 'keep' : 'any');
        if (!sc) throw new Error(`主线第 ${i + 1} 层走不通`);
        mainScenarios.push({ ...sc, floorIndex: i + 1, stall: f.stall, eliteReward: f.eliteReward });
    });
}

// ---------- 主线关卡数据（Lua 版直接读这一份，不另外手写） ----------
{
    const ref = solveChain(buildMainline(pickMainline(1)));
    const pools = MAINLINE.map((pool, fi) => ({
        params: pool.params,
        layouts: pool.layouts.map(l => ({
            name: l.name,
            variants: l.variants.map(v => {
                const f = { ...buildFloor(pool, { layout: 0, variant: 0 }), map: v.map, contract: v.contract, intel: v.intel };
                // 楼梯口情报说哪只怪：用"按求解器最优走到上一层出口"的属性选（Lua 版没有求解器）
                const hero = fi === 0 ? CHARACTERS.digger.base : ref[fi - 1].best!;
                const pick = v.intel || !parseFloor(f).cells.some(c => c.kind === 'monster') ? undefined : choosePick(f, hero, CHARACTERS.digger);
                return { map: v.map, contract: v.contract, intel: v.intel, intelPick: pick && { cell: pick.cell + 1, mustFight: pick.mustFight } };
            }),
        })),
    }));
    writeFileSync('love/src/data/mainline.lua', `-- 由 tools/export-vectors.ts 从 src/core/mainline.ts 自动生成，不要手改。
-- 20 层主线白盒：每层的参数、布局和配置。intelPick 的格子下标已经换成 Lua 的 1 开始。
-- 层位、地图、数值、井租、补给摊价格都是讨论项（见 src/core/mainline.ts 开头的说明）。
return ${lua({ pools })}
`);
}

const out = `-- 由 tools/export-vectors.ts 自动生成，不要手改。
-- 来源：TypeScript 原型（src/core）。LÖVE + Lua 版必须逐条算出同样的结果。
return ${lua({ character: CHARACTERS.digger, combat, scenarios, monsterViews, stalls, picks, mainScenarios, deaths, rolls, slotSessions, weaponChoices, intels })}
`;
mkdirSync('love/tests', { recursive: true });
writeFileSync('love/tests/vectors.lua', out);
console.log(`战斗 ${combat.length}；新怪属性 ${monsterViews.length}；补给摊 ${stalls.length}；主线选图 ${picks.length}；主线楼层 ${mainScenarios.length}；楼层 ${scenarios.length} 条（${scenarios.reduce((n: number, s) => n + (s as { steps: unknown[] }).steps.length, 0)} 步）；致死 ${deaths.length}；转轮 ${rolls.length} 组；井中轮操作 ${slotSessions.length} 组；武器三选一 ${weaponChoices.length}；情报 ${intels.length}`);
