/** 楼层：用文字地图配置，解析成格子数组。 */
import { ItemId, MonsterId, WeaponId } from './config';

export type Cell =
    | { kind: 'wall' }
    | { kind: 'floor' }
    /** 出口：to = 0 是 '>'，to = 1 是 '<'（有两个出口的层，各通向下一层的一个候选） */
    | { kind: 'exit'; to: number }
    | { kind: 'monster'; id: MonsterId }
    | { kind: 'item'; id: ItemId }
    | { kind: 'door'; door: 'bone' | 'blood' }
    /** 设施：不能走过去，站在旁边使用。stall 补给摊、wheel 大转盘、pawn 当铺、altar 骨坛 */
    | { kind: 'stall' }
    | { kind: 'wheel' }
    | { kind: 'pawn' }
    | { kind: 'altar' };

/** 设施格子（站在旁边用，不能走上去） */
export const FACILITY_KINDS = ['stall', 'wheel', 'pawn', 'altar'] as const;
export function isFacility(c: Cell): boolean {
    return (FACILITY_KINDS as readonly string[]).includes(c.kind);
}

/** 楼层类型（楼梯二选一时不告诉玩家，只给一句不说破的话） */
export type FloorKind = 'normal' | 'elite' | 'wheel' | 'pawn' | 'altar' | 'camp' | 'boss';

/** 补给摊上的一样货：每样只能买一次（货品和价格都是讨论项） */
export interface StallOffer {
    id: 'atk' | 'def' | 'hp' | 'key';
    amount: number;
    price: number;
}

export interface FloorDef {
    name: string;
    /** 一句提示，显示在楼层开始时 */
    hint?: string;
    map: string[];
    /** 血门通过要扣的生命 */
    bloodCost: number;
    /** 宝石基础加成（角色的 gemBonus 另算） */
    gem: number;
    smallPotion: number;
    bigPotion: number;
    gold: number;
    /** 楼层类型（不写就是普通层） */
    kind?: FloorKind;
    /** 带印记的怪（格子下标）：打败后可以把对应的武器刻到断臂转轮上 */
    marks?: number[];
    /** 当铺卖的图案（武器或赖子 'wild'） */
    shop?: (WeaponId | 'wild')[];
    /** 离开这一层时要交的井租（金币） */
    rent?: number;
    /** 打败本层精英后三选一拿武器 */
    eliteReward?: boolean;
    /** 本层补给摊的货（地图上的 M） */
    stall?: StallOffer[];
}

/**
 * 地图字符：
 *   #  墙        .  空地      @  入口（主角起点）   >  出口（通向第一个候选）   <  第二个出口（通向第二个候选）
 *   D  骨门      B  血门
 *   k  骨钥      h  小血瓶    H  大血瓶   r  赤晶   b  青晶   $  金币袋
 *   m  井苔      e  盲鳗      f  骨蛙     c  锈甲虫  v  回声蝠  g  溺魂  x  裂岩蟹  G  石鳞守卫
 *   w  井鼠      u  盐蚀蛞蝓  p  骸骨祭司  K  守门人（精英）  E  井底之眼（Boss 占位）
 *   M  补给摊（货品写在楼层的 stall 里）   S  大转盘（井中轮）   N  当铺   A  骨坛（设施都站在旁边用）
 */
const LEGEND: Record<string, Cell> = {
    '#': { kind: 'wall' },
    '.': { kind: 'floor' },
    '@': { kind: 'floor' },
    '>': { kind: 'exit', to: 0 },
    '<': { kind: 'exit', to: 1 },
    D: { kind: 'door', door: 'bone' },
    B: { kind: 'door', door: 'blood' },
    k: { kind: 'item', id: 'key' },
    h: { kind: 'item', id: 'smallPotion' },
    H: { kind: 'item', id: 'bigPotion' },
    r: { kind: 'item', id: 'redGem' },
    b: { kind: 'item', id: 'blueGem' },
    $: { kind: 'item', id: 'gold' },
    m: { kind: 'monster', id: 'moss' },
    e: { kind: 'monster', id: 'eel' },
    f: { kind: 'monster', id: 'frog' },
    c: { kind: 'monster', id: 'beetle' },
    v: { kind: 'monster', id: 'bat' },
    g: { kind: 'monster', id: 'wraith' },
    x: { kind: 'monster', id: 'crab' },
    G: { kind: 'monster', id: 'guardian' },
    w: { kind: 'monster', id: 'rat' },
    u: { kind: 'monster', id: 'slug' },
    p: { kind: 'monster', id: 'priest' },
    K: { kind: 'monster', id: 'gatekeeper' },
    E: { kind: 'monster', id: 'eye' },
    M: { kind: 'stall' },
    S: { kind: 'wheel' },
    N: { kind: 'pawn' },
    A: { kind: 'altar' },
};

export interface ParsedFloor {
    w: number;
    h: number;
    cells: Cell[];
    start: number;
}

export function parseFloor(def: FloorDef): ParsedFloor {
    const h = def.map.length;
    const w = def.map[0].length;
    const cells: Cell[] = [];
    let start = -1;
    let exits = 0;
    def.map.forEach((row, y) => {
        if (row.length !== w) throw new Error(`${def.name}: 第 ${y + 1} 行长度不对`);
        for (let x = 0; x < w; x++) {
            const ch = row[x];
            const cell = LEGEND[ch];
            if (!cell) throw new Error(`${def.name}: 未知字符 "${ch}"`);
            if (ch === '@') start = y * w + x;
            if (cell.kind === 'exit') exits |= 1 << cell.to;
            cells.push({ ...cell } as Cell);
        }
    });
    if (start < 0) throw new Error(`${def.name}: 没有入口 @`);
    // 出口：只有 '>'，或者 '>' 和 '<' 各一个
    if (exits !== 1 && exits !== 3) throw new Error(`${def.name}: 出口必须是一个 '>'，或者 '>' 和 '<' 各一个`);
    if (def.map.join('').split('>').length !== 2 || def.map.join('').split('<').length > 2) throw new Error(`${def.name}: 每种出口只能有一个`);
    return { w, h, cells, start };
}

/** 第 i 格相邻格子上的怪物；alive 用来排除已经打掉的（求解器里格子数组不变） */
export function adjacentMonsters(cells: Cell[], w: number, h: number, i: number, alive: (j: number) => boolean = () => true): MonsterId[] {
    const out: MonsterId[] = [];
    for (const n of neighbors(i, w, h)) {
        const c = cells[n];
        if (c.kind === 'monster' && alive(n)) out.push(c.id);
    }
    return out;
}

export function neighbors(i: number, w: number, h: number): number[] {
    const x = i % w;
    const y = (i - x) / w;
    const out: number[] = [];
    if (y > 0) out.push(i - w);
    if (y < h - 1) out.push(i + w);
    if (x > 0) out.push(i - 1);
    if (x < w - 1) out.push(i + 1);
    return out;
}
