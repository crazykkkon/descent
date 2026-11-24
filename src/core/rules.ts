/** 和格子交互的规则。游戏和求解器共用这一份，保证两边结果一致。 */
import { CharacterDef, Hero, MONSTERS, MonsterDef, powered, WEAPONS } from './config';
import { simulateCombat } from './combat';
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
            const m = mon ?? powered(MONSTERS[cell.id], floor.power)
            const r = simulateCombat(hero, m);
            let reason = '';
            if (!r.canAttack) reason = `打不动${m.name}：攻击要高于它的防御 ${m.def}`;
            else if (!r.canWin) reason = `打不死${m.name}：它回血比你打得快`;
            else if (r.damage >= hero.hp) reason = `打${m.name}要损失 ${r.damage} 生命，你会死`;
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
