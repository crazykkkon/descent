-- 井的契约（第一版只有"不喝血瓶"一种条件）。和 TypeScript 原型 src/core/contract.ts 一致。
--
-- 1. 楼梯口签约：押金立刻扣掉，属性立刻生效，作用在下一层。
-- 2. 下一层喝下任何一瓶血瓶的那一刻就毁约：押金归井，拿到的属性留着。
-- 3. 守约走到出口：退还 refund 生命和 gold 金币。

local config = require('core.config')
local combat = require('core.combat')
local floorMod = require('core.floor')

local M = {}

-- 实际要押的生命（井神的钩可以少押）
function M.depositFor(c, hero)
    local w = hero.weapon and config.WEAPONS[hero.weapon]
    return math.max(0, c.deposit - (w and w.contractDiscount or 0))
end

function M.text(c)
    local get = {}
    if c.atk and c.atk ~= 0 then get[#get + 1] = '攻击 +' .. c.atk end
    if c.def and c.def ~= 0 then get[#get + 1] = '防御 +' .. c.def end
    return {
        pay = '押 ' .. c.deposit .. ' 生命',
        get = '立刻得到 ' .. table.concat(get, '、') .. '（永久）',
        cond = '下一层一瓶血瓶都不喝，走到出口',
        reward = '退还 ' .. c.refund .. ' 生命' .. ((c.gold or 0) > 0 and ('，再给 ' .. c.gold .. ' 金币') or ''),
    }
end

-- 签约卡上的"签前 / 签后"对照（和原型 contractPreview 一致）：每种怪按开局时的周围算一次，
-- 只列签约后有变化的，按省下的血从多到少排（打不动 → 打得动排最前），最多 max 行。
-- 返回 { { name, before, after, saved } }，saved 为 nil 表示从打不过变成打得过。
function M.preview(next, hero, c, max)
    max = max or 4
    local p = floorMod.parse(next)
    local signed = config.copyHero(hero)
    signed.atk, signed.def = hero.atk + (c.atk or 0), hero.def + (c.def or 0)
    local function text(h, m)
        local r = combat.simulate(h, m)
        if not r.canAttack then return '打不动', nil end
        if not r.canWin then return '打不死', nil end
        return '-' .. r.damage, r.damage
    end
    local seen, rows = {}, {}
    for i, cell in ipairs(p.cells) do
        if cell.kind == 'monster' then
            local m = config.monsterInContext(config.MONSTERS[cell.id], floorMod.adjacentMonsters(p.cells, p.w, p.h, i))
            local key = m.id .. ':' .. m.atk .. ':' .. m.def
            if not seen[key] then
                seen[key] = true
                local at, ad = text(hero, m)
                local bt, bd = text(signed, m)
                if at ~= bt then
                    rows[#rows + 1] = { name = m.name, before = at, after = bt, saved = (ad and bd) and (ad - bd) or nil, order = #rows }
                end
            end
        end
    end
    -- 和 JS 的稳定排序一致：省得多的在前，相同时保持出现顺序
    table.sort(rows, function(x, y)
        local a, b = x.saved or math.huge, y.saved or math.huge
        if a ~= b then return a > b end
        return x.order < y.order
    end)
    local out = {}
    for k = 1, math.min(max, #rows) do rows[k].order = nil; out[k] = rows[k] end
    return out
end

return M
