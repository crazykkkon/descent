-- 对账测试：用 TypeScript 原型导出的标准算例（tests/vectors.lua）逐条检查 Lua 版的规则。
-- 用法（在 love/ 目录下）：luajit tests/run.lua
package.path = 'src/?.lua;' .. package.path

local config = require('core.config')
local combat = require('core.combat')
local Run = require('core.run')
local serialize = require('core.serialize')
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
for _, sc in ipairs(V.scenarios) do
    local f = sc.floor
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

-- 3. 硬打致死
for _, d in ipairs(V.deaths) do
    local run = Run.new({ { name = 't', map = d.map, bloodCost = 40, gem = 2, smallPotion = 50, bigPotion = 150, gold = 20 } }, 'digger', 1)
    run.hero.hp = d.hp
    local r = run:step(2)
    check(r.ok == d.ok and run.status == d.status and run.hero.hp == d.heroHp, '硬打 ' .. d.monster)
end

print(string.format('对账：%d 条一致，%d 条不一致（战斗 %d 条、楼层 %d 条、致死 %d 条）', pass, fail, #V.combat, #V.scenarios, #V.deaths))
os.exit(fail == 0 and 0 or 1)
