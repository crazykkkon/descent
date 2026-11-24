-- 战斗公式：完全固定、没有随机。预览和实际结算用同一个函数，保证"预览掉血 = 实际掉血"。
-- 和 TypeScript 原型 src/core/combat.ts 一致。

local config = require('core.config')

local M = {}

local MAX_ROUNDS = 1000

-- 算上武器以后的攻防
function M.effectiveStats(hero)
    local w = hero.weapon and config.WEAPONS[hero.weapon]
    return hero.atk + (w and w.atk or 0), hero.def + (w and w.def or 0)
end

-- 返回 { canAttack, canWin, damage, hits }。hero.boons：骨坛移到武器上的特性（列表）
function M.simulate(hero, m)
    local w = hero.weapon and config.WEAPONS[hero.weapon]
    local boons = {}
    for _, b in ipairs(hero.boons or {}) do boons[b] = true end
    local atk, def = M.effectiveStats(hero)
    local lifestealMon = m.traits.lifesteal == true
    local pierce = w and w.pierce or 0
    local mdef = m.def
    local function heroHitNow()
        local hit = math.max(atk - math.max(mdef - pierce, 0), 0)
        if w and w.antiLifesteal and lifestealMon then hit = hit * 2 end
        return hit
    end
    if heroHitNow() == 0 then return { canAttack = false, canWin = false, damage = 0, hits = 0 } end

    local hitsPerRound = m.traits.double and 2 or 1
    local thorns = m.traits.thorns == true
    local corrode = m.traits.corrode == true
    -- 腐蚀：怪物每打一下，主角这场战斗的防御 −1
    local curDef = def

    local mhp = m.hp
    local damage, heal, hits = 0, 0, 0
    local function done() return { canAttack = true, canWin = true, damage = math.max(damage - heal, 0), hits = hits } end

    local function heroAttack()
        local hit = heroHitNow()
        mhp = mhp - hit
        hits = hits + 1
        if thorns then damage = damage + config.THORNS_DAMAGE end
        if boons.lifesteal then heal = heal + math.floor(hit / 4) end
        if boons.corrode then mdef = mdef - 1 end
        return mhp <= 0
    end
    local function monsterAttack()
        local monsterHit = math.max(m.atk - curDef, 0)
        damage = damage + monsterHit
        if lifestealMon then mhp = math.min(m.hp, mhp + math.floor(monsterHit / 2)) end
        if corrode then curDef = curDef - config.CORRODE_DEF end
        if boons.thorns then mhp = mhp - config.THORNS_DAMAGE end
        return mhp <= 0
    end

    -- 开打前先刺：鱼叉一下、骨坛的先攻一下（可以叠加）
    local opening = (w and w.firstHit and 1 or 0) + (boons.firstStrike and 1 or 0)
    for _ = 1, opening do if heroAttack() then return done() end end
    if m.traits.firstStrike and not (w and w.noFirstStrike) then
        if monsterAttack() then return done() end
    end

    for _ = 1, MAX_ROUNDS do
        if heroAttack() then return done() end
        for _ = 1, hitsPerRound do
            if monsterAttack() then return done() end
        end
    end
    return { canAttack = true, canWin = false, damage = damage, hits = hits }
end

return M
