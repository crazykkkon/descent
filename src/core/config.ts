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
    guardian: { id: 'guardian', name: '石鳞守卫', hp: 300, atk: 40, def: 18, traits: ['double'], elite: true, gold: 50 },
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
}

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
