/**
 * 从 TypeScript 原型导出"标准算例"：同一组输入在原型里算出的结果。
 * LÖVE + Lua 版用这些算例逐条对账，保证移植后战损、断臂转轮、大转盘、当铺、骨坛、诏令、路线、存档完全一致。
 *
 * 同时导出 Lua 版的地图池（love/src/data/pools.lua）：路线生成在 Lua 里按同样的算法跑，地图数据只在原型里写一份。
 *
 * 用法：npx tsx tools/export-vectors.ts
 */
import { writeFileSync, mkdirSync } from 'node:fs';
import { Boon, CHARACTERS, Hero, MONSTERS, MonsterId, WEAPONS, WeaponId } from '../src/core/config';
import { simulateCombat } from '../src/core/combat';
import { FloorDef } from '../src/core/floor';
import { Run } from '../src/core/game';
import { DEMO_POOLS, F2_CONTRACT, buildFloor } from '../src/core/levels';
import { solveChain, solveFromStart } from '../src/core/solver';
import { decreeFor } from '../src/core/decree';
import { ArmSym, EngraveSym, armOutcomeCounts, newArm } from '../src/core/arm';
import { whisper } from '../src/core/whisper';
import * as R from '../src/core/route';
import * as Meta from '../src/core/meta';

// ---------- 把 JS 值写成 Lua 表 ----------
const LUA_KEYWORDS = new Set(['and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for', 'function', 'goto', 'if', 'in', 'local', 'nil', 'not', 'or', 'repeat', 'return', 'then', 'true', 'until', 'while']);
function lua(v: unknown, indent = ''): string {
    const next = indent + '  ';
    if (v === null || v === undefined) return 'nil';
    if (typeof v === 'number' || typeof v === 'boolean') return String(v);
    if (typeof v === 'string') return JSON.stringify(v); // JSON 字符串转义在 Lua 里也成立（不含 \u 时）
    if (Array.isArray(v)) {
        if (!v.length) return '{}';
        const simple = v.every(x => typeof x !== 'object' || x === null);
        // 数组里有 null 时用显式下标，避免 Lua 表出洞
        if (v.some(x => x === null || x === undefined)) return `{ ${v.map((x, i) => `[${i + 1}] = ${lua(x, next)}`).join(', ')}, n = ${v.length} }`;
        if (simple) return `{ ${v.map(x => lua(x)).join(', ')} }`;
        return `{\n${v.map(x => next + lua(x, next)).join(',\n')}\n${indent}}`;
    }
    const entries = Object.entries(v as Record<string, unknown>).filter(([, x]) => x !== undefined);
    if (!entries.length) return '{}';
    return `{\n${entries.map(([k, x]) => `${next}${/^[A-Za-z_]\w*$/.test(k) && !LUA_KEYWORDS.has(k) ? k : `[${JSON.stringify(k)}]`} = ${lua(x, next)}`).join(',\n')}\n${indent}}`;
}
const tiny = (map: string[], extra: Partial<FloorDef> = {}): FloorDef => ({ name: 't', map, bloodCost: 40, gem: 2, smallPotion: 50, bigPotion: 150, gold: 20, ...extra });
const heroOf = (h: Hero) => ({ hp: h.hp, atk: h.atk, def: h.def, keys: h.keys, gold: h.gold, weapon: h.weapon, boons: h.boons });

// ---------- 1. 战斗算例（含骨坛移来的特性） ----------
const STATS: [number, number][] = [[10, 10], [13, 10], [13, 13], [16, 13], [16, 16], [19, 16], [22, 19], [25, 22], [30, 25], [36, 28], [44, 34]];
const weapons: (WeaponId | null)[] = [null, ...(Object.keys(WEAPONS) as WeaponId[])];
const boonSets: Boon[][] = [[], ['lifesteal'], ['firstStrike'], ['thorns'], ['corrode'], ['lifesteal', 'corrode', 'thorns', 'firstStrike']];
const combat: unknown[] = [];
for (const id of Object.keys(MONSTERS) as MonsterId[]) {
    for (const [atk, def] of STATS) {
        for (const w of weapons) {
            for (const b of (w === null || w === 'harpoon' ? boonSets : [[]])) {
                const boons = b.length ? b : undefined;
                const r = simulateCombat({ atk, def, weapon: w ?? undefined, boons }, MONSTERS[id]);
                combat.push({ monster: id, atk, def, weapon: w ?? undefined, boons, canAttack: r.canAttack, canWin: r.canWin, damage: r.damage, hits: r.hits });
            }
        }
    }
}

