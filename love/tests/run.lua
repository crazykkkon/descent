-- 对账测试：用 TypeScript 原型导出的标准算例（tests/vectors.lua）逐条检查 Lua 版的规则。
-- 用法（在 love/ 目录下）：luajit tests/run.lua
package.path = 'src/?.lua;' .. package.path

local config = require('core.config')
local combat = require('core.combat')
local Run = require('core.run')
local serialize = require('core.serialize')
local slot = require('core.slot')
local intel = require('core.intel')
local floorMod = require('core.floor')
local levels = require('core.levels')
local contractMod = require('core.contract')
local mainline = require('data.mainline')
local V = dofile('tests/vectors.lua')

local pass, fail = 0, 0
local function check(cond, what)
    if cond then pass = pass + 1 else
        fail = fail + 1
        if fail <= 20 then print('不一致：' .. what) end
    end
end

-- 1. 战斗算例
for _, c in ipairs(V.combat) do
    local r = combat.simulate({ atk = c.atk, def = c.def, weapon = c.weapon }, config.MONSTERS[c.monster])
    local tag = string.format('%s 攻%d防%d %s', c.monster, c.atk, c.def, c.weapon or '无武器')
    check(r.canAttack == c.canAttack and r.canWin == c.canWin and r.damage == c.damage and r.hits == c.hits,
        string.format('战斗 %s：期望 %s/%s/%d/%d，实际 %s/%s/%d/%d', tag,
            tostring(c.canAttack), tostring(c.canWin), c.damage, c.hits,
            tostring(r.canAttack), tostring(r.canWin), r.damage, r.hits))
end

-- 2. 楼层逐步算例（原型的格子下标从 0 开始，这里 +1）
local function heroEq(h, e)
    return h.hp == e.hp and h.atk == e.atk and h.def == e.def and h.keys == e.keys and h.gold == e.gold
end
local function runScenario(sc)
    local f = sc.floor
    f.stall, f.eliteReward = sc.stall, sc.eliteReward or f.eliteReward
    f.contract = sc.contract
    local entryFloor = { name = 'entry', map = { '@>' }, bloodCost = f.bloodCost, gem = f.gem, smallPotion = f.smallPotion, bigPotion = f.bigPotion, gold = f.gold }
    local run = Run.new({ entryFloor, f }, 'digger', 1)
    run.hero = config.copyHero(sc.entry)
    run:step(2)
    run:finishFloor(false, sc.sign)
    check(heroEq(run.hero, sc.start), sc.name .. '：签约后入场属性')
    for k, st in ipairs(sc.steps) do
        local r = run:step(st.cell + 1)
        local ok = r.ok == st.ok and run.hero.hp == st.hp and run.hero.atk == st.atk and run.hero.def == st.def
            and run.hero.keys == st.keys and run.hero.gold == st.gold and run.pos == st.pos + 1
            and run.status == st.status and run:contractActive() == st.contractActive
        check(ok, string.format('%s 第 %d 步（格子 %d）：期望 生命%d 金%d 位置%d %s 契约%s，实际 生命%d 金%d 位置%d %s 契约%s',
            sc.name, k, st.cell, st.hp, st.gold, st.pos, st.status, tostring(st.contractActive),
            run.hero.hp, run.hero.gold, run.pos - 1, run.status, tostring(run:contractActive())))
        -- 每一步都存档再读回来，检查存档没有丢东西
        local back = Run.load(run.floors, serialize.load(serialize.dump(run:save())))
        check(heroEq(back.hero, run.hero) and back.pos == run.pos and back.status == run.status and back:contractActive() == run:contractActive(),
            sc.name .. ' 第 ' .. k .. ' 步：存档读档后状态变了')
        run = back
    end
    local s = run:exitSummary()
    check((s.contract and s.contract.kept) == sc.exit.kept and s.leftoverPotions == sc.exit.leftoverPotions and s.potionGold == sc.exit.potionGold,
        sc.name .. '：出口结算 实际 剩药' .. s.leftoverPotions .. ' 契约' .. tostring(s.contract and s.contract.kept))
    if sc.rentMethod then run:payRent(sc.rentMethod) end
    run:finishFloor(false, false)
    check(heroEq(run.hero, sc.final) and run.status == sc.final.status,
        string.format('%s：结算后 期望 生命%d 金%d %s，实际 生命%d 金%d %s', sc.name, sc.final.hp, sc.final.gold, sc.final.status, run.hero.hp, run.hero.gold, run.status))
