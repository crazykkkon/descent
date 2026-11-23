-- 白盒第一步：第 2 层"双道"（交接稿建议先做这一层）。
-- 数据和 TypeScript 原型 src/core/levels.ts 里的"双道"完全一致。

local NO_POTION = { condition = 'noPotion', deposit = 50, atk = 3, def = 0, refund = 60, gold = 10 }

local M = {}

-- 第 1 层楼梯口（白盒里第 1 层还没做，先用一个"只有楼梯"的空层代替）
M.stairs = {
    name = '第 1 层 · 井口',
    map = { '@>' },
    bloodCost = 40, gem = 2, smallPotion = 50, bigPotion = 150, gold = 20,
}

M.floor = {
    name = '第 2 层 · 苔壁',
    layout = '双道',
    hint = '如果签了契约：喝下任何一瓶血瓶都会毁约，押金不退。',
    map = {
        '@.e.h.e.h.>',
        '.#########.',
        '.....e...f.',
        '#m#########',
        '#r#########',
        '###########',
        '###########',
    },
    bloodCost = 60, gem = 2, smallPotion = 50, bigPotion = 150, gold = 20,
    contract = NO_POTION,
    intel = '下一层有两瓶血瓶。',
}

-- 走出第 1 层时的典型状态（原型里第 1 层拿全加成后的状态之一）
M.entryHero = { hp = 150, atk = 13, def = 13, keys = 0, gold = 0 }

return M