// ---------- 2. 楼层逐步算例：按求解器路线一步步走，每一步之后的状态 ----------
function floorParams(f: FloorDef) {
    return {
        name: f.name, map: f.map, bloodCost: f.bloodCost, gem: f.gem, smallPotion: f.smallPotion, bigPotion: f.bigPotion, gold: f.gold,
        rent: f.rent, power: f.power, eliteReward: f.eliteReward, kind: f.kind, marks: f.marks, shop: f.shop, stall: f.stall, hint: f.hint,
    };
}

function scenario(name: string, f: FloorDef, entry: Hero, exit = 0) {
    const run = new Run([f]);
    run.hero = { ...entry };
    const plan = solveFromStart(f, { ...entry }, undefined, exit).best;
    if (!plan) return null;
    const targets = [...plan.plan, run.cells.findIndex(x => x.kind === 'exit' && x.to === exit)];
    const steps: unknown[] = [];
    for (const t of targets) {
        const path = run.findPath(t);
        if (!path) break;
        for (const cell of path) {
            const r = run.step(cell);
            steps.push({ cell, ok: r.ok, hero: heroOf(run.hero), pos: run.pos, status: run.status, queue: run.engraveQueue.length });
            run.engraveQueue = [];
            if (!r.ok) break;
        }
    }
    const s = run.exitSummary();
    const exitTaken = run.exitTaken;
    const rentMethod = run.rentDue() ? (run.hero.gold >= run.rentDue() ? 'gold' : 'atk') : undefined;
    if (rentMethod) run.payRent(rentMethod);
    run.finishFloor(false);
    return { name, floor: floorParams(f), entry, steps, rentMethod, exit: { leftoverPotions: s.leftoverPotions, potionGold: s.potionGold }, final: { ...heroOf(run.hero), status: run.status }, exitTaken };
}

const scenarios: unknown[] = [];
for (const fi of [0, 1, 2]) {
    DEMO_POOLS[fi].layouts.forEach((l, li) => l.variants.forEach((_, vi) => {
        const f = { ...buildFloor(DEMO_POOLS[fi], { layout: li, variant: vi }), rent: undefined };
        const e = fi === 0 ? { ...CHARACTERS.digger.base } : { hp: 170, atk: 16, def: 16, keys: 1, gold: 20 };
        const sc = scenario(`第${fi + 1}层·${l.name}${vi + 1}`, f, e);
        if (sc) scenarios.push(sc);
    }));
}
// 新怪（群居、腐蚀、庇护、守门人）
const AURA_MAPS: string[][] = [
    ['@.www..', '.#####.', '...u..>'],
    ['@..p...', '.#.K.#.', '.#.p.#>'],
    ['@.wpw..', '.#.w.#.', 'u...pK>'],
    ['@ppp...', '..w#...', '.www..>'],
];
const monsterViews: unknown[] = [];
AURA_MAPS.forEach((map, mi) => {
    const f = tiny(map, { name: `新怪${mi + 1}` });
    for (const e of [{ hp: 1500, atk: 40, def: 30, keys: 0, gold: 0 }, { hp: 2500, atk: 33, def: 26, keys: 0, gold: 0, weapon: 'hammer' as WeaponId, boons: ['corrode', 'thorns'] as Boon[] }]) {
        const sc = scenario(`新怪${mi + 1}`, f, e);
        if (!sc) throw new Error(`新怪${mi + 1} 走不通`);
        scenarios.push(sc);
    }
    const run = new Run([f]);
    run.cells.forEach((c, i) => { if (c.kind === 'monster') { const m = run.monsterAt(i); monsterViews.push({ map, cell: i, atk: m.atk, def: m.def }); } });
});
// 路线里的每一层（种子 1，按两种选法连续求解时的入场状态）
const routeWalks: unknown[] = [];
{
    const plan = R.buildRoute(1);
    for (const k of [0, 1]) {
        const picks = plan.map(o => Math.min(k, o.length - 1));
        const floors = plan.map((o, d) => o[picks[d]]);
        // 第 d 层走的出口 = 第 d+1 层选的候选
        const exits = plan.map((_, d) => (plan[d + 1]?.length === 2 ? picks[d + 1] : 0));
        const chain = solveChain(floors, undefined, 40, exits);
        floors.forEach((f, d) => {
            if (d === 0) return;
            const sc = scenario(`路线 选法${k} 第${d + 1}层`, f, chain[d - 1].best!, exits[d]);
            if (!sc) throw new Error(`路线第 ${d + 1} 层走不通`);
            routeWalks.push(sc);
        });
    }
}

