/**
 * 浏览器试玩（横屏 16:9，Steam 试玩版的界面原型）：顶部状态栏、中间地图、右边信息栏。
 * 只负责显示和输入，所有规则都在 src/core 里。
 *
 * 操作：
 *   电脑（有鼠标）：鼠标悬停看战斗预览，点击直接出手 / 移动；方向键或 WASD 也能走
 *   手机（触屏）：轻点查看，再点一次或按"出手"确认
 */
import { Hero, MONSTERS } from '../src/core/config';
import { simulateCombat } from '../src/core/combat';
import { Run, RunSave } from '../src/core/game';
import { DEMO_POOLS, FloorChoice, buildFloors, pickChoices } from '../src/core/levels';
import { solveFloor, solveFromStart } from '../src/core/solver';

const $ = <T extends HTMLElement = HTMLElement>(id: string) => document.getElementById(id) as T;
const stage = $('stage');
const board = $('board');
const wrap = $('boardWrap');
const tip = $('tip');

const HOVER = window.matchMedia('(hover: hover) and (pointer: fine)').matches;
const SAVE_KEY = 'descent.demo.save.v1';
const LAST_KEY = 'descent.demo.lastChoices.v1';

interface SaveFile { choices: FloorChoice[]; run: RunSave }

let choices: FloorChoice[] = [];
let run!: Run;
let selected = -1;
let hovered = -1;
let lastHero: Hero | null = null;
/** 本层入场时的最优解，结算时对比 */
let floorBest: number | null = null;

// ---------- 存档（浏览器本地；Steam 版换成本地文件） ----------
function store(key: string, value: unknown) {
    try { localStorage.setItem(key, JSON.stringify(value)); } catch { /* 存不了也能玩 */ }
}
function loadKey<T>(key: string): T | null {
    try { const s = localStorage.getItem(key); return s ? JSON.parse(s) as T : null; } catch { return null; }
}
function clearSave() {
    try { localStorage.removeItem(SAVE_KEY); } catch { /* ignore */ }
}
function saveRun() {
    if (run.status === 'finished') { clearSave(); return; }
    store(SAVE_KEY, { choices, run: run.save() } satisfies SaveFile);
}

// ---------- 尺寸 ----------
function fit() {
    const h = stage.getBoundingClientRect().height;
    stage.style.setProperty('--u', `${h / 100}px`);
    if (!run) return;
    const r = wrap.getBoundingClientRect();
    const u = h / 100;
    const gap = u * 0.5;
    const pad = u * 0.8 * 2 + 2;
    const cell = Math.floor(Math.min((r.width - pad - gap * (run.w - 1)) / run.w, (r.height - pad - gap * (run.h - 1)) / run.h));
    board.style.gridTemplateColumns = `repeat(${run.w}, ${cell}px)`;
    board.style.gridTemplateRows = `repeat(${run.h}, ${cell}px)`;
    board.style.setProperty('--cell', `${cell}px`);
}
window.addEventListener('resize', () => { fit(); placeTip(); });

// ---------- 顶部状态栏 ----------
function stat(color: string, ico: string, val: number | string, bump: boolean, cls = '') {
    return `<div class="stat ${cls}"><div class="ico" style="background:${color}">${ico}</div><span class="val${bump ? ' bump' : ''}">${val}</span></div>`;
}

function renderHud() {
    const h = run.hero;
    const b = (k: keyof Hero) => !!lastHero && h[k] !== lastHero[k];
    const [num, name] = run.floor.name.split(' · ');
    const layout = DEMO_POOLS[run.floorIndex].layouts[choices[run.floorIndex].layout].name;
    $('hud').innerHTML = `
        <div class="title"><span class="name">${name ?? num}</span><span class="sub">${num} / 共 ${run.floors.length} 层 · ${layout}</span></div>
        ${stat('var(--hp)', '血', h.hp, b('hp'))}
        ${stat('var(--atk)', '攻', h.atk, b('atk'))}
        ${stat('var(--def)', '防', h.def, b('def'))}
        ${stat('var(--key)', '钥', h.keys, b('keys'))}
        ${stat('var(--gold)', '金', h.gold, b('gold'))}
        ${stat('#3a4a52', '步', run.steps, false, 'steps')}`;
    lastHero = { ...h };
}

