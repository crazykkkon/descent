/**
 * 井的契约（试玩版只有一种条件："下一层不喝血瓶"）。
 *
 * 流程：
 * 1. 上一层楼梯口挂出契约：押多少血、立刻得到什么、守约退还多少。
 * 2. 签约：押金立刻扣掉，属性立刻生效。
 * 3. 下一层：喝下任何一瓶血瓶的那一刻就算毁约，押金归井，拿到的属性留给你。
 * 4. 守约走到出口：退还押金和利息。
 *
 * 价格是设计者手调的，求解器只负责验算（tools/contract.ts 列出拒签 / 守约 / 毁约三条路的结果）。
 */
import { FloorDef, adjacentMonsters, parseFloor } from './floor';
import { Hero, MONSTERS, WEAPONS, monsterInContext } from './config';
import { simulateCombat } from './combat';

export interface ContractDef {
    condition: 'noPotion';
    /** 签约时押的血 */
    deposit: number;
    /** 签约后立刻得到的属性 */
    atk: number;
    def: number;
    /** 守约走到出口时退还的血（押金 + 利息） */
    refund: number;
    /** 守约额外给的金币 */
    gold: number;
}

export interface ActiveContract {
    def: ContractDef;
    /** 契约作用在哪一层 */
    floorIndex: number;
    broken: boolean;
}

/** 契约结算结果（出口结算时显示） */
export interface ContractResult {
    def: ContractDef;
    kept: boolean;
}

export function contractText(c: ContractDef): { pay: string; get: string; cond: string; reward: string } {
    const get = [c.atk ? `攻击 +${c.atk}` : '', c.def ? `防御 +${c.def}` : ''].filter(Boolean).join('、');
    return {
        pay: `押 ${c.deposit} 生命`,
        get: `立刻得到 ${get}（永久）`,
        cond: '下一层一瓶血瓶都不喝，走到出口',
        reward: `退还 ${c.refund} 生命${c.gold ? `，再给 ${c.gold} 金币` : ''}`,
    };
}

/** 实际要押的生命（井神的钩可以少押） */
export function depositFor(c: ContractDef, hero: Hero): number {
    const d = hero.weapon ? WEAPONS[hero.weapon].contractDiscount ?? 0 : 0;
    return Math.max(0, c.deposit - d);
}

/** 守约时这一层的样子：血瓶不能碰，相当于墙（求解器用来验算守约的走法） */
export function keepVersion(floor: FloorDef): FloorDef {
    return { ...floor, map: floor.map.map(r => r.replace(/[hH]/g, '#')) };
}

export interface ContractPreviewRow {
    name: string;
    /** 不签时打它的掉血（"-99"、"打不动"、"打不死"） */
    before: string;
    /** 签约拿到属性后打它的掉血 */
    after: string;
    /** 少掉多少血（打不动 / 打不死变成打得过时为 null） */
    saved: number | null;
}

/**
 * 签约卡上的"签前 / 签后"对照：下一层每种怪（按开局时周围的怪算真实攻防）各算一次，
 * 只列签约后有变化的，按省下的血从多到少排，最多 max 行。打不动 → 打得动排在最前。
 */
export function contractPreview(next: FloorDef, hero: Hero, c: ContractDef, max = 4): ContractPreviewRow[] {
    const p = parseFloor(next);
    const signed: Hero = { ...hero, atk: hero.atk + c.atk, def: hero.def + c.def };
    const seen = new Set<string>();
    const rows: ContractPreviewRow[] = [];
    const text = (h: Hero, m: ReturnType<typeof monsterInContext>) => {
        const r = simulateCombat(h, m);
        return { t: !r.canAttack ? '打不动' : !r.canWin ? '打不死' : `-${r.damage}`, d: r.canAttack && r.canWin ? r.damage : null };
    };
    p.cells.forEach((cell, i) => {
        if (cell.kind !== 'monster') return;
        const m = monsterInContext(MONSTERS[cell.id], adjacentMonsters(p.cells, p.w, p.h, i));
        const key = `${m.id}:${m.atk}:${m.def}`;
        if (seen.has(key)) return;
        seen.add(key);
        const a = text(hero, m);
        const b = text(signed, m);
        if (a.t === b.t) return;
        rows.push({ name: m.name, before: a.t, after: b.t, saved: a.d !== null && b.d !== null ? a.d - b.d : null });
    });
    // 省得多的在前；打不动 / 打不死变成打得过的（saved 为 null）排最前；相同时保持出现顺序
    const v = (r: ContractPreviewRow) => r.saved ?? Infinity;
    rows.sort((x, y) => (v(x) === v(y) ? 0 : v(y) > v(x) ? 1 : -1));
    return rows.slice(0, max);
}
