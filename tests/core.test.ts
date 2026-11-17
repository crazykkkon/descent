import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CHARACTERS, MONSTERS, MonsterDef } from '../src/core/config';
import { simulateCombat } from '../src/core/combat';
import { FloorDef } from '../src/core/floor';
import { Run } from '../src/core/game';
import { DEMO_POOLS, allChoices, buildFloor, buildFloors, pickChoices } from '../src/core/levels';
import { parseFloor } from '../src/core/floor';
import { stairIntel } from '../src/core/intel';
import { greedyFloor, solveFromStart, solveRun } from '../src/core/solver';

const hero = { atk: 10, def: 10 };
const mk = (traits: MonsterDef['traits'], over: Partial<MonsterDef> = {}): MonsterDef =>
    ({ id: 'moss', name: 'x', hp: 30, atk: 15, def: 2, traits, gold: 0, ...over });

test('设计文档里的例子：攻10防10打井苔损失15', () => {
    assert.equal(simulateCombat(hero, MONSTERS.moss).damage, 15);
});

test('打不动：攻击不高于防御', () => {
    const r = simulateCombat(hero, MONSTERS.beetle);
    assert.equal(r.canAttack, false);
});

test('先攻：多挨一下', () => {
    assert.equal(simulateCombat(hero, mk(['firstStrike'])).damage, 20);
});

test('二连击：每回合两下', () => {
    assert.equal(simulateCombat(hero, mk(['double'])).damage, 30);
});

test('反伤：每次攻击自己扣3', () => {
    assert.equal(simulateCombat(hero, mk(['thorns'])).damage, 15 + 4 * 3);
});

test('吸血：回血太快就打不死', () => {
    assert.equal(simulateCombat({ atk: 16, def: 16 }, MONSTERS.wraith).canWin, false);
    assert.equal(simulateCombat({ atk: 22, def: 22 }, MONSTERS.wraith).canWin, true);
});

const tiny = (map: string[], extra: Partial<FloorDef> = {}): FloorDef =>
    ({ name: 't', map, bloodCost: 40, gem: 2, smallPotion: 50, bigPotion: 150, gold: 20, ...extra });

test('预览掉血 = 实际掉血，怪物格子变空地，主角不动', () => {
    const run = new Run([tiny(['@m>'])]);
    const preview = run.info(1).combat!.damage;
    const r = run.move(1, 0);
    assert.ok(r.ok);
    assert.equal(run.hero.hp, 200 - preview);
    assert.equal(run.pos, 0);
    assert.equal(run.cells[1].kind, 'floor');
});

test('打不过的怪也可以硬上：打完就死，这一局结束', () => {
    const run = new Run([tiny(['@f>'])]);
    run.hero.hp = 10;
    assert.equal(run.move(1, 0).ok, true);
    assert.equal(run.status, 'dead');
    assert.equal(run.hero.hp, 0);
    assert.equal(run.move(1, 0).ok, false);
    // 打不动（攻击不够破防）的怪也可以上
    const r2 = new Run([tiny(['@c>'])]);
    assert.equal(r2.move(1, 0).ok, true);
    assert.equal(r2.status, 'dead');
    // 死了以后还能重开本层
    r2.restartFloor();
    assert.equal(r2.status, 'playing');
    assert.equal(r2.hero.hp, 200);
});

test('打败怪物按强度掉金币；金币袋照样能捡', () => {
    const run = new Run([tiny(['@me$>'])]);
    run.move(1, 0);
    assert.equal(run.hero.gold, MONSTERS.moss.gold);
    run.move(1, 0); run.move(1, 0);
    assert.equal(run.hero.gold, MONSTERS.moss.gold + MONSTERS.eel.gold);
    run.move(1, 0); run.move(1, 0);
    assert.equal(run.hero.gold, MONSTERS.moss.gold + MONSTERS.eel.gold + 20);
    // 越强的怪掉得越多
    const g = (id: keyof typeof MONSTERS) => MONSTERS[id].gold;
    assert.ok(g('moss') < g('eel') && g('eel') < g('frog') && g('frog') < g('wraith') && g('wraith') < g('guardian'));
});

test('骨门要钥匙，血门扣血', () => {
    const run = new Run([tiny(['@DkB>'])]);
    assert.equal(run.move(1, 0).ok, false);
    const r2 = new Run([tiny(['@kDB>'])]);
    r2.move(1, 0); r2.move(1, 0);
    assert.equal(r2.hero.keys, 0);
    r2.move(1, 0);
    assert.equal(r2.hero.hp, 160);
});

test('宝石：掘井人额外 +1', () => {
    const run = new Run([tiny(['@r>'])]);
    run.move(1, 0);
    assert.equal(run.hero.atk, 13);
});