// ---------- 地图 ----------
const SHORT: Record<string, string> = { moss: '苔', eel: '鳗', frog: '蛙', beetle: '甲', bat: '蝠', wraith: '魂', crab: '蟹', guardian: '守' };

function cellHtml(i: number): { cls: string; html: string } {
    const c = run.cells[i];
    if (i === run.pos) return { cls: 'hero', html: '<div class="heroToken">我</div>' };
    switch (c.kind) {
        case 'wall': return { cls: 'wall', html: '' };
        case 'floor': return { cls: 'floor', html: '' };
        case 'exit': return { cls: `exit${run.eliteAlive() ? ' locked' : ''}`, html: '<span class="glyph">▼</span><span class="sub">出口</span>' };
        case 'door':
            return c.door === 'bone'
                ? { cls: 'door', html: '<span class="glyph">门</span><span class="sub">骨钥</span>' }
                : { cls: 'door blood', html: `<span class="glyph">血门</span><span class="sub">-${run.floor.bloodCost}</span>` };
        case 'item':
            switch (c.id) {
                case 'redGem': return { cls: 'item', html: '<div class="gem red"></div>' };
                case 'blueGem': return { cls: 'item', html: '<div class="gem blue"></div>' };
                case 'smallPotion': return { cls: 'item', html: '<div class="potion"></div>' };
                case 'bigPotion': return { cls: 'item', html: '<div class="potion big"></div>' };
                case 'key': return { cls: 'item', html: '<span class="glyph" style="color:var(--key)">钥</span>' };
                case 'gold': return { cls: 'item', html: '<span class="glyph" style="color:var(--gold)">金</span>' };
            }
            break;
        case 'monster': {
            const m = MONSTERS[c.id];
            const r = simulateCombat(run.hero, m);
            const dead = !r.canWin || r.damage >= run.hero.hp;
            const sub = !r.canAttack ? '打不动' : !r.canWin ? '打不死' : `-${r.damage}`;
            return { cls: `monster${m.elite ? ' elite' : ''}`, html: `<span class="glyph">${SHORT[c.id]}</span><span class="sub ${dead ? 'bad' : 'ok'}">${sub}</span>` };
        }
    }
    return { cls: 'floor', html: '' };
}

function renderBoard() {
    if (board.children.length !== run.cells.length) {
        board.innerHTML = '';
        run.cells.forEach((_, i) => {
            const d = document.createElement('div');
            d.addEventListener('click', () => onTap(i));
            if (HOVER) d.addEventListener('mouseenter', () => {
                const k = run.cells[i].kind;
                hovered = k === 'wall' || k === 'floor' ? -1 : i;
                showInfo(hovered >= 0 ? hovered : selected);
            });
            board.appendChild(d);
        });
        fit();
    }
    run.cells.forEach((_, i) => {
        const el = board.children[i] as HTMLElement;
        const { cls, html } = cellHtml(i);
        el.className = `cell ${cls}${i === selected ? ' sel' : ''}`;
        el.innerHTML = html;
    });
}

if (HOVER) board.addEventListener('mouseleave', () => { hovered = -1; showInfo(selected); });

function floatText(i: number, text: string, color: string) {
    const el = board.children[i] as HTMLElement | undefined;
    if (!el || !text) return;
    const r = el.getBoundingClientRect();
    const s = stage.getBoundingClientRect();
    const f = document.createElement('div');
    f.className = 'float';
    f.style.color = color;
    f.style.left = `${r.left - s.left + r.width / 2}px`;
    f.style.top = `${r.top - s.top + r.height * 0.25}px`;
    f.textContent = text;
    stage.appendChild(f);
    setTimeout(() => f.remove(), 900);
}

// ---------- 战斗预览 ----------
interface Preview { lose: number; left: number; text: string; ok: boolean }

function preview(i: number): Preview | null {
    const c = run.cells[i];
    if (c.kind !== 'monster') return null;
    const r = simulateCombat(run.hero, MONSTERS[c.id]);
    if (!r.canAttack) return { lose: 0, left: run.hero.hp, text: '打不动', ok: false };
    if (!r.canWin) return { lose: 0, left: run.hero.hp, text: '打不死', ok: false };
    const left = run.hero.hp - r.damage;
    return { lose: r.damage, left, text: left <= 0 ? '会死' : `剩 ${left}`, ok: left > 0 };
}

