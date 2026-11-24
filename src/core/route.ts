/**
 * 一局的路线（断臂转轮版，设计方案第五、六章）。
 *
 * - 第 1、2 层：固定是教学层（沿用试玩版的布局池，按种子换图）。
 * - 第 3 层起每层楼梯二选一，不标类型。第 10 层中段精英、第 19 层守门人、第 20 层井底之眼固定。
 * - 第 9、17 层出口交井租。
 * - 新手教程局：第 1～5 层，第 5 层遇到打不过的井底之眼。
 *
 * 地图、数值、类型的出现比例全部是讨论项。整条路线由本局种子决定（Lua 版用同样的算法逐位复现）。
 */
import { MARK_WEAPON, MONSTERS, UPGRADE_CHARS, WeaponId, WEAPONS } from './config';
import { FloorDef, FloorKind, StallOffer, parseFloor } from './floor';
import { DEMO_POOLS, F2_CLASSIC, F2_CONTRACT, F5_ELITE, F4_GAMBLE, FloorPool, buildFloor } from './levels';
import { draw, pick } from './rng';
import { BIG_MAPS } from './bigmaps';
import { DEPTH_POWER, weaponPool } from './meta';

/**
 * 地图尺寸：16×11（制作人定）。route.ts / levels.ts 里写的是小图（逻辑原稿，11×7 或 9×7），
 * tools/expand.ts 把它们放大成 16×11（加外墙、拉长走廊，打法和原稿完全一样，求解器核对过），
 * 并给要分岔的图加第二个出口 '<'，结果存在 bigmaps.ts。改了小图要重新跑 npm run expand。
 */
export const MAP_W = 16;
export const MAP_H = 11;
export function mapKey(small: string[]): string { return small.join('/'); }
/** 小图 → 16×11 大图（还没生成时先用小图，测试会检查） */
export function big(small: string[]): string[] { return BIG_MAPS[mapKey(small)] ?? small; }
/** 这一层只有一个出口：把第二个出口 '<' 堵成墙（出口是终点，堵掉不影响别处） */
export function oneExit(map: string[]): string[] { return map.map(r => r.replace('<', '#')); }

/** 各段的数值 */
export const SHALLOW = { gem: 1, smallPotion: 50, bigPotion: 150, gold: 25, bloodCost: 80 };
export const DEEP = { gem: 1, smallPotion: 50, bigPotion: 120, gold: 30, bloodCost: 100 };
export const BOTTOM = { gem: 1, smallPotion: 60, bigPotion: 150, gold: 40, bloodCost: 120 };

/** 井租：第几层（从 0 开始）→ 金额 */
export const RENTS: Record<number, number> = { 8: 120, 16: 250 };

export const ROUTE_LENGTH = 20;

const STALL_SHALLOW: StallOffer[] = [{ id: 'hp', amount: 80, price: 25 }, { id: 'atk', amount: 1, price: 40 }, { id: 'def', amount: 1, price: 40 }];
const STALL_DEEP: StallOffer[] = [{ id: 'hp', amount: 150, price: 40 }, { id: 'atk', amount: 2, price: 70 }, { id: 'def', amount: 2, price: 70 }];

export interface MapEntry {
    name: string;
    hint: string;
    kind: FloorKind;
    map: string[];
    /** 小图原稿（放大前） */
    small: string[];
    /** 最早出现在第几层（从 0 开始），用来让新怪晚一点出现 */
    from?: number;
}

function poolMaps(pool: FloorPool, kind: FloorKind, hint: string, from?: number): MapEntry[] {
    const out: MapEntry[] = [];
    pool.layouts.forEach((l, li) => l.variants.forEach((_, vi) => {
        const f = buildFloor(pool, { layout: li, variant: vi });
        out.push({ name: `${l.name}${l.variants.length > 1 ? vi + 1 : ''}`, hint, kind, map: big(f.map), small: f.map, from });
    }));
    return out;
}

const E = (name: string, hint: string, kind: FloorKind, map: string[], from?: number): MapEntry => ({ name, hint, kind, map: big(map), small: map, from });