end

for _, sc in ipairs(V.scenarios) do runScenario(sc) end

-- 2b. 新怪：按周围格子算出的攻防
for _, mv in ipairs(V.monsterViews) do
    local run = Run.new({ { name = 't', map = mv.map, bloodCost = 40, gem = 2, smallPotion = 50, bigPotion = 150, gold = 20 } }, 'digger', 1)
    local m = run:monsterAt(mv.cell + 1)
    check(m.atk == mv.atk and m.def == mv.def, string.format('新怪 %s 格子%d：期望 攻%d防%d，实际 攻%d防%d', table.concat(mv.map, '/'), mv.cell, mv.atk, mv.def, m.atk, m.def))
end

-- 3. 硬打致死
for _, d in ipairs(V.deaths) do
    local run = Run.new({ { name = 't', map = d.map, bloodCost = 40, gem = 2, smallPotion = 50, bigPotion = 150, gold = 20 } }, 'digger', 1)
    run.hero.hp = d.hp
    local r = run:step(2)
    check(r.ok == d.ok and run.status == d.status and run.hero.hp == d.heroHp, '硬打 ' .. d.monster)
end

-- 4a. 井中轮转轮序列（随机数逐位一致）
for _, r in ipairs(V.rolls) do
    local st = slot.newState()
    for k, want in ipairs(r.seq) do
        local res = slot.roll(slot.SLOTS[r.machine], st, r.seed, r.key)
        local got = table.concat(res, ',')
        check(got == want, string.format('转轮 种子%d 键%d %s 第 %d 次：期望 %s，实际 %s', r.seed, r.key, r.machine, k, want, got))
    end
end

-- 4b. 井中轮完整操作（每一步都存档读档）
local function slotHeroEq(h, e)
    return heroEq(h, e) and h.weapon == e.weapon
end
for _, ss in ipairs(V.slotSessions) do
    local f = { name = 't', map = ss.map, bloodCost = 40, gem = 2, smallPotion = 50, bigPotion = 150, gold = 20 }
    local run = Run.new({ f }, 'digger', ss.seed)
    run:step(4)
    run.hero = { hp = 400, atk = 13, def = 13, keys = 0, gold = 300 }
    for k, st in ipairs(ss.steps) do
        local tag = string.format('井中轮 种子%d %s 脚本%d 第 %d 步', ss.seed, ss.machine, ss.script, k)
        if st.act == 'spin' then
            local r = run:slotSpin(5, st.pay, st.held)
            check(r.ok == st.ok and (r.result and table.concat(r.result, ',')) == st.result and r.bite == st.bite
                and slotHeroEq(run.hero, st.hero) and run:slotState(5).spins == st.spins and run.status == st.status,
                string.format('%s：期望 %s 咬%s 生命%d 金%d，实际 %s 咬%s 生命%d 金%d', tag, tostring(st.result), tostring(st.bite), st.hero.hp, st.hero.gold,
                    tostring(r.result and table.concat(r.result, ',')), tostring(r.bite), run.hero.hp, run.hero.gold))
        else
            local lines = run:slotCollect(5)
            check(table.concat(lines, '|') == table.concat(st.lines, '|') and slotHeroEq(run.hero, st.hero) and run.status == st.status,
                tag .. '：收下 期望 ' .. table.concat(st.lines, '|') .. '，实际 ' .. table.concat(lines, '|'))
        end
        run = Run.load(run.floors, serialize.load(serialize.dump(run:save())))
    end
end