let tipCell = -1;
function placeTip() {
    if (tipCell < 0) { tip.style.display = 'none'; return; }
    const p = preview(tipCell);
    const el = board.children[tipCell] as HTMLElement | undefined;
    if (!p || !el) { tip.style.display = 'none'; return; }
    tip.innerHTML = p.ok
        ? `<b>-${p.lose}</b> → <span class="after">${p.text}</span>`
        : `<span class="after dead">${p.text}</span>`;
    const r = el.getBoundingClientRect();
    const w = wrap.getBoundingClientRect();
    // 气泡放在不挡东西的一侧：优先上方，上方有东西（或在最上排）就放下方，都有就放侧面
    const x = tipCell % run.w;
    const y = Math.floor(tipCell / run.w);
    const busy = (cx: number, cy: number) => {
        if (cx < 0 || cy < 0 || cx >= run.w || cy >= run.h) return true;
        const k = run.cells[cy * run.w + cx].kind;
        return k !== 'wall' && k !== 'floor';
    };
    const cx = r.left - w.left + r.width / 2;
    const cy = r.top - w.top + r.height / 2;
    if (y > 0 && !busy(x, y - 1)) {
        tip.style.left = `${cx}px`; tip.style.top = `${r.top - w.top - 4}px`; tip.style.transform = 'translate(-50%, -100%)';
    } else if (y < run.h - 1 && !busy(x, y + 1)) {
        tip.style.left = `${cx}px`; tip.style.top = `${r.bottom - w.top + 4}px`; tip.style.transform = 'translate(-50%, 0)';
    } else if (x < run.w / 2) {
        tip.style.left = `${r.right - w.left + 4}px`; tip.style.top = `${cy}px`; tip.style.transform = 'translate(0, -50%)';
    } else {
        tip.style.left = `${r.left - w.left - 4}px`; tip.style.top = `${cy}px`; tip.style.transform = 'translate(-100%, -50%)';
    }
    tip.style.display = 'block';
}

// ---------- 右栏 ----------
const ACTION: Record<string, string> = { monster: '出手', door: '开门', item: '拿取', exit: '下楼' };

function showInfo(i: number) {
    const title = $('infoTitle');
    const lines = $('infoLines');
    const confirm = $('confirm');
    tipCell = -1;
    confirm.style.display = 'none';
    if (i < 0 || i === run.pos) {
        title.textContent = run.floor.name;
        lines.innerHTML = HOVER
            ? '鼠标移到格子上查看详情，点击执行。<br>点空地直接走过去。'
            : '轻点格子查看详情，再点一次或按下方按钮执行。<br>点空地直接走过去。';
        placeTip();
        return;
    }
    const info = run.info(i);
    title.textContent = info.title;
    const p = preview(i);
    let html = info.lines.filter(l => !l.startsWith('战斗预计') && !l.startsWith('⚠')).map(l => `<div>${l}</div>`).join('');
    if (p) {
        html += p.ok
            ? `<div class="preview"><span class="k">预计损失</span><span class="k">打完剩余</span><span class="v lose">-${p.lose}</span><span class="v left">${p.left}</span></div>`
            : `<div class="preview"><span class="k">结果</span><span class="k">当前生命</span><span class="v dead">${p.text}</span><span class="v">${run.hero.hp}</span></div>`;
        if (p.text === '打不动') html += '<div class="warn">攻击要高于它的防御才能破防</div>';
        if (p.text === '会死') html += '<div class="warn">这一仗打完你会死，先去变强或者绕开它</div>';
        tipCell = i;
    }
    lines.innerHTML = html;
    // 手机：选中后出现确认按钮
    const c = run.cells[i];
    if (!HOVER && i === selected && ACTION[c.kind]) {
        confirm.textContent = ACTION[c.kind];
        confirm.style.display = 'block';
        (confirm as HTMLButtonElement).disabled = !!p && !p.ok;
    }
    placeTip();
}

function setMsg(text: string, err = false) {
    const m = $('msg');
    m.textContent = text;
    m.className = err ? 'err' : '';
}

function checkDanger() {
    let stuck = false;
    if (run.status === 'playing') {
        stuck = !solveFloor({ w: run.w, h: run.h, cells: run.cells, pos: run.pos }, run.hero, run.floor, run.ch).solvable;
    }
    $('danger').style.display = stuck ? 'block' : 'none';
}

