/**
 * Steam 试玩版关卡：3 层，每层 3 种手工布局 × 2 套怪物和奖励。
 * 新开一局时按随机种子给每层选一种；同一布局的两套配置墙壁完全一样，只有内容不同。
 * 地图字符说明见 floor.ts。
 */
import { FloorDef } from './floor';

export interface FloorParams {
    name: string;
    hint: string;
    bloodCost: number;
    gem: number;
    smallPotion: number;
    bigPotion: number;
    gold: number;
}

export interface VariantDef {
    /** 这套配置的设计意图（给设计者看，不在游戏里显示，免得剧透） */
    note: string;
    map: string[];
}

export interface LayoutDef {
    name: string;
    variants: VariantDef[];
}

export interface FloorPool {
    params: FloorParams;
    layouts: LayoutDef[];
}

export interface FloorChoice {
    layout: number;
    variant: number;
}

const base = { gem: 2, smallPotion: 50, bigPotion: 150, gold: 20 };

export const DEMO_POOLS: FloorPool[] = [
    // ---------------- 第 1 层：9×7 教学层 ----------------
    {
        params: {
            ...base,
            name: '第 1 层 · 井口',
            hint: '怪物格子上的数字是打它要掉的血。不用清怪，走到出口就行；奖励都在怪物身后，值不值得打，自己算。',
            bloodCost: 40,
        },
        layouts: [
            {
                name: '两条路',
                variants: [
                    {
                        note: '花 15 血打井苔拿赤晶，能让后面的盲鳗少掉 30 血',
                        map: [
                            '..m.r#...',
                            '.#####.#.',
                            '@...e...>',
                            '.###.###.',
                            '.#b.m#h..',
                            '.#####.#.',
                            '....m....',
                        ],
                    },
                    {
                        note: '上路井苔守着青晶，中路盲鳗挡着出口，下路绕远但只有井苔',
                        map: [
                            '..m.b#.h.',
                            '.#####.#.',
                            '@...e...>',
                            '.###.###.',
                            '.#r.m#...',
                            '.#####.#.',
                            '....m..m.',
                        ],
                    },
                ],
            },
            {
                name: '回廊',
                variants: [
                    {
                        note: '外圈是环道，中间的小屋里有宝石，从上面进还是从下面进？',
                        map: [
                            '@...e....',
                            '.###.###.',
                            '.#r...b#.',
                            '.##...##.',
                            '..m.#.m..',
                            '.#######e',
                            '...m.h.e>',
                        ],
                    },
                    {
                        note: '小屋里只有一颗赤晶，但血瓶在环道另一头',
                        map: [
                            '@...m....',
                            '.###.###.',
                            '.#b.$..#.',
                            '.##...##.',
                            '..e.#.m..',
                            '.#######m',
                            '...m.r.e>',
                        ],
                    },
                ],
            },
            {
                name: '侧室',
                variants: [
                    {
                        note: '一条主路，两边的小房间各有奖励，守卫有强有弱',
                        map: [
                            '#r#h..#b#',
                            '#m###e#e#',
                            '#.#...#.#',
                            '@.....e.>',
                            '#.#.#.###',
                            '#e#D#m..#',
                            '#k#h#..h#',
                        ],
                    },
                    {
                        note: '钥匙和骨门：门后的大血瓶要不要现在拿？',
                        map: [
                            '#b#...#r#',
                            '#e###m#m#',
                            '#.#...#.#',
                            '@.....e.>',
                            '#.#.#.###',
                            '#m#D#m..#',
                            '#k#h#..h#',
                        ],
                    },
                ],
            },
        ],
    },
    // ---------------- 第 2 层：11×7 ----------------
    {
        params: {
            ...base,
            name: '第 2 层 · 苔壁',
            hint: '锈甲虫防御很高，攻击不够就打不动。先想想宝石在哪。',
            bloodCost: 60,
        },
        layouts: [
            {
                name: '岔路',
                variants: [
                    {
                        note: '上路的盲鳗守着骨钥；两颗赤晶一颗在右下角，一颗在井苔身后',
                        map: [
                            '@..e.#m..r.',
                            '.###.#.###.',
                            '.#e.k....#>',
                            '.#.###D#.#.',
                            '...#b..#...',
                            '##e#.###.#.',
                            'h..f.....rv',
                        ],
                    },
                    {
                        note: '骨钥在盲鳗身后，骨门后面是青晶；下路的盲鳗守着血瓶',
                        map: [
                            '@..e.#D..b.',
                            '.###.#.###.',
                            '.#m.e....#>',
                            '.#.###k#.#.',
                            '...#r..#...',
                            '##f#.###.#.',
                            'h..e.....rv',
                        ],
                    },
                ],
            },
            {
                name: '环道',
                variants: [
                    {
                        note: '只想赶路会被骨蛙堵死：先拿两颗赤晶再打它',
                        map: [
                            '@...f...D..',
                            '.###.#.###.',
                            '.#h..e..r#.',
                            '.#.###.##..',
                            '.#..r..m#.>',
                            '.##.###.#b.',
                            '..m.e...f.k',
                        ],
                    },
                    {
                        note: '中间的骨门可以不开，两只盲鳗各守一颗宝石',
                        map: [
                            '@...e...f..',
                            '.###.#.###.',
                            '.#r..D..e#.',
                            '.#.###.##..',
                            '.#..b..f#.>',
                            '.##.###.#h.',
                            '..e.e...r.k',
                        ],
                    },
                ],
            },
            {
                name: '侧室',
                variants: [
                    {
                        note: '出口被骨门封住，骨钥在盲鳗身后的侧室里',
                        map: [
                            '#h#.m.#b#.r',
                            '#e#.#.#f#.#',
                            '#.#.#.#.#.#',
                            '@....m...D>',
                            '#.#.#.#.#.#',
                            '#e#.c.#m#h#',
                            '#k#.#.#r#.#',
                        ],
                    },
                    {
                        note: '侧室里的宝石都有井苔守着，主路尽头的骨蛙非打不可',
                        map: [
                            '#b#.c.#r#.h',
                            '#m#.#.#m#.#',
                            '#.#.#.#.#.#',
                            '@........f>',
                            '#.#.#.#.#.#',
                            '#e#.v.#c#m#',
                            '#r#.#.#$#$#',
                        ],
                    },
                ],
            },
        ],
    },
    // ---------------- 第 3 层：11×7 ----------------
    {
        params: {
            ...base,
            name: '第 3 层 · 回声',
            hint: '回声蝠会先打你一下；溺魂会吸血，攻击不够根本打不死。打不过的怪，也许可以绕开？',
            bloodCost: 80,
        },
        layouts: [
            {
                name: '岔路',
                variants: [
                    {
                        note: '回声蝠守着骨门，门后的骨钥还能再开一扇门',
                        map: [
                            '@..f.#B..h.',
                            '.###.#.###.',
                            '.#v.D....#>',
                            '.#.###k#.#.',
                            '...#r..#...',
                            '##v#.###.#.',
                            'h..f.....bb',
                        ],
                    },
                    {
                        note: '裂岩蟹守着中路，走血门绕开它更划算',
                        map: [
                            '@..v.#e..h.',
                            '.###.#.###.',
                            '.#D.x....#>',
                            '.#.###r#.#.',
                            '...#k..#...',
                            '##B#.###.#.',
                            'h..v.....bb',
                        ],
                    },
                ],
            },
            {
                name: '环道',
                variants: [
                    {
                        note: '用骨钥开门可以少打一场；锈甲虫要攻击够了才打得动',
                        map: [
                            '@...D...g..',
                            '.###.#.###.',
                            '.#k..h..h#.',
                            '.#.###.##..',
                            '.#..r..f#.>',
                            '.##.###.#b.',
                            '..v.c...B.b',
                        ],
                    },
                    {
                        note: '骨蛙守着上面的环道，先拿赤晶再去打锈甲虫',
                        map: [
                            '@...f...x..',
                            '.###.#.###.',
                            '.#b..h..h#.',
                            '.#.###.##..',
                            '.#..r..c#.>',
                            '.##.###.#k.',
                            '..f.D...B.b',
                        ],
                    },
                ],
            },
            {
                name: '侧室',
                variants: [
                    {
                        note: '主路上的骨蛙非打不可；侧室里的锈甲虫守着骨钥',
                        map: [
                            '#k#.f.#e#.b',
                            '#c#.#.#r#.#',
                            '#.#.#.#.#.#',
                            '@....f...B>',
                            '#.#.#.#.#.#',
                            '#f#.v.#h#b#',
                            '#h#.#.#.#.#',
                        ],
                    },
                    {
                        note: '主路的血门可以绕开骨蛙；两只盲鳗守着出口和血瓶',
                        map: [
                            '#h#.v.#b#.v',
                            '#x#.#.#b#.#',
                            '#.#.#.#.#.#',
                            '@....B...e>',
                            '#.#.#.#.#.#',
                            '#v#...#e#k#',
                            '#r#.#.#h#.#',
                        ],
                    },
                ],
            },
        ],
    },
];

