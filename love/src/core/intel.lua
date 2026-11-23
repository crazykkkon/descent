-- 楼梯口情报：和 TypeScript 原型 src/core/intel.ts 的 stairIntel 一致。
-- Lua 版不带求解器：情报说哪只怪，事先在原型里用 choosePick 选好，写进关卡数据的 intelPick
-- （cell 是 Lua 的 1 开始下标）。这里只按现在的属性算掉血对比。

local config = require('core.config')
local combat = require('core.combat')
local floorMod = require('core.floor')

local M = {}

M.HIGH_DEF = 14

local function damageText(hero, m)
    local r = combat.simulate(hero, m)
    if not r.canAttack then return '打不动' end
    if not r.canWin then return '打不死' end
    -- 只给数字，不替玩家下"会不会死"的结论
    return '-' .. r.damage
end

local function with(hero, atk, def)
    local h = config.copyHero(hero)
    h.atk, h.def = atk, def
    return h
end

-- next：下一层；hero：主角现在的属性；current：{ floor, cells } 当前层（找没拿的宝石），可以不传
-- 返回 { headline, lines, monster, mustFight }；下一层没有怪或没写 intelPick 时返回 nil
function M.stairIntel(next, hero, ch, current)
    if not next.intelPick then return nil end
    local p = floorMod.parse(next)
    local c = p.cells[next.intelPick.cell]
    assert(c and c.kind == 'monster', next.name .. '：intelPick 指向的格子不是怪物')
    local pick = config.MONSTERS[c.id]
    local mustFight = next.intelPick.mustFight
    local t = pick.traits

    local where = mustFight and '挡在必经之路上' or '守在主要路线上'
    local headline
    if pick.def >= M.HIGH_DEF then headline = '下一层有高防守卫：' .. pick.name .. where
    elseif t.lifesteal then headline = '下一层有会吸血的' .. pick.name .. where
    elseif t.firstStrike then headline = '下一层有先手攻击的' .. pick.name .. where
    elseif t.thorns then headline = '下一层有会反伤的' .. pick.name .. where
    else headline = '下一层的' .. pick.name .. where end

    local lines = { pick.name .. '：生命 ' .. pick.hp .. '　攻击 ' .. pick.atk .. '　防御 ' .. pick.def }
    if pick.def >= M.HIGH_DEF then lines[#lines + 1] = '攻击要高于 ' .. pick.def .. ' 才打得动它' end
    if t.lifesteal then lines[#lines + 1] = '它会吸血，攻击不够高就打不死' end
    if t.firstStrike then lines[#lines + 1] = '它会先打你一下，防御越高越好打' end
    if t.thorns then lines[#lines + 1] = '你每打它一下自己也掉 3 血，攻击越高、打的次数越少' end
    lines[#lines + 1] = '按你现在的属性（攻 ' .. hero.atk .. ' / 防 ' .. hero.def .. '）打它：' .. damageText(hero, pick)

    if current then
        local gem = current.floor.gem + ch.gemBonus
        local reds, blues = 0, 0
        for _, x in ipairs(current.cells) do
            if x.kind == 'item' and x.id == 'redGem' then reds = reds + 1 end
            if x.kind == 'item' and x.id == 'blueGem' then blues = blues + 1 end
        end
        local a, d = hero.atk + gem * reds, hero.def + gem * blues
        if reds > 0 then lines[#lines + 1] = '本层还有 ' .. reds .. ' 颗赤晶没拿，拿了以后（攻 ' .. a .. '）打它：' .. damageText(with(hero, a, hero.def), pick) end
        if blues > 0 then lines[#lines + 1] = '本层还有 ' .. blues .. ' 颗青晶没拿，拿了以后（防 ' .. d .. '）打它：' .. damageText(with(hero, hero.atk, d), pick) end
        if reds > 0 and blues > 0 then lines[#lines + 1] = '两种都拿（攻 ' .. a .. ' / 防 ' .. d .. '）：' .. damageText(with(hero, a, d), pick) end
    end
    return { headline = headline, lines = lines, monster = pick.id, mustFight = mustFight }
end

return M
