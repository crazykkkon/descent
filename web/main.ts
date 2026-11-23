/**
 * 浏览器试玩（横屏 16:9，Steam 试玩版的界面原型）：顶部状态栏、中间地图、右边信息栏。
 * 只负责显示和输入，所有规则都在 src/core 里。
 *
 * 操作：
 *   电脑（有鼠标）：鼠标悬停看战斗预览，点击直接出手 / 移动；方向键或 WASD 也能走
 *   手机（触屏）：轻点查看，再点一次或按"出手"确认
 *   没有撤回、没有重开本层：走过、打过就不能退回；死了就从第 1 层重新开始，地图随机换
 */
import { Hero, MONSTERS, WEAPONS, WeaponId } from '../src/core/config';
import { effectiveStats, simulateCombat } from '../src/core/combat';
import { Run, RunSave } from '../src/core/game';
import { DEMO_POOLS, FloorChoice, buildFloors, pickChoices } from '../src/core/levels';
import { solveFloor, solveFromStart } from '../src/core/solver';
import { contractText, depositFor, keepVersion } from '../src/core/contract';
import { SLOTS, Sym, holdHint, machineOdds, payout } from '../src/core/slot';
import { RENT_STAT_COST } from '../src/core/game';

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
let floorBest: Hero | null = null;
/** 契约层：守约 / 不管契约 两种走法能带出的最高生命 */
let floorContract: { keep: number | null; any: number | null } | null = null;

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
    requestAnimationFrame(() => placeHero(false));
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
        ${stat('var(--atk)', '攻', effectiveStats(h).atk, b('atk') || b('weapon'))}
        ${stat('var(--def)', '防', effectiveStats(h).def, b('def') || b('weapon'))}
        <div class="weaponChip${b('weapon') ? ' bump' : ''}" title="${h.weapon ? WEAPONS[h.weapon].desc : '还没有武器'}">⚔ ${h.weapon ? WEAPONS[h.weapon].name : '无武器'}</div>
        ${stat('var(--key)', '钥', h.keys, b('keys'))}
        ${stat('var(--gold)', '金', h.gold, b('gold'))}
        ${stat('#3a4a52', '步', run.steps, false, 'steps')}`;
    lastHero = { ...h };
}

// ---------- 地图 ----------
const SHORT: Record<string, string> = { moss: '苔', eel: '鳗', frog: '蛙', beetle: '甲', bat: '蝠', wraith: '魂', crab: '蟹', guardian: '守', rat: '鼠', slug: '蝓', priest: '祭', gatekeeper: '门' };

function cellHtml(i: number): { cls: string; html: string } {
    const c = run.cells[i];
    switch (c.kind) {
        case 'wall': return { cls: 'wall', html: '' };
        case 'stall': return { cls: 'slot', html: '<span class="glyph">摊</span><span class="sub">补给</span>' };
        case 'slot': return { cls: `slot ${c.id}`, html: `<span class="glyph">轮</span><span class="sub">${SLOTS[c.id].name}</span>` };
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
            const m = run.monsterAt(i);
            const r = simulateCombat(run.hero, m);
            const dead = !r.canWin || r.damage >= run.hero.hp;
            const sub = !r.canAttack ? '打不动' : !r.canWin ? '打不死' : `-${r.damage}`;
            return { cls: `monster${m.elite ? ' elite' : ''}`, html: `<span class="glyph">${SHORT[c.id]}</span><span class="sub ${dead ? 'bad' : 'ok'}">${sub}</span>` };
        }
    }
    return { cls: 'floor', html: '' };
}

/** 主角棋子：独立于格子，移动时用 CSS 过渡一格一格走 */
const heroEl = document.createElement('div');
heroEl.id = 'hero';
heroEl.innerHTML = '<div class="heroToken">我</div>';

function placeHero(animate: boolean) {
    const el = board.children[run.pos] as HTMLElement | undefined;
    if (!el) return;
    heroEl.style.transition = animate ? `transform ${STEP_MS}ms linear` : 'none';
    heroEl.style.width = `${el.offsetWidth}px`;
    heroEl.style.height = `${el.offsetHeight}px`;
    heroEl.style.transform = `translate(${el.offsetLeft}px, ${el.offsetTop}px)`;
}

/** 打怪、开门、捡东西时朝目标"撞"一下 */
function bump(target: number) {
    const from = board.children[run.pos] as HTMLElement;
    const to = board.children[target] as HTMLElement;
    const dx = (to.offsetLeft - from.offsetLeft) * 0.35;
    const dy = (to.offsetTop - from.offsetTop) * 0.35;
    heroEl.style.transition = `transform ${STEP_MS / 2}ms ease-out`;
    heroEl.style.transform = `translate(${from.offsetLeft + dx}px, ${from.offsetTop + dy}px)`;
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
        board.appendChild(heroEl);
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
/** ok=false 表示这一仗打完会死（打不动、打不死、血不够），但玩家仍然可以硬上 */
interface Preview { lose: number; left: number; text: string; ok: boolean; gold: number }

function preview(i: number): Preview | null {
    const c = run.cells[i];
    if (c.kind !== 'monster') return null;
    const m = run.monsterAt(i);
    const r = simulateCombat(run.hero, m);
    if (!r.canAttack) return { lose: 0, left: 0, text: '打不动', ok: false, gold: m.gold };
    if (!r.canWin) return { lose: 0, left: 0, text: '打不死', ok: false, gold: m.gold };
    const left = run.hero.hp - r.damage;
    return { lose: r.damage, left, text: left <= 0 ? '会死' : `剩 ${left}`, ok: left > 0, gold: m.gold };
}

function isFatal(i: number): boolean {
    const p = preview(i);
    return !!p && !p.ok;
}

let tipCell = -1;
function placeTip() {
    if (tipCell < 0) { tip.style.display = 'none'; return; }
    const p = preview(tipCell);
    const el = board.children[tipCell] as HTMLElement | undefined;
    if (!p || !el) { tip.style.display = 'none'; return; }
    tip.innerHTML = p.ok
        ? `<b>-${p.lose}</b> → <span class="after">${p.text}</span> <span class="goldTip">+${p.gold}金</span>`
        : `<span class="after dead">${p.text === '会死' ? '会死' : `${p.text}·硬打会死`}</span>`;
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
const ACTION: Record<string, string> = { monster: '出手', door: '开门', item: '拿取', exit: '下楼', slot: '去转一把' };

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
    let html = info.lines.filter(l => !l.startsWith('战斗预计') && !l.startsWith('⚠') && !l.startsWith('打败后掉落')).map(l => `<div>${l}</div>`).join('');
    if (p) {
        html += p.ok
            ? `<div class="preview"><span class="k">预计损失</span><span class="k">打完剩余</span><span class="v lose">-${p.lose}</span><span class="v left">${p.left}</span><span class="k gold">掉落 ${p.gold} 金币</span></div>`
            : `<div class="preview"><span class="k">结果</span><span class="k">当前生命</span><span class="v dead">${p.text}</span><span class="v">${run.hero.hp}</span><span class="k gold">掉落 ${p.gold} 金币</span></div>`;
        if (p.text === '打不动') html += '<div class="warn">攻击要高于它的防御才能破防。硬打的话你会死。</div>';
        if (p.text === '打不死') html += '<div class="warn">它回血比你打得快。硬打的话你会死。</div>';
        if (p.text === '会死') html += '<div class="warn">这一仗打完你会死。可以硬上，但这一局就结束了。</div>';
        tipCell = i;
    }
    if (run.cells[i].kind === 'exit') html += intelHtml() + contractCardHtml();
    const ci = run.cells[i];
    if (ci.kind === 'item' && (ci.id === 'smallPotion' || ci.id === 'bigPotion') && run.contractActive()) {
        html += `<div class="warn">喝下会毁约：押下的 ${run.contract!.def.deposit} 生命不退</div>`;
    }
    lines.innerHTML = html;
    // 手机：选中后出现确认按钮
    const c = run.cells[i];
    if (!HOVER && i === selected && ACTION[c.kind]) {
        const fatal = !!p && !p.ok;
        confirm.textContent = fatal ? '硬打（会死）' : ACTION[c.kind];
        confirm.className = fatal ? 'danger' : 'primary';
        confirm.style.display = 'block';
    }
    placeTip();
}

/** 楼梯口情报（下一层的一条情报） */
function intelHtml(): string {
    const it = run.nextFloorIntel();
    if (!it) return '<div class="intel"><b>这是试玩版的最后一层</b></div>';
    return `<div class="intel"><div class="intelHead">📜 下一层情报</div><b>${it.headline}</b>${it.lines.map(l => `<div>${l}</div>`).join('')}</div>`;
}

function setMsg(text: string, err = false) {
    const m = $('msg');
    m.textContent = text;
    m.className = err ? 'err' : '';
}

function renderContract() {
    const el = $('contractBox');
    const ct = run.contract;
    if (!ct || ct.floorIndex !== run.floorIndex) { el.style.display = 'none'; return; }
    el.className = ct.broken ? 'broken' : '';
    el.innerHTML = ct.broken
        ? `🪝 契约已毁：押下的 ${ct.def.deposit} 生命归井了，血瓶随便喝。`
        : `🪝 契约生效中：本层一瓶血瓶都不喝，走到出口退还 ${ct.def.refund} 生命${ct.def.gold ? ` + ${ct.def.gold} 金币` : ''}。`;
    el.style.display = 'block';
}

function checkDanger() {
    const el = $('danger');
    if (run.status !== 'playing') { el.style.display = 'none'; return; }
    const c = run.floorCheck();
    if (c.canReachExit) { el.style.display = 'none'; return; }
    el.innerHTML = '⚠ 现在已经活着走不到出口了，<b>这一局走不下去了</b>。只能新开一局（从第 1 层重来，地图会换）。';
    el.style.display = 'block';
}

function render() {
    renderHud();
    renderBoard();
    renderContract();
    checkDanger();
    showInfo(HOVER && hovered >= 0 ? hovered : selected);
}

// ---------- 弹窗 ----------
type Btn = { label: string; primary?: boolean; danger?: boolean; on: () => void };
function modal(html: string, buttons: Btn[]) {
    const box = $('modalBox');
    box.classList.remove('slotBox');
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
    const rows: string[] = [];
    if (s.contract) {
        rows.push(s.contract.kept
            ? `<div class="row contractOk"><span>🪝 契约守住了</span><b>+${s.contract.def.refund} 生命${s.contract.def.gold ? `，+${s.contract.def.gold} 金币` : ''}</b></div>`
            : `<div class="row contractBad"><span>🪝 契约已毁</span><b>押下的 ${s.contract.def.deposit} 生命归井</b></div>`);
    }
    rows.push(
        `<div class="row"><span>本层生命变化（不含契约退还）</span><b>${diffHp >= 0 ? '+' : ''}${diffHp}</b></div>`,
        `<div class="row"><span>地图上剩下的血瓶 ×${s.leftoverPotions}</span><b>+${s.potionGold} 金币</b></div>`,
    );
    // 这一层换到了什么
    const st = run.floorStartHero;
    const gains = [
        ['攻击', run.hero.atk - st.atk], ['防御', run.hero.def - st.def], ['骨钥', run.hero.keys - st.keys],
    ].filter(([, d]) => d !== 0).map(([k, d]) => `${k} ${(d as number) > 0 ? '+' : ''}${d}`);
    rows.push(`<div class="row"><span>本层换到的属性</span><b>${gains.length ? gains.join('，') : '没有'}</b></div>`);
    if (floorContract) {
        // 契约层：分别给出守约和不守约能带出的最高生命，让玩家看清自己这一步的账
        const k = floorContract.keep;
        const b = floorContract.any;
        const mine = s.contract?.kept ? run.hero.hp + s.contract.def.refund : run.hero.hp;
        rows.push(`<p class="small">这一层，守约的走法最多能带出 ${k ?? '—'} 生命（含退还）；不管契约的走法最多 ${b ?? '—'}。你带出 ${mine}。</p>`);
    } else if (floorBest) {
        // 不说"最优解"：生命最多的走法不一定最好，宝石在后面几层还会继续起作用
        const b = floorBest;
        const same = b.atk === run.hero.atk && b.def === run.hero.def;
        const route = same ? '' : `（那条走法离开时 攻 ${b.atk} / 防 ${b.def}）`;
        const mine = `你以 ${run.hero.hp} 血离开，攻 ${run.hero.atk} / 防 ${run.hero.def}`;
        rows.push(`<p class="small">本层能带出的最高生命是 ${b.hp}${route}。${mine}${gains.length && run.hero.hp < b.hp ? `：你用 ${b.hp - run.hero.hp} 血换到了 ${gains.join('、')}` : ''}。</p>`);
    }
    const next = (sell: boolean) => {
        if (run.rentDue()) { showRent(() => next(sell)); return; }
        recordContract(`带着 ${s.contract?.kept ? run.hero.hp + s.contract.def.refund : run.hero.hp} 血离开`);
        run.finishFloor(sell, pendingSign);
        pendingSign = false;
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

// ---------- 契约记录（跨局保存，方便试玩反馈） ----------
const HISTORY_KEY = 'descent.demo.contracts.v1';
interface ContractRecord { map: string; choice: '拒签' | '守约' | '毁约'; result: string }

/** 在契约层结束（走出去或者倒下）时记一笔 */
function recordContract(result: string) {
    if (!run.floor.contract) return;
    const ct = run.contract && run.contract.floorIndex === run.floorIndex ? run.contract : null;
    const choice: ContractRecord['choice'] = !ct ? '拒签' : ct.broken ? '毁约' : '守约';
    const map = DEMO_POOLS[run.floorIndex].layouts[choices[run.floorIndex].layout].name;
    const list = loadKey<ContractRecord[]>(HISTORY_KEY) ?? [];
    list.push({ map, choice, result });
    store(HISTORY_KEY, list.slice(-10));
}

function historyHtml(): string {
    const list = loadKey<ContractRecord[]>(HISTORY_KEY) ?? [];
    if (!list.length) return '';
    const rows = list.slice(-6).map((r, i, a) => `<div class="row"><span>${list.length - a.length + i + 1}. 第 2 层「${r.map}」</span><b>${r.choice} · ${r.result}</b></div>`).join('');
    return `<p class="small">你的契约记录（最近几局，截图发给我们就是最好的反馈）：</p>${rows}`;
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
        <div class="row"><span>分数</span><b>${run.score()}</b></div>${historyHtml()}`,
        [{ label: '新开一局', primary: true, on: () => newRun() }]);
}

