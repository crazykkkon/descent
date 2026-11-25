/**
 * 大转盘（"井中轮"层）：盘面 8 格全部公开，每格 1/8；奖励和风险都有。结果由本局种子决定。
 */
import { draw, risingPrice } from './rng';

export type WheelPrize = 'gold' | 'hp' | 'atk' | 'def' | 'engrave' | 'leech' | 'erase';

export interface WheelSector { prize: WheelPrize; amount: number; text: string }

export const WHEEL: WheelSector[] = [
    { prize: 'gold', amount: 30, text: '金币 +30' },
    { prize: 'hp', amount: 60, text: '生命 +60' },
    { prize: 'atk', amount: 1, text: '攻击 +1' },
    { prize: 'engrave', amount: 1, text: '新图案' },
    { prize: 'gold', amount: 30, text: '金币 +30' },
    { prize: 'def', amount: 1, text: '防御 +1' },
    { prize: 'leech', amount: 40, text: '井蛭 −40 生命' },
    { prize: 'erase', amount: 1, text: '擦掉一个图案' },
];

export const WHEEL_BASE_PRICE = 30;

export function wheelPrice(spins: number): number {
    return risingPrice(WHEEL_BASE_PRICE, spins);
}

/** 第 n 次转停在哪一格 */
export function wheelStop(seed: number, key: number, n: number): number {
    return Math.floor(draw(seed, key, n) * WHEEL.length);
}
