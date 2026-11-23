-- 静态配置：怪物、武器、道具、角色。
-- 数值和 TypeScript 原型（src/core/config.ts）完全一致，用 tests/vectors.lua 对账。

local M = {}

M.THORNS_DAMAGE = 3

M.TRAIT_NAMES = {
    firstStrike = '先攻', lifesteal = '吸血', thorns = '反伤', double = '二连击',
}
M.TRAIT_DESC = {
    firstStrike = '战斗开始时它先打一次',
    lifesteal = '每次命中，回复造成伤害的一半',
    thorns = '你每次攻击，自己受到 3 点伤害',
    double = '每回合攻击两次',
}

-- traits 用集合表示：traits.double == true
local function T(...)
    local t = {}
    for _, k in ipairs({ ... }) do t[k] = true end
    return t
end

M.MONSTERS = {
    moss     = { id = 'moss',     name = '井苔',   hp = 30,  atk = 15, def = 2,  gold = 3,  traits = T() },
    eel      = { id = 'eel',      name = '盲鳗',   hp = 45,  atk = 20, def = 5,  gold = 6,  traits = T() },
    frog     = { id = 'frog',     name = '骨蛙',   hp = 60,  atk = 22, def = 8,  gold = 10, traits = T() },
    beetle   = { id = 'beetle',   name = '锈甲虫', hp = 40,  atk = 18, def = 14, gold = 9,  traits = T() },
    bat      = { id = 'bat',      name = '回声蝠', hp = 35,  atk = 25, def = 6,  gold = 9,  traits = T('firstStrike') },
    wraith   = { id = 'wraith',   name = '溺魂',   hp = 80,  atk = 28, def = 10, gold = 16, traits = T('lifesteal') },
    crab     = { id = 'crab',     name = '裂岩蟹', hp = 70,  atk = 30, def = 12, gold = 16, traits = T('thorns') },
    guardian = { id = 'guardian', name = '石鳞守卫', hp = 90, atk = 26, def = 14, gold = 50, traits = T('double'), elite = true },
}

M.WEAPONS = {
    boneKnife  = { id = 'boneKnife',  name = '骨刀',     desc = '攻击 +4', atk = 4, def = 0, sell = 25 },
    harpoon    = { id = 'harpoon',    name = '鱼叉',     desc = '每场战斗开始先刺一下（多一次攻击）', atk = 0, def = 0, firstHit = true, sell = 25 },
    hammer     = { id = 'hammer',     name = '破壳锤',   desc = '攻击无视怪物 4 点防御', atk = 0, def = 0, pierce = 4, sell = 30 },
    mossBlade  = { id = 'mossBlade',  name = '苔衣短剑', desc = '每次击杀回复 8 生命', atk = 0, def = 0, killHeal = 8, sell = 25 },
    bellStaff  = { id = 'bellStaff',  name = '回声铃杖', desc = '攻击 +1；敌人的"先攻"失效', atk = 1, def = 0, noFirstStrike = true, sell = 25 },
    saltDagger = { id = 'saltDagger', name = '盐晶匕首', desc = '对会吸血的怪伤害翻倍', atk = 0, def = 0, antiLifesteal = true, sell = 25 },
    rustSword  = { id = 'rustSword',  name = '锈蚀大剑', desc = '攻击 +9，防御 −5（诅咒）', atk = 9, def = -5, sell = 35 },
    wellHook   = { id = 'wellHook',   name = '井神的钩', desc = '每次签契约，押金 −20', atk = 0, def = 0, contractDiscount = 20, sell = 40 },
}

-- 武器的固定顺序（和原型 WEAPONS 的键顺序一致，三选一的随机数按这个顺序取）
M.WEAPON_ORDER = { 'boneKnife', 'harpoon', 'hammer', 'mossBlade', 'bellStaff', 'saltDagger', 'rustSword', 'wellHook' }

M.ITEM_NAMES = {
    smallPotion = '小血瓶', bigPotion = '大血瓶', redGem = '赤晶', blueGem = '青晶', key = '骨钥', gold = '金币袋',
}

M.CHARACTERS = {
    digger = {
        id = 'digger', name = '掘井人',
        base = { hp = 200, atk = 10, def = 10, keys = 0, gold = 0 },
        gemBonus = 1,
    },
}

-- 出口交易
M.EXIT = { leftoverPotionGold = 5, keySellGold = 15 }

function M.copyHero(h)
    return { hp = h.hp, atk = h.atk, def = h.def, keys = h.keys, gold = h.gold, weapon = h.weapon }
end

return M
