import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CHARACTERS, MONSTERS, MonsterDef } from '../src/core/config';
import { simulateCombat } from '../src/core/combat';
import { FloorDef } from '../src/core/floor';
import { Run } from '../src/core/game';
import { DEMO_POOLS, F2_CLASSIC, allChoices, buildFloor, buildFloors, pickChoices } from '../src/core/levels';
import { keepVersion } from '../src/core/contract';
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
    // 没有重开本层：死了就只能整局重来
    assert.equal((r2 as unknown as Record<string, unknown>).restartFloor, undefined);
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

test('关卡结构：第 1 层 3 布局 × 2 套；第 2 层 3 张契约图；第 3 层 4 布局 × 2 套；同一布局两套墙壁一样', () => {
    assert.deepEqual(DEMO_POOLS.map(p => p.layouts.length), [3, 3, 4]);
    for (const pool of DEMO_POOLS) {
        for (const l of pool.layouts) {
            if (l.variants.length < 2) continue;
            const shape = (m: string[]) => m.map(r => r.replace(/[^#@>]/g, '.')).join('|');
            assert.equal(shape(l.variants[0].map), shape(l.variants[1].map), `${pool.params.name} ${l.name}`);
            assert.notEqual(l.variants[0].map.join(), l.variants[1].map.join());
        }
    }
    // 契约图：每张都挂着同一份契约、同一句情报，且情报是真话（正好两瓶血瓶）
    const f2 = DEMO_POOLS[1].layouts.map((l, li) => buildFloor(DEMO_POOLS[1], { layout: li, variant: 0 }));
    for (const f of f2) {
        assert.ok(f.contract && f.intel);
        assert.deepEqual(f.contract, f2[0].contract);
        assert.equal(f.intel, f2[0].intel);
        const potions = parseFloor(f).cells.filter(c => c.kind === 'item' && (c.id === 'smallPotion' || c.id === 'bigPotion')).length;
        assert.equal(potions, 2, f.map.join('|'));
    }
    // 原来的第 2 层先收起来，近路布局还在第 3 层和备用池里
    assert.equal(F2_CLASSIC.layouts.length, 4);
});

test('开局不打怪就拿不到宝石和血瓶（奖励都在怪物身后）', () => {
    DEMO_POOLS.forEach(pool => pool.layouts.forEach((l, li) => l.variants.forEach((_, vi) => {
        const f = buildFloor(pool, { layout: li, variant: vi });
        const run = new Run([f]);
        const bait = !!f.contract; // 契约图上的血瓶是故意摆在路上的诱惑
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

test('契约图的手调价格：三张图各自让拒签、守约、毁约中的一种最划算', () => {
    const entry = { ...CHARACTERS.digger.base, hp: 150, atk: 13, def: 13 };
    const out = (li: number) => {
        const f = buildFloor(DEMO_POOLS[1], { layout: li, variant: 0 });
        const c = f.contract!;
        const signed = { ...entry, hp: entry.hp - c.deposit, atk: entry.atk + c.atk };
        const refuse = solveFromStart(f, entry).best?.hero.hp ?? -1;
        const k = solveFromStart(keepVersion(f), signed).best;
        const keep = k ? k.hero.hp + c.refund : -1;
        const brk = solveFromStart(f, signed).best?.hero.hp ?? -1;
        return { refuse, keep, brk };
    };
    const L = (name: string) => DEMO_POOLS[1].layouts.findIndex(l => l.name === name);
    const a = out(L('侧厅'));
    assert.ok(a.keep > a.refuse && a.keep > a.brk, JSON.stringify(a));
    const b = out(L('长廊'));
    assert.ok(b.brk > b.keep, JSON.stringify(b));
    assert.ok(Math.abs(b.brk - b.refuse) <= 20, `长廊图上毁约和拒签应该接近：${JSON.stringify(b)}`);
    const c = out(L('双道'));
    assert.ok(c.refuse > c.keep && c.refuse > c.brk, JSON.stringify(c));
    // 拿第 1 层全部加成出来的玩家，三张图拒签都能活着过去
    DEMO_POOLS[0].layouts.forEach((l, li) => l.variants.forEach((_, vi) => {
        const e = solveFromStart(buildFloor(DEMO_POOLS[0], { layout: li, variant: vi }), CHARACTERS.digger.base).bestAll!.hero;
        DEMO_POOLS[1].layouts.forEach((m, mi) => assert.ok(solveFromStart(buildFloor(DEMO_POOLS[1], { layout: mi, variant: 0 }), e).solvable, `${l.name}${vi + 1} → ${m.name}`));
    }));
});

test('契约：签约扣押金、属性立刻生效；喝血瓶毁约；守约到出口退还', () => {
    const c = { condition: 'noPotion' as const, deposit: 50, atk: 3, def: 0, refund: 60, gold: 10 };
    const mk = () => new Run([tiny(['@>']), { ...tiny(['@h.>']), contract: c, intel: '下一层有一瓶血瓶。' }, tiny(['@>'])]);
    // 守约
    const a = mk();
    assert.deepEqual(a.offeredContract(), c);
    assert.equal(a.nextFloorIntel()!.headline, '下一层有一瓶血瓶。');
    a.move(1, 0); a.finishFloor(false, true);
    assert.equal(a.hero.hp, 150);
    assert.equal(a.hero.atk, 13);
    assert.ok(a.contractActive());
    const saved = JSON.parse(JSON.stringify(a.save()));
    // 存档读档后契约还在
    assert.ok(Run.load(a.floors, saved).contractActive());
    // 血瓶挡在路上：走过去就喝了，契约当场毁掉
    a.move(1, 0);
    assert.equal(a.contractActive(), false);
    // 绕得开血瓶的图：守约
    const b = new Run([tiny(['@>']), { ...tiny(['@.>', 'h..']), contract: c }, tiny(['@>'])]);
    b.move(1, 0); b.finishFloor(false, true);
    b.move(1, 0); b.move(1, 0);
    assert.equal(b.exitSummary().contract!.kept, true);
    b.finishFloor(false);
    assert.equal(b.hero.hp, 150 + 60);
    assert.equal(b.hero.gold, 10 + 5, '守约奖励 10 金 + 地图上剩一瓶血瓶换 5 金');
    assert.equal(b.hero.atk, 13, '宝石留着');
    // 毁约：喝下血瓶那一刻
    const d = new Run([tiny(['@>']), { ...tiny(['@.>', 'h..']), contract: c }, tiny(['@>'])]);
    d.move(1, 0); d.finishFloor(false, true);
    const r = d.move(0, 1);
    assert.match(r.msg, /契约已毁/);
    assert.equal(d.contractActive(), false);
    d.move(1, 0); d.move(1, 0); d.move(0, -1);
    d.finishFloor(false);
    assert.equal(d.hero.hp, 150 + 50, '押金不退，血瓶照喝');
    assert.equal(d.hero.atk, 13);
    // 不签
    const e = mk();
    e.move(1, 0); e.finishFloor(false, false);
    assert.equal(e.hero.hp, 200);
    assert.equal(e.contract, null);
    // 押不起就签不了
    const g = mk();
    g.hero.hp = 40;
    g.move(1, 0); g.finishFloor(false, true);
    assert.equal(g.contract, null);
    assert.equal(g.hero.hp, 40);
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

test('层内检查：已经活着走不到出口时能发现', () => {
    const run = new Run([tiny(['@e>'])]);
    assert.deepEqual(run.floorCheck(), { canReachExit: true });
    run.hero.hp = 30;
    assert.deepEqual(run.floorCheck(), { canReachExit: false });
});

test('所有选图组合都能通关', () => {
    for (const c of allChoices()) assert.ok(solveRun(buildFloors(c)).bestHp > 0, JSON.stringify(c));
});

test('同一个种子选到同一组地图；新开一局换思路：每层换图，而且换一种布局', () => {
    assert.deepEqual(pickChoices(42), pickChoices(42));
    const L = (i: number, c: { layout: number }) => DEMO_POOLS[i].layouts[c.layout].name;
    for (let seed = 1; seed < 300; seed++) {
        const a = pickChoices(seed);
        const b = pickChoices(seed + 1000, DEMO_POOLS, a);
        b.forEach((c, i) => {
            assert.ok(c.layout !== a[i].layout || c.variant !== a[i].variant);
            assert.notEqual(L(i, c), L(i, a[i]), `第 ${i + 1} 层换布局`);
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
        run.finishFloor(false);
    }
    assert.equal(run.status, 'finished');
});