// ---------- 3. 硬打致死 ----------
const deaths = (['frog', 'beetle', 'wraith'] as MonsterId[]).map(id => {
    const f = tiny(['@' + ({ frog: 'f', beetle: 'c', wraith: 'g' } as Record<string, string>)[id] + '>']);
    const run = new Run([f]);
    run.hero.hp = 30;
    const r = run.step(1);
    return { monster: id, map: f.map, hp: 30, ok: r.ok, status: run.status, heroHp: run.hero.hp };
});

// ---------- 4. 断臂转轮：转、锁轴、空手 ----------
type ArmAct = { pay: 'gold' | 'blood'; held?: boolean[] };
const armScripts: ArmAct[][] = [
    [{ pay: 'gold' }, { pay: 'gold' }, { pay: 'gold', held: [true, false, false] }, { pay: 'blood' }, { pay: 'gold', held: [true, true, false] }, { pay: 'gold' }],
    [{ pay: 'blood' }, { pay: 'gold', held: [false, true, false] }, { pay: 'gold', held: [false, true, true] }, { pay: 'gold' }, { pay: 'gold' }, { pay: 'blood' }, { pay: 'gold' }],
];
type Reels = ArmSym[][];
const R5 = (...rs: ArmSym[][]): Reels => rs.map(r => [...r, ...Array(5 - r.length).fill(null)]);
const reelsOut = (rs: Reels) => rs.map(r => r.map(x => x ?? 'blank'));
const armSets: Reels[] = [
    R5(['boneKnife'], ['boneKnife'], ['boneKnife']),
    R5(['hammer', 'hammer'], ['hammer', null, 'hammer'], ['hammer']),
    R5(['harpoon', 'mossBlade', 'saltDagger', 'harpoon', 'harpoon'], ['harpoon', 'harpoon', 'mossBlade', 'harpoon', 'saltDagger'], ['harpoon', 'harpoon', 'harpoon', 'mossBlade', 'harpoon']),
    R5(['rustSword', null, 'rustSword'], [], ['rustSword']),
    // 赖子
    R5(['boneKnife', 'wild', null, 'hammer'], ['wild', 'boneKnife', 'hammer'], ['boneKnife', 'wild', 'hammer', null, 'wild']),
    R5(['wild', 'wild', 'wild', 'wild', 'wild'], ['wild', 'harpoon', null], ['harpoon', 'wild']),
];
// 各种结果的机会（界面显示用）：不锁、锁住各种组合
const armOddsVec: unknown[] = [];
for (const set of armSets) {
    for (const stops of [[0, 0, 0], [1, 2, 3], [4, 1, 0]]) {
        for (const held of [undefined, [true, false, false], [false, true, true], [true, false, true]]) {
            const arm = newArm();
            arm.reels = set.map(r => [...r]);
            arm.stops = [...stops];
            const { counts, total } = armOutcomeCounts(arm, held);
            armOddsVec.push({ reels: reelsOut(set), stops, held, counts, total });
        }
    }
}
const armSessions: unknown[] = [];
for (const seed of [1, 9, 4242, 2147483647]) {
    for (const set of armSets) {
        armScripts.forEach((script, si) => {
            const run = new Run([tiny(['@.>'])], 'digger', seed);
            run.arm!.reels = set.map(r => [...r]);
            run.hero = { hp: 500, atk: 13, def: 13, keys: 0, gold: 300 };
            const steps = script.map(a => {
                const r = run.armSpin(a.pay, a.held);
                void 0;
                return { pay: a.pay, held: a.held, ok: r.ok, faces: r.faces ? r.faces.map(x => x ?? 'blank') : undefined, stops: [...run.arm!.stops], hero: heroOf(run.hero), spins: run.arm!.spins };
            });
            armSessions.push({ seed, reels: reelsOut(set), script: si, steps });
        });
    }
}
// 刻图案：选轮子、刻满时选格子覆盖
const engraveOps: unknown[] = [];
{
    const run = new Run([tiny(['@.>'])], 'digger', 1);
    const ws: EngraveSym[] = ['boneKnife', 'hammer', 'wild', 'mossBlade', 'bellStaff', 'saltDagger', 'wild'];
    const tries: [number, number?][] = [[0], [0], [1], [2], [0], [0], [0], [0], [0, 2], [1], [2, 4], [3], [1, 9]];
    tries.forEach(([reel, cell], k) => {
        const w = ws[k % ws.length];
        run.engraveQueue = [{ from: 'elite', choices: [w] }];
        const r = run.engrave(w, reel, cell);
        engraveOps.push({ weapon: w, reel, cell, ok: r.ok, msg: r.msg, reels: reelsOut(run.arm!.reels), stops: [...run.arm!.stops], hero: heroOf(run.hero) });
    });
}