function render() {
    renderHud();
    renderBoard();
    ($('undo') as HTMLButtonElement).disabled = !run.canUndo();
    checkDanger();
    showInfo(HOVER && hovered >= 0 ? hovered : selected);
}

// ---------- 弹窗 ----------
type Btn = { label: string; primary?: boolean; danger?: boolean; on: () => void };
function modal(html: string, buttons: Btn[]) {
    const box = $('modalBox');
    box.innerHTML = html + '<div class="btns" id="mbtns"></div>';
    const w = $('mbtns');
    for (const b of buttons) {
        const el = document.createElement('button');
        el.textContent = b.label;
        if (b.primary) el.className = 'primary';
        if (b.danger) el.className = 'danger';
        if (buttons.length === 1) el.classList.add('wide');
        el.onclick = () => { $('modal').style.display = 'none'; b.on(); };
        w.appendChild(el);
    }
    $('modal').style.display = 'flex';
}
const modalOpen = () => $('modal').style.display === 'flex';

function showExit() {
    const s = run.exitSummary();
    const startHp = run.floorStartHero.hp;
    const diffHp = run.hero.hp - startHp;
    const rows = [
        `<div class="row"><span>本层生命变化</span><b>${diffHp >= 0 ? '+' : ''}${diffHp}</b></div>`,
        `<div class="row"><span>地图上剩下的血瓶 ×${s.leftoverPotions}</span><b>+${s.potionGold} 金币</b></div>`,
    ];
    if (floorBest !== null) {
        const d = floorBest - run.hero.hp;
        rows.push(`<p class="small">本层最优解出口时生命 ${floorBest}${d <= 0 ? '，你找到了最优解！' : `，你比最优解少 ${d}。`}</p>`);
    }
    const next = (sell: boolean) => {
        run.finishFloor(sell);
        saveRun();
        if (run.status === 'finished') showEnd();
        else { startFloor(); render(); }
    };
    const btns: Btn[] = s.keys > 0
        ? [
            { label: `卖掉 ${s.keys} 把骨钥（+${s.keyGold}）`, on: () => next(true) },
            { label: '留着骨钥，下楼', primary: true, on: () => next(false) },
        ]
        : [{ label: '下楼', primary: true, on: () => next(false) }];
    modal(`<h2>${run.floor.name} 完成</h2>${rows.join('')}`, btns);
}

function showEnd() {
    clearSave();
    render();
    modal(`<h2>试玩结束</h2>
        <p>你走完了试玩版的 ${run.floors.length} 层。每次新开一局，每层都会换一张地图。</p>
        <div class="row"><span>剩余生命</span><b>${run.hero.hp}</b></div>
        <div class="row"><span>攻击 / 防御</span><b>${run.hero.atk} / ${run.hero.def}</b></div>
        <div class="row"><span>金币</span><b>${run.hero.gold}</b></div>
        <div class="row"><span>总步数</span><b>${run.totalSteps}</b></div>
        <div class="row"><span>分数</span><b>${run.score()}</b></div>`,
        [{ label: '新开一局', primary: true, on: () => newRun() }]);
}

// ---------- 输入 ----------
function afterAct(r: { ok: boolean; msg: string }, at: number, before: Hero) {
    if (r.msg) setMsg(r.msg, !r.ok);
    if (r.ok) {
        const lost = before.hp - run.hero.hp;
        if (lost > 0) floatText(at, `-${lost}`, '#ff6b81');
        else if (run.hero.hp > before.hp) floatText(at, `+${run.hero.hp - before.hp}`, '#7dffb0');
        else if (run.hero.atk > before.atk) floatText(at, `攻+${run.hero.atk - before.atk}`, '#ffb07a');
        else if (run.hero.def > before.def) floatText(at, `防+${run.hero.def - before.def}`, '#8ac8ff');
    }
    selected = -1;
    render();
    saveRun();
    if (run.status === 'floorDone') setTimeout(showExit, 200);
}

function act(i: number) {
    const before = { ...run.hero };
    const r = run.tapCell(i);
    if (!r.ok && !r.msg) r.msg = '走不过去';
    afterAct(r, i, before);
}

