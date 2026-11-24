import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CHARACTERS, MONSTERS, MonsterDef, WeaponId } from '../src/core/config';
import { simulateCombat } from '../src/core/combat';
import { FloorDef } from '../src/core/floor';
import { Run } from '../src/core/game';
import { DEMO_POOLS, F2_CLASSIC, allChoices, buildFloor, buildFloors, pickChoices } from '../src/core/levels';
import { parseFloor } from '../src/core/floor';
import { greedyFloor, paretoFilter, solveFromStart, solveRun } from '../src/core/solver';

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

test('预览掉血 = 实际掉血，战斗胜利后一步站到怪物格', () => {
    const run = new Run([tiny(['@m>'])]);
    const preview = run.info(1).combat!.damage;
    const r = run.move(1, 0);
    assert.ok(r.ok);
    assert.equal(run.hero.hp, 200 - preview);
    assert.equal(run.pos, 1);
    assert.equal(run.steps, 1);
    assert.equal(run.cells[1].kind, 'floor');
});

test('打不过的怪也可以硬上：打完就死，这一局结束', () => {
    const run = new Run([tiny(['@f>'])]);
    run.hero.hp = 10;
    assert.equal(run.move(1, 0).ok, true);
    assert.equal(run.status, 'dead');
    assert.equal(run.hero.hp, 0);
    assert.equal(run.pos, 0);
    assert.equal(run.cells[1].kind, 'monster');
    assert.equal(run.move(1, 0).ok, false);
    // 打不动（攻击不够破防）的怪也可以上
    const r2 = new Run([tiny(['@c>'])]);
    assert.equal(r2.move(1, 0).ok, true);
    assert.equal(r2.status, 'dead');
    // 没有重开本层：死了就只能整局重来
    assert.equal((r2 as unknown as Record<string, unknown>).restartFloor, undefined);
});

test('打败怪物按强度掉金币；金币袋照样能捡', () => {
    const run = new Run([tiny(['@me$>'])]);
    run.move(1, 0);
    assert.equal(run.hero.gold, MONSTERS.moss.gold);
    run.move(1, 0);
    assert.equal(run.hero.gold, MONSTERS.moss.gold + MONSTERS.eel.gold);
    run.move(1, 0);
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
    run.move(1, 0); run.move(1, 0); run.move(1, 0);
    const s = run.exitSummary();
    assert.equal(s.leftoverPotions, 1);
    run.finishFloor(true);
    assert.equal(run.hero.gold, MONSTERS.moss.gold + 5 + 15);
    assert.equal(run.status, 'finished');
});

test('点击寻路：沿路接近，打赢后停在怪物格；没有撤回', () => {
    const run = new Run([tiny(['@..m', '...>'])]);
    assert.deepEqual(run.findPath(3), [1, 2, 3]);
    run.tapCell(3);
    assert.equal(run.pos, 3);
    assert.equal(run.cells[3].kind, 'floor');
    assert.equal(run.steps, 3);
    assert.equal((run as unknown as Record<string, unknown>).undo, undefined);
});

test('求解器：只能靠宝石过的小谜题', () => {
    // 先拿赤晶才打得动锈甲虫
    const r = solveFromStart(tiny(['@c>', 'rrr']), CHARACTERS.digger.base);
    assert.ok(r.solvable);
    assert.ok(r.best!.plan.filter(i => i >= 3).length >= 2);
});

test('试玩版地图尺寸：第 1、4、5 层 9×7，第 2、3 层 11×7', () => {
    DEMO_POOLS.forEach((pool, fi) => pool.layouts.forEach((l, li) => l.variants.forEach((_, vi) => {
        const p = parseFloor(buildFloor(pool, { layout: li, variant: vi }));
        assert.deepEqual([p.w, p.h], fi === 1 || fi === 2 ? [11, 7] : [9, 7], `${pool.params.name} ${l.name}${vi + 1}`);
    })));
});

