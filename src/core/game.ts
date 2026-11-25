/**
 * 一局游戏的状态和操作（断臂转轮版，设计方案第五、六章）。
 * 没有撤回、没有重开本层：死了就整局重来。
 *
 * 楼层之内完全确定；随机只发生在楼层之间和设施上（断臂转轮、大转盘、诏令、选路线），全部由本局种子决定。
 */
import { BASE_WEAPONS, BIG_GEM, Boon, BOON_NAMES, CHARACTERS, CharacterDef, EXIT, Hero, ITEM_NAMES, MARK_WEAPON, MONSTER_BOON, MONSTERS, MonsterDef, monsterInContext, powered, TRAIT_DESC, TRAIT_NAMES, WEAPONS, WeaponId } from './config';
import { CombatResult, simulateCombat } from './combat';
import { adjacentMonsters, Cell, FloorDef, isFacility, neighbors, parseFloor, StallOffer } from './floor';
import { interact, isElite } from './rules';
import { solveFloor } from './solver';
import { ArmState, ArmSym, ARM_BASE_PRICE, HOLD_MULTIPLIER, armEmpty, armHas, armOutcome, armRoll, engraveCell, engravedCells, EngraveSym, firstBlank, newArm, WILD, WILD_CHANCE, WILD_NAME, WILD_PRICE } from './arm';
import { draw } from './rng';
import { WHEEL, WheelSector, wheelPrice, wheelStop } from './wheel';
import { ActiveDecree, DECREE_PENALTY, DECREE_SPAN, DecreeDef, SILVER_BONUS_HP, TIER_NAMES, decreeFor, killCounts } from './decree';
import { bloodPrice, pick, risingPrice } from './rng';
import { perkValue } from './meta';

/** dead：主角死了，这一局结束 */
export type Status = 'playing' | 'floorDone' | 'finished' | 'dead';

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

/** 补给摊货品的说明，例如"攻击 +3" */
export function stallText(o: StallOffer): string {
    return { atk: `攻击 +${o.amount}`, def: `防御 +${o.amount}`, hp: `生命 +${o.amount}`, key: `骨钥 ×${o.amount}` }[o.id];
}

/** 图案的名字（武器名或"赖子"） */
export function symName(id: EngraveSym): string {
    return id === WILD ? WILD_NAME : WEAPONS[id].name;
}

/** 当铺的价格 */
export const PAWN = { keyPrice: 15, pawnGold: 40, redeemRate: 1.2, buyPrice: 60, erasePrice: 20 };
/** 骨坛：献 2 点攻击或 1 把骨钥（宝石变小以后从 3 改成 2） */
export const ALTAR_ATK_COST = 2;

/** 等着玩家决定要不要刻的图案 */
export interface PendingEngrave {
    from: 'elite' | 'mark' | 'decree' | 'wheel';
    choices: EngraveSym[];
}

export interface PawnedRow {
    weapon: EngraveSym;
    /** 原来刻在哪个轮子上（从 0 开始） */
    reel: number;
    /** 当掉时在第几层（从 0 开始） */
    floor: number;
}

export interface RunSave {
    characterId: string;
    seed: number;
    tutorial: boolean;
    picks: number[];
    floorIndex: number;
    current: Snapshot;
    floorStart: Snapshot;
    totalSteps: number;
    status: Status;
    rentPaid: boolean;
    arm: ArmState | null;
    wheels: Record<string, { spins: number; draws: number }>;
    pawned: PawnedRow[];
    bought: string[];
    altarUsed: string[];
    boonsSeen: Boon[];
    decree: ActiveDecree | null;
    decreeOffer: DecreeDef | null;
    engraveQueue: PendingEngrave[];
    drank: boolean;
    exitTaken?: number;
    pool?: WeaponId[];
    perks?: Record<string, number>;
    revived?: boolean;
    rewardOffer?: RewardOffer | null;
}

/**
 * 打败精英后的三选一（制作人 2026-11-24：让每场战斗都成为构筑的一部分）：
 * 攻击强化、刻一个武器图案（再从三把里挑）、恢复生命但付一半金币。数值是讨论项。
 */
export interface RewardOffer {
    /** 选"攻击强化"加多少攻击 */
    atk: number;
    /** 选"恢复生命"回多少血 */
    heal: number;
    /** 选"恢复生命"要付多少金币（当时金币的一半，向上取整） */
    cost: number;
    /** 选"刻图案"时的三把武器 */
    choices: EngraveSym[];
}
export type RewardKind = 'atk' | 'engrave' | 'heal';
/** 精英奖励的数值：攻击 1 + 层号/5（宝石变小以后跟着缩小，原来是 3 + 层号/6），生命 120 + 15 × 层号（层号从 0 开始） */
export const ELITE_ATK = 1;
export function eliteReward(floorIndex: number, gold: number, choices: EngraveSym[]): RewardOffer {
    return { atk: ELITE_ATK + Math.floor(floorIndex / 5), heal: 120 + 15 * floorIndex, cost: Math.ceil(gold / 2), choices };
}