/** 第 1、2 层的图（只有一个出口） */
export const F1_MAPS: MapEntry[] = poolMaps(DEMO_POOLS[0], 'normal', DEMO_POOLS[0].params.hint);
export const F2_MAPS: MapEntry[] = poolMaps(F2_CONTRACT, 'normal', F2_CONTRACT.params.hint);

/** 普通层：前段（第 3～9 层） */
export const NORMAL_SHALLOW: MapEntry[] = [
    ...poolMaps(DEMO_POOLS[2], 'normal', '回声蝠会先打你一下；溺魂会吸血，攻击不够根本打不死。', 3),
    ...poolMaps(F2_CLASSIC, 'normal', '锈甲虫防御很高，攻击不够就打不动。'),
    E('暗河', '井鼠挤在一起时更凶：每有一只相邻的井鼠，攻击 +5。先打边上落单的。', 'normal', [
        '@....#.wwr.',
        '.###.#.w##.',
        '.#h......#.',
        '.#.##.##.#.',
        '.e.#..ww.#.',
        '.###...w.#.',
        '....v.#..f>',
    ], 4),
    E('盐窟', '盐蚀蛞蝓每打中你一下，你这一仗的防御就 −1。', 'normal', [
        '@..k.#..u.$',
        '.###.#.####',
        '.#e..D....h',
        '.#.#####.#.',
        '.c.#u.b#.#.',
        '.#.#.###.#.',
        '...f.....x>',
    ], 4),
    E('骨龛', '骸骨祭司让相邻的怪物防御 +6。先拆祭司，还是硬闯？', 'normal', [
        '@...e..#..h',
        '.#####.#.#.',
        '.#r..B.p..h',
        '.#.####x###',
        '.....g...f.',
        '.###.#.###.',
        'h..m.#...v>',
    ], 5),
];

/** 普通层：后段（第 11～18 层） */
export const NORMAL_DEEP: MapEntry[] = [
    ...NORMAL_SHALLOW.slice(-3),
    E('绳桥', '短短一段，桥那头有光。', 'normal', [
        '@.e.$#..h..',
        '.###.#.###.',
        '...v...w.w>',
        '###########',
        '###########',
        '###########',
        '###########',
    ]),
    E('收租口', '血门近路省战力，多打一场能凑金币。', 'normal', [
        '@..f..$..g.',
        '.#####.###.',
        '.B.......#.',
        '.#.#####.#.',
        '.#..$..c.#.',
        '.#######.#.',
        '...w.w...$>',
    ]),
    E('双井道', '两条井道，一条要钥匙。', 'normal', [
        '@.w..#..x.h',
        '.#w#.#.###.',
        '.#r#...g...',
        '.#.#####.#.',
        '.v...k...#.',
        '.#####D###.',
        'h....u....>',
    ]),
    E('蓄水窖', '近路上全是血瓶。', 'normal', [
        '@.H.u.h...>',
        '.####.####.',
        '.x..g..w.w.',
        '.#########.',
        '.b..m..$...',
        '###########',
        '###########',
    ]),
    E('锈栅', '用骨钥绕开被庇护的蛞蝓，还是先拆掉祭司？', 'normal', [
        '@..k.#.p.$.',
        '.###.#.u##.',
        '.#$.D......',
        '.#.#####.#.',
        '.w.w...g.#.',
        '.#####.###.',
        '.....h...x>',
    ]),
    E('裂石廊', '头顶的石头在掉渣。', 'normal', [
        '@...r...w.>',
        '.#########.',
        '...h...u...',
        '###########',
        '###########',
        '###########',
        '###########',
    ]),
    E('回声库', '守卫身后是金币。', 'normal', [
        '@..g..$.$..',
        '.#########.',
        '.k.D..x..h.',
        '.#########.',
        '..u..b..w.w',
        '##########.',
        '##########>',
    ]),
    E('抵押厅', '每一格都有人押过东西。', 'normal', [
        '@..x...u..$',
        '.#####.###.',
        '.h..p.g...$',
        '.#.#####.#.',
        '.w...r...#.',
        '.#.#####.#.',
        '.....$...u>',
    ]),
];

