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
    rat        = { id = 'rat',        name = '井鼠',     hp = 40,  atk = 34, def = 14, gold = 8,  traits = T('swarm'), basePower = 3 },
    slug       = { id = 'slug',       name = '盐蚀蛞蝓', hp = 90,  atk = 38, def = 18, gold = 14, traits = T('corrode'), basePower = 3 },
    priest     = { id = 'priest',     name = '骸骨祭司', hp = 100, atk = 30, def = 22, gold = 16, traits = T('shelter'), basePower = 3 },
    gatekeeper = { id = 'gatekeeper', name = '守门人',   hp = 160, atk = 44, def = 24, gold = 80, traits = T('double'), elite = true, basePower = 5 },
    -- 第 20 层 Boss 的占位（站位战还没做）
    eye        = { id = 'eye',        name = '井底之眼', hp = 500, atk = 70, def = 34, gold = 0,  traits = T(), elite = true, basePower = 12 },
    -- 第 6 层起换掉 7 种小怪的更凶的同类（数值是讨论项）
    thornMoss    = { id = 'thornMoss',    name = '棘苔',   hp = 39,  atk = 25, def = 7,  gold = 5,  traits = T() },
    spikeEel     = { id = 'spikeEel',     name = '刺鳗',   hp = 58,  atk = 30, def = 10, gold = 9,  traits = T() },
    armorFrog    = { id = 'armorFrog',    name = '铠蛙',   hp = 78,  atk = 32, def = 13, gold = 15, traits = T() },
    ironBeetle   = { id = 'ironBeetle',   name = '铁甲虫', hp = 52,  atk = 28, def = 19, gold = 14, traits = T() },
    shriekBat    = { id = 'shriekBat',    name = '啸蝠',   hp = 45,  atk = 35, def = 11, gold = 14, traits = T('firstStrike') },
    grudgeWraith = { id = 'grudgeWraith', name = '怨魂',   hp = 92,  atk = 34, def = 13, gold = 22, traits = T('lifesteal') },
    shardCrab    = { id = 'shardCrab',    name = '碎岩蟹', hp = 82,  atk = 36, def = 15, gold = 22, traits = T('thorns') },
}

-- 正式局的怪物数值（宝石分大小以后主角的攻防只有原来的一半多一点；教程和测试小图还用上面的原始数值）。和原型 RUN_STATS 一致
M.RUN_STATS = {
    moss = { hp = 30, atk = 13, def = 2 },
    eel = { hp = 45, atk = 17, def = 4 },
    frog = { hp = 60, atk = 18, def = 6 },
    beetle = { hp = 40, atk = 14, def = 9 },
    bat = { hp = 35, atk = 20, def = 4 },
    wraith = { hp = 80, atk = 20, def = 6 },
    crab = { hp = 70, atk = 22, def = 8 },
    guardian = { hp = 90, atk = 17, def = 9 },
    rat = { hp = 44, atk = 21, def = 7 },
    slug = { hp = 99, atk = 23, def = 9 },
    priest = { hp = 110, atk = 18, def = 11 },
    gatekeeper = { hp = 176, atk = 27, def = 12 },
    eye = { hp = 550, atk = 42, def = 18 },
    thornMoss = { hp = 43, atk = 16, def = 4 },
    spikeEel = { hp = 64, atk = 19, def = 5 },
    armorFrog = { hp = 86, atk = 20, def = 7 },
    ironBeetle = { hp = 57, atk = 18, def = 10 },
    shriekBat = { hp = 50, atk = 22, def = 6 },
    grudgeWraith = { hp = 101, atk = 21, def = 7 },
    shardCrab = { hp = 90, atk = 23, def = 8 },
}
M.RUN_SWARM_ATK, M.RUN_SHELTER_DEF = 3, 3