/** 交井租的方式 */
export type RentMethod = 'gold' | 'atk' | 'def';
/** 交不上井租时，用攻击或防御抵的点数 */
export const RENT_STAT_COST = 2;

export interface ActResult {
    ok: boolean;
    msg: string;
}

export interface ArmSpinResult extends ActResult {
    faces?: ArmSym[];
}

export interface WheelResult extends ActResult {
    sector?: number;
}

export interface CellInfo {
    title: string;
    lines: string[];
    combat?: CombatResult;
}

export interface RunOptions {
    /** 新手教程局：没有断臂转轮、没有诏令 */
    tutorial?: boolean;
    /** 碎片商店里开着的强化（id → 等级）；教程局不生效 */
    perks?: Record<string, number>;
    /** 图案池（解锁的武器也在里面）；不给就是一开始的 8 把 */
    pool?: WeaponId[];
}

export class Run {
    readonly ch: CharacterDef;
    /** 每层的候选楼层：只有一个时直接下去，两个时楼梯二选一 */
    readonly plan: FloorDef[][];
    readonly tutorial: boolean;
    hero: Hero;
    floorIndex = 0;
    /** 每层选了第几个候选 */
    picks: number[] = [0];
    w = 0;
    h = 0;
    cells: Cell[] = [];
    pos = 0;
    steps = 0;
    kills = 0;
    totalSteps = 0;
    status: Status = 'playing';
    seed: number;
    rentPaid = false;
    /** 断臂转轮（教程局没有） */
    arm: ArmState | null;
    /** 每台大转盘的状态，键是"层:格子" */
    wheels: Record<string, { spins: number; draws: number }> = {};
    /** 当掉的武器图案 */
    pawned: PawnedRow[] = [];
    /** 补给摊、当铺买过的货，键是"层:格子:第几样" */
    bought: string[] = [];
    /** 用过的骨坛，键是"层:格子" */
    altarUsed: string[] = [];
    /** 这一局杀过的、骨坛能移的特性 */
    boonsSeen: Boon[] = [];
    /** 正在进行的诏令 */
    decree: ActiveDecree | null = null;
    /** 本层开头送来、还没决定接不接的诏令 */
    decreeOffer: DecreeDef | null = null;
    /** 等着决定要不要刻的图案（依次处理） */
    engraveQueue: PendingEngrave[] = [];
    /** 本层喝过血瓶没有（诏令用） */
    drank = false;
    /** 从哪个出口走的（0 = '>'，1 = '<'），决定下一层是哪个候选 */
    exitTaken = 0;
    /** 图案池：精英三选一、大转盘新图案从这里抽 */
    pool: WeaponId[] = [...BASE_WEAPONS];
    /** 开着的强化 */
    perks: Record<string, number> = {};
    /** 溺者已经复活过 */
    revived = false;
    /** 打败精英后还没选的三选一奖励 */
    rewardOffer: RewardOffer | null = null;
    /** 上一次结算时诏令的消息（界面显示后清掉） */
    notes: string[] = [];
    private floorStart!: Snapshot;

    /**
     * @param plan 每层的候选楼层；传一维数组时每层只有一个候选
     */
    constructor(plan: FloorDef[][] | FloorDef[], characterId = 'digger', seed = 1, opts: RunOptions = {}) {
        this.plan = (plan as unknown[]).map(x => (Array.isArray(x) ? x : [x])) as FloorDef[][];
        this.seed = seed >>> 0;
        this.ch = CHARACTERS[characterId];
        this.hero = { ...this.ch.base };
        this.tutorial = !!opts.tutorial;
        this.arm = this.tutorial ? null : newArm();
        if (opts.pool) this.pool = [...opts.pool];
        if (!this.tutorial && opts.perks) this.perks = { ...opts.perks };
        this.applyPerks();
        this.loadFloor(0);
    }

    /** 开局强化（碎片商店） */
    private applyPerks() {
        const v = (id: string) => perkValue(id, this.perks[id] ?? 0);
        this.hero.atk += v('atk');
        this.hero.def += v('def');
        this.hero.hp += v('hp');
        this.hero.keys += v('keys');
        this.hero.gold += v('gold');
        // 旧印子：开局随机刻一个武器图案（不落在中间一行，要转到才拿得到）
        if (v('engrave') && this.arm) {
            const w = this.pool[pick(this.seed, 9900, 0, this.pool.length)];
            engraveCell(this.arm, pick(this.seed, 9900, 1, 3), w);
        }
    }

    get floor(): FloorDef { return this.plan[this.floorIndex][this.picks[this.floorIndex] ?? 0]; }

    /** 下一层的候选（最后一层返回空） */
    nextOptions(): FloorDef[] { return this.plan[this.floorIndex + 1] ?? []; }

