/** 静态配置：怪物、道具、角色。数值来自设计文档 4.2 / 4.4 / 4.8，后续用求解器调整。 */

export type Trait = 'firstStrike' | 'lifesteal' | 'thorns' | 'double' | 'swarm' | 'corrode' | 'shelter';

export const TRAIT_NAMES: Record<Trait, string> = {
    firstStrike: '先攻',
    lifesteal: '吸血',
    thorns: '反伤',
    double: '二连击',
    swarm: '群居',
    corrode: '腐蚀',
    shelter: '庇护',
};

export const TRAIT_DESC: Record<Trait, string> = {
    firstStrike: '战斗开始时它先打一次',
    lifesteal: '每次命中，回复造成伤害的一半',
    thorns: '你每次攻击，自己受到 3 点伤害',
    double: '每回合攻击两次',
    swarm: '每有一只相邻的同类，攻击 +5',
    corrode: '每次命中，你在这场战斗里的防御 −1',
    shelter: '相邻的其他怪物防御 +6（几只祭司围着也只加一次）',
};

/** 反伤每次的伤害 */
export const THORNS_DAMAGE = 3;
/** 群居：每只相邻同类加的攻击 */
export const SWARM_ATK = 5;
/** 腐蚀：怪物每次命中让主角这场战斗的防御减多少 */
export const CORRODE_DEF = 1;
/** 庇护：相邻其他怪物加的防御（不叠加：原案里守门人两边各一只祭司时防御 30） */
export const SHELTER_DEF = 6;

export type MonsterId = 'moss' | 'eel' | 'frog' | 'beetle' | 'bat' | 'wraith' | 'crab' | 'guardian' | 'rat' | 'slug' | 'priest' | 'gatekeeper' | 'eye'
    | 'thornMoss' | 'spikeEel' | 'armorFrog' | 'ironBeetle' | 'shriekBat' | 'grudgeWraith' | 'shardCrab';

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
    /** 这只怪的原始数值已经相当于加强了几级（深处才出现的怪）；按层加强时先扣掉这么多 */
    basePower?: number;
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
    // 下面四只的数值来自原设计方案第 4 章（层位和最终数值是讨论项，二十层平衡时再调）
    rat: { id: 'rat', name: '井鼠', hp: 40, atk: 34, def: 14, traits: ['swarm'], gold: 8, basePower: 3 },
    slug: { id: 'slug', name: '盐蚀蛞蝓', hp: 90, atk: 38, def: 18, traits: ['corrode'], gold: 14, basePower: 3 },
    priest: { id: 'priest', name: '骸骨祭司', hp: 100, atk: 30, def: 22, traits: ['shelter'], gold: 16, basePower: 3 },
    gatekeeper: { id: 'gatekeeper', name: '守门人', hp: 160, atk: 44, def: 24, traits: ['double'], elite: true, gold: 80, basePower: 5 },
    // 第 20 层 Boss 的占位：回合制站位战（召唤、落石、危区）还没做，先用一场确定的战斗代替
    eye: { id: 'eye', name: '井底之眼', hp: 500, atk: 70, def: 34, traits: [], elite: true, gold: 0, basePower: 12 },
    // 第 6 层起换掉 7 种小怪的更凶的同类（制作人：后面的小怪要换成更厉害的怪）。大约是原来的 攻 +10、防 +5、生命 ×1.3（本来就强的怨魂、碎岩蟹加得少一些）；数值是讨论项
    thornMoss: { id: 'thornMoss', name: '棘苔', hp: 39, atk: 25, def: 7, traits: [], gold: 5 },
    spikeEel: { id: 'spikeEel', name: '刺鳗', hp: 58, atk: 30, def: 10, traits: [], gold: 9 },
    armorFrog: { id: 'armorFrog', name: '铠蛙', hp: 78, atk: 32, def: 13, traits: [], gold: 15 },
    ironBeetle: { id: 'ironBeetle', name: '铁甲虫', hp: 52, atk: 28, def: 19, traits: [], gold: 14 },
    shriekBat: { id: 'shriekBat', name: '啸蝠', hp: 45, atk: 35, def: 11, traits: ['firstStrike'], gold: 14 },
    grudgeWraith: { id: 'grudgeWraith', name: '怨魂', hp: 92, atk: 34, def: 13, traits: ['lifesteal'], gold: 22 },
    shardCrab: { id: 'shardCrab', name: '碎岩蟹', hp: 82, atk: 36, def: 15, traits: ['thorns'], gold: 22 },
};