// ---------- 输入 ----------
const STEP_MS = 130;
const sleep = (ms: number) => new Promise(r => setTimeout(r, ms));
/** 正在走路时不接受新的操作 */
let busy = false;

function popText(at: number, before: Hero) {
    const lost = before.hp - run.hero.hp;
    if (lost > 0) floatText(at, `-${lost}`, '#ff6b81');
    else if (run.hero.hp > before.hp) floatText(at, `+${run.hero.hp - before.hp}`, '#7dffb0');
    else if (run.hero.atk > before.atk) floatText(at, `攻+${run.hero.atk - before.atk}`, '#ffb07a');
    else if (run.hero.def > before.def) floatText(at, `防+${run.hero.def - before.def}`, '#8ac8ff');
    else if (run.hero.keys > before.keys) floatText(at, '骨钥+1', '#e8d38a');
}

/** 沿路线一格一格走；最后一格是怪物、门或道具时，走到旁边再交互。走过就不能撤回。 */
async function walk(path: number[], confirmedExit = false, confirmedFatal = false, confirmedBreak = false) {
    if (busy || !path.length) return;
    let askExit = false;
    let askFatal = -1;
    let askBreak = -1;
    busy = true;
    document.body.dataset.walking = '1';
    selected = -1;
    tipCell = -1;
    placeTip();
    try {
        for (const cell of path) {
            const c = run.cells[cell];
            const before = { ...run.hero };
            // 下楼前先停在楼梯口，看一眼下一层的情报再决定
            if (c.kind === 'exit' && !confirmedExit && run.nextFloorIntel() && !run.eliteAlive()) { askExit = true; break; }
            if (c.kind === 'floor' || c.kind === 'exit') {
                const r = run.step(cell);
                if (!r.ok) { setMsg(r.msg || '走不过去', true); break; }
                placeHero(true);
                renderHud();
                await sleep(STEP_MS);
                continue;
            }
            // 打会死的仗：走到旁边先确认
            if (c.kind === 'monster' && isFatal(cell) && !confirmedFatal) { askFatal = cell; break; }
            // 签了"不喝血瓶"的契约：喝之前先确认
            if (c.kind === 'item' && (c.id === 'smallPotion' || c.id === 'bigPotion') && run.contractActive() && !confirmedBreak) { askBreak = cell; break; }
            // 交互：先撞一下，再结算
            const r0 = run.step(cell);
            if (!r0.ok) { setMsg(r0.msg, true); break; }
            bump(cell);
            await sleep(STEP_MS / 2);
            setMsg(r0.msg, run.status === 'dead');
            if (run.status === 'dead') {
                heroEl.classList.add('dead');
                floatText(cell, '倒下', '#ff4d6a');
                renderHud();
                placeHero(true);
                await sleep(STEP_MS * 3);
                break;
            }
            popText(cell, before);
            if (run.hero.gold > before.gold && c.kind === 'monster') setTimeout(() => floatText(cell, `+${run.hero.gold - before.gold}金`, '#f0c94a'), 250);
            renderBoard();
            renderHud();
            placeHero(true);
            await sleep(STEP_MS);
        }
    } finally {
        busy = false;
        document.body.dataset.walking = '';
        hovered = -1;
        render();
        saveRun();
        if (run.status === 'floorDone') setTimeout(showExit, 150);
        if (run.status === 'dead') setTimeout(showDeath, 150);
        if (askExit) confirmStairs();
        if (askFatal >= 0) confirmFatal(askFatal);
        if (askBreak >= 0) confirmBreak(askBreak);
        if (run.pendingWeapons && run.status === 'playing') showWeaponChoice();
        else if (pendingSlot >= 0 && run.status === 'playing') { const i = pendingSlot; pendingSlot = -1; openSlot(i); }
        pendingSlot = -1;
    }
}