    private loadFloor(i: number) {
        this.floorIndex = i;
        const p = parseFloor(this.floor);
        this.w = p.w;
        this.h = p.h;
        this.cells = p.cells;
        this.pos = p.start;
        this.steps = 0;
        this.kills = 0;
        this.status = 'playing';
        this.rentPaid = false;
        this.drank = false;
        this.exitTaken = 0;
        if (this.arm) this.arm.spins = 0;
        // 溺者复活以后，每进一层扣生命（最少留 1）
        if (this.revived && this.ch.drain && i > 0) this.hero.hp = Math.max(1, this.hero.hp - this.ch.drain);
        this.decreeOffer = !this.tutorial && !this.decree ? decreeFor(this.seed, i) : null;
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
    }

    /** 本层入场时的属性 */
    get floorStartHero(): Hero { return { ...this.floorStart.hero }; }

    // ---------- 断臂转轮 ----------

    /** 把手上的武器换成 id（undefined = 空手），带上骨坛移来的特性 */
    private hold(id: WeaponId | undefined) {
        if (id) {
            this.hero.weapon = id;
            const b = this.arm?.boons[id];
            if (b && b.length) this.hero.boons = [...b];
            else delete this.hero.boons;
        } else {
            delete this.hero.weapon;
            delete this.hero.boons;
        }
    }

    /** 图案被擦掉 / 当掉后：手上的武器要是已经不在转轮上，就变空手 */
    private checkHold() {
        if (!this.arm) return;
        if (this.hero.weapon && !armHas(this.arm, this.hero.weapon)) this.hold(undefined);
    }

    get pendingEngrave(): PendingEngrave | null { return this.engraveQueue[0] ?? null; }

    /** 精英、诏令给的三选一（不含手上这把）；有很小的机会第三个换成赖子 */
    private rollWeaponChoices(salt = 0): EngraveSym[] {
        const pool = this.pool.filter(w => w !== this.hero.weapon);
        const out: WeaponId[] = [];
        let n = 0;
        while (out.length < 3 && out.length < pool.length) {
            const r = ((Math.imul(this.seed ^ (this.floorIndex * 7919 + salt * 131 + ++n * 104729), 2654435761) >>> 0) % pool.length);
            if (!out.includes(pool[r])) out.push(pool[r]);
        }
        const res: EngraveSym[] = [...out];
        if (res.length === 3 && draw(this.seed, 9100 + this.floorIndex * 10 + salt, 0) < WILD_CHANCE) res[2] = WILD;
        return res;
    }

    /** 刻满时的提示（没刻满返回 null） */
    private fullReel(reel: number, cell?: number): ActResult | null {
        if (!this.arm || reel < 0 || reel >= this.arm.reels.length) return { ok: false, msg: '' };
        // 只能刻在空格上；有图案的格子要先去当铺擦掉（制作人定）
        if (cell === undefined && firstBlank(this.arm, reel) < 0) return { ok: false, msg: `第 ${reel + 1} 个轮子刻满了。要刻在这个轮子上，先去当铺擦掉一格` };
        const old = cell === undefined ? null : this.arm.reels[reel][cell];
        if (old) return { ok: false, msg: `这一格已经有${symName(old)}了，不能覆盖。要刻在这里，先去当铺把它擦掉` };
        return null;
    }

    /** 把等待中的图案刻到第 reel 个轮子的空格上（有图案的格子不能覆盖）；刻上不等于拿到，要转到才行 */
    engrave(id: EngraveSym, reel: number, cell?: number): ActResult {
        const p = this.pendingEngrave;
        if (!this.arm || !p || !p.choices.includes(id)) return { ok: false, msg: '' };
        const full = this.fullReel(reel, cell);
        if (full) return full;
        const k = engraveCell(this.arm, reel, id, cell);
        if (k < 0) return { ok: false, msg: '' };
        this.engraveQueue.shift();
        // 刻上不等于拿到：要拉杆转到才换成这把武器
        this.checkHold();
        return { ok: true, msg: `把${symName(id)}刻在第 ${reel + 1} 个轮子的第 ${k + 1} 格，转到它才拿得到` };
    }

    /** 不刻 */
    skipEngrave(): void { this.engraveQueue.shift(); }

    /** 精英奖励三选一：攻击强化 / 刻图案（接着从三把里挑）/ 恢复生命付一半金币 */
    chooseReward(kind: RewardKind): ActResult {
        const o = this.rewardOffer;
        if (!o) return { ok: false, msg: '' };
        this.rewardOffer = null;
        if (kind === 'atk') { this.hero.atk += o.atk; return { ok: true, msg: `攻击 +${o.atk}` }; }
        if (kind === 'heal') {
            this.hero.hp += o.heal;
            this.hero.gold -= o.cost;
            return { ok: true, msg: `生命 +${o.heal}，付了 ${o.cost} 金币` };
        }
        this.engraveQueue.push({ from: 'elite', choices: o.choices });
        return { ok: true, msg: '' };
    }

    /** 断臂转轮下一次转的价格；held 里锁住的轮子越多越贵（锁一个 ×2，锁两个 ×3） */
    armPrice(held?: boolean[]): { gold: number; blood: number } {
        let base = risingPrice(ARM_BASE_PRICE, this.arm?.spins ?? 0);
        // 润滑油（碎片商店）：每层第一次半价
        if (this.perks.halfSpin && (this.arm?.spins ?? 0) === 0) base /= 2;
        const n = (held ?? []).filter(Boolean).length;
        const gold = Math.round((base * HOLD_MULTIPLIER[Math.min(n, 2)]) / 5) * 5;
        return { gold, blood: bloodPrice(gold) };
    }

