/**
 * 断臂转轮：三个轮子，每个轮子一圈 3 格（画成 3×3）。刻一把武器 = 占满同一行的三格。
 * 转一次：每个轮子各停在一格；三个轮子停在同一把武器上 → 换成这把；三个都是空格 → 空手；其他 → 不变。
 * 转到某把武器的概率 =（刻了它的行数 ÷ 3）的三次方。
 */
import { Boon, WeaponId } from './config';
import { draw } from './rng';

export const ARM_ROWS = 3;
/** 每层第一次转的价格（之后 ×1.5，换层重新算） */
export const ARM_BASE_PRICE = 10;

/** 一格：武器或空格（null） */
export type ArmSym = WeaponId | null;

export interface ArmState {
    /** 每一行刻的武器（null = 空行） */
    rows: ArmSym[];
    /** 骨坛移到各把武器上的特性 */
    boons: Partial<Record<WeaponId, Boon[]>>;
    /** 本层已经转了几次（决定价格） */
    spins: number;
    /** 已经用掉的随机数个数 */
    draws: number;
    /** 每个轮子现在停在第几行（锁轴重转时锁住的轮子不变） */
    stops: number[] | null;
}

export function newArm(): ArmState {
    return { rows: [null, null, null], boons: {}, spins: 0, draws: 0, stops: null };
}

/** 三个轮子停下的图案 */
export function armFaces(arm: ArmState): ArmSym[] | null {
    return arm.stops ? arm.stops.map(k => arm.rows[k]) : null;
}

/** 转一次（held 里为 true 的轮子不动）。key 用来区分楼层，保证每层的随机数不同 */
export function armRoll(arm: ArmState, seed: number, key: number, held?: boolean[]): ArmSym[] {
    const stops: number[] = [];
    for (let i = 0; i < 3; i++) {
        if (held?.[i] && arm.stops) { stops.push(arm.stops[i]); continue; }
        stops.push(Math.floor(draw(seed, key, arm.draws++) * ARM_ROWS));
    }
    arm.stops = stops;
    return armFaces(arm)!;
}

/** 三个轮子的结果：'weapon' 换武器，'empty' 变空手，'none' 不变 */
export function armOutcome(faces: ArmSym[]): { kind: 'weapon'; id: WeaponId } | { kind: 'empty' } | { kind: 'none' } {
    if (faces[0] === faces[1] && faces[1] === faces[2]) return faces[0] ? { kind: 'weapon', id: faces[0] } : { kind: 'empty' };
    return { kind: 'none' };
}

/** 转到这把武器的概率 */
export function armOdds(arm: ArmState, id: ArmSym): number {
    const n = arm.rows.filter(r => r === id).length;
    return (n * n * n) / (ARM_ROWS * ARM_ROWS * ARM_ROWS);
}

/** 锁住一些轮子后，重转得到三连的概率（三个面要一样） */
export function armHoldOdds(arm: ArmState, held: boolean[]): { target: ArmSym; p: number } | null {
    const faces = armFaces(arm);
    if (!faces) return null;
    const heldFaces = faces.filter((_, i) => held[i]);
    if (!heldFaces.length || heldFaces.some(f => f !== heldFaces[0])) return null;
    const target = heldFaces[0];
    const share = arm.rows.filter(r => r === target).length / ARM_ROWS;
    return { target, p: Math.pow(share, 3 - heldFaces.length) };
}

/** 刻一把武器：有空行就刻在第一个空行；没有空行时必须指定覆盖哪一行。返回刻在哪一行（-1 = 不行） */
export function engraveRow(arm: ArmState, id: WeaponId, row?: number): number {
    const k = row ?? arm.rows.indexOf(null);
    if (k < 0 || k >= ARM_ROWS) return -1;
    arm.rows[k] = id;
    // 刻好以后转轮停在这一行上（立刻拿在手上）
    arm.stops = [k, k, k];
    return k;
}

export function armHas(arm: ArmState, id: WeaponId): boolean {
    return arm.rows.includes(id);
}
