/** 战斗公式：完全固定、没有随机。预览和实际结算用同一个函数，保证"预览掉血 = 实际掉血"。 */
import { MonsterDef, THORNS_DAMAGE } from './config';

export interface CombatStats {
    atk: number;
    def: number;
}

export interface CombatResult {
    /** 主角能否破防（伤害为 0 时不能发起战斗） */
    canAttack: boolean;
    /** 能否在有限回合内打死（吸血怪回血太快时打不死） */
    canWin: boolean;
    /** 主角损失的总生命 */
    damage: number;
    /** 主角攻击次数 */
    hits: number;
}

const MAX_ROUNDS = 1000;

export function simulateCombat(hero: CombatStats, m: MonsterDef): CombatResult {
    const heroHit = Math.max(hero.atk - m.def, 0);
    if (heroHit === 0) return { canAttack: false, canWin: false, damage: 0, hits: 0 };

    const monsterHit = Math.max(m.atk - hero.def, 0);
    const hitsPerRound = m.traits.includes('double') ? 2 : 1;
    const lifesteal = m.traits.includes('lifesteal');
    const thorns = m.traits.includes('thorns');

    let mhp = m.hp;
    let damage = 0;
    let hits = 0;

    const monsterAttack = () => {
        damage += monsterHit;
        if (lifesteal) mhp = Math.min(m.hp, mhp + Math.floor(monsterHit / 2));
    };

    if (m.traits.includes('firstStrike')) monsterAttack();

    for (let round = 0; round < MAX_ROUNDS; round++) {
        mhp -= heroHit;
        hits++;
        if (thorns) damage += THORNS_DAMAGE;
        if (mhp <= 0) return { canAttack: true, canWin: true, damage, hits };
        for (let i = 0; i < hitsPerRound; i++) monsterAttack();
    }
    return { canAttack: true, canWin: false, damage, hits };
}