function confirmFatal(cell: number) {
    const c = run.cells[cell];
    if (c.kind !== 'monster') return;
    const m = MONSTERS[c.id];
    const p = preview(cell)!;
    const why = p.text === '打不动' ? `你的攻击 ${run.hero.atk} 破不了它的防御 ${m.def}`
        : p.text === '打不死' ? '它回血比你打得快'
        : `这一仗要损失 ${p.lose} 生命，你只有 ${run.hero.hp}`;
    modal(`<h2>硬打${m.name}？</h2><p>${why}。打下去你会死，这一局就结束了。</p>`, [
        { label: '算了', primary: true, on: () => setMsg('没有出手。') },
        { label: '硬打', danger: true, on: () => void walk([cell], false, true) },
    ]);
}

function showDeath() {
    // 死了就整局重来：存档清掉，刷新页面也回不到这一局
    clearSave();
    recordContract(`倒在这一层`);
    modal(`<h2>你倒下了</h2>
        <p>你倒在了${run.floor.name}。</p>
        <div class="row"><span>攻击 / 防御</span><b>${run.hero.atk} / ${run.hero.def}</b></div>
        <div class="row"><span>金币</span><b>${run.hero.gold}</b></div>
        <p class="small">这一局结束了。重新开始要从第 1 层走起，地图会换成新的。</p>${historyHtml()}`,
        [{ label: '从第 1 层重新开始', primary: true, on: () => newRun() }]);
}

