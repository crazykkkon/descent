/** 静态配置：怪物、道具、角色。数值来自设计文档 4.2 / 4.4 / 4.8，后续用求解器调整。 */

export type Trait = 'firstStrike' | 'lifesteal' | 'thorns' | 'double';

export const TRAIT_NAMES: Record<Trait, string> = {
    firstStrike: '先攻',
    lifesteal: '吸血',
    thorns: '反伤',
    double: '二连击',
};

export const TRAIT_DESC: Record<Trait, string> = {
    firstStrike: '战斗开始时它先打一次',
    lifesteal: '每次命中，回复造成伤害的一半',
    thorns: '你每次攻击，自己受到 3 点伤害',
    double: '每回合攻击两次',
};

/** 反伤每次的伤害 */
export const THORNS_DAMAGE = 3;

export type MonsterId = 'moss' | 'eel' | 'frog' | 'beetle' | 'bat' | 'wraith' | 'crab' | 'guardian';

export interface MonsterDef {
    id: MonsterId;
    name: string;
    hp: number;
    atk: number;
    def: number;
    traits: Trait[];
    /** 打败后掉落的金币，按强度给 */
    gold: number;
    /** 精英：所在层必须打败它才能使用出口 */
    elite?: boolean;
}

export const MONSTERS: Record<MonsterId, MonsterDef> = {
    moss: { id: 'moss', name: '井苔', hp: 30, atk: 15, def: 2, traits: [], gold: 3 },
    eel: { id: 'eel', name: '盲鳗', hp: 45, atk: 20, def: 5, traits: [], gold: 6 },
    frog: { id: 'frog', name: '骨蛙', hp: 60, atk: 22, def: 8, traits: [], gold: 10 },
    beetle: { id: 'beetle', name: '锈甲虫', hp: 40, atk: 18, def: 14, traits: [], gold: 9 },
    bat: { id: 'bat', name: '回声蝠', hp: 35, atk: 25, def: 6, traits: ['firstStrike'], gold: 9 },
    wraith: { id: 'wraith', name: '溺魂', hp: 80, atk: 28, def: 10, traits: ['lifesteal'], gold: 16 },
    crab: { id: 'crab', name: '裂岩蟹', hp: 70, atk: 30, def: 12, traits: ['thorns'], gold: 16 },
    guardian: { id: 'guardian', name: '石鳞守卫', hp: 90, atk: 26, def: 14, traits: ['double'], elite: true, gold: 50 },
};

export type ItemId = 'smallPotion' | 'bigPotion' | 'redGem' | 'blueGem' | 'key' | 'gold';

export const ITEM_NAMES: Record<ItemId, string> = {
    smallPotion: '小血瓶',
    bigPotion: '大血瓶',
    redGem: '赤晶',
    blueGem: '青晶',
    key: '骨钥',
    gold: '金币袋',
};

export interface Hero {
    hp: number;
    atk: number;
    def: number;
    keys: number;
    gold: number;
    /** 手上的武器（只有一个武器格） */
    weapon?: WeaponId;
}

export type WeaponId = 'boneKnife' | 'harpoon' | 'hammer' | 'mossBlade' | 'bellStaff' | 'saltDagger' | 'rustSword' | 'wellHook';

export interface WeaponDef {
    id: WeaponId;
    name: string;
    desc: string;
    atk: number;
    def: number;
    /** 每场战斗开始先刺一下（多一次攻击） */
    firstHit?: boolean;
    /** 攻击无视怪物多少点防御 */
    pierce?: number;
    /** 每次击杀回复的生命 */
    killHeal?: number;
    /** 敌人的"先攻"失效 */
    noFirstStrike?: boolean;
    /** 对会吸血的怪伤害翻倍 */
    antiLifesteal?: boolean;
    /** 签契约时押金减少 */
    contractDiscount?: number;
    /** 出口卖掉换多少金币 */
    sell: number;
}

/** 武器效果全部是确定的，战斗预览和求解器都会算进去（设计文档 20.4） */
export const WEAPONS: Record<WeaponId, WeaponDef> = {
    boneKnife: { id: 'boneKnife', name: '骨刀', desc: '攻击 +4', atk: 4, def: 0, sell: 25 },
    harpoon: { id: 'harpoon', name: '鱼叉', desc: '每场战斗开始先刺一下（多一次攻击）', atk: 0, def: 0, firstHit: true, sell: 25 },
    hammer: { id: 'hammer', name: '破壳锤', desc: '攻击无视怪物 4 点防御', atk: 0, def: 0, pierce: 4, sell: 30 },
    mossBlade: { id: 'mossBlade', name: '苔衣短剑', desc: '每次击杀回复 8 生命', atk: 0, def: 0, killHeal: 8, sell: 25 },
    bellStaff: { id: 'bellStaff', name: '回声铃杖', desc: '攻击 +1；敌人的"先攻"失效', atk: 1, def: 0, noFirstStrike: true, sell: 25 },
    saltDagger: { id: 'saltDagger', name: '盐晶匕首', desc: '对会吸血的怪伤害翻倍', atk: 0, def: 0, antiLifesteal: true, sell: 25 },
    rustSword: { id: 'rustSword', name: '锈蚀大剑', desc: '攻击 +9，防御 −5（诅咒）', atk: 9, def: -5, sell: 35 },
    wellHook: { id: 'wellHook', name: '井神的钩', desc: '每次签契约，押金 −20', atk: 0, def: 0, contractDiscount: 20, sell: 40 },
};

export interface CharacterDef {
    id: string;
    name: string;
    base: Hero;
    /** 宝石额外效果（掘井人 +1） */
    gemBonus: number;
}

export const CHARACTERS: Record<string, CharacterDef> = {
    digger: {
        id: 'digger',
        name: '掘井人',
        base: { hp: 200, atk: 10, def: 10, keys: 0, gold: 0 },
        gemBonus: 1,
    },
};

/** 出口交易（设计文档 5.3）。清层不再额外给奖励：奖励直接放在怪物身后，让玩家自己判断值不值得打。 */
export const EXIT = {
    leftoverPotionGold: 5,
    keySellGold: 15,
};
