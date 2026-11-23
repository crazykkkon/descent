-- 井的契约（第一版只有"不喝血瓶"一种条件）。和 TypeScript 原型 src/core/contract.ts 一致。
--
-- 1. 楼梯口签约：押金立刻扣掉，属性立刻生效，作用在下一层。
-- 2. 下一层喝下任何一瓶血瓶的那一刻就毁约：押金归井，拿到的属性留着。
-- 3. 守约走到出口：退还 refund 生命和 gold 金币。

local config = require('core.config')

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

return M
