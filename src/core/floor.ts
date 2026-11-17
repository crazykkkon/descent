/** 楼层：用文字地图配置，解析成格子数组。 */
import { ItemId, MonsterId } from './config';

export type Cell =
    | { kind: 'wall' }
    | { kind: 'floor' }
    | { kind: 'exit' }
    | { kind: 'monster'; id: MonsterId }
    | { kind: 'item'; id: ItemId }
    | { kind: 'door'; door: 'bone' | 'blood' };

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
}

/**
 * 地图字符：
 *   #  墙        .  空地      @  入口（主角起点）   >  出口
 *   D  骨门      B  血门
 *   k  骨钥      h  小血瓶    H  大血瓶   r  赤晶   b  青晶   $  金币袋
 *   m  井苔      e  盲鳗      f  骨蛙     c  锈甲虫  v  回声蝠  g  溺魂  x  裂岩蟹  G  石鳞守卫
 */
const LEGEND: Record<string, Cell> = {
    '#': { kind: 'wall' },
    '.': { kind: 'floor' },
    '@': { kind: 'floor' },
    '>': { kind: 'exit' },
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
            if (cell.kind === 'exit') exits++;
            cells.push({ ...cell } as Cell);
        }
    });
    if (start < 0) throw new Error(`${def.name}: 没有入口 @`);
    if (exits !== 1) throw new Error(`${def.name}: 出口必须正好 1 个`);
    return { w, h, cells, start };
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
