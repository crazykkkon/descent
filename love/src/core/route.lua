-- 一局的路线：和原型 src/core/route.ts 的 buildRoute / buildTutorial 逐位一致。
-- 地图池在 src/data/pools.lua（从原型导出）。层号在算法里按原型的 0 开始计算（d），只在结果里换成 Lua 的习惯。
-- 印记怪的格子下标（marks）是 Lua 的 1 开始。

local config = require('core.config')
local floorMod = require('core.floor')
local rng = require('core.rng')
local P = require('data.pools')
local metaMod = require('core.meta')

local M = {}
M.LENGTH = 20
-- 只有一个候选的层（从 0 开始）：第 1、2、3、10、11、19、20 层
M.FIXED = { [0] = true, [1] = true, [2] = true, [9] = true, [10] = true, [18] = true, [19] = true }

-- 这一层只有一个出口：把第二个出口 '<' 堵成墙
local function oneExit(map)
    local out = {}
    for i, r in ipairs(map) do out[i] = (r:gsub('<', '#', 1)) end
    return out
end
M.oneExit = oneExit

local function copy(t)
    local o = {}
    for k, v in pairs(t) do o[k] = v end
    return o
end

local RENT = {}
for _, r in ipairs(P.RENTS) do RENT[r.floor] = r.rent end

local STALL_SHALLOW = { { id = 'hp', amount = 80, price = 25 }, { id = 'atk', amount = 1, price = 40 }, { id = 'def', amount = 1, price = 40 } }
local STALL_DEEP = { { id = 'hp', amount = 150, price = 40 }, { id = 'atk', amount = 2, price = 70 }, { id = 'def', amount = 2, price = 70 } }

local function band(d)
    if d >= 18 then return P.BOTTOM elseif d >= 10 then return P.DEEP end
    return P.SHALLOW
end