    /** 转断臂转轮。held 里为 true 的轮子锁住不动（更贵） */
    armSpin(pay: 'gold' | 'blood', held?: boolean[]): ArmSpinResult {
        const arm = this.arm;
        if (this.status !== 'playing' || !arm) return { ok: false, msg: '' };
        if (armEmpty(arm)) return { ok: false, msg: '转轮上还没有刻任何图案' };
        const hold = !!held && held.some(Boolean);
        if (hold && held!.every(Boolean)) return { ok: false, msg: '要锁住一两个轮子，留至少一个重转' };
        const price = this.armPrice(held);
        if (pay === 'gold') {
            if (this.hero.gold < price.gold) return { ok: false, msg: `金币不够（要 ${price.gold}）` };
            this.hero.gold -= price.gold;
        } else {
            if (this.hero.hp <= price.blood) return { ok: false, msg: `生命不够（要 ${price.blood}）` };
            this.hero.hp -= price.blood;
        }
        const faces = armRoll(arm, this.seed, this.floorIndex * 1000 + 999, hold ? held : undefined);
        arm.spins++;
        const o = armOutcome(faces);
        if (o.kind === 'weapon') {
            const same = this.hero.weapon === o.id;
            this.hold(o.id);
            return { ok: true, msg: same ? `三个轮子都停在${WEAPONS[o.id].name}上，还是它` : `三个轮子都停在${WEAPONS[o.id].name}上，换成了${WEAPONS[o.id].name}`, faces };
        }
        if (o.kind === 'empty') {
            this.hold(undefined);
            return { ok: true, msg: '三个轮子都停在空格上，手里空了', faces };
        }
        return { ok: true, msg: '没有连成一线，手上的武器不变', faces };
    }

    // ---------- 设施 ----------

    private nextTo(i: number): boolean { return neighbors(this.pos, this.w, this.h).includes(i); }

    private facility(i: number, kind: Cell['kind'], name: string): ActResult | null {
        const c = this.cells[i];
        if (this.status !== 'playing' || !c || c.kind !== kind) return { ok: false, msg: '' };
        if (!this.nextTo(i)) return { ok: false, msg: `站在${name}旁边才能用它` };
        return null;
    }

    private pay(gold: number): ActResult | null {
        if (this.hero.gold < gold) return { ok: false, msg: `金币不够（要 ${gold}）` };
        this.hero.gold -= gold;
        return null;
    }

    sold(i: number, k: number): boolean { return this.bought.includes(`${this.floorIndex}:${i}:${k}`); }

    /** 补给摊（营火层） */
    stallBuy(i: number, k: number): ActResult {
        const o = this.floor.stall?.[k];
        const bad = this.facility(i, 'stall', '补给摊') ?? (o ? null : { ok: false, msg: '' });
        if (bad) return bad;
        if (this.sold(i, k)) return { ok: false, msg: '这样已经买过了' };
        const unpaid = this.pay(o!.price);
        if (unpaid) return unpaid;
        if (o!.id === 'atk') this.hero.atk += o!.amount;
        else if (o!.id === 'def') this.hero.def += o!.amount;
        else if (o!.id === 'hp') this.hero.hp += o!.amount;
        else this.hero.keys += o!.amount;
        this.bought.push(`${this.floorIndex}:${i}:${k}`);
        return { ok: true, msg: `买下${stallText(o!)}，花了 ${o!.price} 金币` };
    }

    wheelState(i: number): { spins: number; draws: number } {
        return (this.wheels[`${this.floorIndex}:${i}`] ??= { spins: 0, draws: 0 });
    }

    wheelPrice(i: number): { gold: number; blood: number } {
        const gold = wheelPrice(this.wheelState(i).spins);
        return { gold, blood: bloodPrice(gold) };
    }

    /** 转大转盘 */
    /** 下一次转会停在哪一格（只看、不付钱也不结算；画面先把转盘转到这一格，停下来再调 wheelSpin） */
    wheelPeek(i: number): number {
        return wheelStop(this.seed, this.floorIndex * 1000 + i, this.wheelState(i).draws);
    }

