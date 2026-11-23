/**
 * 井中轮（老虎机，设计文档第二十章）。
 *
 * - 三个转轮，每个转轮 8 格图案，全部印在机器上，概率能算出来。
 * - 转一次要付钱（金币，或者用生命"血注"），同一台机器每转一次涨一半价。
 * - 每次转完二选一：
 *     收下：按这次的图案领奖；
 *     锁轴重转：放弃这次的奖励，锁住一两个转轮，半价重转其余的。
 * - 井蛭在转出来的那一刻就咬人，收不收都要挨（锁住井蛭也不会再咬第二次）。
 * - 结果由本局随机种子决定，退出再进来结果不变。
 */
import { WeaponId } from './config';

export type Sym = 'blade' | 'hammer' | 'harpoon' | 'potion' | 'coin' | 'leech';

export const SYM_NAMES: Record<Sym, string> = {
    blade: '骨刀', hammer: '破壳锤', harpoon: '鱼叉', potion: '血瓶', coin: '金币', leech: '井蛭',
};

/** 武器图案对应的武器 */
export const SYM_WEAPON: Partial<Record<Sym, WeaponId>> = { blade: 'boneKnife', hammer: 'hammer', harpoon: 'harpoon' };

export type SlotId = 'risky' | 'steady';

export interface SlotDef {
    id: SlotId;
    name: string;
    desc: string;
    reels: [Sym[], Sym[], Sym[]];
}

const R = (s: string): Sym[] => s.split(' ').map(x => ({ 刀: 'blade', 锤: 'hammer', 叉: 'harpoon', 瓶: 'potion', 金: 'coin', 蛭: 'leech' } as Record<string, Sym>)[x]);

export const SLOTS: Record<SlotId, SlotDef> = {
    risky: {
        id: 'risky', name: '骨轮', desc: '武器多，井蛭也多',
        reels: [
            R('刀 刀 锤 叉 蛭 蛭 金 瓶'),
            R('刀 锤 锤 叉 蛭 蛭 金 瓶'),
            R('刀 锤 叉 叉 蛭 蛭 金 瓶'),
        ],
    },
    steady: {
        id: 'steady', name: '苔轮', desc: '血瓶和金币多，武器很少（三连骨刀极难，但两把骨刀能换赤晶）',
        reels: [
            R('瓶 瓶 瓶 金 金 刀 蛭 金'),
            R('瓶 瓶 金 金 金 刀 蛭 瓶'),
            R('瓶 瓶 金 金 瓶 刀 蛭 金'),
        ],
    },
};

export const LEECH_BITE = 15;
export const LEECH_TRIPLE = 60;
export const POTION_HP = 40;
export const COIN_GOLD = 15;

/** 第 n 次转（从 0 开始）的价格：20 → 30 → 45 → 70 → 105 … */
export function spinPrice(spins: number): number {
    return Math.round((20 * Math.pow(1.5, spins)) / 5) * 5;
}

/** 血注：用生命代替金币，价格 × 1.5 */
export function bloodPrice(gold: number): number {
    return Math.ceil(gold * 1.5);
}

export interface SlotState {
    /** 已经转了几次（决定下一次的价格） */
    spins: number;
    /** 已经用掉的随机数个数（保证结果由种子决定） */
    draws: number;
    /** 当前停在机器上、还没收下的结果 */
    pending: Sym[] | null;
}

export function newSlotState(): SlotState {
    return { spins: 0, draws: 0, pending: null };
}

/** 一次转轮结果能领到的奖励（不含井蛭，井蛭在转出来时就结算） */
export interface Payout {
    weapon?: WeaponId;
    /** 赤晶个数 */
    gems: number;
    hp: number;
    gold: number;
    lines: string[];
}

export function payout(r: Sym[]): Payout {
    const p: Payout = { gems: 0, hp: 0, gold: 0, lines: [] };
    const count = (s: Sym) => r.filter(x => x === s).length;
    for (const s of ['blade', 'hammer', 'harpoon'] as Sym[]) {
        if (count(s) === 3) { p.weapon = SYM_WEAPON[s]; p.lines.push(`三连${SYM_NAMES[s]}：得到武器「${SYM_NAMES[s]}」`); }
        else if (count(s) === 2) { p.gems++; p.lines.push(`两个${SYM_NAMES[s]}：得到一颗赤晶`); }
    }
    if (count('potion') >= 2) { p.hp += count('potion') * POTION_HP; p.lines.push(`${count('potion')} 个血瓶：+${count('potion') * POTION_HP} 生命`); }
    if (count('coin') >= 2) { p.gold += count('coin') * COIN_GOLD; p.lines.push(`${count('coin')} 个金币：+${count('coin') * COIN_GOLD} 金币`); }
    if (!p.lines.length) p.lines.push('什么都没有');
    return p;
}