// ---------- 5. 刻图案：精英三选一、印记怪 ----------
const engraves: unknown[] = [];
for (const seed of [1, 5, 77, 31337, 2, 3, 4, 6, 8, 13, 21, 34]) {
    for (const floors of [1, 4, 10]) {
        for (const current of [undefined, 'boneKnife', 'hammer'] as (WeaponId | undefined)[]) {
            const fs: FloorDef[] = [];
            for (let k = 0; k < floors; k++) fs.push(tiny(['@>']));
            fs[floors - 1] = tiny(['@Ge>'], { eliteReward: true, marks: [2] });
            const run = new Run(fs, 'digger', seed);
            for (let k = 0; k < floors - 1; k++) { run.move(1, 0); run.finishFloor(false); }
            run.hero = { hp: 999, atk: 60, def: 60, keys: 0, gold: 0, weapon: current };
            run.move(1, 0);
            run.move(1, 0);
            engraves.push({ seed, floorIndex: floors, current, queue: run.engraveQueue.map(p => ({ from: p.from, choices: p.choices })) });
        }
    }
}

// ---------- 6. 大转盘 ----------
const wheels: unknown[] = [];
for (const seed of [3, 11, 2024, 99991, 4000000000, 5, 6, 7]) {
    const run = new Run([tiny(['@.>', '.S.'])], 'digger', seed);
    run.move(0, 1);
    run.hero = { hp: 3000, atk: 13, def: 13, keys: 0, gold: 3000 };
    run.arm!.reels = R5(['boneKnife', 'hammer'], ['harpoon', null, 'boneKnife'], ['boneKnife']);
    run.hero.weapon = 'boneKnife';
    const steps: unknown[] = [];
    for (let k = 0; k < 24; k++) {
        const r = run.wheelSpin(4, k % 3 === 2 ? 'blood' : 'gold');
        steps.push({ ok: r.ok, sector: r.sector, hero: heroOf(run.hero), reels: reelsOut(run.arm!.reels), queue: run.engraveQueue.map(p => p.choices[0]), status: run.status });
        run.engraveQueue = [];
    }
    wheels.push({ seed, steps });
}

