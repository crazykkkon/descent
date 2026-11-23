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

-- 返回 { canAttack, canWin, damage, hits }
function M.simulate(hero, m)
    local w = hero.weapon and config.WEAPONS[hero.weapon]
    local atk, def = M.effectiveStats(hero)
    local lifesteal = m.traits.lifesteal == true
    local pierce = w and w.pierce or 0
    local heroHit = math.max(atk - math.max(m.def - pierce, 0), 0)
    if w and w.antiLifesteal and lifesteal then heroHit = heroHit * 2 end
    if heroHit == 0 then return { canAttack = false, canWin = false, damage = 0, hits = 0 } end

    local corrode = m.traits.corrode == true
    -- 腐蚀：怪物每打一下，主角这场战斗的防御 −1
    local curDef = def
    local hitsPerRound = m.traits.double and 2 or 1
    local thorns = m.traits.thorns == true

    local mhp = m.hp
    local damage = 0
    local hits = 0

    local function monsterAttack()
        local monsterHit = math.max(m.atk - curDef, 0)
        damage = damage + monsterHit
        if lifesteal then mhp = math.min(m.hp, mhp + math.floor(monsterHit / 2)) end
        if corrode then curDef = curDef - config.CORRODE_DEF end
    end

    -- 鱼叉：开打前先刺一下
    if w and w.firstHit then
        mhp = mhp - heroHit
        hits = hits + 1
        if thorns then damage = damage + config.THORNS_DAMAGE end
        if mhp <= 0 then return { canAttack = true, canWin = true, damage = damage, hits = hits } end
    end
    if m.traits.firstStrike and not (w and w.noFirstStrike) then monsterAttack() end

    for _ = 1, MAX_ROUNDS do
        mhp = mhp - heroHit
        hits = hits + 1
        if thorns then damage = damage + config.THORNS_DAMAGE end
        if mhp <= 0 then return { canAttack = true, canWin = true, damage = damage, hits = hits } end
        for _ = 1, hitsPerRound do monsterAttack() end
    end
    return { canAttack = true, canWin = false, damage = damage, hits = hits }
end

return M
