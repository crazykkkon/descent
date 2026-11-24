-- 对账测试：用 TypeScript 原型导出的标准算例（tests/vectors.lua）逐条检查 Lua 版的规则。
-- 用法（在 love/ 目录下）：luajit tests/run.lua
package.path = 'src/?.lua;' .. package.path

local config = require('core.config')
local combat = require('core.combat')
local Run = require('core.run')
local serialize = require('core.serialize')
local decreeMod = require('core.decree')
local whisperMod = require('core.whisper')
local route = require('core.route')
local floorMod = require('core.floor')
local V = dofile('tests/vectors.lua')

local pass, fail = 0, 0
local function check(cond, what)
    if cond then pass = pass + 1 else
        fail = fail + 1
        if fail <= 25 then print('不一致：' .. what) end
    end
end

-- 原型导出的数组里有空值时写成 { [1]=..., n=3 }；这里统一读成 Lua 的列表，空值换成 false
local function list(t)
    if t == nil then return nil end
    local n = t.n or #t
    local o = {}
    for i = 1, n do
        local x = t[i]
        if x == nil or x == 'blank' then x = false end
        o[i] = x
    end
    return o
end
local function str(t)
    if t == nil then return 'nil' end
    if type(t) ~= 'table' then return tostring(t) end
    local parts = {}
    for i = 1, (t.n or #t) do parts[i] = tostring(t[i] == nil and false or t[i]) end
    return table.concat(parts, ',')
end
local function sameList(a, b) return str(list(a)) == str(list(b)) end

local function heroEq(h, e)
    return h.hp == e.hp and h.atk == e.atk and h.def == e.def and h.keys == e.keys and h.gold == e.gold
        and h.weapon == e.weapon and sameList(h.boons or {}, e.boons or {})
end
local function heroStr(h)
    return string.format('生命%d 攻%d 防%d 钥%d 金%d 武器%s %s', h.hp, h.atk, h.def, h.keys, h.gold, tostring(h.weapon), str(h.boons))
end
local function reload(run)
    return Run.load(run.plan, serialize.load(serialize.dump(run:save())))
end
-- 原型的楼层参数 → Lua 的楼层（marks 换成 1 开始）
local function luaFloor(fp)
    local f = {}
    for k, v in pairs(fp) do f[k] = v end
    if fp.marks then
        f.marks = {}
        for k, c in ipairs(fp.marks) do f.marks[k] = c + 1 end
    end
    return f
end
local function tiny(map, extra)
    local f = { name = 't', map = map, bloodCost = 40, gem = 2, smallPotion = 50, bigPotion = 150, gold = 20 }
    for k, v in pairs(extra or {}) do f[k] = v end
    return f
end

-- 1. 战斗
for _, c in ipairs(V.combat) do
    local r = combat.simulate({ atk = c.atk, def = c.def, weapon = c.weapon, boons = c.boons }, config.MONSTERS[c.monster])
    check(r.canAttack == c.canAttack and r.canWin == c.canWin and r.damage == c.damage and r.hits == c.hits,
        string.format('战斗 %s 攻%d防%d %s %s：期望 %d/%d，实际 %d/%d', c.monster, c.atk, c.def, tostring(c.weapon), str(c.boons), c.damage, c.hits, r.damage, r.hits))
end

-- 2. 楼层逐步（每一步都存档读档）
local function runScenario(sc)
    local run = Run.new({ luaFloor(sc.floor) }, 'digger', 1)
    run.hero = config.copyHero(sc.entry)
    for k, st in ipairs(sc.steps) do
        local r = run:step(st.cell + 1)
        local queued = #run.engraveQueue
        run.engraveQueue = {}
        check(r.ok == st.ok and heroEq(run.hero, st.hero) and run.pos == st.pos + 1 and run.status == st.status and queued == st.queue,
            string.format('%s 第 %d 步（格子 %d）：期望 %s 位置%d %s 刻%d，实际 %s 位置%d %s 刻%d', sc.name, k, st.cell,
                heroStr(st.hero), st.pos, st.status, st.queue, heroStr(run.hero), run.pos - 1, run.status, queued))
        local back = reload(run)
        check(heroEq(back.hero, run.hero) and back.pos == run.pos and back.status == run.status, sc.name .. ' 第 ' .. k .. ' 步：存档读档后状态变了')
        run = back
    end
    local s = run:exitSummary()
    check(s.leftoverPotions == sc.exit.leftoverPotions and s.potionGold == sc.exit.potionGold, sc.name .. '：出口结算')
    if sc.rentMethod then run:payRent(sc.rentMethod) end
    run:finishFloor(false)
    check(heroEq(run.hero, sc.final) and run.status == sc.final.status, sc.name .. '：结算后 期望 ' .. heroStr(sc.final) .. '，实际 ' .. heroStr(run.hero))
end
for _, sc in ipairs(V.scenarios) do runScenario(sc) end
for _, sc in ipairs(V.routeWalks) do runScenario(sc) end

for _, mv in ipairs(V.monsterViews) do
    local run = Run.new({ tiny(mv.map) }, 'digger', 1)
    local m = run:monsterAt(mv.cell + 1)
    check(m.atk == mv.atk and m.def == mv.def, '新怪属性 ' .. table.concat(mv.map, '/') .. ' 格子' .. mv.cell)
end

-- 3. 硬打致死
for _, d in ipairs(V.deaths) do
    local run = Run.new({ tiny(d.map) }, 'digger', 1)
    run.hero.hp = d.hp
    local r = run:step(2)
    check(r.ok == d.ok and run.status == d.status and run.hero.hp == d.heroHp, '硬打 ' .. d.monster)
end

-- 4. 断臂转轮
for _, a in ipairs(V.armSessions) do
    local run = Run.new({ tiny({ '@.>' }) }, 'digger', a.seed)
    run.arm.rows = list(a.rows)
    run.hero = { hp = 500, atk = 13, def = 13, keys = 0, gold = 300 }
    for k, st in ipairs(a.steps) do
        local r = run:armSpin(st.pay, st.held and list(st.held) or nil)
        local tag = string.format('断臂转轮 种子%d 图案%s 脚本%d 第%d次', a.seed, str(a.rows), a.script, k)
        check(r.ok == st.ok and sameList(r.faces, st.faces) and heroEq(run.hero, st.hero) and run.arm.spins == st.spins,
            tag .. '：期望 ' .. str(list(st.faces)) .. ' ' .. heroStr(st.hero) .. '，实际 ' .. str(r.faces) .. ' ' .. heroStr(run.hero))
        run = reload(run)
    end
end

-- 5. 刻图案（精英三选一、印记怪）
for _, e in ipairs(V.engraves) do
    local fs = {}
    for k = 1, e.floorIndex do fs[k] = tiny({ '@>' }) end
    fs[e.floorIndex] = tiny({ '@Ge>' }, { eliteReward = true, marks = { 3 } })
    local run = Run.new(fs, 'digger', e.seed)
    for _ = 1, e.floorIndex - 1 do run:move(1, 0); run:finishFloor(false) end
    run.hero = { hp = 999, atk = 60, def = 60, keys = 0, gold = 0, weapon = e.current }
    run:move(1, 0)
    run:move(1, 0)
    local got, want = {}, {}
    for _, p in ipairs(run.engraveQueue) do got[#got + 1] = p.from .. ':' .. table.concat(p.choices, '/') end
    for _, p in ipairs(e.queue) do want[#want + 1] = p.from .. ':' .. table.concat(p.choices, '/') end
    check(table.concat(got, ' ') == table.concat(want, ' '), string.format('刻图案 种子%d 第%d层 %s：期望 %s，实际 %s', e.seed, e.floorIndex, tostring(e.current), table.concat(want, ' '), table.concat(got, ' ')))
end

-- 6. 大转盘
for _, w in ipairs(V.wheels) do
    local run = Run.new({ tiny({ '@.>', '.S.' }) }, 'digger', w.seed)
    run:move(0, 1)
    run.hero = { hp = 3000, atk = 13, def = 13, keys = 0, gold = 3000 }
    run.arm.rows = { 'boneKnife', 'hammer', 'harpoon' }
    run.arm.stops = { 1, 1, 1 }
    run.hero.weapon = 'boneKnife'
    for k, st in ipairs(w.steps) do
        local r = run:wheelSpin(5, (k - 1) % 3 == 2 and 'blood' or 'gold')
        local q = {}
        for _, p in ipairs(run.engraveQueue) do q[#q + 1] = p.choices[1] end
        run.engraveQueue = {}
        check(r.ok == st.ok and (r.sector and r.sector - 1) == st.sector and heroEq(run.hero, st.hero) and sameList(run.arm.rows, st.rows)
            and table.concat(q, ',') == table.concat(st.queue, ',') and run.status == st.status,
            string.format('大转盘 种子%d 第%d次：期望 格%s %s 图案%s，实际 格%s %s 图案%s', w.seed, k, tostring(st.sector), heroStr(st.hero), str(list(st.rows)), tostring(r.sector and r.sector - 1), heroStr(run.hero), str(run.arm.rows)))
        run = reload(run)
    end
end

-- 7. 当铺、骨坛、补给摊
for n, sh in ipairs(V.shops) do
    local plan = {}
    for k, fp in ipairs(sh.plan) do plan[k] = luaFloor(fp) end
    local run = Run.new(plan, 'digger', 1)
    run.hero.gold, run.hero.keys = sh.gold, sh.keys
    run.arm.rows = { 'boneKnife', false, false }
    run.arm.stops = { 1, 1, 1 }
    run.hero.weapon = 'boneKnife'
    for k, st in ipairs(sh.steps) do
        local a = st.a and st.a + 1
        local b = st.b and st.b + 1
        local r = { ok = true, msg = '' }
        if st.op == 'key' then r = run:pawnSellKey(4)
        elseif st.op == 'pawn' then r = run:pawnRow(4, a)
        elseif st.op == 'buy' then r = run:pawnBuy(4, a, b)
        elseif st.op == 'erase' then r = run:pawnErase(4, a)
        elseif st.op == 'redeem' then r = run:pawnRedeem(4, a, b)
        else run:move(1, 0); run:move(1, 0); run:finishFloor(false) end
        local pw, want = {}, {}
        for _, p in ipairs(run.pawned) do pw[#pw + 1] = p.weapon .. '@' .. (p.floor - 1) end
        for _, p in ipairs(st.pawned) do want[#want + 1] = p.weapon .. '@' .. p.floor end
        check(r.ok == st.ok and r.msg == st.msg and heroEq(run.hero, st.hero) and sameList(run.arm.rows, st.rows) and table.concat(pw, ',') == table.concat(want, ','),
            string.format('当铺 %d 第%d步 %s：期望 %s「%s」 %s，实际 %s「%s」 %s', n, k, st.op, tostring(st.ok), st.msg, heroStr(st.hero), tostring(r.ok), r.msg, heroStr(run.hero)))
        run = reload(run)
    end
end
for n, al in ipairs(V.altars) do
    local run = Run.new({ tiny(al.map) }, 'digger', 1)
    run.hero = { hp = 9999, atk = 60, def = 60, keys = 1, gold = 0 }
    run.arm.rows = { 'boneKnife', 'hammer', false }
    run.arm.stops = { 1, 1, 1 }
    run.hero.weapon = 'boneKnife'
    local kills = #al.map[1] - 4
    for _ = 0, kills do run:move(1, 0) end
    check(sameList(run.boonsSeen, al.seen), '骨坛 ' .. n .. '：杀过的特性 ' .. str(run.boonsSeen) .. ' / ' .. str(al.seen))
    for k, st in ipairs(al.steps) do
        local r = run:altarOffer(kills + 3, st.pay, st.boon, st.weapon)
        local same = true
        for w, list2 in pairs(st.boons) do same = same and sameList(run.arm.boons[w] or {}, list2) end
        check(r.ok == st.ok and r.msg == st.msg and heroEq(run.hero, st.hero) and same, string.format('骨坛 %d 第%d步：期望 %s「%s」，实际 %s「%s」', n, k, tostring(st.ok), st.msg, tostring(r.ok), r.msg))
    end
end
for n, sl in ipairs(V.stalls) do
    local run = Run.new({ luaFloor(sl.floor) }, 'digger', 1)
    run.hero.gold = sl.gold
    run:move(1, 0)
    for k, st in ipairs(sl.steps) do
        local r = run:stallBuy(3, st.k + 1)
        check(r.ok == st.ok and r.msg == st.msg and heroEq(run.hero, st.hero), '补给摊 ' .. n .. ' 第 ' .. k .. ' 次')
        run = reload(run)
    end
end

-- 8. 诏令
for _, d in ipairs(V.decreeDraws) do
    local got = decreeMod.decreeFor(d.seed, d.floorIndex + 1)
    check((got and got.kind) == (d.def and d.def.kind) and (got and got.tier) == (d.def and d.def.tier), string.format('诏令 种子%d 第%d层', d.seed, d.floorIndex + 1))
end
for _, dr in ipairs(V.decreeRuns) do
    local plan = {}
    for k, m in ipairs(dr.maps) do plan[k] = tiny(m) end
    local run = Run.new(plan, 'digger', 1)
    run.hero = { hp = 600, atk = 40, def = 30, keys = 0, gold = 0 }
    for d, lg in ipairs(dr.log) do
        if run.decreeOffer then
            run.decreeOffer = { kind = dr.kind, tier = dr.n == 1 and 'bronze' or 'silver', n = dr.kind == 'gold' and 30 or dr.n, text = dr.kind }
            run:acceptDecree()
        end
        for _ = 1, 20 do
            if run.status ~= 'playing' then break end
            run:move(1, 0)
        end
        run.engraveQueue = {}
        run:finishFloor(false)
        local notes = table.concat(run.notes, '|')
        run.notes = {}
        check(heroEq(run.hero, lg.hero) and (run.decree and run.decree.progress) == (lg.decree and lg.decree.progress) and notes == table.concat(lg.notes or {}, '|') and run.status == lg.status,
            string.format('诏令 %s/%d 第%d层：期望 %s「%s」，实际 %s「%s」', dr.kind, dr.n, d, heroStr(lg.hero), table.concat(lg.notes or {}, '|'), heroStr(run.hero), notes))
        run = reload(run)
    end
end

-- 9. 路线和楼梯口的话
local function floorStr(f, base)
    local marks = {}
    for k, c in ipairs(f.marks or {}) do marks[k] = c - (base or 0) end
    local stall = {}
    for k, o in ipairs(f.stall or {}) do stall[k] = o.id .. o.amount .. '/' .. o.price end
    return table.concat({ tostring(f.name), table.concat(f.map, '/'), tostring(f.kind), tostring(f.bloodCost), tostring(f.gem), tostring(f.smallPotion), tostring(f.bigPotion),
        tostring(f.gold), tostring(f.rent), tostring(f.eliteReward), table.concat(marks, ','), table.concat(f.shop or {}, ','), table.concat(stall, ','), tostring(f.hint) }, ' | ')
end
for _, r in ipairs(V.routes) do
    local plan = route.build(r.seed)
    check(#plan == #r.plan, '路线 种子' .. r.seed .. '：层数')
    for d, opts in ipairs(r.plan) do
        check(#plan[d] == #opts, string.format('路线 种子%d 第%d层：候选数', r.seed, d))
        for k, want in ipairs(opts) do
            local got = plan[d][k]
            if got then
                local a, b = floorStr(got, 1), floorStr(want, 0)
                check(a == b, string.format('路线 种子%d 第%d层 候选%d：\n  期望 %s\n  实际 %s', r.seed, d, k, b, a))
                check(whisperMod.whisper(got) == want.whisper, string.format('楼梯口的话 种子%d 第%d层', r.seed, d))
                floorMod.parse(got)
            end
        end
    end
end
for _, t in ipairs(V.tutorials) do
    local plan = route.tutorial(t.seed)
    for d, opts in ipairs(t.plan) do
        check(floorStr(plan[d][1], 1) == floorStr(opts[1], 0), string.format('教程 种子%d 第%d层：期望 %s 实际 %s', t.seed, d, floorStr(opts[1], 0), floorStr(plan[d][1], 1)))
    end
end

print(string.format('对账：%d 条一致，%d 条不一致（战斗 %d、楼层 %d+%d、断臂转轮 %d、刻图案 %d、大转盘 %d、当铺 %d、骨坛 %d、诏令 %d+%d、路线 %d、教程 %d）',
    pass, fail, #V.combat, #V.scenarios, #V.routeWalks, #V.armSessions, #V.engraves, #V.wheels, #V.shops, #V.altars, #V.decreeDraws, #V.decreeRuns, #V.routes, #V.tutorials))
os.exit(fail == 0 and 0 or 1)