/** 下楼时要不要签楼梯口的契约（在出口结算后生效） */
let pendingSign = false;

function contractCardHtml(): string {
    const c = run.offeredContract();
    if (!c) return '';
    const t = contractText(c);
    const dep = depositFor(c, run.hero);
    const afford = run.hero.hp > dep;
    return `<div class="contract"><div class="contractHead">🪝 楼梯边垂下一枚铁钩，钩上挂着一纸契约</div>
        <div class="contractRow"><span>押</span><b>${dep} 生命</b>（现在就扣，你有 ${run.hero.hp}）${dep < c.deposit ? '　井神的钩：少押 ' + (c.deposit - dep) : ''}</div>
        <div class="contractRow"><span>得</span><b>${t.get}</b></div>
        <div class="contractRow"><span>约</span><b>${t.cond}</b></div>
        <div class="contractRow"><span>还</span><b>${t.reward}</b></div>
        <div class="small">下一层可以随时喝血瓶，喝下那一刻就算毁约：押下的生命归井，拿到的属性归你。${afford ? '' : '<br><b class="warnText">你的生命不够押。</b>'}</div></div>`;
}

// ---------- 井中轮 ----------
const SYM_SHORT: Record<Sym, string> = { blade: '刀', hammer: '锤', harpoon: '叉', potion: '瓶', coin: '金', leech: '蛭' };
const symChip = (s: Sym, cls = '') => `<span class="sym s-${s} ${cls}">${SYM_SHORT[s]}</span>`;
let slotHeld: boolean[] = [false, false, false];