test('走到出口进入结算，不需要清怪；只能往下走', () => {
    const run = new Run([tiny(['@>', 'm.']), tiny(['@>'])]);
    run.move(1, 0);
    assert.equal(run.status, 'floorDone');
    run.finishFloor(false);
    assert.equal(run.floorIndex, 1);
});

test('精英活着时出口被封住', () => {
    const run = new Run([tiny(['@.>', 'G..'])]);
    run.move(1, 0);
    assert.equal(run.move(1, 0).ok, false);
    assert.equal(run.status, 'playing');
});

test('清层不再有额外奖励；剩余血瓶换金币、卖钥匙', () => {
    const run = new Run([tiny(['@mk>', '..h.'])]);
    run.move(1, 0); run.move(1, 0); run.move(1, 0); run.move(1, 0);
    const s = run.exitSummary();
    assert.equal(s.leftoverPotions, 1);
    run.finishFloor(true);
    assert.equal(run.hero.gold, MONSTERS.moss.gold + 5 + 15);
    assert.equal(run.status, 'finished');
});

test('点击寻路：走到怪物旁边再打；没有撤回', () => {
    const run = new Run([tiny(['@..m', '...>'])]);
    assert.deepEqual(run.findPath(3), [1, 2, 3]);
    run.tapCell(3);
    assert.equal(run.pos, 2);
    assert.equal(run.cells[3].kind, 'floor');
    assert.equal(run.steps, 3);
    assert.equal((run as unknown as Record<string, unknown>).undo, undefined);
});

test('重开本层回到入场状态', () => {
    const run = new Run([tiny(['@rm>'])]);
    run.move(1, 0); run.move(1, 0);
    run.restartFloor();
    assert.equal(run.hero.atk, 10);
    assert.equal(run.pos, 0);
});

test('求解器：只能靠宝石过的小谜题', () => {
    // 先拿赤晶才打得动锈甲虫
    const r = solveFromStart(tiny(['@c>', 'rrr']), CHARACTERS.digger.base);
    assert.ok(r.solvable);
    assert.ok(r.best!.plan.filter(i => i >= 3).length >= 2);
});

test('试玩版地图尺寸：第 1 层 9×7，第 2、3 层 11×7', () => {
    DEMO_POOLS.forEach((pool, fi) => pool.layouts.forEach((l, li) => l.variants.forEach((_, vi) => {
        const p = parseFloor(buildFloor(pool, { layout: li, variant: vi }));
        assert.deepEqual([p.w, p.h], fi === 0 ? [9, 7] : [11, 7], `${pool.params.name} ${l.name}${vi + 1}`);
    })));
});

