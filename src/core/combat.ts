/** 战斗公式：完全固定、没有随机。预览和实际结算用同一个函数，保证"预览掉血 = 实际掉血"。 */
import { Boon, CORRODE_DEF, MonsterDef, THORNS_DAMAGE, WEAPONS, WeaponId } from './config';

export interface CombatStats {
    atk: number;
    def: number;
    weapon?: WeaponId;
    boons?: Boon[];
}

/** 算上武器以后的攻防（界面显示用） */
export function effectiveStats(hero: CombatStats): { atk: number; def: number } {
    const w = hero.weapon ? WEAPONS[hero.weapon] : undefined;
    return { atk: hero.atk + (w?.atk ?? 0), def: hero.def + (w?.def ?? 0) };
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
    const w = hero.weapon ? WEAPONS[hero.weapon] : undefined;
    const boons = hero.boons ?? [];
    const { atk, def } = effectiveStats(hero);
    const lifestealMon = m.traits.includes('lifesteal');
    const pierce = w?.pierce ?? 0;
    // 骨坛移来的腐蚀：你每打中一下，怪这一仗的防御 −1
    let mdef = m.def;
    const heroHitNow = () => {
        let hit = Math.max(atk - Math.max(mdef - pierce, 0), 0);
        if (w?.antiLifesteal && lifestealMon) hit *= 2;
        return hit;
    };
    if (heroHitNow() === 0) return { canAttack: false, canWin: false, damage: 0, hits: 0 };

    const hitsPerRound = m.traits.includes('double') ? 2 : 1;
    const thorns = m.traits.includes('thorns');
    const corrode = m.traits.includes('corrode');
    const myCorrode = boons.includes('corrode');
    const myThorns = boons.includes('thorns');
    const myLifesteal = boons.includes('lifesteal');
    // 腐蚀：怪物每打一下，主角这场战斗的防御 −1（只在这一仗里有效）
    let curDef = def;

    let mhp = m.hp;
    let damage = 0;
    let heal = 0;
    let hits = 0;
    const done = () => ({ canAttack: true, canWin: true, damage: Math.max(damage - heal, 0), hits });

    /** 主角打一下；返回怪死了没有 */
    const heroAttack = () => {
        const hit = heroHitNow();
        mhp -= hit;
        hits++;
        if (thorns) damage += THORNS_DAMAGE;
        if (myLifesteal) heal += Math.floor(hit / 4);
        if (myCorrode) mdef -= 1;
        return mhp <= 0;
    };
    /** 怪打一下；返回怪死了没有（反伤可能把它自己打死） */
    const monsterAttack = () => {
        const monsterHit = Math.max(m.atk - curDef, 0);
        damage += monsterHit;
        if (lifestealMon) mhp = Math.min(m.hp, mhp + Math.floor(monsterHit / 2));
        if (corrode) curDef -= CORRODE_DEF;
        if (myThorns) mhp -= THORNS_DAMAGE;
        return mhp <= 0;
    };

    // 开打前先刺：鱼叉一下、骨坛的先攻一下（可以叠加）
    const opening = (w?.firstHit ? 1 : 0) + (boons.includes('firstStrike') ? 1 : 0);
    for (let k = 0; k < opening; k++) if (heroAttack()) return done();
    if (m.traits.includes('firstStrike') && !w?.noFirstStrike) if (monsterAttack()) return done();

    for (let round = 0; round < MAX_ROUNDS; round++) {
        if (heroAttack()) return done();
        for (let i = 0; i < hitsPerRound; i++) if (monsterAttack()) return done();
    }
    return { canAttack: true, canWin: false, damage, hits };
}