const ELITE_HINT = '精英封住了出口。打败它可以往断臂转轮上刻一把武器。';
export const ELITE_SHALLOW: MapEntry[] = poolMaps(F5_ELITE, 'elite', ELITE_HINT);
export const ELITE_DEEP: MapEntry[] = [
    E('锈厅', '石鳞守卫身边站着祭司。先拆祭司，还是直接打？', 'elite', [
        '@..r.#..b..',
        '.###.#.###.',
        '.#h..x...#.',
        '.#.#####.#.',
        '.u...pG..#.',
        '.#######.#.',
        '.........>.',
    ]),
    ...ELITE_SHALLOW,
];

export const WHEEL_MAPS: MapEntry[] = poolMaps(F4_GAMBLE, 'wheel', '井壁上嵌着一台大转盘。站到旁边点它，花金币或生命转一次。');
export const PAWN_MAPS: MapEntry[] = [
    E('当铺', '有人在这里收东西，也卖东西。', 'pawn', [
        '@...m...r..',
        '.###.###.#.',
        '.#b..N..e#.',
        '.#.#####.#.',
        '...f..k...>',
        '###########',
        '###########',
    ]),
];
export const ALTAR_MAPS: MapEntry[] = [
    E('骨坛', '骨坛上堆着怪物的骨头。献点东西，能把它们的本事移到你的武器上。', 'altar', [
        '@..v...h...',
        '.#######.#.',
        '.r..A..g.#.',
        '.#######.#.',
        '..b..c.r..>',
        '###########',
        '###########',
    ]),
];
export const CAMP_MAPS: MapEntry[] = [
    E('营火', '火边有个补给摊。', 'camp', [
        '@...h...H..',
        '.###M###...',
        '...e.r..b.>',
        '###########',
        '###########',
        '###########',
        '###########',
    ]),
];

/** 固定层 */
export const MID_ELITE = E('断绞盘', '石鳞守卫身边站着一只骸骨祭司。先拆祭司，还是直接打被庇护的守卫？', 'elite', [
    '@..b.#..h..',
    '.###.#.###.',
    '.#h..e...#.',
    '.#.#####.#.',
    '.c...up..#.',
    '.#####G.##.',
    '######>####',
]);
export const GATE = E('守门', '守门人两边各一只骸骨祭司（庇护不叠加）。先拆祭司，还是直接挑战？', 'elite', [
    '@..r..b..h.',
    '.#########.',
    '.u..w.w..u.',
    '.###...###.',
    '.###pKp###.',
    '#####.#####',
    '#####>#####',
]);
export const BOSS = E('井底之眼', '（Boss 站位战还没做，先是一场确定的战斗。）', 'boss', [
    '@...h.h...b',
    '.#########.',
    '.g.r.E.r.g.',
    '.####.####.',
    '.####>####.',
    '###########',
    '###########',
]);
/** 新手教程第 5 层：井底之眼守着出口，打不过 */
export const TUTORIAL_BOSS = E('井底', '出口前趴着一个巨大的东西。', 'boss', [
    '#########',
    '#########',
    '@.h..r.E>',
    '#########',
    '#########',
    '#########',
    '#########',
].map(r => r.padEnd(9, '#')));

function band(d: number) { return d >= 18 ? BOTTOM : d >= 10 ? DEEP : SHALLOW; }

/** 普通层随机给一只怪打上印记（第 1 层一定有，帮玩家拿到第一把武器） */
function markFor(seed: number, d: number, slot: number, map: string[]): number[] | undefined {
    const cells = parseFloor({ name: 't', map, bloodCost: 0, gem: 0, smallPotion: 0, bigPotion: 0, gold: 0 }).cells;
    const cand = cells.map((c, i) => (c.kind === 'monster' && MARK_WEAPON[c.id] && !MONSTERS[c.id].elite ? i : -1)).filter(i => i >= 0);
    if (!cand.length) return undefined;
    if (d > 0 && draw(seed, 8100 + d * 10 + slot, 0) >= 0.6) return undefined;
    return [cand[pick(seed, 8100 + d * 10 + slot, 1, cand.length)]];
}

/**
 * 大宝石（制作人定）：第 1～6 层只有小宝石（+1）；第 7 层起偶尔出现大宝石（+3），第 7～10 层一层最多一颗、概率很小；
 * 第 11 层起大小都有，每颗宝石是大的概率越往下越高。按种子定好（求解器照样能算）。概率是讨论项。
 */
