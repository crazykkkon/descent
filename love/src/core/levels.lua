-- 选图：每局按种子给每层选布局和配置。和 TypeScript 原型 src/core/levels.ts 的 rng / pickChoices / buildFloor 一致。
-- choice = { layout, variant }，都从 0 开始（和原型、存档一致）。

local slot = require('core.slot')
local bit = require('bit')

local M = {}
local u32, imul, bxor = slot.u32, slot.imul, slot.bxor
local function shr(a, n) return math.floor(a / 2 ^ n) end

-- 可重复的随机数（同一个种子得到同一串数）
function M.rng(seed)
    local a = u32(seed)
    return function()
        a = u32(a + 0x6d2b79f5)
        local t = a
        t = imul(bxor(t, shr(t, 15)), u32(bit.bor(t, 1)))
        t = bxor(t, u32(t + imul(bxor(t, shr(t, 7)), u32(bit.bor(t, 61)))))
        return bxor(t, shr(t, 14)) / 4294967296
    end
end

local function layoutNames(pool)
    local t = {}
    for _, l in ipairs(pool.layouts) do t[#t + 1] = l.name end
    table.sort(t)
    return table.concat(t, '|')
end
local function sameFamily(a, b) return layoutNames(a) == layoutNames(b) end

local function prefer(options, keep)
    local f = {}
    for _, c in ipairs(options) do if keep(c) then f[#f + 1] = c end end
    return #f > 0 and f or options
end

-- avoid：上一局的选择（可以不传）
function M.pickChoices(seed, pools, avoid)
    local rand = M.rng(seed)
    local picked = {}
    for i, pool in ipairs(pools) do
        local options = {}
        for li, l in ipairs(pool.layouts) do
            for vi = 1, #l.variants do options[#options + 1] = { layout = li - 1, variant = vi - 1 } end
        end
        local function name(c) return pool.layouts[c.layout + 1].name end
        local prev = avoid and avoid[i]
        if prev then options = prefer(options, function(c) return c.layout ~= prev.layout or c.variant ~= prev.variant end) end
        if avoid then
            local used = {}
            for j, c in ipairs(avoid) do
                if pools[j] and sameFamily(pools[j], pool) then used[pools[j].layouts[c.layout + 1].name] = true end
            end
            options = prefer(options, function(c) return not used[name(c)] end)
        end
        local before = picked[i - 1]
        if before and sameFamily(pools[i - 1], pool) then
            local prevName = pools[i - 1].layouts[before.layout + 1].name
            options = prefer(options, function(c) return name(c) ~= prevName end)
        end
        picked[i] = options[math.floor(rand() * #options) + 1]
    end
    return picked
end

-- 按选图结果生成一层的定义
function M.buildFloor(pool, choice)
    local v = pool.layouts[choice.layout + 1].variants[choice.variant + 1]
    local f = {}
    for k, x in pairs(pool.params) do f[k] = x end
    f.map, f.contract, f.intel, f.intelPick = v.map, v.contract, v.intel, v.intelPick
    f.layout = pool.layouts[choice.layout + 1].name
    return f
end

function M.buildFloors(pools, choices)
    local out = {}
    for i, c in ipairs(choices) do out[i] = M.buildFloor(pools[i], c) end
    return out
end

return M
