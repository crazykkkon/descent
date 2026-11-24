-- 一局的路线：和原型 src/core/route.ts 的 buildRoute / buildTutorial 逐位一致。
-- 地图池在 src/data/pools.lua（从原型导出）。层号在算法里按原型的 0 开始计算（d），只在结果里换成 Lua 的习惯。
-- 印记怪的格子下标（marks）是 Lua 的 1 开始。

local config = require('core.config')
local floorMod = require('core.floor')
local rng = require('core.rng')
local P = require('data.pools')

local M = {}
M.LENGTH = 20

local function copy(t)
    local o = {}
    for k, v in pairs(t) do o[k] = v end
    return o
end

local RENT = {}
for _, r in ipairs(P.RENTS) do RENT[r.floor] = r.rent end

local STALL_SHALLOW = { { id = 'hp', amount = 80, price = 25 }, { id = 'atk', amount = 2, price = 40 }, { id = 'def', amount = 2, price = 40 } }
local STALL_DEEP = { { id = 'hp', amount = 150, price = 40 }, { id = 'atk', amount = 3, price = 70 }, { id = 'def', amount = 3, price = 70 } }

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

local function toFloor(seed, d, slot, e)
    local f = copy(band(d))
    f.name = '第 ' .. (d + 1) .. ' 层 · ' .. e.name
    f.hint, f.map, f.kind = e.hint, e.map, e.kind
    if e.kind == 'elite' or e.kind == 'boss' then f.eliteReward = (e.kind == 'elite') end
    if e.kind == 'normal' then f.marks = markFor(seed, d, slot, e.map) end
    if e.kind == 'camp' then f.stall = d >= 10 and STALL_DEEP or STALL_SHALLOW end
    if e.kind == 'pawn' then
        local all = config.WEAPON_ORDER
        local a = rng.pick(seed, 8500 + d * 10 + slot, 0, #all)
        local b = rng.pick(seed, 8500 + d * 10 + slot, 1, #all - 1)
        if b >= a then b = b + 1 end
        f.shop = { all[a + 1], all[b + 1] }
        -- 很小的机会第二件换成赖子
        if rng.draw(seed, 8600 + d * 10 + slot, 0) < 0.1 then f.shop[2] = 'wild' end
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
function M.build(seed)
    local used, plan = {}, {}
    for d = 0, M.LENGTH - 1 do
        local opts = {}
        if d == 0 or d == 1 then
            local pool = d == 0 and P.F1 or P.F2
            local map = pool.maps[rng.pick(seed, 8000 + d, 0, #pool.maps) + 1]
            local f = copy(pool.params)
            f.map, f.kind = map, 'normal'
            f.marks = markFor(seed, d, 0, map)
            opts[1] = f
        elseif d == 9 then opts[1] = toFloor(seed, d, 0, P.MID_ELITE)
        elseif d == 18 then opts[1] = toFloor(seed, d, 0, P.GATE)
        elseif d == 19 then opts[1] = toFloor(seed, d, 0, P.BOSS)
        else
            local fightKind = (d >= 4 and rng.draw(seed, 8200 + d, 0) < 0.3) and 'elite' or 'normal'
            local otherKind = OTHER_KINDS[rng.pick(seed, 8200 + d, 1, #OTHER_KINDS) + 1]
            local a = choose(seed, 8300 + d * 10, poolOf(fightKind, d), d, used)
            local b = choose(seed, 8300 + d * 10 + 1, poolOf(otherKind, d), d, used)
            local entries = rng.draw(seed, 8200 + d, 2) < 0.5 and { a, b } or { b, a }
            for slot = 0, 1 do opts[slot + 1] = toFloor(seed, d, slot, entries[slot + 1]) end
        end
        plan[d + 1] = opts
    end
    return plan
end

-- 新手教程局：第 1～5 层，第 5 层遇到打不过的井底之眼
function M.tutorial(seed)
    local f1 = copy(P.F1.params)
    f1.map, f1.kind = P.F1.maps[rng.pick(seed, 8000, 0, #P.F1.maps) + 1], 'normal'
    local f2 = copy(P.F2.params)
    f2.map, f2.kind = P.F2.maps[rng.pick(seed, 8001, 0, #P.F2.maps) + 1], 'normal'
    local f3 = copy(P.SHALLOW)
    f3.name, f3.hint, f3.kind = '第 3 层 · 回声', P.NORMAL_SHALLOW[1].hint, 'normal'
    f3.map = P.TUTORIAL_F3[rng.pick(seed, 8002, 0, #P.TUTORIAL_F3) + 1]
    local f4 = copy(P.SHALLOW)
    f4.name, f4.hint, f4.map, f4.kind = '第 4 层 · 鳞厅', '石鳞守卫封住了出口。先拿宝石，再去打它。', P.ELITE_SHALLOW[1].map, 'elite'
    local f5 = copy(P.SHALLOW)
    f5.name, f5.hint, f5.map, f5.kind = '第 5 层 · 井底', P.TUTORIAL_BOSS.hint, P.TUTORIAL_BOSS.map, 'boss'
    return { { f1 }, { f2 }, { f3 }, { f4 }, { f5 } }
end

return M