export const BIG_GEM_FROM = 6;
export const BIG_GEM_MIX_FROM = 10;
/** 第 7～10 层：这一层出一颗大宝石的概率 */
export const BIG_GEM_EARLY = 0.25;
/** 第 11 层起：每颗宝石是大的概率 = BIG_GEM_P0 + BIG_GEM_STEP × (层号 − 11)，最多 BIG_GEM_PMAX */
export const BIG_GEM_P0 = 0.3;
export const BIG_GEM_STEP = 0.04;
export const BIG_GEM_PMAX = 0.7;
export function bigGems(map: string[], seed: number, d: number, slot: number): string[] {
    if (d < BIG_GEM_FROM) return map;
    const gems: [number, number][] = [];
    map.forEach((r, y) => { for (let x = 0; x < r.length; x++) if (r[x] === 'r' || r[x] === 'b') gems.push([y, x]); });
    if (!gems.length) return map;
    const key = 8700 + d * 10 + slot;
    let pickSet: number[];
    if (d < BIG_GEM_MIX_FROM) {
        pickSet = draw(seed, key, 0) < BIG_GEM_EARLY ? [pick(seed, key, 1, gems.length)] : [];
    } else {
        const p = Math.min(BIG_GEM_PMAX, BIG_GEM_P0 + BIG_GEM_STEP * (d - BIG_GEM_MIX_FROM));
        pickSet = gems.map((_, k) => k).filter(k => draw(seed, key, 2 + k) < p);
    }
    if (!pickSet.length) return map;
    const rows = map.map(r => r.split(''));
    for (const k of pickSet) {
        const [y, x] = gems[k];
        rows[y][x] = rows[y][x] === 'r' ? 'R' : 'C';
    }
    return rows.map(r => r.join(''));
}

/** 第 6 层起（d ≥ UPGRADE_FROM）小怪换成更凶的同类 */
export const UPGRADE_FROM = 5;
/** 第 7 层起（d > POWER_FROM）每往下一层，怪物加强一级，最多 POWER_MAX 级 */
export const POWER_FROM = 5;
/** 最多加强几级：14 = 一直加到第 20 层（原来是 6，第 12 层以后怪不再变强，后期一大半的怪打不疼主角） */
export const POWER_MAX = 14;

/** 这一层的怪按深度换成更凶的同类、加强几级（制作人：后面的小怪太好打） */
export function deepen(map: string[], d: number): string[] {
    if (d < UPGRADE_FROM) return map;
    return map.map(r => r.replace(/[mefcvgx]/g, ch => UPGRADE_CHARS[ch]));
}
// 第 20 层也加（每只怪按自己的 basePower 扣掉，井底之眼是精英再减半）；教程的井底不走这里
export function powerFor(d: number, _kind?: FloorKind): number {
    return d <= POWER_FROM ? 0 : Math.min(POWER_MAX, d - POWER_FROM);
}

/** 路线选项（灵魂碎片解锁的东西、深度模式） */
export interface RouteOptions {
    /** 深度模式 0～3 */
    depth?: number;
    /** 已经解锁的东西（meta.ts 的 UNLOCKS id） */
    unlocks?: string[];
}

