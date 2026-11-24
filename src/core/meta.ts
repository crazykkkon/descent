/**
 * 局外成长：灵魂碎片、碎片商店（强化、解锁）、深度模式（制作人 2026-11-24 提出）。
 * 这里只放规则（原型和 Lua 版共用，用标准算例对账）；碎片余额、买过什么、开关存在 LÖVE 版的 meta 存档里。
 * 价格、数值、解锁内容都是讨论项。
 */
import { BASE_WEAPONS, WeaponId } from './config';

/**
 * 一局结束能拿多少碎片：越深越值钱，走完第 N 层得 N 个（死在第 5 层 = 走完 4 层 = 10 个，第 10 层 45 个）；
 * 通关再加 50。深度模式每级多给 25%。
 * @param reached 死在第几层（从 1 开始）；通关时不看这个数
 */
export function shardsFor(reached: number, won: boolean, depth = 0): number {
    const done = won ? 20 : Math.max(0, reached - 1);
    const base = (done * (done + 1)) / 2 + (won ? 50 : 0);
    return Math.floor((base * (100 + 25 * depth)) / 100);
}

/** 强化：买了以后每局开局生效，可以随时关掉（关掉不退碎片）。costs[k] 是买第 k+1 级的价格 */
export interface PerkDef { id: string; name: string; costs: number[]; values: number[]; desc: (v: number) => string }
export const PERKS: PerkDef[] = [
    { id: 'atk', name: '磨刀石', costs: [20, 40, 80], values: [1, 2, 3], desc: v => `开局攻击 +${v}` },
    { id: 'def', name: '护甲片', costs: [20, 40, 80], values: [1, 2, 3], desc: v => `开局防御 +${v}` },
    { id: 'hp', name: '血囊', costs: [10, 30, 60], values: [30, 60, 100], desc: v => `开局生命 +${v}` },
    { id: 'keys', name: '钥匙串', costs: [40], values: [1], desc: v => `开局带 ${v} 把骨钥` },
    { id: 'gold', name: '钱袋', costs: [20, 50], values: [20, 50], desc: v => `开局金币 +${v}` },
    { id: 'engrave', name: '旧印子', costs: [60], values: [1], desc: () => '开局转轮上已刻一个随机武器图案（转到才拿得到）' },
    { id: 'halfSpin', name: '润滑油', costs: [80], values: [1], desc: () => '每层第一次拉杆半价' },
];
export function perkValue(id: string, level: number): number {
    const p = PERKS.find(x => x.id === id);
    return p && level > 0 ? p.values[Math.min(level, p.values.length) - 1] : 0;
}

/** 解锁：一次买断，永久有效 */
export interface UnlockDef { id: string; name: string; cost: number; desc: string; kind: 'weapon' | 'character' | 'depth' | 'facility'; needsClear?: boolean }
export const UNLOCKS: UnlockDef[] = [
    { id: 'lamp', name: '井灯', cost: 60, kind: 'weapon', desc: '新武器图案：防御 +2。加入精英三选一、当铺、大转盘的图案池' },
    { id: 'twinHook', name: '双钩', cost: 60, kind: 'weapon', desc: '新武器图案：攻击 +1，每次击杀回复 4 生命' },
    { id: 'scavenger', name: '拾荒者', cost: 120, kind: 'character', desc: '新角色：生命 150、攻 9、防 8、开局 30 金。开骨门不用骨钥，改扣 10 生命' },
    { id: 'drowned', name: '溺者', cost: 200, kind: 'character', desc: '新角色：生命 100、攻 14、防 6。倒下时复活一次，之后每进一层扣 20 生命' },
    { id: 'campKey', name: '营火的骨钥', cost: 40, kind: 'facility', desc: '营火的补给摊多卖一把骨钥' },
    { id: 'pawnExtra', name: '当铺的第三件', cost: 50, kind: 'facility', desc: '当铺多摆一件武器图案' },
    { id: 'depth', name: '深度模式', cost: 100, kind: 'depth', needsClear: true, desc: '通关后才能买。开局可选深度 1～3：怪更凶、血瓶更少、井租更贵，碎片多 25%～75%' },
];

/** 图案池：一开始的 8 把 + 解锁的武器（按 UNLOCKS 的顺序） */
export function weaponPool(unlocks: string[] = []): WeaponId[] {
    return [...BASE_WEAPONS, ...UNLOCKS.filter(u => u.kind === 'weapon' && unlocks.includes(u.id)).map(u => u.id as WeaponId)];
}

/** 深度模式：第 1 级起每层怪物再加强 2 级；第 2 级起血瓶效果 −25%；第 3 级起井租和补给摊 ×1.5 */
export const MAX_DEPTH = 3;
export const DEPTH_POWER = 2;