test('每层 3 种布局 × 2 套配置；同一布局的两套墙壁、入口、出口完全一样', () => {
    for (const pool of DEMO_POOLS) {
        assert.equal(pool.layouts.length, 3);
        for (const l of pool.layouts) {
            assert.equal(l.variants.length, 2);
            const shape = (m: string[]) => m.map(r => r.replace(/[^#@>]/g, '.')).join('|');
            assert.equal(shape(l.variants[0].map), shape(l.variants[1].map), `${pool.params.name} ${l.name}`);
            assert.notEqual(l.variants[0].map.join(), l.variants[1].map.join());
        }
    }
});

test('开局不打怪就拿不到宝石和血瓶（奖励都在怪物身后）', () => {
    DEMO_POOLS.forEach(pool => pool.layouts.forEach((l, li) => l.variants.forEach((_, vi) => {
        const f = buildFloor(pool, { layout: li, variant: vi });
        const run = new Run([f]);
        const reach = new Set([run.pos]);
        const st = [run.pos];
        while (st.length) {
            const cur = st.pop()!;
            for (let n = 0; n < run.cells.length; n++) {
                const adj = Math.abs(n % run.w - cur % run.w) + Math.abs(Math.floor(n / run.w) - Math.floor(cur / run.w)) === 1;
                if (!adj || reach.has(n)) continue;
                const c = run.cells[n];
                if (c.kind === 'item') assert.ok(c.id === 'gold' || c.id === 'key', `${pool.params.name} ${l.name}${vi + 1} 白拿 ${c.id}`);
                if (c.kind === 'floor' || c.kind === 'item') { reach.add(n); st.push(n); }
            }
        }
    })));
});

test('前两层难度低：每张图都能不死地拿到所有加成，见怪就打的玩家也不会死', () => {
    const base = CHARACTERS.digger.base;
    const f1Out: { hp: number; atk: number; def: number; keys: number; gold: number }[] = [];
    for (const [fi, entries] of [[0, [base]], [1, null]] as const) {
        const pool = DEMO_POOLS[fi];
        const ins = entries ?? f1Out;
        pool.layouts.forEach((l, li) => l.variants.forEach((_, vi) => {
            const f = buildFloor(pool, { layout: li, variant: vi });
            for (const e of ins) {
                const r = solveFromStart(f, e);
                const name = `${pool.params.name} ${l.name}${vi + 1} 入场 ${e.hp}`;
                assert.ok(r.bestAll, `${name}：拿不全所有道具`);
                assert.ok(r.bestAll!.hero.hp >= Math.min(150, e.hp * 0.75), `${name}：拿全后只剩 ${r.bestAll!.hero.hp}`);
                assert.ok(greedyFloor(f, e, undefined, 'clear'), `${name}：见怪就打会死`);
                if (fi === 0) f1Out.push(r.bestAll!.hero);
            }
        }));
    }
});

test('楼梯口情报：必经的高防守卫，给出现在和拿宝石后的掉血对比', () => {
    const next = tiny(['@.c.>']);
    const cur = new Run([tiny(['@rr>']), next]);
    const it = cur.nextFloorIntel()!;
    assert.match(it.headline, /高防守卫/);
    assert.match(it.headline, /必经/);
    assert.equal(it.mustFight, true);
    assert.ok(it.lines.some(l => l.includes('打不动')), it.lines.join('|'));
    assert.ok(it.lines.some(l => /赤晶没拿.*-\d+/.test(l)), it.lines.join('|'));
});

test('楼梯口情报：不拿可以绕开的怪吓唬人', () => {
    // 回声蝠在死胡同里，井苔挡路
    const it = stairIntel(tiny(['@m>', 'v##']), CHARACTERS.digger.base, CHARACTERS.digger)!;
    assert.equal(it.monster, 'moss');
});

test('最后一层没有楼梯口情报；试玩版每层都能生成情报', () => {
    const floors = buildFloors(pickChoices(5));
    const run = new Run(floors);
    assert.ok(run.nextFloorIntel());
    assert.equal(Run.load(floors, { ...run.save(), floorIndex: 2, current: run.save().current, floorStart: run.save().floorStart }).nextFloorIntel(), null);
    for (const fi of [1, 2]) DEMO_POOLS[fi].layouts.forEach((l, li) => l.variants.forEach((_, vi) => {
        assert.ok(stairIntel(buildFloor(DEMO_POOLS[fi], { layout: li, variant: vi }), CHARACTERS.digger.base, CHARACTERS.digger));
    }));
});

test('所有选图组合都能通关', () => {
    for (const c of allChoices()) assert.ok(solveRun(buildFloors(c)).bestHp > 0, JSON.stringify(c));
});

test('同一个种子选到同一组地图；新开一局每层都换图；第 2、3 层不连用同一种布局', () => {
    assert.deepEqual(pickChoices(42), pickChoices(42));
    for (let seed = 1; seed < 200; seed++) {
        const a = pickChoices(seed);
        const b = pickChoices(seed + 1000, DEMO_POOLS, a);
        b.forEach((c, i) => assert.ok(c.layout !== a[i].layout || c.variant !== a[i].variant));
        assert.notEqual(DEMO_POOLS[1].layouts[a[1].layout].name, DEMO_POOLS[2].layouts[a[2].layout].name);
    }
});

test('存档读档：继续游戏时地图和进度不变', () => {
    const choices = pickChoices(7);
    const floors = buildFloors(choices);
    const run = new Run(floors);
    const r = solveFromStart(floors[0], run.hero);
    run.tapCell(r.best!.plan[0]);
    const saved = JSON.parse(JSON.stringify(run.save()));
    const back = Run.load(floors, saved);
    assert.deepEqual(back.cells, run.cells);
    assert.deepEqual(back.hero, run.hero);
    assert.equal(back.pos, run.pos);
    back.restartFloor();
    assert.deepEqual(back.hero, CHARACTERS.digger.base);
});

test('按求解器的路线实际玩，结果和求解器一致', () => {
    const floors = buildFloors(pickChoices(3));
    const run = new Run(floors);
    for (let i = 0; i < floors.length; i++) {
        const r = solveFromStart(floors[i], { ...run.hero });
        for (const cell of r.best!.plan) assert.ok(run.tapCell(cell).ok, `第 ${i + 1} 层格子 ${cell}`);
        run.tapCell(run.cells.findIndex(c => c.kind === 'exit'));
        assert.equal(run.status, 'floorDone');
        assert.equal(run.hero.hp, r.best!.hero.hp);
        run.finishFloor(false);
    }
    assert.equal(run.status, 'finished');
});