test('开局不打怪就拿不到宝石和血瓶（奖励都在怪物身后）', () => {
    DEMO_POOLS.forEach(pool => pool.layouts.forEach((l, li) => l.variants.forEach((_, vi) => {
        const f = buildFloor(pool, { layout: li, variant: vi });
        const run = new Run([f]);
        const bait = pool === DEMO_POOLS[1]; // 第 2 层（原来的契约图）上的血瓶是故意摆在路上的
        const reach = new Set([run.pos]);
        const st = [run.pos];
        while (st.length) {
            const cur = st.pop()!;
            for (let n = 0; n < run.cells.length; n++) {
                const adj = Math.abs(n % run.w - cur % run.w) + Math.abs(Math.floor(n / run.w) - Math.floor(cur / run.w)) === 1;
                if (!adj || reach.has(n)) continue;
                const c = run.cells[n];
                const potion = c.kind === 'item' && (c.id === 'smallPotion' || c.id === 'bigPotion');
                if (c.kind === 'item' && !(bait && potion)) assert.ok(c.id === 'gold' || c.id === 'key', `${pool.params.name} ${l.name}${vi + 1} 白拿 ${c.id}`);
                if (c.kind === 'floor' || c.kind === 'item') { reach.add(n); st.push(n); }
            }
        }
    })));
});

test('第 1 层难度低：每张图都能不死地拿到所有加成，见怪就打的玩家也不会死', () => {
    const base = CHARACTERS.digger.base;
    const pool = DEMO_POOLS[0];
    pool.layouts.forEach((l, li) => l.variants.forEach((_, vi) => {
        const f = buildFloor(pool, { layout: li, variant: vi });
        const r = solveFromStart(f, base);
        assert.ok(r.bestAll && r.bestAll.hero.hp >= 150, `${l.name}${vi + 1}`);
        assert.ok(greedyFloor(f, base, undefined, 'clear'), `${l.name}${vi + 1}：见怪就打会死`);
    }));
});

test('层内检查：已经活着走不到出口时能发现', () => {
    const run = new Run([tiny(['@e>'])]);
    assert.deepEqual(run.floorCheck(), { canReachExit: true });
    run.hero.hp = 30;
    assert.deepEqual(run.floorCheck(), { canReachExit: false });
});

test('同一个种子选到同一组地图；新开一局换思路：每层换图，而且换一种布局', () => {
    assert.deepEqual(pickChoices(42), pickChoices(42));
    const L = (i: number, c: { layout: number }) => DEMO_POOLS[i].layouts[c.layout].name;
    for (let seed = 1; seed < 300; seed++) {
        const a = pickChoices(seed);
        const b = pickChoices(seed + 1000, DEMO_POOLS, a);
        b.forEach((c, i) => {
            const pool = DEMO_POOLS[i];
            const total = pool.layouts.reduce((n, l) => n + l.variants.length, 0);
            if (total > 1) assert.ok(c.layout !== a[i].layout || c.variant !== a[i].variant, `第 ${i + 1} 层换图`);
            if (pool.layouts.length > 1) assert.notEqual(L(i, c), L(i, a[i]), `第 ${i + 1} 层换布局`);
        });
    }
});

