import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CHARACTERS, MONSTERS, MonsterDef } from '../src/core/config';
import { simulateCombat } from '../src/core/combat';
import { FloorDef } from '../src/core/floor';
import { Run } from '../src/core/game';
import { M1_FLOORS } from '../src/core/levels';
import { solveFromStart, solveRun } from '../src/core/solver';

const hero = { atk: 10, def: 10 };
const mk = (traits: MonsterDef['traits'], over: Partial<MonsterDef> = {}): MonsterDef =>
    ({ id: 'moss', name: 'x', hp: 30, atk: 15, def: 2, traits, ...over });

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

test('不会主动发起致死的战斗', () => {
    const run = new Run([tiny(['@f>'])]);
    run.hero.hp = 10;
    assert.equal(run.move(1, 0).ok, false);
    assert.equal(run.hero.hp, 10);
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
    assert.equal(run.exitSummary().cleared, false);
    run.finishFloor(false);
    assert.equal(run.floorIndex, 1);
    assert.equal(run.canUndo(), false);
});

test('精英活着时出口被封住', () => {
    const run = new Run([tiny(['@.>', 'G..'])]);
    run.move(1, 0);
    assert.equal(run.move(1, 0).ok, false);
    assert.equal(run.status, 'playing');
});

test('清层奖励、剩余血瓶、卖钥匙', () => {
    const run = new Run([tiny(['@mk>', '..h.'])]);
    run.move(1, 0); run.move(1, 0); run.move(1, 0); run.move(1, 0);
    const s = run.exitSummary();
    assert.equal(s.cleared, true);
    assert.equal(s.leftoverPotions, 1);
    run.finishFloor(true);
    assert.equal(run.hero.gold, 30 + 5 + 15);
    assert.equal(run.status, 'finished');
});

test('点击寻路 + 一次点击只算一次撤回', () => {
    const run = new Run([tiny(['@..m', '...>'])]);
    run.tapCell(3);
    assert.equal(run.pos, 2);
    assert.equal(run.cells[3].kind, 'floor');
    run.undo();
    assert.equal(run.pos, 0);
    assert.equal(run.cells[3].kind, 'monster');
    assert.equal(run.canUndo(), false);
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

test('M1 三层都能通关，且最优解明显好于乱走', () => {
    const run = solveRun(M1_FLOORS);
    assert.ok(run.perFloor.every(hp => hp > 0), `每层结束生命 ${run.perFloor}`);
    for (const f of M1_FLOORS) assert.ok(solveFromStart(f, CHARACTERS.digger.base).statesVisited < 100000);
});

test('按求解器的路线实际玩，结果和求解器一致', () => {
    const run = new Run(M1_FLOORS);
    let expectHero = CHARACTERS.digger.base;
    for (let i = 0; i < M1_FLOORS.length; i++) {
        const r = solveFromStart(M1_FLOORS[i], { ...run.hero });
        for (const cell of r.best!.plan) assert.ok(run.tapCell(cell).ok, `第 ${i + 1} 层格子 ${cell}`);
        const exit = run.cells.findIndex(c => c.kind === 'exit');
        run.tapCell(exit);
        assert.equal(run.status, 'floorDone');
        assert.equal(run.hero.hp, r.best!.hero.hp);
        expectHero = r.best!.hero;
        run.finishFloor(false);
    }
    assert.equal(run.status, 'finished');
    assert.ok(expectHero.hp > 0);
});