function openSlot(i: number) {
    slotHeld = [false, false, false];
    renderSlot(i);
}

function renderSlot(i: number, spinning = false, lastBite = 0, fresh: boolean[] = [true, true, true]) {
    const c = run.cells[i];
    if (c.kind !== 'slot') return;
    const def = SLOTS[c.id];
    const st = run.slotState(i);
    const odds = machineOdds(def);
    const pct = (x: number) => `${Math.round(x * 1000) / 10}%`;
    const full = run.slotPrice(i, false);
    const hold = run.slotPrice(i, true);
    const pending = st.pending;
    const heldN = slotHeld.filter(Boolean).length;
    const strips = def.reels.map((reel, k) => `<div class="strip"><div class="stripHead">第 ${k + 1} 轮</div>${reel.map(x => symChip(x, 'mini')).join('')}</div>`).join('');
    const result = pending
        ? pending.map((x, k) => `<button class="reel${slotHeld[k] ? ' held' : ''}${x === 'leech' && fresh[k] && lastBite ? ' bit' : ''}" data-k="${k}">${symChip(x, 'big')}<span class="lock">${slotHeld[k] ? '🔒 锁住' : '点击锁住'}</span></button>`).join('')
        : '<div class="small">还没转。</div>';
    const p = pending ? payout(pending) : null;
    const holdLine = pending && heldN > 0 && heldN < 3
        ? `<div class="holdHint">🔒 ${holdHint(def, pending, slotHeld)}<br><span class="small">锁轴重转会放弃这次的奖励；新转出来的井蛭照样咬人。</span></div>` : '';
    const html = `<h2>井中轮 · ${def.name}</h2>
        <div class="slotGrid">
          <div class="slotLeft">
            <p class="small">${def.desc}。每个转轮上的图案都印在机器上：新转一次，三连武器的概率 <b>${pct(odds.weapon)}</b>，至少转出一个井蛭的概率 <b>${pct(odds.anyLeech)}</b>。</p>
            <div class="strips">${strips}</div>
            <div class="small rules">三连武器 → 得到这把武器<br>两个相同武器 → 一颗赤晶<br>两个以上血瓶 → 每个 +40 生命<br>两个以上金币 → 每个 +15 金<br>每个新转出的井蛭 → −15 生命（三个 −60）</div>
          </div>
          <div class="slotRight">
            <div class="reels${spinning ? ' spinning' : ''}">${result}</div>
            ${p && !spinning ? `<div class="payout">收下可得：${p.lines.join('；')}</div>` : ''}
            ${lastBite && !spinning ? `<div class="warnText">井蛭咬掉了 ${lastBite} 生命</div>` : ''}
            ${holdLine}
            <div class="small">你现在：生命 ${run.hero.hp}　金币 ${run.hero.gold}</div>
            <div class="btns" id="slotBtns"></div>
          </div>
        </div>`;
    $('modalBox').classList.add('slotBox');
    $('modalBox').innerHTML = html;
    $('modal').style.display = 'flex';
    const btns = $('slotBtns');
    const add = (label: string, cls: string, on: () => void, disabled = false) => {
        const b = document.createElement('button');
        b.textContent = label;
        b.className = cls;
        b.disabled = disabled || spinning;
        b.onclick = on;
        btns.appendChild(b);
    };
    const spin = (pay: 'gold' | 'blood', withHold: boolean) => {
        const r = run.slotSpin(i, pay, withHold ? slotHeld : undefined);
        if (!r.ok) { setMsg(r.msg, true); renderSlot(i); return; }
        if (!withHold) slotHeld = [false, false, false];
        renderHud();
        saveRun();
        // 转轮动画：先乱转一会儿，再停在结果上
        const reelsEl = () => document.querySelector('#modalBox .reels') as HTMLElement | null;
        renderSlot(i, true);
        const syms: Sym[] = ['blade', 'hammer', 'harpoon', 'potion', 'coin', 'leech'];
        let t = 0;
        const timer = setInterval(() => {
            const el = reelsEl();
            if (!el) return;
            el.querySelectorAll('.reel').forEach((b, k) => {
                if (r.fresh![k]) (b.querySelector('.sym') as HTMLElement).outerHTML = symChip(syms[(t + k * 2) % syms.length], 'big');
            });
            t++;
        }, 70);
        setTimeout(() => {
            clearInterval(timer);
            if (run.status === 'dead') { $('modal').style.display = 'none'; render(); showDeath(); return; }
            renderSlot(i, false, r.bite ?? 0, r.fresh);
        }, 650);
    };
    if (pending) {
        add('收下', 'primary', () => { const lines = run.slotCollect(i); setMsg(lines.join('；')); renderHud(); saveRun(); slotHeld = [false, false, false]; renderSlot(i); });
        const canHold = heldN > 0 && heldN < 3;
        add(`锁轴重转（${hold.gold} 金）`, '', () => spin('gold', true), !canHold || run.hero.gold < hold.gold);
        add(`锁轴重转（血注 ${hold.blood} 血）`, 'danger', () => spin('blood', true), !canHold || run.hero.hp <= hold.blood);
    }
    add(`${pending ? '收下，再转一次' : '转一次'}（${full.gold} 金）`, pending ? '' : 'primary', () => spin('gold', false), run.hero.gold < full.gold);
    add(`血注（${full.blood} 血）`, 'danger', () => spin('blood', false), run.hero.hp <= full.blood);
    add(pending ? '收下，离开' : '离开', 'wide', () => {
        if (run.slotState(i).pending) setMsg(run.slotCollect(i).join('；'));
        $('modal').style.display = 'none';
        render();
        saveRun();
    });
    document.querySelectorAll('#modalBox .reel').forEach(b => (b as HTMLElement).onclick = () => {
        const k = Number((b as HTMLElement).dataset.k);
        slotHeld[k] = !slotHeld[k];
        renderSlot(i, false, 0, fresh);
    });
}

