/**
 * 地图放大：把 route.ts / levels.ts 里的小图原稿（11×7、9×7）放大成 16×11，并给要分岔的图加第二个出口 '<'。
 *
 * 做法（保证打法和原稿完全一样）：
 * 1. 外面包一圈墙。
 * 2. 在两列（两行）之间插一条新走廊：两边都能走的地方是空地，否则是墙。
 *    新走廊里上下相邻的两格都是空地时，要求原来那 2×2 格全是空地，否则会凭空多出一条绕过怪物的路，这个位置就不能插。
 * 3. 出口如果是死胡同、紧挨着外墙，就挪进外墙里（看起来像墙上的洞）。
 * 4. 第二个出口：挑一个只连着一格的墙角（优先外墙），离第一个出口越远越好，
 *    要求所有"能走到第一个出口"的代表属性也都能走到它；两个出口的最优结果不一样的优先。
 * 每张图放大后都用求解器核对：走 '>' 的所有不被压制的结果和原稿一模一样。
 *
 * 用法：npm run expand（重新生成 src/core/bigmaps.ts）
 */
import { writeFileSync } from 'node:fs';
import { CHARACTERS, Hero } from '../src/core/config';
import { FloorDef } from '../src/core/floor';
import * as R from '../src/core/route';
import { solveFromStart, paretoFilter } from '../src/core/solver';

const W = R.MAP_W, H = R.MAP_H;
type Grid = string[][];

const passable = (c: string) => c !== '#';
const plain = (c: string) => c === '.' || c === '@';

/** 在第 x 列和第 x+1 列之间插一列；不行就返回 null */
function insertCol(g: Grid, x: number): Grid | null {
    const col: string[] = [];
    for (let y = 0; y < g.length; y++) col.push(passable(g[y][x]) && passable(g[y][x + 1]) ? '.' : '#');
    for (let y = 0; y + 1 < g.length; y++) {
        if (col[y] === '.' && col[y + 1] === '.' && !(plain(g[y][x]) && plain(g[y][x + 1]) && plain(g[y + 1][x]) && plain(g[y + 1][x + 1]))) return null;
    }
    return g.map((row, y) => [...row.slice(0, x + 1), col[y], ...row.slice(x + 1)]);
}
const transpose = (g: Grid): Grid => g[0].map((_, x) => g.map(r => r[x]));

/** 插 n 列：在所有能插的位置里挑分布最均匀的一组 */
function widen(g: Grid, n: number): Grid {
    const w = g[0].length;
    const ok: number[] = [];
    for (let x = 1; x < w - 2; x++) if (insertCol(g, x)) ok.push(x);
    const k = Math.min(n, ok.length);
    let best: number[] = [], bestScore = -Infinity;
    const pickSets = (start: number, cur: number[]) => {
        if (cur.length === k) {
            // 分布均匀：相邻插入点之间的最小间距尽量大，其次总体靠近等分点
            const pts = [0, ...cur, w - 1];
            let minGap = Infinity;
            for (let i = 1; i < pts.length; i++) minGap = Math.min(minGap, pts[i] - pts[i - 1]);
            const ideal = cur.reduce((s, x, i) => s - Math.abs(x - ((i + 1) * (w - 1)) / (k + 1)), 0);
            const score = minGap * 100 + ideal;
            if (score > bestScore) { bestScore = score; best = [...cur]; }
            return;
        }
        for (let i = start; i < ok.length; i++) pickSets(i + 1, [...cur, ok[i]]);
    };
    pickSets(0, []);
    let out = g;
    for (const x of [...best].sort((a, b) => b - a)) out = insertCol(out, x)!;
    // 插不够的，用加厚外墙补齐
    for (let i = k; i < n; i++) out = out.map(r => (i % 2 ? ['#', ...r] : [...r, '#']));
    return out;
}

function enlarge(small: string[]): Grid {
    let g: Grid = [Array(small[0].length + 2).fill('#'), ...small.map(r => ['#', ...r, '#']), Array(small[0].length + 2).fill('#')];
    g = widen(g, W - g[0].length);
    g = transpose(widen(transpose(g), H - g.length));
    return transpose(recenter(transpose(recenter(g))));
}

const idx = (g: Grid, ch: string) => { for (let y = 0; y < g.length; y++) { const x = g[y].indexOf(ch); if (x >= 0) return [x, y]; } return [-1, -1]; };
const DIRS = [[1, 0], [-1, 0], [0, 1], [0, -1]];
const inside = (x: number, y: number) => x >= 0 && y >= 0 && x < W && y < H;
const ring = (x: number, y: number) => x === 0 || y === 0 || x === W - 1 || y === H - 1;
const openNbrs = (g: Grid, x: number, y: number) => DIRS.map(([dx, dy]) => [x + dx, y + dy]).filter(([a, b]) => inside(a, b) && passable(g[b][a]));

