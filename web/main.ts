/**
 * 浏览器试玩（横屏 16:9）：左边属性、中间地图、右边信息和按钮。
 * 只负责显示和输入，所有规则都在 src/core 里。
 */
import { Hero, MONSTERS } from '../src/core/config';
import { simulateCombat } from '../src/core/combat';
import { Run } from '../src/core/game';
import { M1_FLOORS } from '../src/core/levels';
import { solveFloor, solveFromStart } from '../src/core/solver';

const $ = <T extends HTMLElement = HTMLElement>(id: string) => document.getElementById(id) as T;
const stage = $('stage');
const board = $('board');
const left = $('left');

let run = new Run(M1_FLOORS);
let selected = -1;
let lastHero: Hero = { ...run.hero };
/** 每层入场时的最优解，用来在结算时对比 */
let floorBest: number | null = null;

function fit() {
    const h = stage.getBoundingClientRect().height;
    stage.style.setProperty('--u', `${h / 100}px`);
}
window.addEventListener('resize', fit);

function startFloor() {
    selected = -1;
    floorBest = solveFromStart(run.floor, run.hero, run.ch).best?.hero.hp ?? null;
    setMsg(run.floor.hint ?? '');
    showInfo(-1);
}

// ---------- 左栏 ----------
function stat(cls: string, color: string, ico: string, lbl: string, val: number | string, bump: boolean) {
    return `<div class="stat ${cls}"><div class="ico" style="background:${color}">${ico}</div><span class="lbl">${lbl}</span><span class="val${bump ? ' bump' : ''}">${val}</span></div>`;
}

function renderLeft() {
    const h = run.hero;
    const b = (k: keyof Hero) => h[k] !== lastHero[k];
    left.innerHTML = `
        <div id="floorName">${run.floor.name.split(' · ')[1] ?? run.floor.name}</div>
        <div id="floorSub">${run.floor.name.split(' · ')[0]} / 共 ${run.floors.length} 层<br>角色：${run.ch.name}</div>
        <div class="sep"></div>
        ${stat('hp', 'var(--hp)', '血', '生命', h.hp, b('hp'))}
        ${stat('atk', 'var(--atk)', '攻', '攻击', h.atk, b('atk'))}
        ${stat('def', 'var(--def)', '防', '防御', h.def, b('def'))}
        <div class="sep"></div>
        ${stat('key', 'var(--key)', '钥', '骨钥', h.keys, b('keys'))}
        ${stat('gold', 'var(--gold)', '金', '金币', h.gold, b('gold'))}
        <div class="sep"></div>
        <div class="small">本层步数 ${run.steps}<br>剩余怪物 ${run.monstersLeft()}${run.eliteAlive() ? '<br><span style="color:var(--hp)">精英守卫封住了出口</span>' : ''}</div>
        <div class="grow"></div>
        <div class="small">M1 试玩版：手工 3 层，没有刻印和随机生成。</div>`;
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
    board.style.gridTemplateColumns = `repeat(${run.w}, 1fr)`;
    board.style.gridTemplateRows = `repeat(${run.h}, 1fr)`;
    if (board.children.length !== run.cells.length) {
        board.innerHTML = '';
        run.cells.forEach((_, i) => {
            const d = document.createElement('div');
            d.addEventListener('click', () => onTap(i));
            d.addEventListener('mouseenter', () => { if (selected < 0) showInfo(i); });
            board.appendChild(d);
        });
    }
    run.cells.forEach((_, i) => {
        const el = board.children[i] as HTMLElement;
        const { cls, html } = cellHtml(i);
        el.className = `cell ${cls}${i === selected ? ' sel' : ''}`;
        el.innerHTML = html;
    });
}

function floatText(i: number, text: string, color: string) {
    const el = board.children[i] as HTMLElement | undefined;
    if (!el || !text) return;
    const r = el.getBoundingClientRect();
    const s = stage.getBoundingClientRect();
    const f = document.createElement('div');
    f.className = 'float';
    f.style.color = color;
    f.style.left = `${r.left - s.left + r.width / 2 - 20}px`;
    f.style.top = `${r.top - s.top + r.height * 0.4}px`;
    f.textContent = text;
    stage.appendChild(f);
    setTimeout(() => f.remove(), 900);
}

// ---------- 右栏 ----------
function showInfo(i: number) {
    const title = $('infoTitle');
    const lines = $('infoLines');
    if (i < 0) {
        title.textContent = run.floor.name;
        lines.innerHTML = '点一下格子查看详情，再点一次执行。<br>点空地直接走过去。';
        return;
    }
    const info = run.info(i);
    title.textContent = info.title;
    lines.innerHTML = info.lines.map(l => {
        if (l.startsWith('⚠') || l.includes('会死')) return `<div class="warn">${l}</div>`;
        if (l.startsWith('战斗预计')) return `<div class="big">${l}</div>`;
        return `<div>${l}</div>`;
    }).join('');
}

function setMsg(text: string, err = false) {
    const m = $('msg');
    m.textContent = text;
    m.className = err ? 'err' : '';
}

function checkDanger() {
    let stuck = false;
    if (run.status === 'playing') {
        const r = solveFloor({ w: run.w, h: run.h, cells: run.cells, pos: run.pos }, run.hero, run.floor, run.ch);
        stuck = !r.solvable;
    }
    $('danger').style.display = stuck ? 'block' : 'none';
}

function render() {
    renderLeft();
    renderBoard();
    ($('undo') as HTMLButtonElement).disabled = !run.canUndo();
    checkDanger();
}