function onTap(i: number) {
    if (run.status !== 'playing' || modalOpen()) return;
    const c = run.cells[i];
    if (c.kind === 'wall' || i === run.pos) { selected = -1; renderBoard(); showInfo(-1); return; }
    if (c.kind === 'floor' || HOVER || selected === i) { act(i); return; }
    // 手机：第一次轻点只查看
    selected = i;
    renderBoard();
    showInfo(i);
}

$('confirm').onclick = () => { if (selected >= 0) act(selected); };

const DIRS: Record<string, [number, number]> = {
    ArrowUp: [0, -1], ArrowDown: [0, 1], ArrowLeft: [-1, 0], ArrowRight: [1, 0],
    w: [0, -1], s: [0, 1], a: [-1, 0], d: [1, 0],
};

window.addEventListener('keydown', e => {
    if (modalOpen()) {
        if (e.key === 'Enter' || e.key === ' ') (document.querySelector('#mbtns button.primary') as HTMLButtonElement | null)?.click();
        return;
    }
    const key = e.key.length === 1 ? e.key.toLowerCase() : e.key;
    const d = DIRS[key];
    if (d) {
        e.preventDefault();
        const x = run.pos % run.w + d[0];
        const y = Math.floor(run.pos / run.w) + d[1];
        const before = { ...run.hero };
        const r = run.move(d[0], d[1]);
        hovered = -1;
        afterAct(r, y * run.w + x, before);
    } else if (key === 'z' || key === 'Backspace') undo();
    else if (key === 'r') restart();
    else if (key === 'Escape') { selected = -1; renderBoard(); showInfo(-1); }
});

function undo() {
    if (run.undo()) { setMsg('已撤回一步'); selected = -1; render(); saveRun(); }
}

function restart() {
    run.restartFloor();
    startFloor();
    render();
    saveRun();
    setMsg('已重开本层（地图不变）');
}

// ---------- 开局 / 继续 ----------
function startFloor() {
    selected = -1;
    hovered = -1;
    board.innerHTML = '';
    floorBest = solveFromStart(run.floor, run.floorStartHero, run.ch).best?.hero.hp ?? null;
    setMsg(run.floor.hint ?? '');
}

function begin(c: FloorChoice[], save?: RunSave) {
    choices = c;
    const floors = buildFloors(choices);
    run = save ? Run.load(floors, save) : new Run(floors);
    lastHero = null;
    startFloor();
    render();
    saveRun();
    if (run.status === 'floorDone') showExit();
}

function newRun() {
    const last = loadKey<FloorChoice[]>(LAST_KEY) ?? undefined;
    const seed = Math.floor(Math.random() * 2 ** 31);
    const c = pickChoices(seed, DEMO_POOLS, last);
    store(LAST_KEY, c);
    begin(c);
}

$('undo').onclick = undo;
$('restart').onclick = restart;
$('newRun').onclick = () => modal('<h2>新开一局？</h2><p>这一局的进度会丢失。新的一局每层都会换一张地图。</p>', [
    { label: '取消', on: () => {} },
    { label: '新开一局', danger: true, on: newRun },
]);
$('keysHint').textContent = HOVER
    ? '方向键 / WASD 移动 · Z 撤回 · R 重开本层'
    : '轻点查看，再点一次出手';

fit();
const saved = loadKey<SaveFile>(SAVE_KEY);
if (saved?.choices?.length === DEMO_POOLS.length && saved.run) {
    begin(saved.choices, saved.run);
    modal(`<h2>坠井者 · 试玩版</h2><p>你有一局还没打完（${run.floor.name}）。</p>`, [
        { label: '新开一局', on: newRun },
        { label: '继续', primary: true, on: () => {} },
    ]);
} else {
    newRun();
    modal(`<h2>坠井者 · 试玩版</h2>
        <p>你掉进了一口没有底的井。每层走到出口就能往下走，一共 3 层。</p>
        <p>怪物格子上的数字是打它要掉的血。奖励都在怪物身后，值不值得打，自己算。</p>
        <p class="small">${HOVER ? '鼠标悬停查看战斗预览，点击出手。' : '轻点查看战斗预览，再点一次出手。'}每次新开一局都会换地图。</p>`,
        [{ label: '开始', primary: true, on: () => {} }]);
}