// ---------- 井租 ----------
function showRent(then: () => void) {
    const due = run.rentDue();
    const pay = (m: 'gold' | 'atk' | 'def') => {
        const r = run.payRent(m);
        if (!r.ok) { setMsg(r.msg, true); showRent(then); return; }
        setMsg(r.msg);
        renderHud();
        then();
    };
    const btns: Btn[] = [
        { label: `用 ${RENT_STAT_COST} 点攻击抵`, on: () => pay('atk') },
        { label: `用 ${RENT_STAT_COST} 点防御抵`, on: () => pay('def') },
    ];
    if (run.hero.gold >= due) btns.push({ label: `交 ${due} 金币`, primary: true, on: () => pay('gold') });
    modal(`<h2>井租</h2><p>楼梯口坐着收租的井神：要下楼，先交 <b>${due}</b> 金币的井租。</p>
        <p>你有 ${run.hero.gold} 金币。${run.hero.gold >= due ? '' : '<b class="warnText">金币不够，只能用属性抵。</b>'}</p>
        <p class="small">交不上可以用 ${RENT_STAT_COST} 点攻击或防御抵（永久减少）。</p>`, btns);
}

// ---------- 武器三选一 ----------
function showWeaponChoice() {
    const list = run.pendingWeapons;
    if (!list) return;
    const cur = run.hero.weapon;
    const cards = list.map((w: WeaponId) => `<div class="row"><span>⚔ ${WEAPONS[w].name}</span><b>${WEAPONS[w].desc}</b></div>`).join('');
    modal(`<h2>守卫倒下了</h2><p>它的鳞甲下压着三件东西，你只能拿走一件：</p>${cards}
        <p class="small">${cur ? `你现在拿着${WEAPONS[cur].name}，换掉会当场卖 ${WEAPONS[cur].sell} 金币。` : '你还没有武器。'}</p>`,
        list.map((w: WeaponId) => ({ label: WEAPONS[w].name, primary: false, on: () => { setMsg(run.chooseWeapon(w)); render(); saveRun(); } })));
}