    wheelSpin(i: number, pay: 'gold' | 'blood'): WheelResult {
        const bad = this.facility(i, 'wheel', '大转盘');
        if (bad) return bad;
        const st = this.wheelState(i);
        const price = this.wheelPrice(i);
        if (pay === 'gold') {
            const unpaid = this.pay(price.gold);
            if (unpaid) return unpaid;
        } else {
            if (this.hero.hp <= price.blood) return { ok: false, msg: `生命不够（要 ${price.blood}）` };
            this.hero.hp -= price.blood;
        }
        const key = this.floorIndex * 1000 + i;
        const n = st.draws++;
        const sector = wheelStop(this.seed, key, n);
        st.spins++;
        const s: WheelSector = WHEEL[sector];
        let msg = `停在「${s.text}」`;
        switch (s.prize) {
            case 'gold': this.hero.gold += s.amount; break;
            case 'hp': this.hero.hp += s.amount; break;
            case 'atk': this.hero.atk += s.amount; break;
            case 'def': this.hero.def += s.amount; break;
            case 'engrave': {
                const all = this.pool;
                const w: EngraveSym = draw(this.seed, key + 700, n) < WILD_CHANCE ? WILD : all[pick(this.seed, key + 500, n, all.length)];
                if (this.arm) { this.engraveQueue.push({ from: 'wheel', choices: [w] }); msg += `：${symName(w)}`; }
                break;
            }
            case 'leech':
                this.hero.hp -= s.amount;
                if (this.hero.hp <= 0) {
                    this.hero.hp = 0;
                    this.status = 'dead';
                    return { ok: true, msg: '你倒下了。井蛭吸干了你最后一点血', sector };
                }
                break;
            case 'erase': {
                const cells = this.arm ? engravedCells(this.arm) : [];
                if (!cells.length) { msg += '：转轮上没有图案，什么也没擦掉'; break; }
                const [r, k] = cells[pick(this.seed, key + 600, n, cells.length)];
                msg += `：第 ${r + 1} 个轮子第 ${k + 1} 格的${symName(this.arm!.reels[r][k]!)}没了`;
                this.arm!.reels[r][k] = null;
                this.checkHold();
                break;
            }
        }
        return { ok: true, msg, sector };
    }

    /** 当铺：卖一把骨钥 */
    pawnSellKey(i: number): ActResult {
        const bad = this.facility(i, 'pawn', '当铺');
        if (bad) return bad;
        if (this.hero.keys <= 0) return { ok: false, msg: '你没有骨钥' };
        this.hero.keys--;
        this.hero.gold += PAWN.keyPrice;
        return { ok: true, msg: `卖了一把骨钥，得 ${PAWN.keyPrice} 金币` };
    }

    /** 当铺：当掉转轮上的一格武器图案 */
    pawnCell(i: number, reel: number, cell: number): ActResult {
        const bad = this.facility(i, 'pawn', '当铺');
        if (bad) return bad;
        const w = this.arm?.reels[reel]?.[cell];
        if (!w) return { ok: false, msg: '这一格是空的' };
        this.arm!.reels[reel][cell] = null;
        this.pawned.push({ weapon: w, reel, floor: this.floorIndex });
        this.hero.gold += PAWN.pawnGold;
        this.checkHold();
        return { ok: true, msg: `当掉了${symName(w)}，得 ${PAWN.pawnGold} 金币` };
    }

    /** 赎回当掉的第 j 件现在要多少钱（每过一层涨 20%） */
    redeemPrice(j: number): number {
        const p = this.pawned[j];
        return Math.ceil(PAWN.pawnGold * Math.pow(PAWN.redeemRate, this.floorIndex - p.floor));
    }

    /** 当铺：赎回当掉的第 j 件，刻回原来那个轮子的空格（刻满了要先擦掉一格） */
    pawnRedeem(i: number, j: number, cell?: number): ActResult {
        const bad = this.facility(i, 'pawn', '当铺');
        if (bad) return bad;
        const p = this.pawned[j];
        if (!p || !this.arm) return { ok: false, msg: '' };
        const full = this.fullReel(p.reel, cell);
        if (full) return full;
        const unpaid = this.pay(this.redeemPrice(j));
        if (unpaid) return unpaid;
        engraveCell(this.arm, p.reel, p.weapon, cell);
        this.pawned.splice(j, 1);
        this.checkHold();
        return { ok: true, msg: `赎回了${symName(p.weapon)}` };
    }

    /** 当铺：买第 k 个武器图案刻到第 reel 个轮子上 */
    pawnBuy(i: number, k: number, reel: number, cell?: number): ActResult {
        const bad = this.facility(i, 'pawn', '当铺');
        if (bad) return bad;
        const w = this.floor.shop?.[k];
        if (!w || !this.arm) return { ok: false, msg: '' };
        if (this.sold(i, k)) return { ok: false, msg: '这样已经买过了' };
        const full = this.fullReel(reel, cell);
        if (full) return full;
        const price = this.shopPrice(w);
        const unpaid = this.pay(price);
        if (unpaid) return unpaid;
        engraveCell(this.arm, reel, w, cell);
        this.bought.push(`${this.floorIndex}:${i}:${k}`);
        this.checkHold();
        return { ok: true, msg: `花 ${price} 金币刻上了${symName(w)}` };
    }

    /** 当铺里一件图案的价格（赖子贵得多） */
    shopPrice(w: EngraveSym): number { return w === WILD ? WILD_PRICE : PAWN.buyPrice; }