-- 井越深，怪越凶：第 7 层起每往下一层（power +1），怪物攻击 +DEPTH_ATK/10、防御 +DEPTH_DEF/10（向下取整）、生命 +DEPTH_HP%，一直加到第 20 层；
-- 本来就是深处的怪带 basePower（先扣掉），精英再减半；run = 正式局，先换成 RUN_STATS（和原型 config.powered 一致）
M.DEPTH_ATK, M.DEPTH_DEF, M.DEPTH_HP = 28, 5, 12
function M.powered(m, power, run)
    local r = run and M.RUN_STATS[m.id]
    if r then
        local t = {}
        for k, v in pairs(m) do t[k] = v end
        t.hp, t.atk, t.def = r.hp, r.atk, r.def
        m = t
    end
    power = math.max(0, (power or 0) - (m.basePower or 0))
    if m.elite then power = math.floor(power / 2) end
    if power == 0 then return m end
    local t = {}
    for k, v in pairs(m) do t[k] = v end
    t.hp = math.floor(m.hp * (100 + M.DEPTH_HP * power) / 100)
    t.atk = m.atk + math.floor(M.DEPTH_ATK * power / 10)
    t.def = m.def + math.floor(M.DEPTH_DEF * power / 10)
    return t
end

-- 第 6 层起，地图上的 7 种小怪换成更凶的同类（地图字符 → 换成的字符）
M.UPGRADE_CHARS = { m = 'a', e = 'i', f = 'j', c = 'l', v = 'n', g = 'o', x = 'q' }

-- 按周围格子算出怪物这一刻的真实属性（群居、庇护）。adjacent：相邻格子上还活着的怪物 id 列表
function M.monsterInContext(m, adjacent, power, run)
    m = M.powered(m, power, run)
    local atk, def = m.atk, m.def
    local sheltered = false
    for _, id in ipairs(adjacent) do
        if m.traits.swarm and id == m.id then atk = atk + (run and M.RUN_SWARM_ATK or M.SWARM_ATK) end
        if M.MONSTERS[id].traits.shelter then sheltered = true end
    end
    if sheltered then def = def + (run and M.RUN_SHELTER_DEF or M.SHELTER_DEF) end
    if atk == m.atk and def == m.def then return m end
    local t = {}
    for k, v in pairs(m) do t[k] = v end
    t.atk, t.def = atk, def
    return t
end

M.WEAPONS = {
    boneKnife  = { id = 'boneKnife',  name = '骨刀',     desc = '攻击 +2', atk = 2, def = 0, sell = 25 },
    harpoon    = { id = 'harpoon',    name = '鱼叉',     desc = '每场战斗开始先刺一下（多一次攻击）', atk = 0, def = 0, firstHit = true, sell = 25 },
    hammer     = { id = 'hammer',     name = '破壳锤',   desc = '攻击无视怪物 2 点防御', atk = 0, def = 0, pierce = 2, sell = 30 },
    mossBlade  = { id = 'mossBlade',  name = '苔衣短剑', desc = '每次击杀回复 8 生命', atk = 0, def = 0, killHeal = 8, sell = 25 },
    bellStaff  = { id = 'bellStaff',  name = '回声铃杖', desc = '攻击 +1；敌人的"先攻"失效', atk = 1, def = 0, noFirstStrike = true, sell = 25 },
    saltDagger = { id = 'saltDagger', name = '盐晶匕首', desc = '对会吸血的怪伤害翻倍', atk = 0, def = 0, antiLifesteal = true, sell = 25 },
    rustSword  = { id = 'rustSword',  name = '锈蚀大剑', desc = '攻击 +5，防御 −3（诅咒）', atk = 5, def = -3, sell = 35 },
    wellHook   = { id = 'wellHook',   name = '井神的钩', desc = '每次击杀多得 5 金币', atk = 0, def = 0, killGold = 5, sell = 40 },
    -- 下面两把要用灵魂碎片解锁
    lamp       = { id = 'lamp',       name = '井灯',     desc = '防御 +2', atk = 0, def = 2, sell = 30 },
    twinHook   = { id = 'twinHook',   name = '双钩',     desc = '攻击 +1；每次击杀回复 4 生命', atk = 1, def = 0, killHeal = 4, sell = 30 },
}