function confirmStairs() {
    // 不提示下一层会不会死：顺其自然，下一层的结果要玩家自己去面对
    const exit = run.cells.findIndex(c => c.kind === 'exit');
    const c = run.offeredContract();
    const down = (sign: boolean) => { pendingSign = sign; void walk([exit], true); };
    const buttons: Btn[] = c
        ? [
            { label: '再想想', on: () => setMsg('留在本层。想好了再走到楼梯口。') },
            { label: '不签，下楼', on: () => down(false) },
            ...(run.hero.hp > depositFor(c, run.hero) ? [{ label: `签约（押 ${depositFor(c, run.hero)} 血），下楼`, primary: true, on: () => down(true) }] : []),
        ]
        : [
            { label: '再想想', on: () => setMsg('留在本层。想好了再走到楼梯口。') },
            { label: '下楼', primary: true, on: () => down(false) },
        ];
    modal(`<h2>楼梯口</h2><p>下楼之后就回不来了。下楼前，你听到井底传来的回声：</p>${intelHtml()}${contractCardHtml()}
        ${c ? '' : '<p class="small">还想回头拿点什么的话，选"再想想"。</p>'}`, buttons);
}

function confirmBreak(cell: number) {
    const ct = run.contract!;
    modal(`<h2>喝下这瓶血瓶？</h2><p>你和井签了契约：本层一瓶血瓶都不喝。</p>
        <p>喝下去就毁约：<b class="warnText">押下的 ${ct.def.deposit} 生命不退</b>，攻击 +${ct.def.atk} 照样留着。</p>
        <p class="small">守约走到出口，能拿回 ${ct.def.refund} 生命${ct.def.gold ? ` 和 ${ct.def.gold} 金币` : ''}。</p>`, [
        { label: '不喝，守约', primary: true, on: () => setMsg('没有喝。') },
        { label: '喝（毁约）', danger: true, on: () => void walk([cell], false, false, true) },
    ]);
}