// ---------- 7. 当铺、骨坛、补给摊 ----------
const shops: unknown[] = [];
{
    const plan = [tiny(['@.>', 'N..'], { shop: ['hammer', 'harpoon'] }), tiny(['@.>', 'N..'], { shop: ['boneKnife', 'saltDagger'] }), tiny(['@.>', 'N..'], { shop: ['wellHook', 'wild'] })];
    type Op = [string, ...number[]];
    // pawn 轮子,格子；buy 第几样,轮子,格子?；erase 轮子,格子；redeem 第几件,格子?
    const ops: Op[] = [['key'], ['key'], ['pawn', 1, 0], ['buy', 0, 1], ['buy', 0, 1], ['buy', 1, 2], ['erase', 2, 0], ['next'], ['redeem', 0], ['pawn', 1, 0], ['next'], ['redeem', 0, 3], ['buy', 0, 0, 2], ['buy', 1, 0], ['erase', 0, 2], ['pawn', 0, 0], ['pawn', 0, 4]];
    for (const [gold, keys] of [[300, 2], [60, 1], [0, 0]]) {
        const run = new Run(plan, 'digger', 1);
        run.hero.gold = gold; run.hero.keys = keys;
        run.arm!.reels = R5([], ['boneKnife', 'hammer', 'hammer', 'hammer', 'hammer'], []);
        run.hero.weapon = 'boneKnife';
        const steps = ops.map(([op, a, b, c]) => {
            let r = { ok: true, msg: '' };
            if (op === 'key') r = run.pawnSellKey(3);
            else if (op === 'pawn') r = run.pawnCell(3, a, b);
            else if (op === 'buy') r = run.pawnBuy(3, a, b, c);
            else if (op === 'erase') r = run.pawnErase(3, a, b);
            else if (op === 'redeem') r = run.pawnRedeem(3, a, b);
            else { run.move(1, 0); run.move(1, 0); run.finishFloor(false); }
            return { op, a, b, c, ok: r.ok, msg: r.msg, hero: heroOf(run.hero), reels: reelsOut(run.arm!.reels), pawned: run.pawned.map(p => ({ weapon: p.weapon, reel: p.reel, floor: p.floor })) };
        });
        shops.push({ gold, keys, plan: plan.map(floorParams), steps });
    }
}
const altars: unknown[] = [];
for (const kills of ['vgx', 'g', 'u']) {
    const map = ['@' + kills + '.A>'];
    const run = new Run([tiny(map)], 'digger', 1);
    run.hero = { hp: 9999, atk: 60, def: 60, keys: 1, gold: 0 };
    run.arm!.reels = R5(['boneKnife'], ['hammer'], []);
    run.hero.weapon = 'boneKnife';
    for (let k = 0; k <= kills.length; k++) run.move(1, 0);
    const altar = kills.length + 2;
    const tries: [('atk' | 'key'), Boon, WeaponId][] = [['atk', 'lifesteal', 'boneKnife'], ['key', 'firstStrike', 'boneKnife'], ['atk', 'thorns', 'hammer'], ['atk', 'corrode', 'boneKnife'], ['atk', 'thorns', 'harpoon']];
    const steps = tries.map(([pay, boon, w]) => {
        const r = run.altarOffer(altar, pay, boon, w);
        return { pay, boon, weapon: w, ok: r.ok, msg: r.msg, hero: heroOf(run.hero), boons: JSON.parse(JSON.stringify(run.arm!.boons)) };
    });
    altars.push({ map, seen: run.boonsSeen, steps: JSON.parse(JSON.stringify(steps)) });
}
const stalls: unknown[] = [];
{
    const stallFloor = tiny(['@.M>'], { stall: [{ id: 'atk', amount: 2, price: 40 }, { id: 'hp', amount: 80, price: 25 }, { id: 'key', amount: 1, price: 30 }] });
    for (const [gold, buys] of [[100, [0, 0, 1, 2]], [50, [2, 1, 0]]] as [number, number[]][]) {
        const run = new Run([stallFloor]);
        run.hero.gold = gold;
        run.move(1, 0);
        const steps = buys.map(k => { const r = run.stallBuy(2, k); return { k, ok: r.ok, msg: r.msg, hero: heroOf(run.hero) }; });
        stalls.push({ floor: floorParams(stallFloor), gold, steps });
    }
}