/** 出口是死胡同：挪进旁边的墙里（看起来像墙上的洞），优先朝外的方向 */
function exitIntoWall(g: Grid) {
    const [x, y] = idx(g, '>');
    const nb = openNbrs(g, x, y);
    if (nb.length !== 1) return;
    const [nx, ny] = nb[0];
    const dirs = [...DIRS].sort((p, q) => (p[0] === x - nx && p[1] === y - ny ? -1 : 0) - (q[0] === x - nx && q[1] === y - ny ? -1 : 0));
    for (const [dx, dy] of dirs) {
        const a = x + dx, b = y + dy;
        if (inside(a, b) && g[b][a] === '#' && openNbrs(g, a, b).length === 1) { g[y][x] = '.'; g[b][a] = '>'; return; }
    }
}

/** 内容挤在一边（上下或左右全是墙）时挪到中间 */
function recenter(g: Grid): Grid {
    const wallRow = (r: string[]) => r.every(c => c === '#');
    let t = 0; while (t < g.length && wallRow(g[t])) t++;
    let b = 0; while (b < g.length && wallRow(g[g.length - 1 - b])) b++;
    const top = Math.floor((t + b) / 2);
    if (top === t) return g;
    const content = g.slice(t, g.length - b);
    const wall = () => Array(g[0].length).fill('#');
    return [...Array.from({ length: top }, wall), ...content, ...Array.from({ length: t + b - top }, wall)];
}

/** 从入口走到格子 (x, y) 至少要先处理掉几个怪物或门（道具算能直接走） */
function blockers(g: Grid, tx: number, ty: number): number {
    const [sx, sy] = idx(g, '@');
    const dist = g.map(r => r.map(() => Infinity));
    dist[sy][sx] = 0;
    const dq: [number, number][] = [[sx, sy]];
    while (dq.length) {
        const [x, y] = dq.shift()!;
        for (const [dx, dy] of DIRS) {
            const a = x + dx, b = y + dy;
            if (!inside(a, b) || !passable(g[b][a]) || g[b][a] === '>' || g[b][a] === '<' || 'SNAM'.includes(g[b][a])) continue;
            const cost = /[a-zA-Z]/.test(g[b][a]) && !'khHrb'.includes(g[b][a]) ? 1 : 0;
            const nd = dist[y][x] + cost;
            if (nd < dist[b][a]) { dist[b][a] = nd; if (cost) dq.push([a, b]); else dq.unshift([a, b]); }
        }
    }
    return dist[ty][tx];
}

const toMap = (g: Grid) => g.map(r => r.join(''));
const floorOf = (map: string[], base: FloorDef): FloorDef => ({ ...base, map });
const heroKey = (h: Hero) => `${h.hp}/${h.atk}/${h.def}/${h.keys}/${h.gold}/${h.weapon ?? ''}`;
const sameSet = (a: Hero[], b: Hero[]) => a.map(heroKey).sort().join(',') === b.map(heroKey).sort().join(',');

// ---------- 每张小图的代表入场属性：沿现有路线连续求解，记下走进这张图时的不被压制的属性 ----------
interface Job { e: R.MapEntry; two: boolean; base: FloorDef; heroes: Hero[] }
const jobs = new Map<string, Job>();
const add = (e: R.MapEntry, two: boolean) => {
    const k = R.mapKey(e.small);
    const j = jobs.get(k);
    if (j) j.two ||= two;
    else jobs.set(k, { e, two, base: { ...R.SHALLOW, name: e.name, map: e.small, kind: e.kind }, heroes: [] });
};
for (const e of [...R.F1_MAPS, ...R.F2_MAPS, ...R.TUTORIAL_F3_MAPS, R.MID_ELITE, R.GATE, R.BOSS, R.TUTORIAL_BOSS]) add(e, false);
for (const e of [...R.NORMAL_SHALLOW, ...R.NORMAL_DEEP, ...R.ELITE_SHALLOW, ...R.ELITE_DEEP, ...R.WHEEL_MAPS, ...R.PAWN_MAPS, ...R.ALTAR_MAPS, ...R.CAMP_MAPS]) add(e, true);

const bySmallOrBig = new Map<string, string>();
for (const [k, j] of jobs) { bySmallOrBig.set(R.mapKey(j.e.small), k); bySmallOrBig.set(R.mapKey(j.e.map), k); bySmallOrBig.set(R.mapKey(R.oneExit(j.e.map)), k); }