-- 普通层随机给一只怪打上印记（第 1 层一定有）
local function markFor(seed, d, slot, map)
    local cells = floorMod.parse({ name = 't', map = map }).cells
    local cand = {}
    for i, c in ipairs(cells) do
        if c.kind == 'monster' and config.MARK_WEAPON[c.id] and not config.MONSTERS[c.id].elite then cand[#cand + 1] = i end
    end
    if #cand == 0 then return nil end
    if d > 0 and rng.draw(seed, 8100 + d * 10 + slot, 0) >= 0.6 then return nil end
    return { cand[rng.pick(seed, 8100 + d * 10 + slot, 1, #cand) + 1] }
end

-- 第 6 层起（d ≥ 5）小怪换成更凶的同类；第 7 层起每往下一层怪物加强一级，一直加到第 20 层。和原型 deepen / powerFor 一致
M.UPGRADE_FROM, M.POWER_FROM, M.POWER_MAX = 5, 5, 14
local function deepen(map, d)
    if d < M.UPGRADE_FROM then return map end
    local out = {}
    for i, r in ipairs(map) do out[i] = (r:gsub('[mefcvgx]', config.UPGRADE_CHARS)) end
    return out
end
function M.powerFor(d)
    if d <= M.POWER_FROM then return 0 end
    return math.min(M.POWER_MAX, d - M.POWER_FROM)
end

-- 大宝石（制作人定）：第 1～6 层只有小宝石；第 7～10 层一层最多一颗、概率很小；第 11 层起大小都有，越往下大的越多（和原型 bigGems 一致）
M.BIG_GEM_FROM, M.BIG_GEM_MIX_FROM = 6, 10
M.BIG_GEM_EARLY, M.BIG_GEM_P0, M.BIG_GEM_STEP, M.BIG_GEM_PMAX = 0.25, 0.3, 0.04, 0.7
function M.bigGems(map, seed, d, slot)
    if d < M.BIG_GEM_FROM then return map end
    local gems = {}
    for y, r in ipairs(map) do
        for x = 1, #r do
            local ch = r:sub(x, x)
            if ch == 'r' or ch == 'b' then gems[#gems + 1] = { y, x } end
        end
    end
    if #gems == 0 then return map end
    local key = 8700 + d * 10 + slot
    local set = {}
    if d < M.BIG_GEM_MIX_FROM then
        if rng.draw(seed, key, 0) < M.BIG_GEM_EARLY then set[#set + 1] = rng.pick(seed, key, 1, #gems) + 1 end
    else
        local p = math.min(M.BIG_GEM_PMAX, M.BIG_GEM_P0 + M.BIG_GEM_STEP * (d - M.BIG_GEM_MIX_FROM))
        for k = 1, #gems do if rng.draw(seed, key, 2 + k - 1) < p then set[#set + 1] = k end end
    end
    if #set == 0 then return map end
    local rows = {}
    for y, r in ipairs(map) do rows[y] = r end
    for _, k in ipairs(set) do
        local y, x = gems[k][1], gems[k][2]
        local r = rows[y]
        local ch = r:sub(x, x) == 'r' and 'R' or 'C'
        rows[y] = r:sub(1, x - 1) .. ch .. r:sub(x + 1)
    end
    return rows
end

-- opts：{ depth = 深度模式 0～3, unlocks = { 解锁的 id } }（和原型 RouteOptions 一致）
local function toFloor(seed, d, slot, e, opts)
    local unlocks = (opts and opts.unlocks) or {}
    local f = copy(band(d))
    f.name = '第 ' .. (d + 1) .. ' 层 · ' .. e.name
    f.hint, f.kind = e.hint, e.kind
    f.map = M.bigGems(e.kind == 'boss' and e.map or deepen(e.map, d), seed, d, slot)
    local power = M.powerFor(d, e.kind)
    if power > 0 then f.power = power end
    if e.kind == 'elite' or e.kind == 'boss' then f.eliteReward = (e.kind == 'elite') end
    if e.kind == 'normal' then f.marks = markFor(seed, d, slot, f.map) end
    if e.kind == 'camp' then
        f.stall = {}
        for i, o in ipairs(d >= 10 and STALL_DEEP or STALL_SHALLOW) do f.stall[i] = o end
        -- 解锁"营火的骨钥"：多卖一把骨钥
        if metaMod.has(unlocks, 'campKey') then f.stall[#f.stall + 1] = { id = 'key', amount = 1, price = d >= 10 and 40 or 30 } end
    end
    if e.kind == 'pawn' then
        local all = metaMod.weaponPool(unlocks)
        local a = rng.pick(seed, 8500 + d * 10 + slot, 0, #all)
        local b = rng.pick(seed, 8500 + d * 10 + slot, 1, #all - 1)
        if b >= a then b = b + 1 end
        f.shop = { all[a + 1], all[b + 1] }
        -- 很小的机会第二件换成赖子
        if rng.draw(seed, 8600 + d * 10 + slot, 0) < 0.1 then f.shop[2] = 'wild' end
        -- 解锁"当铺的第三件"：多摆一件
        if metaMod.has(unlocks, 'pawnExtra') then
            local rest = {}
            for _, w in ipairs(all) do if w ~= all[a + 1] and w ~= all[b + 1] then rest[#rest + 1] = w end end
            f.shop[3] = rest[rng.pick(seed, 8500 + d * 10 + slot, 2, #rest) + 1]
        end
    end
    if RENT[d] then f.rent = RENT[d] end
    return f
end

-- 从池子里挑一张这一局还没用过的图
local function choose(seed, key, pool, d, used)
    local ok = {}
    for _, e in ipairs(pool) do if (e.from or 0) <= d then ok[#ok + 1] = e end end
    local start = rng.pick(seed, key, 0, #ok)
    for k = 0, #ok - 1 do
        local e = ok[(start + k) % #ok + 1]
        if not used[e.name] then used[e.name] = true; return e end
    end
    return ok[start + 1]
end

local OTHER_KINDS = { 'normal', 'wheel', 'pawn', 'altar', 'camp', 'wheel', 'pawn', 'camp' }

local function poolOf(kind, d)
    if kind == 'elite' then return d >= 10 and P.ELITE_DEEP or P.ELITE_SHALLOW end
    if kind == 'wheel' then return P.WHEEL_MAPS end
    if kind == 'pawn' then return P.PAWN_MAPS end
    if kind == 'altar' then return P.ALTAR_MAPS end
    if kind == 'camp' then return P.CAMP_MAPS end
    return d >= 10 and P.NORMAL_DEEP or P.NORMAL_SHALLOW
end

-- 一局的完整路线：plan[层] = { 候选1, 候选2? }
function M.build(seed, opts)
    local used, plan = {}, {}
    for d = 0, M.LENGTH - 1 do
        local cands = {}
        if d == 0 or d == 1 then
            local pool = d == 0 and P.F1 or P.F2
            local map = pool.maps[rng.pick(seed, 8000 + d, 0, #pool.maps) + 1]
            local f = copy(pool.params)
            f.map, f.kind = map, 'normal'
            f.marks = markFor(seed, d, 0, map)
            cands[1] = f
        elseif d == 9 then cands[1] = toFloor(seed, d, 0, P.MID_ELITE, opts)
        elseif d == 18 then cands[1] = toFloor(seed, d, 0, P.GATE, opts)
        elseif d == 19 then cands[1] = toFloor(seed, d, 0, P.BOSS, opts)
        else
            local fightKind = (d >= 4 and rng.draw(seed, 8200 + d, 0) < 0.3) and 'elite' or 'normal'
            local a = choose(seed, 8300 + d * 10, poolOf(fightKind, d), d, used)
            if M.FIXED[d] then cands[1] = toFloor(seed, d, 0, a, opts)
            else
                local otherKind = OTHER_KINDS[rng.pick(seed, 8200 + d, 1, #OTHER_KINDS) + 1]
                local b = choose(seed, 8300 + d * 10 + 1, poolOf(otherKind, d), d, used)
                local entries = rng.draw(seed, 8200 + d, 2) < 0.5 and { a, b } or { b, a }
                for slot = 0, 1 do cands[slot + 1] = toFloor(seed, d, slot, entries[slot + 1], opts) end
            end
        end
        plan[d + 1] = cands
    end
    -- 正式局的楼层：怪物用 RUN_STATS 的数值
    for _, cs in ipairs(plan) do for _, f in ipairs(cs) do f.runStats = true end end
    -- 下一层只有一个候选的层：只留一个出口
    for d = 1, M.LENGTH do
        if not plan[d + 1] or #plan[d + 1] ~= 2 then
            for _, f in ipairs(plan[d]) do f.map = oneExit(f.map) end
        end
    end
    -- 深度模式：第 1 级起怪物每级再加强 2 级；第 2 级起血瓶 −25%；第 3 级起井租和补给摊 ×1.5
    local depth = (opts and opts.depth) or 0
    if depth > 0 then
        for _, cs in ipairs(plan) do
            for _, f in ipairs(cs) do
                f.power = (f.power or 0) + metaMod.DEPTH_POWER * depth
                if depth >= 2 then
                    f.smallPotion = math.floor(f.smallPotion * 3 / 4)
                    f.bigPotion = math.floor(f.bigPotion * 3 / 4)
                end
                if depth >= 3 then
                    if f.rent then f.rent = math.floor(f.rent * 3 / 2) end
                    if f.stall then
                        local st = {}
                        for i, o in ipairs(f.stall) do st[i] = { id = o.id, amount = o.amount, price = math.floor(o.price * 3 / 2 / 5 + 0.5) * 5 } end
                        f.stall = st
                    end
                end
            end
        end
    end
    return plan
end

-- 新手教程局：固定 5 张教学地图（原型 TUTORIAL_FLOORS），第 5 层遇到打不过的井底之眼；每层只有一个出口
function M.tutorial(_seed)
    local out = {}
    for i, t in ipairs(P.TUTORIAL) do
        local f = copy(t)
        -- 教程的宝石都是大宝石（+3，和原来 宝石 2 + 掘井人 1 一样，教程的数值不变）
        local m = {}
        for y, r in ipairs(oneExit(t.map)) do m[y] = (r:gsub('r', 'R'):gsub('b', 'C')) end
        f.map = m
        out[i] = { f }
    end
    return out
end

return M
