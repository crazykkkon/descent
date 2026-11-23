-- 和格子交互的规则。和 TypeScript 原型 src/core/rules.ts 一致。

local config = require('core.config')
local combat = require('core.combat')

local M = {}

-- 返回 { ok = true, hero, fatal?, reason? } 或 { ok = false, reason }
-- allowFatal：游戏里允许硬打（打完就死）；求解器不允许。
-- mon：怪物算上周围格子（群居、庇护）以后的属性；不传就用怪物本身的数值
function M.interact(cell, hero, floor, ch, allowFatal, mon)
    if cell.kind == 'monster' then
        local m = mon or config.MONSTERS[cell.id]
        local r = combat.simulate(hero, m)
        local reason
        if not r.canAttack then reason = '打不动' .. m.name .. '：攻击要高于它的防御 ' .. m.def
        elseif not r.canWin then reason = '打不死' .. m.name .. '：它回血比你打得快'
        elseif r.damage >= hero.hp then reason = '打' .. m.name .. '要损失 ' .. r.damage .. ' 生命，你会死'
        end
        if reason then
            if allowFatal then
                local h = config.copyHero(hero)
                h.hp = 0
                return { ok = true, hero = h, fatal = true, reason = reason }
            end
            return { ok = false, reason = reason }
        end
        local h = config.copyHero(hero)
        local w = hero.weapon and config.WEAPONS[hero.weapon]
        h.hp = hero.hp - r.damage + (w and w.killHeal or 0)
        h.gold = hero.gold + m.gold
        return { ok = true, hero = h }
    elseif cell.kind == 'item' then
        local h = config.copyHero(hero)
        local gem = floor.gem + ch.gemBonus
        local id = cell.id
        if id == 'smallPotion' then h.hp = h.hp + floor.smallPotion
        elseif id == 'bigPotion' then h.hp = h.hp + floor.bigPotion
        elseif id == 'redGem' then h.atk = h.atk + gem
        elseif id == 'blueGem' then h.def = h.def + gem
        elseif id == 'key' then h.keys = h.keys + 1
        elseif id == 'gold' then h.gold = h.gold + floor.gold
        end
        return { ok = true, hero = h }
    elseif cell.kind == 'door' then
        if cell.door == 'bone' then
            if hero.keys <= 0 then return { ok = false, reason = '没有骨钥，打不开骨门' } end
            local h = config.copyHero(hero)
            h.keys = h.keys - 1
            return { ok = true, hero = h }
        end
        if hero.hp <= floor.bloodCost then
            return { ok = false, reason = '穿过血门要扣 ' .. floor.bloodCost .. ' 生命，你会死' }
        end
        local h = config.copyHero(hero)
        h.hp = h.hp - floor.bloodCost
        return { ok = true, hero = h }
    end
    return { ok = false, reason = '' }
end

function M.isElite(cell)
    return cell.kind == 'monster' and config.MONSTERS[cell.id].elite == true
end

function M.isPotion(cell)
    return cell.kind == 'item' and (cell.id == 'smallPotion' or cell.id == 'bigPotion')
end

return M
