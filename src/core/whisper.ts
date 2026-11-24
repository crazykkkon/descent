/**
 * 楼梯口的一句话：只透露"下面有多凶"的大概，不说类型、不给数字（制作人：更模糊一点）。
 * 设施层（大转盘、当铺、骨坛、营火）没有专门的句子，按怪物多少和普通层混在一起。
 * 同一档里有几种说法，按地图挑一句，所以同一句话也可能是不同的层。
 */
import { MONSTERS } from './config';
import { FloorDef, parseFloor } from './floor';

export const WHISPERS = {
    /** 有精英，或者怪很多 */
    loud: ['下面有什么东西在动。', '下面传来一阵闷响。', '风从下面往上吹，带着一股腥味。'],
    /** 怪很少 */
    quiet: ['下面很安静。', '下面黑得看不见底。', '下面滴答滴答地漏着水。'],
    /** 其他 */
    mid: ['下面有爪子挠石头的声音。', '下面隐约有回声。', '下面有点潮。'],
};

/** 按地图字符算一个稳定的编号，用来在同一档里挑说法（Lua 版逐字节同样算） */
function mapCode(map: string[]): number {
    let n = 0;
    for (const row of map) for (let i = 0; i < row.length; i++) n = (n + row.charCodeAt(i) * (i + 1)) % 9973;
    return n;
}

export function whisper(f: FloorDef): string {
    const cells = parseFloor(f).cells;
    const monsters = cells.filter(c => c.kind === 'monster');
    const elite = monsters.some(c => c.kind === 'monster' && MONSTERS[c.id].elite);
    const level = elite || monsters.length >= 8 ? 'loud' : monsters.length <= 3 ? 'quiet' : 'mid';
    const list = WHISPERS[level];
    return list[mapCode(f.map) % list.length];
}
