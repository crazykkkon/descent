/** 一局游戏的状态和操作：移动、交互、撤回、重开本层、出口结算。 */
import { CHARACTERS, CharacterDef, EXIT, Hero, ITEM_NAMES, MONSTERS, TRAIT_DESC, TRAIT_NAMES } from './config';
import { CombatResult, simulateCombat } from './combat';
import { Cell, FloorDef, neighbors, parseFloor } from './floor';
import { interact, isElite } from './rules';
import { Intel, stairIntel } from './intel';

export type Status = 'playing' | 'floorDone' | 'finished';

export interface Snapshot {
    hero: Hero;
    cells: Cell[];
    pos: number;
    steps: number;
    kills: number;
}

export interface ExitSummary {
    leftoverPotions: number;
    potionGold: number;
    keys: number;
    keyGold: number;
}

export interface RunSave {
    characterId: string;
    floorIndex: number;
    current: Snapshot;
    floorStart: Snapshot;
    totalSteps: number;
    status: Status;
}

export interface ActResult {
    ok: boolean;
    msg: string;
}

export interface CellInfo {
    title: string;
    lines: string[];
    combat?: CombatResult;
}

export class Run {
    readonly ch: CharacterDef;
    hero: Hero;
    floorIndex = 0;
    w = 0;
    h = 0;
    cells: Cell[] = [];
    pos = 0;
    steps = 0;
    kills = 0;
    totalSteps = 0;
    status: Status = 'playing';
    private floorStart!: Snapshot;

    constructor(readonly floors: FloorDef[], characterId = 'digger') {
        this.ch = CHARACTERS[characterId];
        this.hero = { ...this.ch.base };
        this.loadFloor(0);
    }

    get floor(): FloorDef { return this.floors[this.floorIndex]; }

    private loadFloor(i: number) {
        this.floorIndex = i;
        const p = parseFloor(this.floors[i]);
        this.w = p.w;
        this.h = p.h;
        this.cells = p.cells;
        this.pos = p.start;
        this.steps = 0;
        this.kills = 0;
        this.status = 'playing';
        this.floorStart = this.snapshot();
    }

    private snapshot(): Snapshot {
        return { hero: { ...this.hero }, cells: this.cells.map(c => ({ ...c })), pos: this.pos, steps: this.steps, kills: this.kills };
    }

    private restore(s: Snapshot) {
        this.hero = { ...s.hero };
        this.cells = s.cells.map(c => ({ ...c }));
        this.pos = s.pos;
        this.steps = s.steps;
        this.kills = s.kills;
        this.status = 'playing';
    }

    /** 本层入场时的属性 */
    get floorStartHero(): Hero { return { ...this.floorStart.hero }; }

    /** 楼梯口情报：下一层的一条情报（最后一层没有） */
    nextFloorIntel(): Intel | null {
        const next = this.floors[this.floorIndex + 1];
        if (!next) return null;
        return stairIntel(next, this.hero, this.ch, { floor: this.floor, cells: this.cells });
    }

    /** 重开本层：回到入场状态，地图不变。（没有撤回：走过、打过就不能退回） */
    restartFloor() {
        this.restore(this.floorStart);
    }

    monstersLeft(): number { return this.cells.filter(c => c.kind === 'monster').length; }
    eliteAlive(): boolean { return this.cells.some(isElite); }

    /** 点击格子时显示的信息（包括战斗预览） */
    info(i: number): CellInfo {
        const c = this.cells[i];
        switch (c.kind) {
            case 'monster': {
                const m = MONSTERS[c.id];
                const r = simulateCombat(this.hero, m);
                const lines = [`生命 ${m.hp}　攻击 ${m.atk}　防御 ${m.def}`];
                for (const t of m.traits) lines.push(`【${TRAIT_NAMES[t]}】${TRAIT_DESC[t]}`);
                if (m.elite) lines.push('精英：必须打败它才能使用出口');
                if (!r.canAttack) lines.push('⚠ 你打不动它');
                else if (!r.canWin) lines.push('⚠ 你打不死它');
                else lines.push(`战斗预计损失 ${r.damage} 生命${r.damage >= this.hero.hp ? '（会死）' : ''}`);
                return { title: m.name, lines, combat: r };
            }
            case 'item': {
                const f = this.floor;
                const gem = f.gem + this.ch.gemBonus;
                const eff: Record<string, string> = {
                    smallPotion: `生命 +${f.smallPotion}`,
                    bigPotion: `生命 +${f.bigPotion}`,
                    redGem: `攻击 +${gem}`,
                    blueGem: `防御 +${gem}`,
                    key: '骨钥 +1',
                    gold: `金币 +${f.gold}`,
                };
                return { title: ITEM_NAMES[c.id], lines: [eff[c.id]] };
            }
            case 'door':
                return c.door === 'bone'
                    ? { title: '骨门', lines: ['消耗 1 把骨钥打开'] }
                    : { title: '血门', lines: [`不需要钥匙，通过时扣 ${this.floor.bloodCost} 生命`] };
            case 'exit':
                return { title: '出口', lines: this.eliteAlive() ? ['精英守卫还活着，出口被封住了'] : ['走到这里进入下一层'] };
            case 'wall':
                return { title: '井壁', lines: [] };
            default:
                return { title: '空地', lines: [] };
        }
    }