const ch = CHARACTERS.digger;
for (let seed = 1; seed <= 12; seed++) {
    const plan = R.buildRoute(seed);
    for (let way = 0; way < 2; way++) {
        let heroes: Hero[] = [{ ...ch.base }];
        for (let d = 0; d < plan.length && heroes.length; d++) {
            const opts = plan[d];
            const f0 = opts[Math.min(way, opts.length - 1)];
            for (const f of opts) {
                const j = jobs.get(bySmallOrBig.get(R.mapKey(f.map))!)!;
                j.base = { ...f, map: j.e.small };
                j.heroes.push(...heroes.slice(0, 6));
            }
            const j0 = jobs.get(bySmallOrBig.get(R.mapKey(f0.map))!)!;
            let outs: Hero[] = [];
            for (const hh of heroes) outs.push(...solveFromStart({ ...f0, map: j0.e.small }, hh, ch).pareto.map(o => o.hero));
            if (f0.rent) outs = outs.flatMap(hh => [...(hh.gold >= f0.rent! ? [{ ...hh, gold: hh.gold - f0.rent! }] : []), { ...hh, atk: hh.atk - 3 }, { ...hh, def: hh.def - 3 }]);
            heroes = paretoFilter(outs).sort((a, b) => b.hp - a.hp).slice(0, 40);
        }
    }
}

// ---------- 放大 + 第二个出口 ----------
const out: Record<string, string[]> = {};
let problems = 0;
for (const [k, j] of jobs) {
    const g = enlarge(j.e.small);
    exitIntoWall(g);
    let map = toMap(g);
    // 代表属性：去重后取生命最低、中间、最高几个
    const uniq = paretoFilter(j.heroes.length ? j.heroes : [{ ...ch.base }]).sort((a, b) => a.hp - b.hp);
    const reps = uniq.length <= 5 ? uniq : [0, 0.25, 0.5, 0.75, 1].map(p => uniq[Math.round(p * (uniq.length - 1))]);
    // 核对：走 '>' 的结果和原稿一样
    for (const hh of reps) {
        const a = solveFromStart(floorOf(j.e.small, j.base), hh, ch).pareto.map(o => o.hero);
        const b = solveFromStart(floorOf(map, j.base), hh, ch, 0).pareto.map(o => o.hero);
        if (!sameSet(a, b)) { console.log(`✗ ${j.e.name}：放大后打法变了`); problems++; break; }
    }
    if (j.two) {
        const [ex, ey] = idx(g, '>');
        const [sx, sy] = idx(g, '@');
        const blk0 = Math.min(...openNbrs(g, ex, ey).map(([a, b]) => blockers(g, a, b)));
        const feasible = reps.filter(hh => solveFromStart(floorOf(map, j.base), hh, ch, 0).solvable);
        const mid = feasible[Math.floor(feasible.length / 2)];
        let best: { x: number; y: number; score: number } | null = null;
        for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
            if (g[y][x] !== '#') continue;
            const nb = openNbrs(g, x, y);
            if (nb.length !== 1) continue;
            const [nx, ny] = nb[0];
            if (g[ny][nx] === '>' || Math.abs(nx - ex) + Math.abs(ny - ey) <= 1) continue;
            const dist = Math.abs(x - ex) + Math.abs(y - ey);
            if (dist < 6) continue;
            // 不能一进门就能走：第二个出口前面至少要处理掉一个怪物或门，而且和第一个出口差不多难走到
            const blk1 = blockers(g, nx, ny);
            if (blk1 < 1) continue;
            const g2 = g.map(r => [...r]); g2[y][x] = '<';
            const m2 = toMap(g2);
            if (!feasible.every(hh => solveFromStart(floorOf(m2, j.base), hh, ch, 1).solvable)) continue;
            let score = dist + (ring(x, y) ? 8 : 0) - (Math.abs(x - sx) + Math.abs(y - sy) < 4 ? 20 : 0) - Math.abs(blk1 - blk0) * 4;
            if (mid) {
                const r0 = solveFromStart(floorOf(m2, j.base), mid, ch, 0).best?.hero;
                const r1 = solveFromStart(floorOf(m2, j.base), mid, ch, 1).best?.hero;
                if (r0 && r1 && heroKey(r0) !== heroKey(r1)) score += 6;
            }
            if (!best || score > best.score) best = { x, y, score };
        }
        if (!best) { console.log(`✗ ${j.e.name}：找不到第二个出口的位置`); problems++; }
        else { g[best.y][best.x] = '<'; map = toMap(g); }
    }
    out[k] = map;
    console.log(`${j.two ? '两出口' : '一出口'} ${j.e.name}（代表属性 ${reps.length} 组）\n  ${map.join('\n  ')}`);
}

const body = Object.entries(out).map(([k, m]) => `    ${JSON.stringify(k)}: [\n${m.map(r => `        ${JSON.stringify(r)},`).join('\n')}\n    ],`).join('\n');
writeFileSync('src/core/bigmaps.ts', `/**
 * 由 tools/expand.ts 自动生成，不要手改（改 route.ts / levels.ts 里的小图原稿后重新跑 npm run expand）。
 * 键是小图原稿（各行用 / 连起来），值是放大后的 ${W}×${H} 地图。
 */
export const BIG_MAPS: Record<string, string[]> = {
${body}
};
`);
console.log(`${Object.keys(out).length} 张图${problems ? `，${problems} 个问题` : '，全部核对通过'}`);
if (problems) process.exit(1);