/**
 * 正式局的怪物数值（制作人 2026-11-24 定：宝石分大小，小宝石 +1、大宝石 +3；第一次玩大约 10% 通关、碎片强化买满大约一半）。
 * 宝石变小以后主角的攻防只有原来的一半多一点，所以正式局（buildRoute 生成的楼层，FloorDef.runStats）用这一张表；
 * 新手教程和测试用的小图还用上面 MONSTERS 的原始数值（教程的宝石都是大宝石，数值不变）。
 * 这张表由 tools/balance.ts 的数值体检调出来，数值是讨论项。
 */
export const RUN_STATS: Partial<Record<MonsterId, { hp: number; atk: number; def: number }>> = {
// RUN_STATS_BEGIN
    moss: { hp: 30, atk: 13, def: 2 },
    eel: { hp: 45, atk: 17, def: 4 },
    frog: { hp: 60, atk: 18, def: 6 },
    beetle: { hp: 40, atk: 14, def: 9 },
    bat: { hp: 35, atk: 20, def: 4 },
    wraith: { hp: 80, atk: 20, def: 6 },
    crab: { hp: 70, atk: 22, def: 8 },
    guardian: { hp: 90, atk: 17, def: 9 },
    rat: { hp: 44, atk: 21, def: 7 },
    slug: { hp: 99, atk: 23, def: 9 },
    priest: { hp: 110, atk: 18, def: 11 },
    gatekeeper: { hp: 176, atk: 27, def: 12 },
    eye: { hp: 550, atk: 42, def: 18 },
    thornMoss: { hp: 43, atk: 16, def: 4 },
    spikeEel: { hp: 64, atk: 19, def: 5 },
    armorFrog: { hp: 86, atk: 20, def: 7 },
    ironBeetle: { hp: 57, atk: 18, def: 10 },
    shriekBat: { hp: 50, atk: 22, def: 6 },
    grudgeWraith: { hp: 101, atk: 21, def: 7 },
    shardCrab: { hp: 90, atk: 23, def: 8 },
    // RUN_STATS_END
};
/** 正式局里群居、庇护的加成（原始 SWARM_ATK / SHELTER_DEF 按比例缩小） */
export const RUN_SWARM_ATK = 3;
export const RUN_SHELTER_DEF = 3;

/**
 * 井越深，怪越凶：第 7 层起每往下一层（power +1），这一层的怪攻击 +DEPTH_ATK/10、防御 +DEPTH_DEF/10（向下取整）、生命 +DEPTH_HP%，一直加到第 20 层。
 * - 本来就是深处的怪（井鼠、盐蚀蛞蝓、骸骨祭司、守门人、井底之眼）带 basePower，先扣掉，只按"比它的老家更深多少"加；
 * - 精英再减半（向下取整）。
 * 数值是讨论项（tools/balance.ts 体检）。
 */
export const DEPTH_ATK = 28;
export const DEPTH_DEF = 5;
export const DEPTH_HP = 12;

/** 按这一层的 power 加强后的怪（run = 正式局，先换成 RUN_STATS 的数值；power = 0 只换表） */
export function powered(m: MonsterDef, power = 0, run = false): MonsterDef {
    const r = run ? RUN_STATS[m.id] : undefined;
    if (r) m = { ...m, ...r };
    // 原本就是深处的怪（数值按更深的层定的）：先扣掉它自带的级数，只按"比它的老家更深多少"加强
    power = Math.max(0, power - (m.basePower ?? 0));
    if (m.elite) power = Math.floor(power / 2);
    if (!power) return m;
    return {
        ...m,
        hp: Math.floor((m.hp * (100 + DEPTH_HP * power)) / 100),
        atk: m.atk + Math.floor((DEPTH_ATK * power) / 10),
        def: m.def + Math.floor((DEPTH_DEF * power) / 10),
    };
}