    /** 当铺：花钱擦掉一格 */
    pawnErase(i: number, reel: number, cell: number): ActResult {
        const bad = this.facility(i, 'pawn', '当铺');
        if (bad) return bad;
        const w = this.arm?.reels[reel]?.[cell];
        if (!w) return { ok: false, msg: '这一格是空的' };
        const unpaid = this.pay(PAWN.erasePrice);
        if (unpaid) return unpaid;
        this.arm!.reels[reel][cell] = null;
        this.checkHold();
        return { ok: true, msg: `擦掉了第 ${reel + 1} 个轮子第 ${cell + 1} 格的${symName(w)}` };
    }

    /** 骨坛：献 ALTAR_ATK_COST 点攻击或 1 把骨钥，把一种特性移到转轮上的一把武器上（每座骨坛用一次） */
    altarOffer(i: number, pay: 'atk' | 'key', boon: Boon, weapon: WeaponId): ActResult {
        const bad = this.facility(i, 'altar', '骨坛');
        if (bad) return bad;
        const key = `${this.floorIndex}:${i}`;
        if (this.altarUsed.includes(key)) return { ok: false, msg: '这座骨坛已经用过了' };
        if (!this.boonsSeen.includes(boon)) return { ok: false, msg: `这一局还没杀过带「${BOON_NAMES[boon]}」的怪` };
        if (!this.arm || !armHas(this.arm, weapon)) return { ok: false, msg: '转轮上没有这把武器' };
        const list = (this.arm.boons[weapon] ??= []);
        if (list.includes(boon)) return { ok: false, msg: `${WEAPONS[weapon].name}已经有「${BOON_NAMES[boon]}」了` };
        if (pay === 'key') {
            if (this.hero.keys <= 0) return { ok: false, msg: '你没有骨钥' };
            this.hero.keys--;
        } else {
            this.hero.atk -= ALTAR_ATK_COST;
        }
        list.push(boon);
        this.altarUsed.push(key);
        if (this.hero.weapon === weapon) this.hold(weapon);
        return { ok: true, msg: `${WEAPONS[weapon].name}得到了「${BOON_NAMES[boon]}」` };
    }

    // ---------- 诏令 ----------

    acceptDecree(): ActResult {
        if (!this.decreeOffer) return { ok: false, msg: '' };
        this.decree = { def: this.decreeOffer, until: this.floorIndex + DECREE_SPAN - 1, progress: 0 };
        this.decreeOffer = null;
        return { ok: true, msg: `接下${TIER_NAMES[this.decree.def.tier]}诏令：${this.decree.def.text}` };
    }

    refuseDecree(): void { this.decreeOffer = null; }

    private completeDecree() {
        const d = this.decree!;
        this.engraveQueue.push({ from: 'decree', choices: this.rollWeaponChoices(1) });
        if (d.def.tier === 'silver') this.hero.hp += SILVER_BONUS_HP;
        this.notes.push(`诏令完成：${d.def.text}。${d.def.tier === 'silver' ? `生命 +${SILVER_BONUS_HP}，` : ''}可以刻一把武器`);
        this.decree = null;
    }

    /** 离开一层时检查诏令：这一层做到了就完成；到期没完成就受罚 */
    private settleDecree() {
        const d = this.decree;
        if (!d) return;
        const def = d.def;
        const met =
            (def.kind === 'noPotion' && !this.drank) ||
            (def.kind === 'clear' && this.monstersLeft() === 0) ||
            (def.kind === 'noLoss' && this.hero.hp >= this.floorStart.hero.hp) ||
            (def.kind === 'gold' && this.hero.gold >= def.n);
        if (met) { this.completeDecree(); return; }
        if (this.floorIndex >= d.until) {
            const lose = DECREE_PENALTY[def.tier];
            this.hero.atk -= lose;
            this.notes.push(`诏令逾期：${def.text}。攻击 −${lose}`);
            this.decree = null;
        }
    }

    // ---------- 井租 ----------

    rentDue(): number {
        return this.floor.rent && !this.rentPaid ? this.floor.rent : 0;
    }

    payRent(method: RentMethod): ActResult {
        const due = this.rentDue();
        if (!due) return { ok: true, msg: '' };
        if (method === 'gold') {
            if (this.hero.gold < due) return { ok: false, msg: `金币不够（要 ${due}，你有 ${this.hero.gold}）` };
            this.hero.gold -= due;
        } else if (method === 'atk') {
            this.hero.atk -= RENT_STAT_COST;
        } else {
            this.hero.def -= RENT_STAT_COST;
        }
        this.rentPaid = true;
        return { ok: true, msg: method === 'gold' ? `交了 ${due} 金币井租` : `用 ${RENT_STAT_COST} 点${method === 'atk' ? '攻击' : '防御'}抵了井租` };
    }

    // ---------- 地图 ----------

    /** 本层还能不能活着走到出口 */
    floorCheck(): { canReachExit: boolean } {
        const canReachExit = this.status === 'playing'
            && solveFloor({ w: this.w, h: this.h, cells: this.cells, pos: this.pos }, this.hero, this.floor, this.ch).solvable;
        return { canReachExit };
    }

