-- 断臂转轮：和原型 src/core/arm.ts 一致。三个轮子并排，每个轮子一圈 5 格；刻图案只刻在一个轮子的一格上。
-- 只看中间一行：三个轮子停的格子是同一把武器 → 换成这把；三个都是空格 → 空手；其他 → 不变。
-- Lua 里空格用 false 表示；轮子号、格子号都从 1 开始。

local rng = require('core.rng')
local M = {}

-- 赖子：能顶替任何武器，不顶替空格；三个赖子不变；不能拿在手上。拿到的机会很小
M.WILD = 'wild'
M.WILD_NAME = '赖子'
M.WILD_CHANCE = 0.1
M.WILD_PRICE = 150

M.REELS = 3
M.SIZE = 5
M.BASE_PRICE = 10

function M.new()
    local reels = {}
    for r = 1, M.REELS do
        reels[r] = {}
        for k = 1, M.SIZE do reels[r][k] = false end
    end
    return { reels = reels, boons = {}, spins = 0, draws = 0, stops = { 1, 1, 1 } }
end

-- 中间一行：三个轮子停着的图案
function M.faces(arm)
    local f = {}
    for r = 1, M.REELS do f[r] = arm.reels[r][arm.stops[r]] end
    return f
end

-- 转一次；held[r] 为 true 的轮子不动
function M.roll(arm, seed, key, held)
    for r = 1, M.REELS do
        if not (held and held[r]) then
            arm.stops[r] = math.floor(rng.draw(seed, key, arm.draws) * M.SIZE) + 1
            arm.draws = arm.draws + 1
        end
    end
    return M.faces(arm)
end

-- 'weapon'（换成 id）、'empty'（三个空格 → 空手）、'none'（不变）
function M.outcome(f)
    if not f[1] and not f[2] and not f[3] then return 'empty' end
    if not f[1] or not f[2] or not f[3] then return 'none' end
    local target = nil
    for r = 1, 3 do
        if f[r] ~= M.WILD then
            if target and f[r] ~= target then return 'none' end
            target = f[r]
        end
    end
    if not target then return 'none' end -- 三个赖子
    return 'weapon', target
end

function M.reelCount(arm, r, id)
    local n = 0
    for k = 1, M.SIZE do if arm.reels[r][k] == id then n = n + 1 end end
    return n
end

-- 把没锁住的轮子的所有停法都数一遍：返回 counts（键：武器 id、'empty'、'none'）和总数
function M.outcomeCounts(arm, held)
    local counts, total = {}, 0
    local f = M.faces(arm)
    local cur = {}
    local function walk(r)
        if r > M.REELS then
            local kind, id = M.outcome(cur)
            local key = kind == 'weapon' and id or kind
            counts[key] = (counts[key] or 0) + 1
            total = total + 1
            return
        end
        if held and held[r] then
            cur[r] = f[r]; walk(r + 1)
        else
            for k = 1, M.SIZE do cur[r] = arm.reels[r][k]; walk(r + 1) end
        end
    end
    walk(1)
    return counts, total
end

-- 转一次连成这把武器的概率（id = false 时是三个空格变空手）
function M.odds(arm, id)
    local counts, total = M.outcomeCounts(arm)
    return (counts[id or 'empty'] or 0) / total
end

-- 锁住一些轮子后重转，各种结果的概率：{ { target = 武器 id 或 false（空手）, p } }，按武器顺序
function M.holdOdds(arm, held, order)
    local counts, total = M.outcomeCounts(arm, held)
    local out = {}
    for _, id in ipairs(order) do
        if counts[id] then out[#out + 1] = { target = id, p = counts[id] / total } end
    end
    if counts.empty then out[#out + 1] = { target = false, p = counts.empty / total } end
    return out
end

function M.firstBlank(arm, r)
    for k = 1, M.SIZE do if not arm.reels[r][k] then return k end end
    return nil
end

-- 在第 r 个轮子上刻一把武器：cell 不给就刻在第一个空格；刻满了必须指定格子。刻好后这个轮子转到这一格
function M.engraveCell(arm, r, id, cell)
    if not r or r < 1 or r > M.REELS then return nil end
    local k = cell or M.firstBlank(arm, r)
    if not k or k < 1 or k > M.SIZE then return nil end
    arm.reels[r][k] = id
    arm.stops[r] = k
    return k
end

function M.has(arm, id)
    for r = 1, M.REELS do
        for k = 1, M.SIZE do if arm.reels[r][k] == id then return true end end
    end
    return false
end

-- 所有刻了图案的格子 { {r, k}, ... }，按轮子、格子的顺序
function M.engravedCells(arm)
    local out = {}
    for r = 1, M.REELS do
        for k = 1, M.SIZE do if arm.reels[r][k] then out[#out + 1] = { r, k } end end
    end
    return out
end

function M.empty(arm) return #M.engravedCells(arm) == 0 end

return M