    /** 走空地到目标格子（目标是怪物/道具/门/出口时，最后一步与它交互）。一次走完，界面做动画时改用 findPath + step。 */
    tapCell(target: number): ActResult {
        if (this.status !== 'playing') return { ok: false, msg: '' };
        if (target === this.pos) return { ok: false, msg: '' };
        const path = this.findPath(target);
        if (!path) return { ok: false, msg: '走不过去' };
        let last: ActResult = { ok: true, msg: '' };
        for (const cell of path) {
            last = this.step(cell);
            if (!last.ok) break;
        }
        return last;
    }

    /** 方向键移动一步 */
    move(dx: number, dy: number): ActResult {
        const x = this.pos % this.w + dx;
        const y = Math.floor(this.pos / this.w) + dy;
        if (x < 0 || y < 0 || x >= this.w || y >= this.h) return { ok: false, msg: '' };
        return this.step(y * this.w + x);
    }

    /** 往相邻格子走一步（或和它交互） */
    step(i: number): ActResult {
        if (this.status !== 'playing') return { ok: false, msg: '' };
        if (!neighbors(this.pos, this.w, this.h).includes(i)) return { ok: false, msg: '' };
        const c = this.cells[i];
        if (c.kind === 'wall') return { ok: false, msg: '' };
        if (c.kind === 'exit' && this.eliteAlive()) return { ok: false, msg: '精英守卫还活着，出口被封住了' };

        if (c.kind === 'floor' || c.kind === 'exit') {
            this.pos = i;
            this.steps++;
            if (c.kind === 'exit') this.status = 'floorDone';
            return { ok: true, msg: '' };
        }

        const r = interact(c, this.hero, this.floor, this.ch);
        if (!r.ok) return { ok: false, msg: r.reason };
        const lost = this.hero.hp - r.hero.hp;
        this.hero = r.hero;
        this.steps++;
        let msg: string;
        if (c.kind === 'monster') {
            this.kills++;
            msg = `击败${MONSTERS[c.id].name}，损失 ${lost} 生命`;
        } else {
            this.pos = i;
            msg = c.kind === 'item' ? `获得${ITEM_NAMES[c.id]}` : (c.door === 'bone' ? '打开骨门' : `穿过血门，损失 ${lost} 生命`);
        }
        this.cells[i] = { kind: 'floor' };
        return { ok: true, msg };
    }

    /** 只经过空地的最短路线；返回从下一格到目标的格子列表 */
    findPath(target: number): number[] | null {
        const prev = new Map<number, number>([[this.pos, -1]]);
        const queue = [this.pos];
        while (queue.length) {
            const cur = queue.shift()!;
            for (const n of neighbors(cur, this.w, this.h)) {
                if (prev.has(n)) continue;
                if (n === target) {
                    const path = [n];
                    let p = cur;
                    while (p !== this.pos) { path.unshift(p); p = prev.get(p)!; }
                    return path;
                }
                if (this.cells[n].kind !== 'floor') continue;
                prev.set(n, cur);
                queue.push(n);
            }
        }
        return null;
    }

    exitSummary(): ExitSummary {
        const leftoverPotions = this.cells.filter(c => c.kind === 'item' && (c.id === 'smallPotion' || c.id === 'bigPotion')).length;
        return {
            leftoverPotions,
            potionGold: leftoverPotions * EXIT.leftoverPotionGold,
            keys: this.hero.keys,
            keyGold: this.hero.keys * EXIT.keySellGold,
        };
    }

    /** 出口结算后进入下一层；只能往下，不能回到上一层 */
    finishFloor(sellKeys: boolean) {
        if (this.status !== 'floorDone') return;
        const s = this.exitSummary();
        this.hero.gold += s.potionGold;
        if (sellKeys) {
            this.hero.gold += s.keyGold;
            this.hero.keys = 0;
        }
        this.totalSteps += this.steps;
        if (this.floorIndex + 1 >= this.floors.length) this.status = 'finished';
        else this.loadFloor(this.floorIndex + 1);
    }

    /** 存档：只存状态，不存关卡定义（关卡由外部按选图结果重建） */
    save(): RunSave {
        return {
            characterId: this.ch.id,
            floorIndex: this.floorIndex,
            current: this.snapshot(),
            floorStart: this.floorStart,
            totalSteps: this.totalSteps,
            status: this.status,
        };
    }

    static load(floors: FloorDef[], s: RunSave): Run {
        const run = new Run(floors, s.characterId);
        run.loadFloor(s.floorIndex);
        run.floorStart = s.floorStart;
        run.restore(s.current);
        run.totalSteps = s.totalSteps;
        run.status = s.status;
        return run;
    }

    /** 设计文档第八章的计分公式（步数项在开启坍塌前不计） */
    score(): number {
        return (this.floorIndex + (this.status === 'finished' ? 1 : 0)) * 1000 + this.hero.hp;
    }
}