    /** 第 i 格怪物这一刻的真实属性（算上相邻的井鼠、骸骨祭司） */
    monsterAt(i: number): MonsterDef {
        const c = this.cells[i];
        if (c.kind !== 'monster') throw new Error('不是怪物');
        return monsterInContext(MONSTERS[c.id], adjacentMonsters(this.cells, this.w, this.h, i), this.floor.power, this.floor.runStats);
    }

    /** 这只怪带不带印记 */
    marked(i: number): boolean {
        return !!this.arm && !!this.floor.marks?.includes(i) && this.cells[i].kind === 'monster';
    }

    monstersLeft(): number { return this.cells.filter(c => c.kind === 'monster').length; }
    eliteAlive(): boolean { return this.cells.some(isElite); }

    /** 点击格子时显示的信息（包括战斗预览） */
    info(i: number): CellInfo {
        const c = this.cells[i];
        switch (c.kind) {
            case 'monster': {
                const m = this.monsterAt(i);
                const base = powered(MONSTERS[c.id], this.floor.power, this.floor.runStats);
                const r = simulateCombat(this.hero, m);
                const lines = [`生命 ${m.hp}　攻击 ${m.atk}　防御 ${m.def}`];
                if (m.atk !== base.atk) lines.push(`（群居：身边有同类，攻击从 ${base.atk} 涨到 ${m.atk}）`);
                if (m.def !== base.def) lines.push(`（被骸骨祭司庇护，防御从 ${base.def} 涨到 ${m.def}）`);
                for (const t of m.traits) lines.push(`【${TRAIT_NAMES[t]}】${TRAIT_DESC[t]}`);
                if (m.elite) lines.push('精英：必须打败它才能使用出口');
                if (this.marked(i)) lines.push(`印记：打败后可以把${WEAPONS[MARK_WEAPON[c.id]!].name}刻到转轮上`);
                if (!r.canAttack) lines.push('⚠ 你打不动它，硬打会死');
                else if (!r.canWin) lines.push('⚠ 你打不死它，硬打会死');
                else lines.push(`战斗预计损失 ${r.damage} 生命${r.damage >= this.hero.hp ? '（会死）' : ''}`);
                lines.push(`打败后掉落 ${m.gold} 金币`);
                return { title: m.name, lines, combat: r };
            }
            case 'item': {
                const f = this.floor;
                const gem = f.gem + this.ch.gemBonus;
                const eff: Record<string, string> = {
                    smallPotion: `生命 +${f.smallPotion}`, bigPotion: `生命 +${f.bigPotion}`,
                    redGem: `攻击 +${gem}`, blueGem: `防御 +${gem}`, key: '骨钥 +1', gold: `金币 +${f.gold}`,
                    bigRedGem: `攻击 +${BIG_GEM + this.ch.gemBonus}`, bigBlueGem: `防御 +${BIG_GEM + this.ch.gemBonus}`,
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
            case 'stall':
                return { title: '补给摊', lines: (this.floor.stall ?? []).map((o, k) => `${stallText(o)}：${o.price} 金${this.sold(i, k) ? '（已买）' : ''}`) };
            case 'wheel':
                return { title: '大转盘', lines: [WHEEL.map(s => s.text).join('、'), `转一次 ${this.wheelPrice(i).gold} 金`] };
            case 'pawn':
                return { title: '当铺', lines: ['卖骨钥、当掉或赎回武器图案、买图案、擦图案（都按格子算）'] };
            case 'altar':
                return { title: '骨坛', lines: [`献 ${ALTAR_ATK_COST} 点攻击或 1 把骨钥，把杀过的怪的特性移到一把武器上`] };
            default:
                return { title: '空地', lines: [] };
        }
    }

    /** 走空地到目标格子（目标是怪物/道具/门/出口时，最后一步与它交互）。一次走完。 */
    tapCell(target: number): ActResult {
        if (this.status !== 'playing' || target === this.pos) return { ok: false, msg: '' };
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

    /** 往相邻格子走一步（或和它交互）。打败怪物后站到它的格子上 */
    step(i: number): ActResult {
        if (this.status !== 'playing') return { ok: false, msg: '' };
        if (!neighbors(this.pos, this.w, this.h).includes(i)) return { ok: false, msg: '' };
        const c = this.cells[i];
        if (c.kind === 'wall') return { ok: false, msg: '' };
        if (isFacility(c)) return { ok: false, msg: '站在旁边才能用它' };
        if (c.kind === 'exit' && this.eliteAlive()) return { ok: false, msg: '精英守卫还活着，出口被封住了' };

        if (c.kind === 'floor' || c.kind === 'exit') {
            this.pos = i;
            this.steps++;
            if (c.kind === 'exit') { this.status = 'floorDone'; this.exitTaken = c.to; }
            return { ok: true, msg: '' };
        }

        const r = interact(c, this.hero, this.floor, this.ch, true, c.kind === 'monster' ? this.monsterAt(i) : undefined);
        if (!r.ok) return { ok: false, msg: r.reason };
        if (c.kind === 'item' && (c.id === 'smallPotion' || c.id === 'bigPotion')) this.drank = true;
        if (r.fatal && this.ch.revive && !this.revived) {
            // 溺者：倒下时复活一次，怪还在
            this.revived = true;
            this.hero.hp = this.ch.revive;
            this.steps++;
            return { ok: true, msg: `你倒下了……又从水里爬了起来，生命 ${this.ch.revive}。之后每进一层扣 ${this.ch.drain ?? 0} 生命` };
        }
        if (r.fatal) {
            // 硬上打不过的怪：打完就死
            this.hero = r.hero;
            this.steps++;
            this.status = 'dead';
            return { ok: true, msg: `你倒下了。${r.reason}` };
        }
        const lost = this.hero.hp - r.hero.hp;
        this.hero = r.hero;
        this.steps++;
        let msg: string;
        if (c.kind === 'monster') {
            this.kills++;
            const m = MONSTERS[c.id];
            msg = `击败${m.name}，${lost >= 0 ? `损失 ${lost}` : `回复 ${-lost}`} 生命，获得 ${m.gold} 金币`;
            const boon = MONSTER_BOON[c.id];
            if (boon && !this.boonsSeen.includes(boon)) this.boonsSeen.push(boon);
            if (this.arm) {
                // 精英：三选一刻图案；印记怪：刻它对应的武器
                if (m.elite && this.floor.eliteReward) this.rewardOffer = eliteReward(this.floorIndex, this.hero.gold, this.rollWeaponChoices());
                if (this.floor.marks?.includes(i) && MARK_WEAPON[c.id]) this.engraveQueue.push({ from: 'mark', choices: [MARK_WEAPON[c.id]!] });
            }
            if (this.decree && killCounts(this.decree.def, m)) {
                this.decree.progress++;
                if (this.decree.progress >= this.decree.def.n) this.completeDecree();
            }
        } else {
            msg = c.kind === 'item' ? `获得${ITEM_NAMES[c.id]}` : (c.kind === 'door' && c.door === 'bone' ? '打开骨门' : `穿过血门，损失 ${lost} 生命`);
        }
        this.pos = i;
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

    /**
     * 出口结算后进入下一层；只能往下，不能回到上一层。
     * 下一层有两个候选时，走的是哪个出口就去哪个候选（'>' 第一个，'<' 第二个）。
     */
    finishFloor(sellKeys: boolean) {
        const choice = this.exitTaken;
        if (this.status !== 'floorDone') return;
        if (this.rentDue()) return; // 先交井租才能下楼
        const s = this.exitSummary();
        this.hero.gold += s.potionGold;
        if (sellKeys) {
            this.hero.gold += s.keyGold;
            this.hero.keys = 0;
        }
        this.settleDecree();
        this.totalSteps += this.steps;
        if (this.floorIndex + 1 >= this.plan.length) { this.status = 'finished'; return; }
        const opts = this.plan[this.floorIndex + 1];
        this.picks[this.floorIndex + 1] = Math.max(0, Math.min(opts.length - 1, choice));
        this.loadFloor(this.floorIndex + 1);
    }

    /** 存档：只存状态，不存关卡（关卡由种子重建） */
    save(): RunSave {
        return JSON.parse(JSON.stringify({
            characterId: this.ch.id, seed: this.seed, tutorial: this.tutorial, picks: this.picks,
            floorIndex: this.floorIndex, current: this.snapshot(), floorStart: this.floorStart,
            totalSteps: this.totalSteps, status: this.status, rentPaid: this.rentPaid,
            arm: this.arm, wheels: this.wheels, pawned: this.pawned, bought: this.bought,
            altarUsed: this.altarUsed, boonsSeen: this.boonsSeen, decree: this.decree,
            decreeOffer: this.decreeOffer, engraveQueue: this.engraveQueue, drank: this.drank,
            exitTaken: this.exitTaken, pool: this.pool, perks: this.perks, revived: this.revived, rewardOffer: this.rewardOffer,
        }));
    }

    static load(plan: FloorDef[][] | FloorDef[], s: RunSave): Run {
        const run = new Run(plan, s.characterId, s.seed, { tutorial: s.tutorial });
        run.picks = [...s.picks];
        run.loadFloor(s.floorIndex);
        run.floorStart = s.floorStart;
        run.restore(s.current);
        run.totalSteps = s.totalSteps;
        run.status = s.status;
        run.rentPaid = s.rentPaid;
        run.arm = s.arm;
        run.wheels = s.wheels ?? {};
        run.pawned = s.pawned ?? [];
        run.bought = s.bought ?? [];
        run.altarUsed = s.altarUsed ?? [];
        run.boonsSeen = s.boonsSeen ?? [];
        run.decree = s.decree;
        run.decreeOffer = s.decreeOffer;
        run.engraveQueue = s.engraveQueue ?? [];
        run.drank = s.drank;
        run.exitTaken = s.exitTaken ?? 0;
        if (s.pool) run.pool = [...s.pool];
        run.perks = s.perks ?? {};
        run.revived = !!s.revived;
        run.rewardOffer = s.rewardOffer ?? null;
        return run;
    }
}
