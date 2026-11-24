-- 新手教程局的教学提示（制作人：开局 5 层做成教学关卡的样子，后面不需要过多的提示）。
-- 一层只教一件事；按玩家走到哪一步换下一句。只在教程局显示，正式局不显示任何提示。
-- 地图在原型 src/core/route.ts 的 TUTORIAL_FLOORS（固定 5 张）。

local floorMod = require('core.floor')

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
            return '血瓶走上去就喝，生命 +' .. run:floor().smallPotion .. '。最后打掉盲鳗，走到左边绿色的台阶（出口）就进下一层。不用把怪打完。'
        end
        if h.def > s.def then return '青晶加防御：怪打你没那么疼了。鼠标停在格子上，能看到它的详细数值。' end
        if h.atk > s.atk then return '攻击变高了。看看下一只井苔头上的牌子：掉的血变少了。先拿宝石再打，更划算。' end
        if run.kills >= 1 then return '打赢了，还掉了几个金币。前面红色的是赤晶，走上去就捡：攻击 +' .. (run:floor().gem + run.ch.gemBonus) .. '。' end
        if run.steps >= 1 then return '怪物头上的牌子是打它要掉的血。走过去就会打，打赢后站到它的格子上。' end
        return '用方向键或者点格子走路。按住方向键可以一直走。'
    end,
    -- 第 2 层：骨钥和骨门、打不动的怪、血瓶
    function(run, s)
        if doors(run) < s.doors then
            return '红牌子「打不动」：你的攻击不比锈甲虫的防御高。拿了门后的赤晶就打得动了，但要掉很多血换一袋金币——值不值得，自己算。出口在右边。'
        end
        if run.hero.keys > s.keys then return '拿到骨钥了。走到骨门上，就会用掉一把骨钥把门打开。' end
        return '骨门要骨钥才能开。骨钥在井苔身后，往下走。顺路的血瓶走上去就喝。'
    end,
    -- 第 3 层：两条路怎么选
    function(run, s)
        if run.kills >= 1 or doors(run) < s.doors then
            return '走过的路不能撤回，死了要从第 1 层重来。每走一步之前，先看看牌子上的数。'
        end
        return '两条路都能到出口。上面：过血门（不用钥匙，扣 ' .. run:floor().bloodCost .. ' 生命），还有一只会先出手的回声蝠。下面：打两只怪，路上有一颗赤晶。自己算哪条划算。'
    end,
    -- 第 4 层：精英
    function(run)
        if not run:eliteAlive() then return '精英倒下了，出口开了。' end
        return '带「守」字的是精英：它不倒，出口就打不开。它每回合打你两下——先把宝石和血瓶都拿到手，再去打它。'
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
