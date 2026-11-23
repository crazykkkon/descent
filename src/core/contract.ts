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
import { FloorDef } from './floor';

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

/** 守约时这一层的样子：血瓶不能碰，相当于墙（求解器用来验算守约的走法） */
export function keepVersion(floor: FloorDef): FloorDef {
    return { ...floor, map: floor.map.map(r => r.replace(/[hH]/g, '#')) };
}
