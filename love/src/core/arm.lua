-- 断臂转轮：和原型 src/core/arm.ts 一致。三个轮子并排，每个轮子一圈 5 格；刻图案只刻在一个轮子的一格上。
-- 只看中间一行：三个轮子停的格子是同一把武器 → 换成这把；三个都是空格 → 空手；其他 → 不变。
-- Lua 里空格用 false 表示；轮子号、格子号都从 1 开始。

local rng = require('core.rng')
local M = {}

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

-- 'weapon'（换成 id）、'empty'（空手）、'none'（不变）
function M.outcome(f)
    if f[1] == f[2] and f[2] == f[3] then
        if f[1] then return 'weapon', f[1] end
        return 'empty'
    end
    return 'none'
end

function M.reelCount(arm, r, id)
    local n = 0
    for k = 1, M.SIZE do if arm.reels[r][k] == id then n = n + 1 end end
    return n
end

-- 转一次连成这把武器（id = false 时是三个空格）的概率
function M.odds(arm, id)
    local num = 1
    for r = 1, M.REELS do num = num * M.reelCount(arm, r, id) end
    return num / (M.SIZE ^ M.REELS)
end

-- 锁住一些轮子后重转连成一线的概率；锁住的图案不一样时返回 nil
function M.holdOdds(arm, held)
    local f = M.faces(arm)
    local target, nheld = nil, 0
    for r = 1, M.REELS do
        if held[r] then
            if nheld > 0 and f[r] ~= target then return nil end
            target, nheld = f[r], nheld + 1
        end
    end
    if nheld == 0 then return nil end
    local num, den = 1, 1
    for r = 1, M.REELS do
        if not held[r] then
            num = num * M.reelCount(arm, r, target)
            den = den * M.SIZE
        end
    end
    return target, num / den
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