-- 武器的固定顺序（和原型 WEAPONS 的键顺序一致，三选一的随机数按这个顺序取）
M.WEAPON_ORDER = { 'boneKnife', 'harpoon', 'hammer', 'mossBlade', 'bellStaff', 'saltDagger', 'rustSword', 'wellHook' }

M.ITEM_NAMES = {
    smallPotion = '小血瓶', bigPotion = '大血瓶', redGem = '小赤晶', blueGem = '小青晶', bigRedGem = '大赤晶', bigBlueGem = '大青晶', key = '骨钥', gold = '金币袋',
}
-- 大宝石加多少（制作人定：小宝石 +1、大宝石 +3；小宝石的数值在楼层的 gem 里）
M.BIG_GEM = 3

M.CHARACTERS = {
    digger = {
        -- 原来的特长"宝石效果 +1"去掉了（制作人定：小宝石就是 +1、大宝石就是 +3）；要不要换一个特长是讨论项
        id = 'digger', name = '掘井人', desc = '老练的矿工，生命最多。',
        base = { hp = 200, atk = 10, def = 10, keys = 0, gold = 0 },
        gemBonus = 0,
    },
    -- 下面两个要用灵魂碎片解锁
    scavenger = {
        id = 'scavenger', name = '拾荒者', desc = '开骨门不用骨钥，改成每次扣 10 生命；骨钥留着卖钱。',
        base = { hp = 150, atk = 9, def = 8, keys = 0, gold = 30 },
        gemBonus = 0, boneDoorHp = 10,
    },
    drowned = {
        id = 'drowned', name = '溺者', desc = '倒下时复活一次（生命回到 50），之后每进一层扣 20 生命。',
        base = { hp = 100, atk = 14, def = 6, keys = 0, gold = 0 },
        gemBonus = 0, revive = 50, drain = 20,
    },
}

-- 出口交易
M.EXIT = { leftoverPotionGold = 5, keySellGold = 15 }

-- 骨坛能移到武器上的特性（来自杀过的怪）
M.BOON_NAMES = { lifesteal = '吸血', firstStrike = '先攻', thorns = '反伤', corrode = '腐蚀' }
M.BOON_DESC = {
    lifesteal = '你每次命中回复造成伤害的四分之一（不超过这一仗掉的血）',
    firstStrike = '开打前你先打一下',
    thorns = '怪每打你一下，它自己掉 3 血',
    corrode = '你每打中一下，怪这一仗的防御 −1',
}
M.BOON_ORDER = { 'lifesteal', 'firstStrike', 'thorns', 'corrode' }

-- 印记怪：打败后可以把对应的武器刻到断臂转轮上
M.MARK_WEAPON = { eel = 'harpoon', moss = 'mossBlade', frog = 'boneKnife', bat = 'bellStaff', wraith = 'saltDagger', crab = 'hammer', beetle = 'rustSword', rat = 'wellHook',
    thornMoss = 'mossBlade', spikeEel = 'harpoon', armorFrog = 'boneKnife', ironBeetle = 'rustSword', shriekBat = 'bellStaff', grudgeWraith = 'saltDagger', shardCrab = 'hammer' }
-- 杀过这种怪，骨坛上就能移它的特性
M.MONSTER_BOON = { wraith = 'lifesteal', bat = 'firstStrike', crab = 'thorns', slug = 'corrode', grudgeWraith = 'lifesteal', shriekBat = 'firstStrike', shardCrab = 'thorns' }

local function copyList(t)
    if not t then return nil end
    local o = {}
    for i, x in ipairs(t) do o[i] = x end
    return o
end
M.copyList = copyList

function M.copyHero(h)
    return { hp = h.hp, atk = h.atk, def = h.def, keys = h.keys, gold = h.gold, weapon = h.weapon, boons = copyList(h.boons) }
end

return M