/** 走到旁边以后要打开的井中轮 */
let pendingSlot = -1;

function act(i: number) {
    if (busy) return;
    if (run.cells[i].kind === 'slot') {
        const near = Math.abs(i % run.w - run.pos % run.w) + Math.abs(Math.floor(i / run.w) - Math.floor(run.pos / run.w)) === 1;
        if (near) { openSlot(i); return; }
        const path = run.findPath(i);
        if (!path) { setMsg('走不到它旁边：先清出一条路（打掉挡路的怪、捡掉路上的东西）', true); return; }
        pendingSlot = i;
        void walk(path.slice(0, -1));
        return;
    }
    const path = run.findPath(i);
    if (!path) { setMsg('走不过去', true); return; }
    void walk(path);
}

function onTap(i: number) {
    if (busy || run.status !== 'playing' || modalOpen()) return;
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
        if (busy || run.status !== 'playing') return;
        const x = run.pos % run.w + d[0];
        const y = Math.floor(run.pos / run.w) + d[1];
        if (x < 0 || y < 0 || x >= run.w || y >= run.h) return;
        const t = y * run.w + x;
        if (run.cells[t].kind === 'wall') return;
        if (run.cells[t].kind === 'slot') { openSlot(t); return; }
        void walk([t]);
    }
    else if (key === 'Escape') { selected = -1; renderBoard(); showInfo(-1); }
});


// ---------- 开局 / 继续 ----------
function startFloor() {
    selected = -1;
    hovered = -1;
    board.innerHTML = '';
    floorBest = solveFromStart(run.floor, run.floorStartHero, run.ch).best?.hero ?? null;
    floorContract = null;
    if (run.contract && run.contract.floorIndex === run.floorIndex) {
        const keep = solveFromStart(keepVersion(run.floor), run.floorStartHero, run.ch).best;
        floorContract = { keep: keep ? keep.hero.hp + run.contract.def.refund : null, any: floorBest?.hp ?? null };
    }
    setMsg(run.floor.hint ?? '');
}

function begin(c: FloorChoice[], save?: RunSave) {
    choices = c;
    const floors = buildFloors(choices);
    run = save ? Run.load(floors, save) : new Run(floors, 'digger', Math.floor(Math.random() * 2 ** 31));
    lastHero = null;
    startFloor();
    render();
    saveRun();
    heroEl.classList.toggle('dead', run.status === 'dead');
    if (run.status === 'floorDone') showExit();
    if (run.status === 'dead') showDeath();
    if (run.pendingWeapons && run.status === 'playing') showWeaponChoice();
}

function newRun() {
    const last = loadKey<FloorChoice[]>(LAST_KEY) ?? undefined;
    const seed = Math.floor(Math.random() * 2 ** 31);
    const c = pickChoices(seed, DEMO_POOLS, last);
    store(LAST_KEY, c);
    begin(c);
}

$('newRun').onclick = () => modal('<h2>新开一局？</h2><p>这一局的进度会丢失。新的一局每层都会换一张地图。</p>', [
    { label: '取消', on: () => {} },
    { label: '新开一局', danger: true, on: newRun },
]);
$('keysHint').textContent = HOVER
    ? '方向键 / WASD 移动 · 走过不能撤回 · 死了从第 1 层重来'
    : '轻点查看，再点一次出手 · 走过不能撤回';

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
