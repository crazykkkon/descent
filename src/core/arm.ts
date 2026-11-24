/**
 * 断臂转轮（制作人定，2026-11-24）：三个轮子并排，每个轮子一圈 5 格。
 * - 刻图案只刻在一个轮子的一格上（玩家选哪个轮子）。
 * - 转一次：每个轮子各停在一格；只看中间一行——三个轮子停的格子是同一把武器 → 换成这把；
 *   三个都是空格 → 空手；其他 → 手上的武器不变。
 * - 转到某把武器的概率 = 三个轮子上它各自占的比例相乘（任何一个轮子上没有就不可能）。
 * 画面上每个轮子露出上中下 3 格，中间是转到的那一格；按住拨动可以看整圈，松手弹回。
 */
import { Boon, WeaponId } from './config';
import { draw } from './rng';

export const REELS = 3;
export const REEL_SIZE = 5;
/** 每层第一次转的价格（之后 ×1.5，换层重新算） */
export const ARM_BASE_PRICE = 10;

/** 一格：武器或空格（null） */
export type ArmSym = WeaponId | null;

export interface ArmState {
    /** reels[轮子][格子]：每个轮子一圈 5 格 */
    reels: ArmSym[][];
    /** 骨坛移到各把武器上的特性 */
    boons: Partial<Record<WeaponId, Boon[]>>;
    /** 本层已经转了几次（决定价格） */
    spins: number;
    /** 已经用掉的随机数个数 */
    draws: number;
    /** 每个轮子现在停在第几格 */
    stops: number[];
}

export function newArm(): ArmState {
    return {
        reels: Array.from({ length: REELS }, () => Array<ArmSym>(REEL_SIZE).fill(null)),
        boons: {}, spins: 0, draws: 0, stops: [0, 0, 0],
    };
}

/** 中间一行：三个轮子停着的图案 */
export function armFaces(arm: ArmState): ArmSym[] {
    return arm.stops.map((k, r) => arm.reels[r][k]);
}

/** 转一次（held 里为 true 的轮子不动）。key 用来区分楼层 */
export function armRoll(arm: ArmState, seed: number, key: number, held?: boolean[]): ArmSym[] {
    for (let r = 0; r < REELS; r++) {
        if (held?.[r]) continue;
        arm.stops[r] = Math.floor(draw(seed, key, arm.draws++) * REEL_SIZE);
    }
    return armFaces(arm);
}

/** 中间一行的结果：'weapon' 换武器，'empty' 变空手，'none' 不变 */
export function armOutcome(faces: ArmSym[]): { kind: 'weapon'; id: WeaponId } | { kind: 'empty' } | { kind: 'none' } {
    if (faces.every(f => f === faces[0])) return faces[0] ? { kind: 'weapon', id: faces[0] } : { kind: 'empty' };
    return { kind: 'none' };
}

/** 某个轮子上这把武器（或空格）占几格 */
export function reelCount(arm: ArmState, r: number, id: ArmSym): number {
    return arm.reels[r].filter(x => x === id).length;
}

/** 转一次连成这把武器（或三个空格）的概率 */
export function armOdds(arm: ArmState, id: ArmSym): number {
    let num = 1;
    for (let r = 0; r < REELS; r++) num *= reelCount(arm, r, id);
    return num / Math.pow(REEL_SIZE, REELS);
}

/** 锁住一些轮子后，重转连成一线的概率；锁住的图案不一样时返回 null */
export function armHoldOdds(arm: ArmState, held: boolean[]): { target: ArmSym; p: number } | null {
    const faces = armFaces(arm);
    const heldFaces = faces.filter((_, r) => held[r]);
    if (!heldFaces.length || heldFaces.some(f => f !== heldFaces[0])) return null;
    const target = heldFaces[0];
    let num = 1;
    let den = 1;
    for (let r = 0; r < REELS; r++) {
        if (held[r]) continue;
        num *= reelCount(arm, r, target);
        den *= REEL_SIZE;
    }
    return { target, p: num / den };
}

/** 这个轮子上第一个空格（没有返回 -1） */
export function firstBlank(arm: ArmState, r: number): number {
    return arm.reels[r].indexOf(null);
}

/**
 * 在第 r 个轮子上刻一把武器：cell 不给就刻在第一个空格；这个轮子刻满了必须指定覆盖哪一格。
 * 刻好后这个轮子转到这一格。返回刻在第几格（-1 = 不行）
 */
export function engraveCell(arm: ArmState, r: number, id: WeaponId, cell?: number): number {
    if (r < 0 || r >= REELS) return -1;
    const k = cell ?? firstBlank(arm, r);
    if (k < 0 || k >= REEL_SIZE) return -1;
    arm.reels[r][k] = id;
    arm.stops[r] = k;
    return k;
}

export function armHas(arm: ArmState, id: WeaponId): boolean {
    return arm.reels.some(reel => reel.includes(id));
}

/** 所有刻了图案的格子，按轮子、格子的顺序 */
export function engravedCells(arm: ArmState): [number, number][] {
    const out: [number, number][] = [];
    arm.reels.forEach((reel, r) => reel.forEach((x, k) => { if (x) out.push([r, k]); }));
    return out;
}

export function armEmpty(arm: ArmState): boolean {
    return engravedCells(arm).length === 0;
}