test('近路布局：最优走法用骨钥开近路，绕开主路的大怪', () => {
    for (const [pool, entry] of [[F2_CLASSIC, { ...CHARACTERS.digger.base, hp: 180, atk: 13, def: 13 }], [DEMO_POOLS[2], { ...CHARACTERS.digger.base, hp: 150, atk: 16, def: 13 }]] as const) {
        const li = pool.layouts.findIndex(l => l.name === '近路');
        for (const vi of [0, 1]) {
            const f = buildFloor(pool, { layout: li, variant: vi });
            const p = parseFloor(f);
            const plan = solveFromStart(f, entry).best!.plan;
            assert.ok(plan.some(i => p.cells[i].kind === 'door' && (p.cells[i] as { door: string }).door === 'bone'), `${pool.params.name} 近路${vi + 1} 没走近路`);
            const guard = p.cells.findIndex((c, i) => c.kind === 'monster' && Math.floor(i / p.w) === 3 && i % p.w === 8);
            assert.ok(!plan.includes(guard), `${pool.params.name} 近路${vi + 1} 还是打了主路大怪`);
        }
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
    assert.deepEqual(back.floorStartHero, CHARACTERS.digger.base);
});

test('按求解器的路线实际玩，结果和求解器一致', () => {
    // 挑一组不签契约也走得通的选图
    const choices = allChoices().find(c => {
        let h = { ...CHARACTERS.digger.base };
        for (const f of buildFloors(c)) { const r = solveFromStart(f, h); if (!r.best) return false; h = r.best.hero; }
        return true;
    })!;
    const floors = buildFloors(choices);
    const run = new Run(floors);
    for (let i = 0; i < floors.length; i++) {
        const r = solveFromStart(floors[i], { ...run.hero });
        for (const cell of r.best!.plan) assert.ok(run.tapCell(cell).ok, `第 ${i + 1} 层格子 ${cell}`);
        run.tapCell(run.cells.findIndex(c => c.kind === 'exit'));
        assert.equal(run.status, 'floorDone');
        assert.equal(run.hero.hp, r.best!.hero.hp);
        assert.equal(run.hero.gold, r.best!.hero.gold, `第 ${i + 1} 层：求解器算的金币和实际一致（含怪物掉落）`);
        if (run.pendingEngrave) run.skipEngrave();
        if (run.rentDue()) assert.ok(run.payRent(run.hero.gold >= run.rentDue() ? 'gold' : 'def').ok);
        run.finishFloor(false);
    }
    assert.equal(run.status, 'finished');
});

// ---------- 武器 ----------

test('武器：效果算进战斗预览，和实际结算一致', () => {
    const base = { atk: 19, def: 16 };
    const plain = simulateCombat(base, MONSTERS.guardian).damage;
    assert.ok(simulateCombat({ ...base, weapon: 'boneKnife' }, MONSTERS.guardian).damage < plain, '骨刀攻击 +4');
    assert.ok(simulateCombat({ ...base, weapon: 'hammer' }, MONSTERS.guardian).damage < plain, '破壳锤无视 4 点防御');
    assert.equal(simulateCombat({ atk: 13, def: 13 }, MONSTERS.beetle).canAttack, false);
    assert.equal(simulateCombat({ atk: 13, def: 13, weapon: 'hammer' }, MONSTERS.beetle).canAttack, true, '破壳锤能打动锈甲虫');
    assert.ok(simulateCombat({ ...base, weapon: 'harpoon' }, MONSTERS.moss).hits >= 2);
    assert.ok(simulateCombat({ atk: 13, def: 13, weapon: 'bellStaff' }, MONSTERS.bat).damage < simulateCombat({ atk: 14, def: 13 }, MONSTERS.bat).damage, '铃杖让先攻失效');
    assert.equal(simulateCombat({ atk: 16, def: 16 }, MONSTERS.wraith).canWin, false);
    assert.equal(simulateCombat({ atk: 16, def: 16, weapon: 'saltDagger' }, MONSTERS.wraith).canWin, true, '盐晶匕首克溺魂');
    // 苔衣短剑：击杀回血
    const run = new Run([tiny(['@m>'])]);
    run.hero.weapon = 'mossBlade';
    const before = run.hero.hp;
    const dmg = run.info(1).combat!.damage;
    run.move(1, 0);
    assert.equal(run.hero.hp, before - dmg + 8);
});

test('井租：不交不能下楼；可以用金币、攻击或防御交', () => {
    const mk = () => new Run([{ ...tiny(['@>']), rent: 30 }, tiny(['@>'])]);
    const a = mk();
    a.move(1, 0);
    a.finishFloor(false);
    assert.equal(a.floorIndex, 0, '没交井租不能下楼');
    assert.equal(a.payRent('gold').ok, false, '金币不够');
    assert.ok(a.payRent('atk').ok);
    assert.equal(a.hero.atk, 7);
    a.finishFloor(false);
    assert.equal(a.floorIndex, 1);
    const b = mk();
    b.hero.gold = 50;
    b.move(1, 0);
    assert.ok(b.payRent('gold').ok);
    assert.equal(b.hero.gold, 20);
});

test('求解器：血瓶不再强制喝掉——签了"不喝血瓶"或想留着时，不喝的走法也算得到', () => {
    // 血瓶在支路上：不喝也能走到出口
    const f = tiny(['@.>', 'h..']);
    const r = solveFromStart(f, CHARACTERS.digger.base);
    const drank = (o: { plan: number[] }) => o.plan.includes(3);
    assert.ok(r.best && drank(r.best), '生命最多的走法会喝');
    // 带着金币比较时，不喝药的结果不会被"喝了药的"压掉（求解器给出的 pareto 里至少有一条路线）
    assert.ok(r.pareto.length >= 1);
});

test('求解器：跨层比较时算上金币（血少但钱多的结果不会被丢掉）', () => {
    const rich = { hp: 100, atk: 10, def: 10, keys: 0, gold: 80 };
    const healthy = { hp: 120, atk: 10, def: 10, keys: 0, gold: 0 };
    assert.equal(paretoFilter([rich, healthy]).length, 2);
});

// ---------- 新怪：群居、腐蚀、庇护 ----------

test('腐蚀：怪物每打中一下，主角这一仗的防御 −1', () => {
    // 攻 10 防 10 打 生命 30 攻 15 防 2 的腐蚀怪：每下 8，要 4 下；怪物还手 3 次：5、6、7
    assert.equal(simulateCombat(hero, mk(['corrode'])).damage, 5 + 6 + 7);
    assert.equal(simulateCombat(hero, mk([])).damage, 15);
});

test('群居：每有一只相邻的井鼠，攻击 +5；先打边上的，中间那只就便宜', () => {
    const f = tiny(['@www>']);
    const run = new Run([f], 'digger', 1);
    assert.equal(run.monsterAt(1).atk, 34 + 5);
    assert.equal(run.monsterAt(2).atk, 34 + 10);
    assert.equal(run.monsterAt(3).atk, 34 + 5);
});

test('庇护：相邻的其他怪物防御 +6，几只祭司围着也只加一次；打掉祭司就降回去', () => {
    const f = tiny(['@pKp>', '#####']);
    const run = new Run([f], 'digger', 1);
    assert.equal(run.monsterAt(2).def, 24 + 6, '守门人两边各一只祭司：防御 30（原案）');
    assert.equal(run.monsterAt(1).def, 22, '祭司身边没有别的祭司');
    run.hero = { hp: 9999, atk: 60, def: 60, keys: 0, gold: 0 };
    run.move(1, 0);
    assert.equal(run.monsterAt(2).def, 30, '另一边的祭司还在');
    const r = tiny(['@pp>']);
    const run2 = new Run([r], 'digger', 1);
    assert.equal(run2.monsterAt(1).def, 28, '两只祭司互相庇护');
});

test('求解器：庇护和群居按"还活着的邻居"算，先拆祭司的路线更省血', () => {
    // 祭司在支路上，守门人挡路：先绕去打祭司，再打守门人
    const f = tiny(['@.K>', '.p###', '.....'].map(s => s.padEnd(5, '#')));
    const h = { hp: 2000, atk: 50, def: 30, keys: 0, gold: 0 };
    const r = solveFromStart(f, h);
    assert.ok(r.best);
    const plan = r.best!.plan;
    const priest = 6;
    const gate = 2;
    assert.ok(plan.indexOf(priest) >= 0 && plan.indexOf(priest) < plan.indexOf(gate), '先拆祭司');
    // 和"直接打守门人"的生命对比
    const direct = simulateCombat(h, { ...MONSTERS.gatekeeper, def: 30 }).damage;
    const viaPriest = simulateCombat(h, MONSTERS.priest).damage + simulateCombat(h, MONSTERS.gatekeeper).damage;
    assert.equal(r.best!.hero.hp, h.hp - Math.min(direct, viaPriest));
});


// ---------- 断臂转轮版（设计方案第二十五章） ----------
import { newArm, armOdds, armOutcome, armHoldOdds, engraveCell } from '../src/core/arm';
const reels = (...rs: (WeaponId | null)[][]) => rs.map(r => [...r, ...Array(5 - r.length).fill(null)]);
import { WHEEL } from '../src/core/wheel';
import { DECREES, decreeFor } from '../src/core/decree';
import { whisper } from '../src/core/whisper';
import { buildRoute, buildTutorial, RENTS } from '../src/core/route';
import { solveChain as chain2 } from '../src/core/solver';

test('断臂转轮：开局是空的，打败印记怪可以刻武器，刻上就拿在手上', () => {
    const run = new Run([{ ...tiny(['@e.>']), marks: [1] }], 'digger', 1);
    assert.deepEqual(run.arm!.reels, reels([], [], []));
    assert.equal(run.armSpin('gold').ok, false, '没刻图案不能转');
    run.hero.atk = 30;
    run.move(1, 0);
    assert.deepEqual(run.pendingEngrave, { from: 'mark', choices: ['harpoon'] });
    assert.ok(run.engrave('harpoon', 1).ok, '刻在第 2 个轮子上');
    assert.equal(run.hero.weapon, 'harpoon', '刻上就拿在手上');
    assert.deepEqual(run.arm!.reels, reels([], ['harpoon'], []));
    assert.equal(run.arm!.stops[1], 0, '刻的那个轮子转到这一格');
    assert.equal(run.pendingEngrave, null);
});

test('断臂转轮：三个轮子各 5 格；概率是三个轮子上各自占的比例相乘；只看中间一行', () => {
    const arm = newArm();
    assert.equal(arm.reels.length, 3);
    assert.ok(arm.reels.every(r => r.length === 5));
    engraveCell(arm, 0, 'boneKnife');
    assert.equal(armOdds(arm, 'boneKnife'), 0, '只有一个轮子上有，连不成一线');
    engraveCell(arm, 1, 'boneKnife');
    engraveCell(arm, 2, 'boneKnife');
    assert.equal(armOdds(arm, 'boneKnife'), 1 / 125, '三个轮子各 1 格：0.8%');
    engraveCell(arm, 0, 'boneKnife');
    assert.equal(armOdds(arm, 'boneKnife'), 2 / 125);
    assert.equal(armOdds(arm, null), (3 * 4 * 4) / 125, '三个都停在空格上');
    arm.stops = [0, 0, 0];
    assert.deepEqual(armHoldOdds(arm, [true, true, false]), { target: 'boneKnife', p: 1 / 5 }, '锁住两个，剩下那个轮子 1/5');
    assert.deepEqual(armOutcome(['hammer', 'hammer', 'hammer']), { kind: 'weapon', id: 'hammer' });
    assert.deepEqual(armOutcome([null, null, null]), { kind: 'empty' });
    assert.deepEqual(armOutcome(['hammer', null, 'hammer']), { kind: 'none' });
});

test('断臂转轮：价格每层从 10 金起每次 ×1.5，换层重算；锁轴半价；结果由种子决定', () => {
    const plan = [tiny(['@.>']), tiny(['@.>'])];
    const run = new Run(plan, 'digger', 7);
    run.arm!.reels = reels(['boneKnife'], [null, 'hammer'], ['hammer', 'boneKnife']);
    run.hero.gold = 500;
    assert.equal(run.armPrice(false).gold, 10);
    const a = run.armSpin('gold');
    assert.ok(a.ok && a.faces!.length === 3);
    assert.equal(run.armPrice(false).gold, 15);
    assert.equal(run.armPrice(true).gold, 10, '锁轴半价（取到 5 的倍数）');
    assert.equal(run.hero.gold, 490);
    const kept = run.arm!.stops[0];
    run.armSpin('gold', [true, false, false]);
    assert.equal(run.arm!.stops[0], kept, '锁住的轮子不动');
    assert.equal(run.armSpin('gold', [true, true, true]).ok, false, '不能三个都锁');
    // 同一个种子同样的操作，结果一样
    const run2 = new Run(plan, 'digger', 7);
    run2.arm!.reels = reels(['boneKnife'], [null, 'hammer'], ['hammer', 'boneKnife']);
    run2.hero.gold = 500;
    assert.deepEqual(run2.armSpin('gold').faces, a.faces);
    // 换层后价格重算
    run.move(1, 0); run.move(1, 0);
    run.finishFloor(false);
    assert.equal(run.armPrice(false).gold, 10);
    // 用生命付 ×1.5
    assert.equal(run.armPrice(false).blood, 15);
});

test('断臂转轮：一个轮子刻满 5 格后再刻要选一格覆盖；精英倒下三选一', () => {
    const run = new Run([{ ...tiny(['@G>']), eliteReward: true }], 'digger', 3);
    run.arm!.reels = reels(['boneKnife', 'hammer', 'harpoon', 'boneKnife', 'hammer'], [], []);
    run.hero = { hp: 999, atk: 60, def: 60, keys: 0, gold: 0 };
    run.move(1, 0);
    const p = run.pendingEngrave!;
    assert.equal(p.from, 'elite');
    assert.equal(p.choices.length, 3);
    assert.equal(run.engrave(p.choices[0], 0).ok, false, '第 1 个轮子刻满了要选格子');
    assert.ok(run.engrave(p.choices[0], 0, 3).ok);
    assert.equal(run.arm!.reels[0][3], p.choices[0]);
});

test('骨坛移来的特性：先攻多打一下、反伤、腐蚀、吸血（不超过这一仗掉的血）', () => {
    const base = { atk: 20, def: 10 };
    const m = MONSTERS.frog; // 60 / 22 / 8
    const plain = simulateCombat(base, m);
    assert.ok(simulateCombat({ ...base, boons: ['firstStrike'] }, m).damage < plain.damage);
    assert.ok(simulateCombat({ ...base, boons: ['corrode'] }, m).damage <= plain.damage);
    assert.ok(simulateCombat({ ...base, boons: ['thorns'] }, MONSTERS.guardian).damage <= simulateCombat(base, MONSTERS.guardian).damage);
    const ls = simulateCombat({ atk: 60, def: 60, boons: ['lifesteal'] }, MONSTERS.moss);
    assert.equal(ls.damage, 0, '吸血回复不会超过掉的血');
});

test('骨坛：要杀过对应的怪、转轮上有这把武器；献攻击或骨钥；每座用一次', () => {
    const run = new Run([tiny(['@v.A>'])], 'digger', 1);
    run.hero = { hp: 999, atk: 40, def: 40, keys: 1, gold: 0 };
    run.arm!.reels = reels([], ['boneKnife'], []);
    run.move(1, 0); // 打回声蝠：学到先攻
    assert.deepEqual(run.boonsSeen, ['firstStrike']);
    run.move(1, 0);
    assert.equal(run.altarOffer(3, 'atk', 'lifesteal', 'boneKnife').ok, false, '没杀过溺魂');
    assert.equal(run.altarOffer(3, 'atk', 'firstStrike', 'hammer').ok, false, '转轮上没有破壳锤');
    assert.ok(run.altarOffer(3, 'key', 'firstStrike', 'boneKnife').ok);
    assert.equal(run.hero.keys, 0);
    assert.deepEqual(run.arm!.boons.boneKnife, ['firstStrike']);
    assert.equal(run.altarOffer(3, 'atk', 'firstStrike', 'boneKnife').ok, false, '用过了');
});

test('大转盘：盘面 8 格公开；30 金起每次 ×1.5；擦图案、井蛭；由种子决定', () => {
    assert.equal(WHEEL.length, 8);
    const run = new Run([tiny(['@S>'])], 'digger', 5);
    run.hero.gold = 1000;
    run.hero.hp = 5000;
    run.arm!.reels = reels(['boneKnife', 'hammer'], ['hammer'], []);
    assert.equal(run.wheelPrice(1).gold, 30);
    const seen = new Set<number>();
    for (let k = 0; k < 40; k++) {
        const r = run.wheelSpin(1, k % 2 ? 'gold' : 'blood');
        if (!r.ok) break;
        seen.add(r.sector!);
        run.engraveQueue = [];
    }
    assert.ok(seen.size >= 5, '转得够多时大部分格子都会出现');
    assert.equal(run.wheelState(1).spins > 3, true);
});

test('当铺：卖骨钥、当图案（赎回价每层涨 20%）、买图案、擦图案；不收攻防', () => {
    const plan = [{ ...tiny(['@.>', 'N..']), shop: ['hammer', 'harpoon'] as WeaponId[] }, { ...tiny(['@.>', 'N..']), shop: ['boneKnife', 'harpoon'] as WeaponId[] }];
    const run = new Run(plan, 'digger', 1);
    run.hero.gold = 200; run.hero.keys = 1;
    run.arm!.reels = reels([], ['boneKnife'], []);
    run.hero.weapon = 'boneKnife';
    assert.ok(run.pawnSellKey(3).ok);
    assert.equal(run.hero.gold, 215);
    assert.ok(run.pawnCell(3, 1, 0).ok);
    assert.equal(run.hero.gold, 255);
    assert.equal(run.hero.weapon, undefined, '当掉手上这把就空手了');
    assert.ok(run.pawnBuy(3, 0, 2).ok);
    assert.equal(run.arm!.reels[2][0], 'hammer');
    assert.equal(run.pawnBuy(3, 0, 2).ok, false, '每样只卖一次');
    assert.ok(run.pawnErase(3, 2, 0).ok);
    assert.deepEqual(run.arm!.reels, reels([], [], []));
    run.move(1, 0); run.move(1, 0);
    run.finishFloor(false);
    assert.equal(run.redeemPrice(0), 48, '过了一层：40 × 1.2');
    assert.ok(run.pawnRedeem(3, 0).ok);
    assert.equal(run.arm!.reels[1][0], 'boneKnife', '赎回刻回原来那个轮子');
    assert.equal(run.hero.weapon, 'boneKnife');
});

test('诏令：第 3 层开头送来，可以拒绝；完成给刻图案；逾期攻击 −2 / −4', () => {
    const plan = Array.from({ length: 6 }, () => tiny(['@.>', 'm..']));
    const offered = decreeFor(1, 2);
    assert.ok(offered && DECREES.includes(offered));
    assert.equal(decreeFor(1, 3), null);
    const run = new Run(plan, 'digger', 1);
    const next = () => { run.tapCell(run.cells.findIndex(c => c.kind === 'exit')); run.finishFloor(false); };
    next(); next();
    assert.equal(run.floorIndex, 2);
    assert.ok(run.decreeOffer);
    run.decreeOffer = { kind: 'gold', tier: 'silver', n: 9999, text: '带着至少 9999 金币走出一层' };
    assert.ok(run.acceptDecree().ok);
    const atk = run.hero.atk;
    next(); next(); next();
    assert.equal(run.hero.atk, atk - 4, '三层没完成，银诏令攻击 −4');
    assert.equal(run.decree, null);
    // 完成：不喝药的那一层
    const r2 = new Run(plan, 'digger', 1);
    r2.decreeOffer = DECREES.find(d => d.kind === 'noPotion')!;
    r2.acceptDecree();
    r2.tapCell(r2.cells.findIndex(c => c.kind === 'exit'));
    r2.finishFloor(false);
    assert.equal(r2.decree, null);
    assert.equal(r2.pendingEngrave?.from, 'decree');
});

test('楼梯口的一句话：只说大概有多凶，设施层没有专门的句子', async () => {
    const { WHISPERS } = await import('../src/core/whisper');
    assert.ok(WHISPERS.loud.includes(whisper(tiny(['@G>']))));
    assert.ok(WHISPERS.loud.includes(whisper(tiny(['@mmmmmmmm>']))));
    assert.ok(WHISPERS.quiet.includes(whisper(tiny(['@m>']))));
    assert.ok(WHISPERS.quiet.includes(whisper({ ...tiny(['@S>']), kind: 'wheel' })), '大转盘层和怪少的普通层说法一样');
    for (const s of [...WHISPERS.loud, ...WHISPERS.quiet, ...WHISPERS.mid]) assert.doesNotMatch(s, /转盘|当铺|骨坛|营火|精英|\d/);
});

test('路线：由种子决定；第 3 层起每层两条楼梯（第 10、19、20 层固定）；第 9、17 层交井租', () => {
    const a = buildRoute(42);
    assert.deepEqual(a.map(o => o.map(f => f.map.join(''))), buildRoute(42).map(o => o.map(f => f.map.join(''))));
    assert.equal(a.length, 20);
    a.forEach((opts, d) => assert.equal(opts.length, [0, 1, 9, 18, 19].includes(d) ? 1 : 2, `第 ${d + 1} 层`));
    for (const [d, rent] of Object.entries(RENTS)) for (const f of a[+d]) assert.equal(f.rent, rent);
    assert.ok(a[0][0].marks?.length, '第 1 层一定有印记怪，帮玩家拿到第一把武器');
    for (const opts of a) for (const f of opts) parseFloor(f);
});

test('路线：几种选法都能一路求解到井底（保守下限）', () => {
    for (const seed of [1, 2, 3]) {
        const plan = buildRoute(seed);
        for (const k of [0, 1]) {
            const c = chain2(plan.map(o => o[Math.min(k, o.length - 1)]));
            assert.equal(c.length, 20, `种子 ${seed} 选法 ${k}`);
            assert.ok(c[19].best && c[19].best.hp > 0);
        }
    }
});

test('新手教程局：5 层、没有断臂转轮、没有诏令，第 5 层的井底之眼打不过', () => {
    const plan = buildTutorial(1);
    assert.equal(plan.length, 5);
    const run = new Run(plan, 'digger', 1, { tutorial: true });
    assert.equal(run.arm, null);
    assert.equal(run.decreeOffer, null);
    const last = plan[4][0];
    const r = solveFromStart(last, { hp: 2000, atk: 30, def: 30, keys: 0, gold: 0 });
    assert.equal(r.solvable, false, '按教程能达到的属性打不过井底之眼');
});

test('存档读档：断臂转轮、当铺、诏令、选过的楼梯都保留', () => {
    const plan = buildRoute(9);
    const run = new Run(plan, 'digger', 9);
    run.arm!.reels = reels(['hammer'], [null, 'boneKnife'], ['boneKnife']);
    run.hero.gold = 100;
    run.armSpin('gold');
    run.pawned.push({ weapon: 'harpoon', reel: 2, floor: 0 });
    const back = Run.load(plan, JSON.parse(JSON.stringify(run.save())));
    assert.deepEqual(back.arm, run.arm);
    assert.deepEqual(back.pawned, run.pawned);
    assert.deepEqual(back.hero, run.hero);
    assert.equal(back.floor.map.join(''), run.floor.map.join(''));
});
