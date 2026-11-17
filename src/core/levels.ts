/** M1 手工关卡：3 层教学难度。地图字符说明见 floor.ts。 */
import { FloorDef } from './floor';

const base = { gem: 2, smallPotion: 50, bigPotion: 150, gold: 20 };

export const M1_FLOORS: FloorDef[] = [
    {
        ...base,
        name: '第 1 层 · 井口',
        hint: '点怪物可以看到打它会损失多少生命。不需要打光所有怪，走到出口就行。',
        bloodCost: 40,
        map: [
            '@.m.r#h',
            '.##.##f',
            '.#k.D.b',
            '.####.#',
            'm.e..e.',
            '.#####B',
            'h..e..>',
        ],
    },
    {
        ...base,
        name: '第 2 层 · 苔壁',
        hint: '锈甲虫防御很高，攻击不够就打不动。先想想宝石在哪。',
        bloodCost: 60,
        map: [
            '@.m.#.k',
            '.##e#..',
            '.#r.c.#',
            'h##.#b.',
            '.e.f#.#',
            'B#.##.c',
            'H#e..#>',
        ],
    },
    {
        ...base,
        name: '第 3 层 · 回声',
        hint: '回声蝠会先打你一下；溺魂会吸血，攻击不够根本打不死。打不过的怪，也许可以绕开？',
        bloodCost: 80,
        map: [
            'b.v.#.@',
            '.#.#e.k',
            'h.g.D.#',
            '#.#.#.r',
            'f.c.v..',
            '.#B#.#B',
            'h.x..g>',
        ],
    },
];
