-- 回放的数字和跳过时的血量不在 TS 规则算例里。用真实战斗日志检查混合效果。
local combat = require('core.combat')
local config = require('core.config')
local feedback = require('view.battle_feedback')
local battle = require('view.battle')

local log = {}
combat.simulate({ hp = 100, atk = 16, def = 0, boons = { 'thorns', 'lifesteal' } },
    { hp = 18, atk = 40, def = 0, traits = { thorns = true, lifesteal = true } }, log)
local readouts = feedback.new()
local function apply(event, before)
    local tags = {}
    for _, tag in ipairs(event.tags) do tags[tag] = true end
    feedback.hit(readouts, event, tags, before)
end
apply(log[1], 18)
assert(readouts.mon.hit.value == '−16' and log[1].loss == -1)
assert(readouts.hero.effects[1].value == '−' .. config.THORNS_DAMAGE and readouts.hero.effects[2].value == '+4')
apply(log[2], log[1].mhp)
assert(readouts.hero.hit.value == '−40' and readouts.mon.effects[2].value == '+16') -- 只恢复缺少的 16
apply({ who = 'mon', hit = 0, tags = {} }, 1)
assert(readouts.hero.hit.value == '0' and readouts.hero.hit.label == '格挡')
apply({ who = 'hero', hit = 0, tags = {} }, 1)
assert(readouts.mon.hit.value == '0' and readouts.mon.hit.label == '未破防')
apply({ who = 'skip', mhp = 7, loss = -2, tags = {} }, 16)
assert(readouts.mon.hit.value == '−9' and readouts.hero.hit.value == '+2')
feedback.update(readouts, 1)
assert(not readouts.mon.hit and not readouts.hero.hit and #readouts.mon.effects == 0)

local previousLove = love
love = { math = { random = math.random } }
for _, speed in ipairs({ 1, 2.5 }) do
    for _, elapsed in ipairs({ 0, 0.04, 0.19, 0.40, 1 }) do
        local finishes = 0
        battle.start({ heroHp = 25, monHp = 8, mon = { id = 'moss' }, speed = speed, log = {
            { who = 'mon', hit = 4, loss = 4, mhp = 8, tags = {} },
            { who = 'hero', hit = 8, loss = 3, mhp = 0, tags = { 'thorns', 'kill' } },
        }, onDone = function() finishes = finishes + 1 end })
        battle.update(0.16)
        for _ = 1, math.floor(elapsed * 120) do battle.update(1 / 120) end
        battle.skip()
        assert(battle.heroHp() == 18)
        battle.skip()
        battle.update(0.2)
        assert(not battle.active() and finishes == 1)
    end
end
love = previousLove
print('战斗回放检查通过（分项飘字、零伤、快进、两种速度下跳过）')
