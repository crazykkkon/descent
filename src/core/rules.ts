/** 和格子交互的规则。游戏和求解器共用这一份，保证两边结果一致。 */
import { CharacterDef, Hero, MONSTERS, MonsterDef, powered, WEAPONS, BIG_GEM } from './config';
import { effectiveStats, simulateCombat } from './combat';
import { Cell, FloorDef } from './floor';

/** fatal：这一仗打完主角死了（生命为 0） */
export type Outcome = { ok: true; hero: Hero; fatal?: boolean; reason?: string } | { ok: false; reason: string };

/**
 * @param allowFatal 是否允许打会死的仗。游戏里允许（玩家可以硬上，打完就死）；
 *                   求解器和乱打的玩家模拟不允许（它们只找活路）。
 * @param mon 怪物算上周围格子（群居、庇护）以后的属性；不传就用怪物本身的数值
 */
export function interact(cell: Cell, hero: Hero, floor: FloorDef, ch: CharacterDef, allowFatal = false, mon?: MonsterDef): Outcome {
    switch (cell.kind) {
        case 'monster': {
            const m = mon ?? powered(MONSTERS[cell.id], floor.power, floor.runStats)
            const r = simulateCombat(hero, m);
            // 打不动、它也伤不到你（没有反伤）：两边谁也伤不到谁，打不起来（制作人 2026-11-24：打不动也能硬打，被一点点耗死）
            if (!r.canAttack && Math.max(m.atk - effectiveStats(hero).def, 0) === 0 && !m.traits.includes('thorns')) {
                return { ok: false, reason: `你和${m.name}都无法伤到对方` };
            }
            let reason = '';
            if (!r.canAttack) reason = `${m.name}的防御是 ${m.def}。你的攻击必须高于这个数值才能造成伤害`;
            else if (!r.canWin) reason = `${m.name}在战斗中不断回血，你的伤害不足以击败它`;
            else if (r.damage >= hero.hp) reason = `与${m.name}交战要承受 ${r.damage} 点伤害，现有生命不足以撑到最后`;
            if (reason) return allowFatal ? { ok: true, hero: { ...hero, hp: 0 }, fatal: true, reason } : { ok: false, reason };
            const w = hero.weapon ? WEAPONS[hero.weapon] : undefined;
            return { ok: true, hero: { ...hero, hp: hero.hp - r.damage + (w?.killHeal ?? 0), gold: hero.gold + m.gold + (w?.killGold ?? 0) } };
        }
        case 'item': {
            const h = { ...hero };
            const gem = floor.gem + ch.gemBonus;
            switch (cell.id) {
                case 'smallPotion': h.hp += floor.smallPotion; break;
                case 'bigPotion': h.hp += floor.bigPotion; break;
                case 'redGem': h.atk += gem; break;
                case 'blueGem': h.def += gem; break;
                case 'bigRedGem': h.atk += BIG_GEM + ch.gemBonus; break;
                case 'bigBlueGem': h.def += BIG_GEM + ch.gemBonus; break;
                case 'key': h.keys += 1; break;
                case 'gold': h.gold += floor.gold; break;
            }
            return { ok: true, hero: h };
        }
        case 'door':
            if (cell.door === 'bone') {
                // 拾荒者：不用骨钥，扣生命
                if (ch.boneDoorHp) {
                    if (hero.hp <= ch.boneDoorHp) return { ok: false, reason: `撬开骨门要扣 ${ch.boneDoorHp} 生命，你会死` };
                    return { ok: true, hero: { ...hero, hp: hero.hp - ch.boneDoorHp } };
                }
                if (hero.keys <= 0) return { ok: false, reason: '没有骨钥，打不开骨门' };
                return { ok: true, hero: { ...hero, keys: hero.keys - 1 } };
            }
            if (hero.hp <= floor.bloodCost) return { ok: false, reason: `穿过血门要扣 ${floor.bloodCost} 生命，你会死` };
            return { ok: true, hero: { ...hero, hp: hero.hp - floor.bloodCost } };
        default:
            return { ok: false, reason: '' };
    }
}

/** 这个格子上的东西被处理后是否可以通行 */
export function isEntity(cell: Cell): boolean {
    return cell.kind === 'monster' || cell.kind === 'item' || cell.kind === 'door';
}

export function isElite(cell: Cell): boolean {
    return cell.kind === 'monster' && !!MONSTERS[cell.id].elite;
}
