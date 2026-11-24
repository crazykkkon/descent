/**
 * 井神的诏令：第 3、8、13 层开头各来一张，同时最多一张，可以拒绝。
 * 期限：从接下的这一层起，3 层之内完成。完成有奖励，逾期受罚（铜攻击 −2，银攻击 −4）。金诏令只在深度模式。
 */
import { MonsterDef } from './config';
import { pick } from './rng';

export type DecreeKind = 'killTrait' | 'noPotion' | 'clear' | 'noLoss' | 'gold';
export type DecreeTier = 'bronze' | 'silver';

export interface DecreeDef {
    kind: DecreeKind;
    tier: DecreeTier;
    /** 需要的数量（杀几只、带多少金） */
    n: number;
    text: string;
}

export const TIER_NAMES: Record<DecreeTier, string> = { bronze: '铜', silver: '银' };
export const DECREE_PENALTY: Record<DecreeTier, number> = { bronze: 1, silver: 2 };
/** 银诏令完成时额外给的生命 */
export const SILVER_BONUS_HP = 100;
/** 诏令来的层（从 0 开始数：第 3、8、13 层） */
export const DECREE_FLOORS = [2, 7, 12];
/** 期限：含接下的这一层在内的层数 */
export const DECREE_SPAN = 3;

export const DECREES: DecreeDef[] = [
    { kind: 'killTrait', tier: 'bronze', n: 2, text: '打败 2 只会先攻、吸血或反伤的怪' },
    { kind: 'noPotion', tier: 'bronze', n: 1, text: '有一层一瓶血瓶都不喝，走到出口' },
    { kind: 'clear', tier: 'silver', n: 1, text: '有一层把怪全部打完再走' },
    { kind: 'noLoss', tier: 'silver', n: 1, text: '有一层走出去时的生命不比进来时少' },
    { kind: 'gold', tier: 'silver', n: 150, text: '带着至少 150 金币走出一层' },
];

export interface ActiveDecree {
    def: DecreeDef;
    /** 最后一层（含）：floorIndex 超过它还没完成就算逾期 */
    until: number;
    progress: number;
}

/** 第 floorIndex 层开头来的诏令（不是诏令层返回 null） */
export function decreeFor(seed: number, floorIndex: number): DecreeDef | null {
    if (!DECREE_FLOORS.includes(floorIndex)) return null;
    return DECREES[pick(seed, 7000 + floorIndex, 0, DECREES.length)];
}

/** 打败一只怪时诏令的进度 */
export function killCounts(def: DecreeDef, m: MonsterDef): boolean {
    return def.kind === 'killTrait' && m.traits.some(t => t === 'firstStrike' || t === 'lifesteal' || t === 'thorns');
}
