/**
 * 楼梯口情报：下楼前透露下一层的一条情报，让"要不要折回去拿宝石"有依据。
 *
 * 情报从下一层的真实地图算出来，只挑"多半要打"的怪，不拿可以随便绕开的怪吓唬人：
 * 1. 候选 = 必经守卫（把它当成墙，入口就走不到出口）+ 按现在属性下一层最省血路线上要打的怪；
 * 2. 候选里优先挑有特点的（高防 > 吸血 > 先攻 > 反伤 > 二连击），再挑最难打的。
 * 同时给出"按现在的属性打它"和"拿了本层剩下的宝石后打它"的掉血对比。
 */
import { CharacterDef, Hero, MONSTERS, MonsterDef, MonsterId } from './config';
import { simulateCombat } from './combat';
import { Cell, FloorDef, neighbors, parseFloor } from './floor';
import { solveFloor } from './solver';

export interface Intel {
    /** 一句话情报，比如"下一层有高防守卫" */
    headline: string;
    /** 详细说明和掉血对比 */
    lines: string[];
    monster?: MonsterId;
    /** 是否是不打就过不去的必经守卫 */
    mustFight: boolean;
}

/** 把 index 处当成墙后，入口还能不能走到出口（其他怪物、门、道具都当作可以通过） */
function blocks(cells: Cell[], w: number, h: number, start: number, wall: number): boolean {
    const seen = new Uint8Array(cells.length);
    const stack = [start];
    seen[start] = 1;
    while (stack.length) {
        const cur = stack.pop()!;
        for (const n of neighbors(cur, w, h)) {
            if (seen[n] || n === wall) continue;
            seen[n] = 1;
            const c = cells[n];
            if (c.kind === 'exit') return false;
            if (c.kind !== 'wall') stack.push(n);
        }
    }
    return true;
}

/** 防御达到这个值算"高防守卫" */
const HIGH_DEF = 14;

const TRAIT_RANK = (m: MonsterDef): number => {
    if (m.def >= HIGH_DEF) return 5;
    if (m.traits.includes('lifesteal')) return 4;
    if (m.traits.includes('firstStrike')) return 3;
    if (m.traits.includes('thorns')) return 2;
    if (m.traits.includes('double')) return 1;
    return 0;
};

function damageText(hero: Hero, m: MonsterDef): string {
    const r = simulateCombat(hero, m);
    if (!r.canAttack) return '打不动';
    if (!r.canWin) return '打不死';
    // 只给数字，不替玩家下"会不会死"的结论
    return `-${r.damage}`;
}

/**
 * @param next 下一层
 * @param hero 主角现在的属性
 * @param current 当前这一层（用来找还没拿的宝石）；不传就不做对比
 */
export function stairIntel(next: FloorDef, hero: Hero, ch: CharacterDef, current?: { floor: FloorDef; cells: Cell[] }): Intel | null {
    const p = parseFloor(next);
    const monsters = p.cells
        .map((c, i) => (c.kind === 'monster' ? { i, m: MONSTERS[c.id] } : null))
        .filter((x): x is { i: number; m: MonsterDef } => !!x);
    if (!monsters.length) return null;

    const hard = (m: MonsterDef) => {
        const r = simulateCombat(hero, m);
        return !r.canAttack || !r.canWin ? Infinity : r.damage;
    };
    const must = monsters.filter(x => blocks(p.cells, p.w, p.h, p.start, x.i));
    const route = solveFloor({ w: p.w, h: p.h, cells: p.cells, pos: p.start }, hero, next, ch).best?.plan ?? [];
    const onRoute = monsters.filter(x => route.includes(x.i) && !must.includes(x));
    const pool = must.length || onRoute.length ? [...must, ...onRoute] : monsters;
    const pick = [...pool].sort((a, b) => TRAIT_RANK(b.m) - TRAIT_RANK(a.m) || hard(b.m) - hard(a.m))[0].m;
    const mustFight = must.some(x => x.m === pick);

    const where = mustFight ? '挡在必经之路上' : '守在主要路线上';
    let headline: string;
    if (pick.def >= HIGH_DEF) headline = `下一层有高防守卫：${pick.name}${where}`;
    else if (pick.traits.includes('lifesteal')) headline = `下一层有会吸血的${pick.name}${where}`;
    else if (pick.traits.includes('firstStrike')) headline = `下一层有先手攻击的${pick.name}${where}`;
    else if (pick.traits.includes('thorns')) headline = `下一层有会反伤的${pick.name}${where}`;
    else headline = `下一层的${pick.name}${where}`;

    const lines = [`${pick.name}：生命 ${pick.hp}　攻击 ${pick.atk}　防御 ${pick.def}`];
    if (pick.def >= HIGH_DEF) lines.push(`攻击要高于 ${pick.def} 才打得动它`);
    if (pick.traits.includes('lifesteal')) lines.push('它会吸血，攻击不够高就打不死');
    if (pick.traits.includes('firstStrike')) lines.push('它会先打你一下，防御越高越好打');
    if (pick.traits.includes('thorns')) lines.push('你每打它一下自己也掉 3 血，攻击越高、打的次数越少');
    lines.push(`按你现在的属性（攻 ${hero.atk} / 防 ${hero.def}）打它：${damageText(hero, pick)}`);

    // 本层还没拿的宝石：拿了以后再打它要掉多少
    if (current) {
        const gem = current.floor.gem + ch.gemBonus;
        const reds = current.cells.filter(c => c.kind === 'item' && c.id === 'redGem').length;
        const blues = current.cells.filter(c => c.kind === 'item' && c.id === 'blueGem').length;
        if (reds) lines.push(`本层还有 ${reds} 颗赤晶没拿，拿了以后（攻 ${hero.atk + gem * reds}）打它：${damageText({ ...hero, atk: hero.atk + gem * reds }, pick)}`);
        if (blues) lines.push(`本层还有 ${blues} 颗青晶没拿，拿了以后（防 ${hero.def + gem * blues}）打它：${damageText({ ...hero, def: hero.def + gem * blues }, pick)}`);
        if (reds && blues) lines.push(`两种都拿（攻 ${hero.atk + gem * reds} / 防 ${hero.def + gem * blues}）：${damageText({ ...hero, atk: hero.atk + gem * reds, def: hero.def + gem * blues }, pick)}`);
    }
    return { headline, lines, monster: pick.id, mustFight };
}