-- 5. 精英倒下后的武器三选一
for _, wc in ipairs(V.weaponChoices) do
    local fs = {}
    for k = 1, wc.floorIndex do fs[k] = { name = 't', map = { '@>' }, bloodCost = 40, gem = 2, smallPotion = 50, bigPotion = 150, gold = 20 } end
    fs[wc.floorIndex] = { name = 't', map = { '@G>' }, bloodCost = 40, gem = 2, smallPotion = 50, bigPotion = 150, gold = 20, eliteReward = true }
    local run = Run.new(fs, 'digger', wc.seed)
    for _ = 1, wc.floorIndex - 1 do run:step(2); run:finishFloor(false) end
    run.hero = { hp = 999, atk = 60, def = 60, keys = 0, gold = 0, weapon = wc.current }
    run:step(2)
    local got = table.concat(run.pendingWeapons or {}, ',')
    local want = table.concat(wc.choices or {}, ',')
    check(got == want, string.format('武器三选一 种子%d 第%d层 现有%s：期望 %s，实际 %s', wc.seed, wc.floorIndex, tostring(wc.current), want, got))
end

-- 6. 楼梯口情报
for _, it in ipairs(V.intels) do
    local next = {}
    for k, v in pairs(it.floor) do next[k] = v end
    next.intelPick = { cell = it.intelPick.cell + 1, mustFight = it.intelPick.mustFight }
    local cur = it.current
    local r = intel.stairIntel(next, it.hero, config.CHARACTERS.digger, { floor = cur, cells = floorMod.parse(cur).cells })
    check(r and r.headline == it.headline and table.concat(r.lines, '|') == table.concat(it.lines, '|') and r.mustFight == it.mustFight,
        '情报 ' .. it.floor.name .. '：期望 ' .. it.headline .. ' / ' .. table.concat(it.lines, '|') .. '，实际 ' .. (r and (r.headline .. ' / ' .. table.concat(r.lines, '|')) or 'nil'))
end

-- 6b. 签约卡对照
for n, pv in ipairs(V.previews) do
    local rows = contractMod.preview(pv.floor, pv.hero, pv.contract)
    local function fmt(rs)
        local t = {}
        for _, r in ipairs(rs) do t[#t + 1] = r.name .. r.before .. '>' .. r.after .. '/' .. tostring(r.saved) end
        return table.concat(t, '|')
    end
    check(fmt(rows) == fmt(pv.rows), '签约对照 ' .. n .. ' ' .. pv.floor.name .. '：期望 ' .. fmt(pv.rows) .. '，实际 ' .. fmt(rows))
end

-- 7. 补给摊
for n, st in ipairs(V.stalls) do
    local f = st.floor
    f.stall = st.stall
    local run = Run.new({ f }, 'digger', 1)
    run.hero.gold = st.gold
    check(run:stallBuy(3, 1).ok == st.pre, '补给摊 ' .. n .. '：没走到旁边就能买')
    run:step(2)
    for k, x in ipairs(st.steps) do
        local r = run:stallBuy(3, x.k + 1)
        check(r.ok == x.ok and r.msg == x.msg and heroEq(run.hero, x.hero), string.format('补给摊 %d 第 %d 次：期望 %s，实际 %s', n, k, x.msg, r.msg))
        run = Run.load(run.floors, serialize.load(serialize.dump(run:save())))
    end
end

-- 8. 主线选图和逐层路线
for _, p in ipairs(V.picks) do
    local got = levels.pickChoices(p.seed, mainline.pools, p.avoid)
    local ok = #got == #p.choices
    for i, c in ipairs(p.choices) do ok = ok and got[i].layout == c.layout and got[i].variant == c.variant end
    check(ok, '主线选图 种子' .. p.seed)
end
for _, sc in ipairs(V.mainScenarios) do runScenario(sc) end

print(string.format('对账：%d 条一致，%d 条不一致（战斗 %d、楼层 %d、致死 %d、转轮 %d、井中轮 %d、三选一 %d、情报 %d、补给摊 %d、主线 %d 层）', pass, fail, #V.combat, #V.scenarios, #V.deaths, #V.rolls, #V.slotSessions, #V.weaponChoices, #V.intels, #V.stalls, #V.mainScenarios))
os.exit(fail == 0 and 0 or 1)
