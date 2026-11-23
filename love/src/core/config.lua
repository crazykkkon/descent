-- 静态配置：怪物、武器、道具、角色。
-- 数值和 TypeScript 原型（src/core/config.ts）完全一致，用 tests/vectors.lua 对账。

local M = {}

M.THORNS_DAMAGE = 3
M.SWARM_ATK = 5     -- 群居：每只相邻同类加的攻击
M.CORRODE_DEF = 1   -- 腐蚀：怪物每次命中让主角这场战斗的防御减多少
M.SHELTER_DEF = 6   -- 庇护：相邻其他怪物加的防御（不叠加）

M.TRAIT_NAMES = {
    firstStrike = '先攻', lifesteal = '吸血', thorns = '反伤', double = '二连击',
    swarm = '群居', corrode = '腐蚀', shelter = '庇护',
}
M.TRAIT_DESC = {
    firstStrike = '战斗开始时它先打一次',
    lifesteal = '每次命中，回复造成伤害的一半',
    thorns = '你每次攻击，自己受到 3 点伤害',
    double = '每回合攻击两次',
    swarm = '每有一只相邻的同类，攻击 +5',
    corrode = '每次命中，你在这场战斗里的防御 −1',
    shelter = '相邻的其他怪物防御 +6（几只祭司围着也只加一次）',
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
    -- 下面四只的数值来自原设计方案第 4 章（层位和最终数值是讨论项）
    rat        = { id = 'rat',        name = '井鼠',     hp = 40,  atk = 34, def = 14, gold = 8,  traits = T('swarm') },
    slug       = { id = 'slug',       name = '盐蚀蛞蝓', hp = 90,  atk = 38, def = 18, gold = 14, traits = T('corrode') },
    priest     = { id = 'priest',     name = '骸骨祭司', hp = 100, atk = 30, def = 22, gold = 16, traits = T('shelter') },
    gatekeeper = { id = 'gatekeeper', name = '守门人',   hp = 160, atk = 44, def = 24, gold = 80, traits = T('double'), elite = true },
    -- 第 20 层 Boss 的占位（站位战还没做）
    eye        = { id = 'eye',        name = '井底之眼', hp = 360, atk = 60, def = 32, gold = 0,  traits = T(), elite = true },
}

-- 按周围格子算出怪物这一刻的真实属性（群居、庇护）。adjacent：相邻格子上还活着的怪物 id 列表
function M.monsterInContext(m, adjacent)
    local atk, def = m.atk, m.def
    local sheltered = false
    for _, id in ipairs(adjacent) do
        if m.traits.swarm and id == m.id then atk = atk + M.SWARM_ATK end
        if M.MONSTERS[id].traits.shelter then sheltered = true end
    end
    if sheltered then def = def + M.SHELTER_DEF end
    if atk == m.atk and def == m.def then return m end
    local t = {}
    for k, v in pairs(m) do t[k] = v end
    t.atk, t.def = atk, def
    return t
end

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