/**
 * 按周围格子算出怪物这一刻的真实属性（群居、庇护）。
 * @param adjacent 相邻格子上还活着的怪物
 */
export function monsterInContext(m: MonsterDef, adjacent: MonsterId[], power = 0, run = false): MonsterDef {
    m = powered(m, power, run);
    let atk = m.atk;
    let def = m.def;
    if (m.traits.includes('swarm')) atk += (run ? RUN_SWARM_ATK : SWARM_ATK) * adjacent.filter(id => id === m.id).length;
    if (adjacent.some(id => MONSTERS[id].traits.includes('shelter'))) def += run ? RUN_SHELTER_DEF : SHELTER_DEF;
    return atk === m.atk && def === m.def ? m : { ...m, atk, def };
}

export type ItemId = 'smallPotion' | 'bigPotion' | 'redGem' | 'blueGem' | 'bigRedGem' | 'bigBlueGem' | 'key' | 'gold';

/** 大宝石（大赤晶 / 大青晶）加多少（制作人定：小宝石 +1、大宝石 +3；小宝石的数值在楼层的 gem 里） */
export const BIG_GEM = 3;

export const ITEM_NAMES: Record<ItemId, string> = {
    smallPotion: '小血瓶',
    bigPotion: '大血瓶',
    redGem: '小赤晶',
    blueGem: '小青晶',
    bigRedGem: '大赤晶',
    bigBlueGem: '大青晶',
    key: '骨钥',
    gold: '金币袋',
};

export interface Hero {
    hp: number;
    atk: number;
    def: number;
    keys: number;
    gold: number;
    /** 断臂转轮现在停在的武器（空手时没有） */
    weapon?: WeaponId;
    /** 这把武器在骨坛上移来的特性 */
    boons?: Boon[];
}

/** 骨坛能移到武器上的特性（来自杀过的怪） */
export type Boon = 'lifesteal' | 'firstStrike' | 'thorns' | 'corrode';
export const BOON_NAMES: Record<Boon, string> = { lifesteal: '吸血', firstStrike: '先攻', thorns: '反伤', corrode: '腐蚀' };
export const BOON_DESC: Record<Boon, string> = {
    lifesteal: '你每次命中回复造成伤害的四分之一（不超过这一仗掉的血）',
    firstStrike: '开打前你先打一下',
    thorns: '怪每打你一下，它自己掉 3 血',
    corrode: '你每打中一下，怪这一仗的防御 −1',
};

export type WeaponId = 'boneKnife' | 'harpoon' | 'hammer' | 'mossBlade' | 'bellStaff' | 'saltDagger' | 'rustSword' | 'wellHook' | 'lamp' | 'twinHook';

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
    /** 每次击杀多得的金币 */
    killGold?: number;
    /** 出口卖掉换多少金币 */
    sell: number;
}

/** 武器效果全部是确定的，战斗预览和求解器都会算进去（设计文档 20.4） */
export const WEAPONS: Record<WeaponId, WeaponDef> = {
    boneKnife: { id: 'boneKnife', name: '骨刀', desc: '攻击 +2', atk: 2, def: 0, sell: 25 },
    harpoon: { id: 'harpoon', name: '鱼叉', desc: '每场战斗开始先刺一下（多一次攻击）', atk: 0, def: 0, firstHit: true, sell: 25 },
    hammer: { id: 'hammer', name: '破壳锤', desc: '攻击无视怪物 2 点防御', atk: 0, def: 0, pierce: 2, sell: 30 },
    mossBlade: { id: 'mossBlade', name: '苔衣短剑', desc: '每次击杀回复 8 生命', atk: 0, def: 0, killHeal: 8, sell: 25 },
    bellStaff: { id: 'bellStaff', name: '回声铃杖', desc: '攻击 +1；敌人的"先攻"失效', atk: 1, def: 0, noFirstStrike: true, sell: 25 },
    saltDagger: { id: 'saltDagger', name: '盐晶匕首', desc: '对会吸血的怪伤害翻倍', atk: 0, def: 0, antiLifesteal: true, sell: 25 },
    rustSword: { id: 'rustSword', name: '锈蚀大剑', desc: '攻击 +5，防御 −3（诅咒）', atk: 5, def: -3, sell: 35 },
    wellHook: { id: 'wellHook', name: '井神的钩', desc: '每次击杀多得 5 金币', atk: 0, def: 0, killGold: 5, sell: 40 },
    // 下面两把要用灵魂碎片解锁，解锁后才进图案池（数值是讨论项）
    lamp: { id: 'lamp', name: '井灯', desc: '防御 +2', atk: 0, def: 2, sell: 30 },
    twinHook: { id: 'twinHook', name: '双钩', desc: '攻击 +1；每次击杀回复 4 生命', atk: 1, def: 0, killHeal: 4, sell: 30 },
};