/** 新转出来的井蛭咬掉的生命（锁住的旧井蛭不再咬） */
export function leechBite(r: Sym[], fresh: boolean[]): number {
    const n = r.filter((s, i) => s === 'leech' && fresh[i]).length;
    if (r.every(s => s === 'leech') && fresh.every(Boolean)) return LEECH_TRIPLE;
    return n * LEECH_BITE;
}

/** 可重复的随机数：同一个种子、同一台机器、同一个序号，结果永远一样 */
function draw(seed: number, key: number, n: number): number {
    let a = (seed ^ Math.imul(key + 1, 0x9e3779b1) ^ Math.imul(n + 1, 0x85ebca6b)) >>> 0;
    a = Math.imul(a ^ (a >>> 16), 0x7feb352d) >>> 0;
    a = Math.imul(a ^ (a >>> 15), 0x846ca68b) >>> 0;
    return ((a ^ (a >>> 16)) >>> 0) / 4294967296;
}

/** 转一次。held 为 true 的转轮保留原图案。返回新结果和哪些转轮是新转出来的。 */
export function roll(def: SlotDef, st: SlotState, seed: number, key: number, held: boolean[] = [false, false, false]): { result: Sym[]; fresh: boolean[] } {
    const result: Sym[] = [];
    const fresh: boolean[] = [];
    for (let i = 0; i < 3; i++) {
        if (held[i] && st.pending) { result.push(st.pending[i]); fresh.push(false); continue; }
        const reel = def.reels[i];
        result.push(reel[Math.floor(draw(seed, key, st.draws++) * reel.length)]);
        fresh.push(true);
    }
    return { result, fresh };
}

/** 新转一次（不锁轴）三连武器的概率 */
export function tripleWeaponOdds(def: SlotDef): number {
    let p = 0;
    for (const s of ['blade', 'hammer', 'harpoon'] as Sym[]) {
        p += def.reels.reduce((acc, reel) => acc * reel.filter(x => x === s).length / reel.length, 1);
    }
    return p;
}

/** 锁轴重转：锁住的转轮不变，其余重转后凑成某种武器三连的概率 */
export function holdOdds(def: SlotDef, pending: Sym[], held: boolean[]): number {
    const heldSyms = pending.filter((_, i) => held[i]);
    if (!heldSyms.length) return tripleWeaponOdds(def);
    const target = heldSyms[0];
    if (!SYM_WEAPON[target] || heldSyms.some(s => s !== target)) return 0;
    return def.reels.reduce((acc, reel, i) => (held[i] ? acc : acc * reel.filter(x => x === target).length / reel.length), 1);
}

/**
 * 锁轴时给玩家看的一句话：锁住这些图案后重转，能凑成什么、概率多少。
 */
export function holdHint(def: SlotDef, pending: Sym[], held: boolean[]): string {
    const heldSyms = pending.filter((_, i) => held[i]);
    if (!heldSyms.length) return '';
    const pctS = (x: number) => `${Math.round(x * 1000) / 10}%`;
    const target = heldSyms[0];
    if (heldSyms.some(s => s !== target)) return '锁住的图案不一样，重转凑不成三连；只能指望另一个转轮出好东西。';
    if (target === 'leech') return '锁住井蛭不会让它再咬你，但它也不会变成别的。';
    const free = def.reels.filter((_, i) => !held[i]);
    const each = free.map(reel => reel.filter(x => x === target).length / reel.length);
    const all = each.reduce((a, b) => a * b, 1);
    const atLeastOne = 1 - each.reduce((a, b) => a * (1 - b), 1);
    const name = SYM_NAMES[target];
    if (SYM_WEAPON[target]) {
        return heldSyms.length === 2
            ? `重转剩下那个转轮，凑成三连${name}（得到武器）的概率 ${pctS(all)}；没中也还保有两个${name}（一颗赤晶）。`
            : `重转另外两个转轮：凑成三连${name}的概率 ${pctS(all)}，至少再出一个${name}（两个能换赤晶）的概率 ${pctS(atLeastOne)}。`;
    }
    return heldSyms.length === 2
        ? `已经有两个${name}了，重转剩下那个转轮，再出一个${name}的概率 ${pctS(all)}。`
        : `重转另外两个转轮，至少再出一个${name}（凑够两个才有奖励）的概率 ${pctS(atLeastOne)}。`;
}

/** 新转一次各种结果的大概率（印在机器上） */
export function machineOdds(def: SlotDef): { weapon: number; anyLeech: number } {
    const noLeech = def.reels.reduce((acc, reel) => acc * reel.filter(x => x !== 'leech').length / reel.length, 1);
    return { weapon: tripleWeaponOdds(def), anyLeech: 1 - noLeech };
}