function toFloor(seed: number, d: number, slot: number, e: MapEntry, opts: RouteOptions = {}): FloorDef {
    const unlocks = opts.unlocks ?? [];
    const p = band(d);
    const map = bigGems(e.kind === 'boss' ? e.map : deepen(e.map, d), seed, d, slot);
    const f: FloorDef = { ...p, name: `第 ${d + 1} 层 · ${e.name}`, hint: e.hint, map, kind: e.kind };
    const power = powerFor(d, e.kind);
    if (power) f.power = power;
    if (e.kind === 'elite' || e.kind === 'boss') f.eliteReward = e.kind === 'elite';
    if (e.kind === 'normal') { const m = markFor(seed, d, slot, map); if (m) f.marks = m; }
    if (e.kind === 'camp') {
        f.stall = [...(d >= 10 ? STALL_DEEP : STALL_SHALLOW)];
        // 解锁"营火的骨钥"：多卖一把骨钥
        if (unlocks.includes('campKey')) f.stall.push({ id: 'key', amount: 1, price: d >= 10 ? 40 : 30 });
    }
    if (e.kind === 'pawn') {
        const all = weaponPool(unlocks);
        const a = pick(seed, 8500 + d * 10 + slot, 0, all.length);
        let b = pick(seed, 8500 + d * 10 + slot, 1, all.length - 1);
        if (b >= a) b++;
        f.shop = [all[a], all[b]];
        // 很小的机会第二件换成赖子
        if (draw(seed, 8600 + d * 10 + slot, 0) < 0.1) f.shop[1] = 'wild';
        // 解锁"当铺的第三件"：多摆一件
        if (unlocks.includes('pawnExtra')) {
            const rest = all.filter(w => w !== all[a] && w !== all[b]);
            f.shop.push(rest[pick(seed, 8500 + d * 10 + slot, 2, rest.length)]);
        }
    }
    if (RENTS[d]) f.rent = RENTS[d];
    return f;
}

/** 从池子里挑一张这一局还没用过的图 */
function choose(seed: number, key: number, pool: MapEntry[], d: number, used: Set<string>): MapEntry {
    const ok = pool.filter(e => (e.from ?? 0) <= d);
    const start = pick(seed, key, 0, ok.length);
    for (let k = 0; k < ok.length; k++) {
        const e = ok[(start + k) % ok.length];
        if (!used.has(e.name)) { used.add(e.name); return e; }
    }
    return ok[start];
}

/** 楼梯后面是什么类型：一条一定是要打的层（普通或精英），另一条可能是设施 */
const OTHER_KINDS: FloorKind[] = ['normal', 'wheel', 'pawn', 'altar', 'camp', 'wheel', 'pawn', 'camp'];

function poolOf(kind: FloorKind, d: number): MapEntry[] {
    switch (kind) {
        case 'elite': return d >= 10 ? ELITE_DEEP : ELITE_SHALLOW;
        case 'wheel': return WHEEL_MAPS;
        case 'pawn': return PAWN_MAPS;
        case 'altar': return ALTAR_MAPS;
        case 'camp': return CAMP_MAPS;
        default: return d >= 10 ? NORMAL_DEEP : NORMAL_SHALLOW;
    }
}

/** 只有一个候选的层（从 0 开始）：第 1、2、3、10、11、19、20 层。第 3、11 层只有一条路，是因为第 2、10 层只有一个出口 */
export const FIXED_FLOORS = [0, 1, 2, 9, 10, 18, 19];

/**
 * 一局的完整路线：每层 1 个或 2 个候选。
 * 下一层有两个候选的层，地图上有两个出口：'>' 通向第一个候选，'<' 通向第二个；其余层只有 '>'。
 */