// ---------- 8. 诏令 ----------
const decreeDraws: unknown[] = [];
for (const seed of [1, 2, 3, 77, 31337, 2147483647, 4000000000]) for (const fi of [2, 7, 12, 5]) decreeDraws.push({ seed, floorIndex: fi, def: decreeFor(seed, fi) });
const decreeRuns: unknown[] = [];
{
    // 6 层：第 3 层接诏令，后面各层分别做到 / 做不到
    const maps = [['@.>', 'm..'], ['@.>', 'm..'], ['@vh>'], ['@m.>'], ['@gx>'], ['@.>']];
    const kinds = ['killTrait', 'noPotion', 'clear', 'noLoss', 'gold'] as const;
    for (const kind of kinds) {
        for (const n of [1, 2]) {
            const run = new Run(maps.map(m => tiny(m)), 'digger', 1);
            run.hero = { hp: 600, atk: 40, def: 30, keys: 0, gold: 0 };
            const log: unknown[] = [];
            for (let d = 0; d < maps.length; d++) {
                if (run.decreeOffer) {
                    run.decreeOffer = { kind, tier: n === 1 ? 'bronze' : 'silver', n: kind === 'gold' ? 30 : n, text: kind };
                    run.acceptDecree();
                }
                // 一路打过去（用格子顺序），走到出口
                for (let guard = 0; guard < 20 && run.status === 'playing'; guard++) run.move(1, 0);
                run.engraveQueue = [];
                run.finishFloor(false);
                log.push({ d, hero: heroOf(run.hero), decree: JSON.parse(JSON.stringify(run.decree)), notes: run.notes.splice(0), status: run.status });
            }
            decreeRuns.push({ kind, n, maps, log: JSON.parse(JSON.stringify(log)) });
        }
    }
}

// ---------- 9. 路线和楼梯口的话 ----------
const routes: unknown[] = [];
for (const seed of [1, 2, 3, 42, 99, 12345, 2147483647, 4000000000, 4, 5, 6, 7, 8, 9]) {
    routes.push({ seed, plan: R.buildRoute(seed).map(o => o.map(f => ({ ...floorParams(f), whisper: whisper(f) }))) });
}
const tutorials = [1, 7, 31337].map(seed => ({ seed, plan: R.buildTutorial(seed).map(o => o.map(floorParams)) }));

// ---------- 11. 灵魂碎片：碎片折算、开局强化、解锁 / 深度模式的路线、新角色 ----------
const shardsVec: unknown[] = [];
for (let reached = 1; reached <= 20; reached++) for (const won of [false, true]) for (let depth = 0; depth <= 3; depth++) {
    shardsVec.push({ reached, won, depth, shards: Meta.shardsFor(reached, won, depth) });
}
const ALL_UNLOCKS = Meta.UNLOCKS.map(u => u.id);
const perkRuns: unknown[] = [];
for (const seed of [1, 2, 3, 42, 777]) {
    for (const [perks, unlocks] of [[{ atk: 1 }, []], [{ atk: 3, def: 2, hp: 3, keys: 1, gold: 2, engrave: 1, halfSpin: 1 }, ALL_UNLOCKS], [{ engrave: 1 }, ['lamp']]] as [Record<string, number>, string[]][]) {
        const pool = Meta.weaponPool(unlocks);
        const run = new Run(R.buildRoute(seed, { unlocks }), 'digger', seed, { perks, pool });
        perkRuns.push({ seed, perks, unlocks, hero: heroOf(run.hero), reels: JSON.parse(JSON.stringify(run.arm!.reels)), price: run.armPrice().gold });
    }
}
const metaRoutes: unknown[] = [];
for (const seed of [1, 5, 9, 2024]) {
    for (const opts of [{ depth: 1 }, { depth: 3 }, { unlocks: ALL_UNLOCKS }, { depth: 2, unlocks: ['pawnExtra', 'campKey'] }]) {
        metaRoutes.push({ seed, opts, plan: R.buildRoute(seed, opts).map(o => o.map(floorParams)) });
    }
}
const charRuns: unknown[] = [];
{
    const maps = [['@D.G>', '.....'], ['@.m.>'], ['@...>']];
    for (const id of ['scavenger', 'drowned']) {
        const run = new Run(maps.map(m => tiny(m)), id, 3);
        const log: unknown[] = [];
        for (let d = 0; d < maps.length; d++) {
            for (let guard = 0; guard < 8 && run.status === 'playing'; guard++) {
                const r = run.move(1, 0);
                log.push({ ok: r.ok, hero: heroOf(run.hero), status: run.status, revived: run.revived });
                if (!r.ok) { run.hero.atk += 60; run.hero.def += 60; }
            }
            if (run.status === 'floorDone') run.finishFloor(false);
            log.push({ floor: run.floorIndex, hero: heroOf(run.hero), status: run.status });
        }
        charRuns.push({ id, maps, log });
    }
}

