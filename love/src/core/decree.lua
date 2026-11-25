-- 井神的诏令：和原型 src/core/decree.ts 一致。
local rng = require('core.rng')
local M = {}

M.TIER_NAMES = { bronze = '铜', silver = '银' }
M.PENALTY = { bronze = 1, silver = 2 }
M.SILVER_BONUS_HP = 100
M.FLOORS = { [3] = true, [8] = true, [13] = true } -- Lua 的层号（从 1 开始）
M.SPAN = 3

M.DECREES = {
    { kind = 'killTrait', tier = 'bronze', n = 2, text = '累计击败 2 只具有先攻、吸血或反伤特性的怪物' },
    { kind = 'noPotion', tier = 'bronze', n = 1, text = '在任意一层不喝血瓶，抵达出口' },
    { kind = 'clear', tier = 'silver', n = 1, text = '在任意一层击败所有怪物，再前往出口' },
    { kind = 'noLoss', tier = 'silver', n = 1, text = '离开任意一层时，剩余生命至少和进这一层时一样多' },
    { kind = 'gold', tier = 'silver', n = 150, text = '离开任意一层时，持有至少 150 金币' },
}

local function copy(d) return { kind = d.kind, tier = d.tier, n = d.n, text = d.text } end

local previousText = {
    killTrait = '打败 2 只会先攻、吸血或反伤的怪',
    noPotion = '有一层一瓶血瓶都不喝，走到出口',
    clear = '有一层把怪全部打完再走',
    noLoss = '有一层走出去时的生命不比进来时少',
    gold = '带着至少 150 金币走出一层',
}

-- 存档里的诏令可能带旧文案。只有目标和数量一致时才更新说明。
function M.restore(def)
    if not def or def.text ~= previousText[def.kind] then return def end
    for _, d in ipairs(M.DECREES) do
        if d.kind == def.kind and d.tier == def.tier and d.n == def.n then return copy(d) end
    end
    return def
end

-- 第 floorIndex 层（从 1 开始）开头来的诏令；不是诏令层返回 nil
function M.decreeFor(seed, floorIndex)
    if not M.FLOORS[floorIndex] then return nil end
    -- 原型用 0 开始的层号做随机数的键
    return copy(M.DECREES[rng.pick(seed, 7000 + floorIndex - 1, 0, #M.DECREES) + 1])
end

function M.killCounts(def, m)
    return def.kind == 'killTrait' and (m.traits.firstStrike or m.traits.lifesteal or m.traits.thorns) and true or false
end

return M