/** 一开始就有的 8 把武器（图案池的顺序；解锁的武器排在后面） */
export const BASE_WEAPONS: WeaponId[] = ['boneKnife', 'harpoon', 'hammer', 'mossBlade', 'bellStaff', 'saltDagger', 'rustSword', 'wellHook'];

export interface CharacterDef {
    id: string;
    name: string;
    /** 一句话介绍（选角色时显示） */
    desc: string;
    base: Hero;
    /** 宝石额外效果（掘井人 +1） */
    gemBonus: number;
    /** 拾荒者：开骨门不用骨钥，改成扣这么多生命 */
    boneDoorHp?: number;
    /** 溺者：倒下时复活一次，生命回到这个数 */
    revive?: number;
    /** 溺者：复活以后每进一层扣这么多生命（最少留 1） */
    drain?: number;
}

export const CHARACTERS: Record<string, CharacterDef> = {
    digger: {
        id: 'digger',
        name: '掘井人',
        // 原来的特长"宝石效果 +1"去掉了（制作人定：小宝石就是 +1、大宝石就是 +3）；要不要换一个特长是讨论项
        desc: '老练的矿工，生命最多。',
        base: { hp: 200, atk: 10, def: 10, keys: 0, gold: 0 },
        gemBonus: 0,
    },
    // 下面两个要用灵魂碎片解锁（原方案 5.5；数值是讨论项）
    scavenger: {
        id: 'scavenger',
        name: '拾荒者',
        desc: '开骨门不用骨钥，改成每次扣 10 生命；骨钥留着卖钱。',
        base: { hp: 150, atk: 9, def: 8, keys: 0, gold: 30 },
        gemBonus: 0,
        boneDoorHp: 10,
    },
    drowned: {
        id: 'drowned',
        name: '溺者',
        desc: '倒下时复活一次（生命回到 50），之后每进一层扣 20 生命。',
        base: { hp: 100, atk: 14, def: 6, keys: 0, gold: 0 },
        gemBonus: 0,
        revive: 50,
        drain: 20,
    },
};

/** 出口交易（设计文档 5.3）。清层不再额外给奖励：奖励直接放在怪物身后，让玩家自己判断值不值得打。 */
export const EXIT = {
    leftoverPotionGold: 5,
    keySellGold: 15,
};

/** 印记怪：打败后可以把对应的武器刻到断臂转轮上 */
export const MARK_WEAPON: Partial<Record<MonsterId, WeaponId>> = {
    eel: 'harpoon', moss: 'mossBlade', frog: 'boneKnife', bat: 'bellStaff',
    wraith: 'saltDagger', crab: 'hammer', beetle: 'rustSword', rat: 'wellHook',
    thornMoss: 'mossBlade', spikeEel: 'harpoon', armorFrog: 'boneKnife', ironBeetle: 'rustSword',
    shriekBat: 'bellStaff', grudgeWraith: 'saltDagger', shardCrab: 'hammer',
};

/** 杀过这种怪，骨坛上就能移它的特性 */
export const MONSTER_BOON: Partial<Record<MonsterId, Boon>> = {
    wraith: 'lifesteal', bat: 'firstStrike', crab: 'thorns', slug: 'corrode',
    grudgeWraith: 'lifesteal', shriekBat: 'firstStrike', shardCrab: 'thorns',
};

/** 第 6 层起，地图上的 7 种小怪换成更凶的同类（地图字符 → 换成的字符） */
export const UPGRADE_CHARS: Record<string, string> = { m: 'a', e: 'i', f: 'j', c: 'l', v: 'n', g: 'o', x: 'q' };
