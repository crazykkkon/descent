/** 和格子交互的规则。游戏和求解器共用这一份，保证两边结果一致。 */
import { CharacterDef, Hero, MONSTERS } from './config';
import { simulateCombat } from './combat';
import { Cell, FloorDef } from './floor';

export type Outcome = { ok: true; hero: Hero } | { ok: false; reason: string };

export function interact(cell: Cell, hero: Hero, floor: FloorDef, ch: CharacterDef): Outcome {
    switch (cell.kind) {
        case 'monster': {
            const m = MONSTERS[cell.id];
            const r = simulateCombat(hero, m);
            if (!r.canAttack) return { ok: false, reason: `打不动${m.name}：攻击要高于它的防御 ${m.def}` };
            if (!r.canWin) return { ok: false, reason: `打不死${m.name}：它回血比你打得快` };
            if (r.damage >= hero.hp) return { ok: false, reason: `打${m.name}要损失 ${r.damage} 生命，你会死` };
            return { ok: true, hero: { ...hero, hp: hero.hp - r.damage } };
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
