-- 断臂转轮：和原型 src/core/arm.ts 一致。三个轮子，每个轮子一圈 3 格；刻一把武器 = 占满同一行。
-- Lua 里空行用 false 表示（避免表里出洞）；行号从 1 开始。

local rng = require('core.rng')
local M = {}

M.ROWS = 3
M.BASE_PRICE = 10

function M.new()
    return { rows = { false, false, false }, boons = {}, spins = 0, draws = 0, stops = nil }
end

-- 三个轮子停下的图案（false = 空格）
function M.faces(arm)
    if not arm.stops then return nil end
    return { arm.rows[arm.stops[1]], arm.rows[arm.stops[2]], arm.rows[arm.stops[3]] }
end

-- 转一次；held[i] 为 true 的轮子不动
function M.roll(arm, seed, key, held)
    local stops = {}
    for i = 1, 3 do
        if held and held[i] and arm.stops then
            stops[i] = arm.stops[i]
        else
            stops[i] = math.floor(rng.draw(seed, key, arm.draws) * M.ROWS) + 1
            arm.draws = arm.draws + 1
        end
    end
    arm.stops = stops
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

local function count(arm, id)
    local n = 0
    for k = 1, M.ROWS do if arm.rows[k] == id then n = n + 1 end end
    return n
end
M.count = count

function M.odds(arm, id)
    local n = count(arm, id)
    return n * n * n / (M.ROWS * M.ROWS * M.ROWS)
end

-- 锁住一些轮子后重转凑成三连的概率；不可能时返回 nil
function M.holdOdds(arm, held)
    local f = M.faces(arm)
    if not f then return nil end
    local target, nheld = nil, 0
    for i = 1, 3 do
        if held[i] then
            if nheld > 0 and f[i] ~= target then return nil end
            target, nheld = f[i], nheld + 1
        end
    end
    if nheld == 0 then return nil end
    local share = count(arm, target) / M.ROWS
    return target, share ^ (3 - nheld)
end

function M.firstBlank(arm)
    for k = 1, M.ROWS do if not arm.rows[k] then return k end end
    return nil
end

-- 刻一把武器：有空行就刻在第一个空行；没有空行时必须指定行。返回刻在哪一行（nil = 不行）
function M.engraveRow(arm, id, row)
    local k = row or M.firstBlank(arm)
    if not k or k < 1 or k > M.ROWS then return nil end
    arm.rows[k] = id
    arm.stops = { k, k, k }
    return k
end

function M.has(arm, id)
    for k = 1, M.ROWS do if arm.rows[k] == id then return true end end
    return false
end

return M