// ---------- 10. 存档 ----------
// （每一步对账时 Lua 都会存档再读回来）

const out = `-- 由 tools/export-vectors.ts 自动生成，不要手改。
-- 来源：TypeScript 原型（src/core）。LÖVE + Lua 版必须逐条算出同样的结果。
return ${lua({ character: CHARACTERS.digger, combat, scenarios, monsterViews, routeWalks, deaths, armSessions, armOddsVec, engraveOps, engraves, wheels, shops, altars, stalls, decreeDraws, decreeRuns, routes, tutorials, shardsVec, perkRuns, metaRoutes, charRuns })}
`;
mkdirSync('love/tests', { recursive: true });
writeFileSync('love/tests/vectors.lua', out);

// ---------- Lua 版的地图池 ----------
// 导出地图池时不带小图原稿（Lua 只用放大后的图）
const ent = (list: R.MapEntry[]) => list.map(({ small: _small, ...e }) => e);
const pools = {
    SHALLOW: R.SHALLOW, DEEP: R.DEEP, BOTTOM: R.BOTTOM, RENTS: Object.entries(R.RENTS).map(([d, v]) => ({ floor: +d, rent: v })),
    F1: { params: DEMO_POOLS[0].params, maps: R.F1_MAPS.map(e => e.map) },
    F2: { params: F2_CONTRACT.params, maps: R.F2_MAPS.map(e => e.map) },
    NORMAL_SHALLOW: ent(R.NORMAL_SHALLOW), NORMAL_DEEP: ent(R.NORMAL_DEEP), ELITE_SHALLOW: ent(R.ELITE_SHALLOW), ELITE_DEEP: ent(R.ELITE_DEEP),
    WHEEL_MAPS: ent(R.WHEEL_MAPS), PAWN_MAPS: ent(R.PAWN_MAPS), ALTAR_MAPS: ent(R.ALTAR_MAPS), CAMP_MAPS: ent(R.CAMP_MAPS),
    MID_ELITE: ent([R.MID_ELITE])[0], GATE: ent([R.GATE])[0], BOSS: ent([R.BOSS])[0], TUTORIAL_BOSS: ent([R.TUTORIAL_BOSS])[0],
    TUTORIAL: R.TUTORIAL_FLOORS,
};
mkdirSync('love/src/data', { recursive: true });
writeFileSync('love/src/data/pools.lua', `-- 由 tools/export-vectors.ts 从 src/core/route.ts 自动生成，不要手改。
-- 路线用的地图池和各段数值。路线生成（love/src/core/route.lua）和原型用同一套算法。
-- 地图、数值、出现比例都是讨论项（设计方案第五、六章）。
return ${lua(pools)}
`);
console.log(`战斗 ${combat.length}；楼层 ${scenarios.length}；新怪属性 ${monsterViews.length}；路线逐层 ${routeWalks.length}；致死 ${deaths.length}；断臂转轮 ${armSessions.length}；刻在哪 ${engraveOps.length}；刻图案 ${engraves.length}；大转盘 ${wheels.length}；当铺 ${shops.length}；骨坛 ${altars.length}；补给摊 ${stalls.length}；诏令 ${decreeDraws.length}+${decreeRuns.length}；路线 ${routes.length}；教程 ${tutorials.length}`);
