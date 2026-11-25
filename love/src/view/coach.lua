-- 新手教程局的教学提示（制作人：开局 5 层做成教学关卡的样子，后面不需要过多的提示）。
-- 一层只教一件事；按玩家走到哪一步换下一句。只在教程局显示，正式局不显示任何提示。
-- 地图在原型 src/core/route.ts 的 TUTORIAL_FLOORS（固定 5 张）。

local floorMod = require('core.floor')
local config = require('core.config')

local M = {}

local function count(run, pred)
    local n = 0
    for _, c in ipairs(run.cells) do if pred(c) then n = n + 1 end end
    return n
end
local function items(run, id) return count(run, function(c) return c.kind == 'item' and c.id == id end) end
local function doors(run) return count(run, function(c) return c.kind == 'door' end) end

-- 每层一个函数：返回这一刻该说的那句话。s 是进这一层时的状态（属性、各种道具的个数）
local FLOORS = {
    -- 第 1 层：走路、打怪、宝石让掉血变少、血瓶、出口
    function(run, s)
        local h = run.hero
        if items(run, 'smallPotion') < s.potions then
            return '踩到血瓶会自动喝下，恢复' .. run:floor().smallPotion .. '点生命。击败左边挡路的盲鳗，就能沿石阶下楼。'
        end
        if h.def > s.def then return '大青晶提高了防御。现在挨同样的一击，掉的血会更少。' end
        if h.atk > s.atk then return '攻击提高了。现在打下一只井苔，能更快结束战斗，少挨几下。' end
        if run.kills >= 1 then return '前面那颗红色晶簇是大赤晶。走过去拾取，攻击增加' .. (config.BIG_GEM + run.ch.gemBonus) .. '点。' end
        if run.steps >= 1 then return '指向怪物可查看攻防。普通攻击时，你的攻击比它的防御高几点，就能打掉几点生命。它打你也这样算。' end
        return '点地面或按方向键移动。按住方向键可连续走。走到怪物那一格就会开战。'
    end,
    -- 第 2 层：骨钥和骨门、打不动的怪、血瓶
    function(run, s)
        if doors(run) < s.doors then
            return '右边就是出口。想拿岔路里的金币？先捡门后的大赤晶，再看看你的攻击能不能穿透锈甲虫的甲壳。'
        end
        if run.hero.keys > s.keys then return '拿到骨钥了。走向骨门会自动用一把钥匙开门。' end
        return '往下走，骨钥就在井苔身后。拿到钥匙就能打开骨门。'
    end,
    -- 第 3 层：两条路怎么选
    function(run, s)
        if run.kills >= 1 or doors(run) < s.doors then
            return '可以折返，也可以直接下楼。已经损失的生命不会因折返而恢复。'
        end
        return '上下两条路都通向出口。上路有先出手的回声蝠，过血门还要花' .. run:floor().bloodCost .. '点生命。下路有两只怪，也有一颗大赤晶。'
    end,
    -- 第 4 层：精英
    function(run)
        if not run:eliteAlive() then return '守卫倒下了，可以下楼了。' end
        return '石鳞守卫封住了出口，每回合能攻击两次。先沿路收集宝石和血瓶，再去挑战它。'
    end,
    -- 第 5 层：井底之眼
    function()
        return '井底。出口前趴着一个巨大的东西……往前走吧。'
    end,
}

local state = { key = nil, start = nil, text = nil, changed = 0 }

-- 每帧调用：返回当前的提示和"刚换了多久"（用来闪一下）；不是教程局返回 nil
function M.current(run, clock)
    if not run.tutorial or run.status ~= 'playing' then return nil end
    local f = FLOORS[run.floorIndex]
    if not f then return nil end
    local key = run.seed .. ':' .. run.floorIndex
    if state.key ~= key then
        -- 进层时的状态：属性取进层快照，道具和门的个数按地图原样数（读档后也对）
        local h = run:floorStartHero()
        local fresh = { cells = floorMod.parse(run:floor()).cells }
        state = {
            key = key, text = nil, changed = clock,
            start = { atk = h.atk, def = h.def, keys = h.keys, potions = items(fresh, 'smallPotion'), doors = doors(fresh) },
        }
    end
    -- 去掉空格：LÖVE 按空格换行，中文里夹的空格会让数字和单位断开
    local t = (f(run, state.start):gsub(' ', ''))
    if t ~= state.text then state.text = t; state.changed = clock end
    return t, clock - state.changed
end

return M