// ---------- 弹窗 ----------
function modal(html: string, buttons: { label: string; primary?: boolean; on: () => void }[]) {
    const box = $('modalBox');
    box.innerHTML = html + '<div class="btns" id="mbtns"></div>';
    const wrap = $('mbtns');
    for (const b of buttons) {
        const el = document.createElement('button');
        el.textContent = b.label;
        if (b.primary) el.className = 'primary';
        if (buttons.length === 1) el.classList.add('wide');
        el.onclick = () => { $('modal').style.display = 'none'; b.on(); };
        wrap.appendChild(el);
    }
    $('modal').style.display = 'flex';
}

function showExit() {
    const s = run.exitSummary();
    const startHp = run.floorStartHero.hp;
    const rows = [
        `<div class="row"><span>本层损失生命</span><b>${startHp - run.hero.hp > 0 ? startHp - run.hero.hp : `+${run.hero.hp - startHp}`}</b></div>`,
        `<div class="row"><span>清光全部怪物</span><b>${s.cleared ? `+${s.clearBonus} 金币` : '否'}</b></div>`,
        `<div class="row"><span>地图上剩下的血瓶 ×${s.leftoverPotions}</span><b>+${s.potionGold} 金币</b></div>`,
    ];
    if (floorBest !== null) {
        const diff = floorBest - run.hero.hp;
        rows.push(`<p class="small">本层最优解出口时生命 ${floorBest}${diff <= 0 ? '，你找到了最优解！' : `，你比最优解少 ${diff}。`}</p>`);
    }
    const next = () => {
        run.finishFloor(sellKeys);
        if (run.status === 'finished') showEnd();
        else { startFloor(); render(); }
    };
    let sellKeys = false;
    const btns = s.keys > 0
        ? [
            { label: `卖掉 ${s.keys} 把骨钥（+${s.keyGold}）`, on: () => { sellKeys = true; next(); } },
            { label: '留着骨钥，下楼', primary: true, on: () => { sellKeys = false; next(); } },
        ]
        : [{ label: '下楼', primary: true, on: next }];
    modal(`<h2>${run.floor.name} 完成</h2>${rows.join('')}`, btns);
}

function showEnd() {
    render();
    modal(`<h2>试玩结束</h2>
        <p>你走完了 M1 的 ${run.floors.length} 层。</p>
        <div class="row"><span>剩余生命</span><b>${run.hero.hp}</b></div>
        <div class="row"><span>攻击 / 防御</span><b>${run.hero.atk} / ${run.hero.def}</b></div>
        <div class="row"><span>金币</span><b>${run.hero.gold}</b></div>
        <div class="row"><span>总步数</span><b>${run.totalSteps}</b></div>
        <div class="row"><span>分数</span><b>${run.score()}</b></div>
        <p class="small">觉得哪里好玩、哪里别扭，都可以记下来反馈。</p>`,
        [{ label: '再来一局', primary: true, on: newRun }]);
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
    if (run.status === 'floorDone') setTimeout(showExit, 200);
}

function onTap(i: number) {
    if (run.status !== 'playing' || $('modal').style.display === 'flex') return;
    const c = run.cells[i];
    if (c.kind === 'wall' || i === run.pos) { selected = -1; showInfo(i === run.pos ? -1 : i); renderBoard(); return; }
    // 空地直接走；其他格子第一次点看详情，第二次点执行
    if (c.kind !== 'floor' && selected !== i) {
        selected = i;
        showInfo(i);
        renderBoard();
        return;
    }
    const before = { ...run.hero };
    const r = run.tapCell(i);
    if (!r.ok && !r.msg) setMsg('走不过去', true);
    afterAct(r, i, before);
}

const DIRS: Record<string, [number, number]> = {
    ArrowUp: [0, -1], ArrowDown: [0, 1], ArrowLeft: [-1, 0], ArrowRight: [1, 0],
    w: [0, -1], s: [0, 1], a: [-1, 0], d: [1, 0],
};

window.addEventListener('keydown', e => {
    if ($('modal').style.display === 'flex') {
        if (e.key === 'Enter' || e.key === ' ') (document.querySelector('#mbtns button.primary') as HTMLButtonElement | null)?.click();
        return;
    }
    const key = e.key.length === 1 ? e.key.toLowerCase() : e.key;
    const d = DIRS[key];
    if (d) {
        e.preventDefault();
        const x = run.pos % run.w + d[0];
        const y = Math.floor(run.pos / run.w) + d[1];
        const target = y * run.w + x;
        const before = { ...run.hero };
        const r = run.move(d[0], d[1]);
        afterAct(r, target, before);
        if (x >= 0 && y >= 0 && x < run.w && y < run.h) showInfo(target);
    } else if (key === 'z' || key === 'Backspace') undo();
    else if (key === 'r') restart();
});

function undo() {
    if (run.undo()) { setMsg('已撤回一步'); selected = -1; render(); }
}

function restart() {
    run.restartFloor();
    startFloor();
    render();
    setMsg('已重开本层');
}

function newRun() {
    run = new Run(M1_FLOORS);
    lastHero = { ...run.hero };
    startFloor();
    render();
}

$('undo').onclick = undo;
$('restart').onclick = restart;
$('newRun').onclick = () => modal('<h2>重新开始？</h2><p>这一局的进度会丢失，从第 1 层重新开始。</p>', [
    { label: '取消', on: () => {} },
    { label: '重新开始', primary: true, on: newRun },
]);

fit();
startFloor();
render();