export function buildFloor(pool: FloorPool, choice: FloorChoice): FloorDef {
    const layout = pool.layouts[choice.layout];
    const v = layout.variants[choice.variant];
    return { ...pool.params, name: `${pool.params.name}`, hint: pool.params.hint, map: v.map };
}

/** 可重复的随机数（同一个种子得到同一串数） */
export function rng(seed: number): () => number {
    let a = seed >>> 0;
    return () => {
        a = (a + 0x6d2b79f5) >>> 0;
        let t = a;
        t = Math.imul(t ^ (t >>> 15), t | 1);
        t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
}

/**
 * 给每层选布局和配置。avoid 是上一局的选择：新开一局时每层都换成不同的地图
 * （每层有 6 种，排除上一局那一种后在剩下 5 种里选）。
 */
export function pickChoices(seed: number, pools: FloorPool[] = DEMO_POOLS, avoid?: FloorChoice[]): FloorChoice[] {
    const rand = rng(seed);
    const picked: FloorChoice[] = [];
    return pools.map((pool, i) => {
        const all: FloorChoice[] = [];
        pool.layouts.forEach((l, li) => l.variants.forEach((_, vi) => all.push({ layout: li, variant: vi })));
        const prev = avoid?.[i];
        let options = prev ? all.filter(c => c.layout !== prev.layout || c.variant !== prev.variant) : all;
        // 第 2、3 层共用同一批墙壁布局：连续两层不出现同一种布局
        const before = picked[i - 1];
        if (before) {
            const prevName = pools[i - 1].layouts[before.layout].name;
            const differ = options.filter(c => pool.layouts[c.layout].name !== prevName);
            if (differ.length) options = differ;
        }
        const choice = options[Math.floor(rand() * options.length)];
        picked.push(choice);
        return choice;
    });
}

export function buildFloors(choices: FloorChoice[], pools: FloorPool[] = DEMO_POOLS): FloorDef[] {
    return choices.map((c, i) => buildFloor(pools[i], c));
}

/** 所有可能的选图组合（测试和检查工具用） */
export function allChoices(pools: FloorPool[] = DEMO_POOLS): FloorChoice[][] {
    let combos: FloorChoice[][] = [[]];
    for (const pool of pools) {
        const next: FloorChoice[][] = [];
        for (const combo of combos) {
            pool.layouts.forEach((l, li) => l.variants.forEach((_, vi) => next.push([...combo, { layout: li, variant: vi }])));
        }
        combos = next;
    }
    return combos;
}