export function buildRoute(seed: number, opts: RouteOptions = {}): FloorDef[][] {
    const used = new Set<string>();
    const plan: FloorDef[][] = [];
    for (let d = 0; d < ROUTE_LENGTH; d++) {
        let entries: MapEntry[];
        if (d === 0 || d === 1) {
            const all = d === 0 ? F1_MAPS : F2_MAPS;
            entries = [all[pick(seed, 8000 + d, 0, all.length)]];
        } else if (d === 9) entries = [MID_ELITE];
        else if (d === 18) entries = [GATE];
        else if (d === 19) entries = [BOSS];
        else {
            const fightKind: FloorKind = d >= 4 && draw(seed, 8200 + d, 0) < 0.3 ? 'elite' : 'normal';
            const a = choose(seed, 8300 + d * 10, poolOf(fightKind, d), d, used);
            if (FIXED_FLOORS.includes(d)) entries = [a];
            else {
                const otherKind = OTHER_KINDS[pick(seed, 8200 + d, 1, OTHER_KINDS.length)];
                const b = choose(seed, 8300 + d * 10 + 1, poolOf(otherKind, d), d, used);
                entries = draw(seed, 8200 + d, 2) < 0.5 ? [a, b] : [b, a];
            }
        }
        plan.push(entries.map((e, slot) => {
            if (d === 0 || d === 1) {
                const base = d === 0 ? DEMO_POOLS[0].params : F2_CONTRACT.params;
                const f: FloorDef = { ...base, name: base.name, hint: e.hint, map: e.map, kind: 'normal' };
                const m = markFor(seed, d, slot, e.map);
                if (m) f.marks = m;
                return f;
            }
            return toFloor(seed, d, slot, e, opts);
        }));
    }
    // 正式局的楼层：怪物用 RUN_STATS 的数值
    for (const cands of plan) for (const f of cands) f.runStats = true;
    // 下一层只有一个候选的层：只留一个出口
    plan.forEach((cands, d) => {
        if ((plan[d + 1]?.length ?? 0) !== 2) for (const f of cands) f.map = oneExit(f.map);
    });
    // 深度模式：第 1 级起怪物每级再加强 2 级（每一层都加，井底之眼也加，精英按一半算）；
    // 第 2 级起血瓶效果 −25%；第 3 级起井租和补给摊的价格 ×1.5
    const depth = opts.depth ?? 0;
    if (depth > 0) for (const cands of plan) for (const f of cands) {
        f.power = (f.power ?? 0) + DEPTH_POWER * depth;
        if (depth >= 2) { f.smallPotion = Math.floor((f.smallPotion * 3) / 4); f.bigPotion = Math.floor((f.bigPotion * 3) / 4); }
        if (depth >= 3) {
            if (f.rent) f.rent = Math.floor((f.rent * 3) / 2);
            if (f.stall) f.stall = f.stall.map(o => ({ ...o, price: Math.round((o.price * 3) / 2 / 5) * 5 }));
        }
    }
    return plan;
}

/**
 * 新手教程局的地图：固定 5 张，一层只教一件事（制作人：开局 5 层做成教学关卡的样子）。
 * 直接画成 16×11，不走放大工具。每一步的教学提示在 LÖVE 界面里（love/src/view/coach.lua）。
 * 第 1 层：走路、打怪、宝石让掉血变少、出口。第 2 层：骨钥和骨门、打不动的怪、血瓶。
 * 第 3 层：两条路怎么选（血门扣血 / 绕路打怪）。第 4 层：精英封住出口。第 5 层：井底之眼，打不过。
 */
const TW = '################';
const tut = (rows: string[]) => {
    const top = Math.floor((MAP_H - rows.length) / 2);
    return [...Array(top).fill(TW), ...rows, ...Array(MAP_H - top - rows.length).fill(TW)];
};
export const TUTORIAL_FLOORS: FloorDef[] = [
    { ...DEMO_POOLS[0].params, name: '第 1 层 · 井口', kind: 'normal', map: tut([
        '#@..m..r..m....#',
        '##############.#',
        '#>..e..h..b....#',
    ]) },
    { ...F2_CONTRACT.params, name: '第 2 层 · 骨门', kind: 'normal', map: tut([
        '#@..e...D.r...>#',
        '####m#h####c####',
        '####k######$####',
    ]) },
    { ...SHALLOW, bloodCost: 50, name: '第 3 层 · 岔路', kind: 'normal', map: tut([
        '#@..v...B.....>#',
        '#h############.#',
        '#...f..r..e....#',
    ]) },
    { ...SHALLOW, name: '第 4 层 · 鳞厅', kind: 'elite', map: tut([
        '#@..m..r..e..b.#',
        '#############.##',
        '#.h..r..b..H...#',
        '#.##############',
        '#.....G.......>#',
    ]) },
    { ...SHALLOW, name: '第 5 层 · 井底', hint: TUTORIAL_BOSS.hint, kind: 'boss', map: TUTORIAL_BOSS.map },
];

/** 新手教程局：第 1～5 层，第 5 层遇到打不过的井底之眼（每层只有一个出口） */
// 教程的宝石都是大宝石（+3，和原来 宝石 2 + 掘井人 1 一样，教程的数值不变）
export function buildTutorial(_seed: number): FloorDef[][] {
    return TUTORIAL_FLOORS.map(f => [{ ...f, map: oneExit(f.map).map(r => r.replace(/r/g, 'R').replace(/b/g, 'C')) }]);
}
