/**
 * 数值体检：按种子生成整局路线，模拟一个"认真玩"的玩家（每层用求解器，能把宝石血瓶都拿到就都拿，
 * 精英奖励选攻击），逐层统计：进层时的攻 / 防 / 生命、这一层怪物里"伤不到你"（0 伤）的比例、
 * 这一层打怪掉了多少血。用来看后期是不是太简单。
 * 用法：npx tsx tools/balance.ts [种子个数，默认 30] [深度模式 0～3，默认 0] [perks = 碎片强化买满]
 * 不算断臂转轮的武器、补给摊、当铺、骨坛、诏令（它们只会让主角更强），所以这里的"0 伤比例"是偏低的估计。
 */
import { buildRoute } from '../src/core/route';
import { solveFromStart } from '../src/core/solver';
import { CHARACTERS, Hero, MONSTERS, monsterInContext } from '../src/core/config';
import { adjacentMonsters, parseFloor } from '../src/core/floor';
import { eliteReward } from '../src/core/game';
import { PERKS, perkValue } from '../src/core/meta';

const seeds = Number(process.argv[2] ?? 30);
const depth = Number(process.argv[3] ?? 0);
/** 碎片强化买满（meta.ts 的 PERKS 最高级：攻、防、生命、骨钥、金币） */
const fullPerks = process.argv[4] === 'perks';
const ch = CHARACTERS.digger;
const rows: { atk: number[]; def: number[]; hp: number[]; zero: number[]; zero8: number[]; lost: number[]; monAtk: number[]; monDef: number[]; n: number }[] =
    Array.from({ length: 20 }, () => ({ atk: [], def: [], hp: [], zero: [], zero8: [], lost: [], monAtk: [], monDef: [], n: 0 }));
let dead = 0;
const stuck: number[] = [];
const finals: number[] = [];
/** 一点攻 / 防值多少生命（用来在"多拿属性"和"多留血"之间取舍） */
const STAT_HP = 10;

for (let seed = 1; seed <= seeds; seed++) {
    for (const way of [0, 1]) {
        const plan = buildRoute(seed, { depth });
        let hero: Hero = { ...ch.base };
        if (fullPerks) {
            const top = (id: string) => perkValue(id, PERKS.find(p => p.id === id)!.costs.length);
            hero = { ...hero, atk: hero.atk + top('atk'), def: hero.def + top('def'), hp: hero.hp + top('hp'), keys: hero.keys + top('keys'), gold: hero.gold + top('gold') };
        }
        for (let d = 0; d < plan.length; d++) {
            const opts = plan[d];
            const f = opts[Math.min(way, opts.length - 1)];
            const exit = plan[d + 1]?.length === 2 ? Math.min(way, 1) : undefined;
            const r = rows[d];
            r.atk.push(hero.atk); r.def.push(hero.def); r.hp.push(hero.hp);
            // 这一层的怪：按进层时的防御算，伤不伤得到你
            const p = parseFloor(f);
            let z = 0, z8 = 0, n = 0;
            p.cells.forEach((c, i) => {
                if (c.kind !== 'monster') return;
                const m = monsterInContext(MONSTERS[c.id], adjacentMonsters(p.cells, p.w, p.h, i), f.power, f.runStats);
                n++;
                r.monAtk.push(m.atk); r.monDef.push(m.def);
                if (m.atk - hero.def <= 0 && !m.traits.includes('thorns')) z++;
                if (m.atk - hero.def - 8 <= 0 && !m.traits.includes('thorns')) z8++;
            });
            if (n) { r.zero.push(z / n); r.zero8.push(z8 / n); }
            const s = solveFromStart(f, hero, ch, exit);
            // 在不被压制的结果里挑"生命 + 属性折算"最高的
            const out = s.pareto.slice().sort((a, b) =>
                (b.hero.hp + STAT_HP * (b.hero.atk + b.hero.def)) - (a.hero.hp + STAT_HP * (a.hero.atk + a.hero.def)))[0];
            if (!out) { dead++; stuck.push(d + 1); break; }
            if (d === plan.length - 1) finals.push(out.hero.hp);
            r.lost.push(Math.max(0, hero.hp - out.hero.hp));
            hero = out.hero;
            if (f.eliteReward) hero = { ...hero, atk: hero.atk + eliteReward(d, hero.gold, []).atk };
            if (f.rent) hero = hero.gold >= f.rent ? { ...hero, gold: hero.gold - f.rent } : { ...hero, atk: hero.atk - 2 };
            r.n++;
        }
    }
}

const avg = (a: number[]) => (a.length ? a.reduce((x, y) => x + y, 0) / a.length : NaN);
const f0 = (x: number) => (isNaN(x) ? '  -' : String(Math.round(x)).padStart(4));
console.log('层 | 进层 攻  防  生命 | 怪 攻  防 | 0伤比例 防+8时 | 本层净掉血（掉血 − 回血）');
rows.forEach((r, d) => {
    if (!r.n) return;
    console.log(`${String(d + 1).padStart(2)} | ${f0(avg(r.atk))} ${f0(avg(r.def))} ${f0(avg(r.hp))} | ${f0(avg(r.monAtk))} ${f0(avg(r.monDef))} | ${(avg(r.zero) * 100).toFixed(0).padStart(4)}%  ${(avg(r.zero8) * 100).toFixed(0).padStart(4)}% | ${f0(avg(r.lost))}`);
});
finals.sort((a, b) => a - b);
const total = seeds * 2;
const hist = new Map<number, number>();
for (const d of stuck) hist.set(d, (hist.get(d) ?? 0) + 1);
console.log(`路线数 ${total}，通关 ${total - dead}（${Math.round(((total - dead) / total) * 100)}%）`);
if (stuck.length) console.log('倒在第几层：' + [...hist.entries()].sort((a, b) => a[0] - b[0]).map(([d, n]) => `${d}层×${n}`).join(' '));
if (finals.length) console.log(`通关时剩余生命：最少 ${finals[0]}，中位 ${finals[finals.length >> 1]}，最多 ${finals[finals.length - 1]}`);
