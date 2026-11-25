-- 局外成长：灵魂碎片、碎片商店（强化、解锁）、深度模式。和原型 src/core/meta.ts 一致（标准算例对账）。
-- 碎片余额、买过什么、开关存在 main.lua 的 meta 存档里。价格、数值、解锁内容都是讨论项。

local M = {}

-- 碎片收入打几折（百分比，和原型 SHARD_RATE 一致）
M.SHARD_RATE = 60

-- 一局结束能拿多少碎片：走完第 N 层得 N 个；通关再加 50；深度每级多 25%。reached：死在第几层（从 1 开始）
function M.shardsFor(reached, won, depth)
    local done = won and 20 or math.max(0, reached - 1)
    local base = done * (done + 1) / 2 + (won and 50 or 0)
    -- 制作人 2026-11-25：碎片给得太多、商店太便宜（强化买满要大约 25 局）→ 收入 ×0.6，价格 ×1.5
    return math.floor(base * M.SHARD_RATE * (100 + 25 * (depth or 0)) / 10000)
end

-- 强化：买了以后每局开局生效，可以随时关掉（关掉不退碎片）。costs[k] 是买第 k 级的价格
M.PERKS = {
    { id = 'atk', name = '磨刀石', costs = { 30, 60, 120 }, values = { 1, 2, 3 }, desc = function(v) return '开局攻击 +' .. v end },
    { id = 'def', name = '护甲片', costs = { 30, 60, 120 }, values = { 1, 2, 3 }, desc = function(v) return '开局防御 +' .. v end },
    { id = 'hp', name = '血囊', costs = { 15, 45, 90 }, values = { 30, 60, 100 }, desc = function(v) return '开局生命 +' .. v end },
    { id = 'keys', name = '钥匙串', costs = { 60 }, values = { 1 }, desc = function(v) return '开局带 ' .. v .. ' 把骨钥' end },
    { id = 'gold', name = '钱袋', costs = { 30, 75 }, values = { 20, 50 }, desc = function(v) return '开局金币 +' .. v end },
    { id = 'engrave', name = '旧印子', costs = { 90 }, values = { 1 }, desc = function() return '每局开始时，断臂转轮自带一个随机武器图案' end },
    { id = 'halfSpin', name = '润滑油', costs = { 120 }, values = { 1 }, desc = function() return '每层首次转动断臂转轮时半价' end },
}
function M.perk(id) for _, p in ipairs(M.PERKS) do if p.id == id then return p end end end
function M.perkValue(id, level)
    local p = M.perk(id)
    if not p or not level or level <= 0 then return 0 end
    return p.values[math.min(level, #p.values)]
end

-- 解锁：一次买断，永久有效
M.UNLOCKS = {
    { id = 'lamp', name = '井灯', cost = 90, kind = 'weapon', desc = '解锁井灯图案。装备井灯时，防御 +2' },
    { id = 'twinHook', name = '双钩', cost = 90, kind = 'weapon', desc = '新武器图案：攻击 +1，每次击杀回复 4 生命' },
    { id = 'scavenger', name = '拾荒者', cost = 180, kind = 'character', desc = '新角色：生命 150、攻 9、防 8、开局 30 金。开骨门不用骨钥，改扣 10 生命' },
    { id = 'drowned', name = '溺者', cost = 300, kind = 'character', desc = '新角色：生命 100、攻 14、防 6。倒下时复活一次，之后每进一层扣 20 生命' },
    { id = 'campKey', name = '营火的骨钥', cost = 60, kind = 'facility', desc = '营火的补给摊多卖一把骨钥' },
    { id = 'pawnExtra', name = '当铺的第三件', cost = 75, kind = 'facility', desc = '当铺多摆一件武器图案' },
    { id = 'depth', name = '深度模式', cost = 150, kind = 'depth', needsClear = true, desc = '通关后可解锁更高难度。深度越高，结算时获得的碎片越多' },
}

local BASE = { 'boneKnife', 'harpoon', 'hammer', 'mossBlade', 'bellStaff', 'saltDagger', 'rustSword', 'wellHook' }
local function has(list, x) for _, v in ipairs(list or {}) do if v == x then return true end end return false end
M.has = has

-- 图案池：一开始的 8 把 + 解锁的武器（按 UNLOCKS 的顺序）
function M.weaponPool(unlocks)
    local out = {}
    for i, w in ipairs(BASE) do out[i] = w end
    for _, u in ipairs(M.UNLOCKS) do if u.kind == 'weapon' and has(unlocks, u.id) then out[#out + 1] = u.id end end
    return out
end

M.MAX_DEPTH = 3
M.DEPTH_POWER = 1

return M
