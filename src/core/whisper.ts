/**
 * 楼梯口的一句话：按下一层的真实内容挑，但不说破（不说类型、不给数字）。
 */
import { MONSTERS } from './config';
import { FloorDef, parseFloor } from './floor';

export function whisper(f: FloorDef): string {
    switch (f.kind) {
        case 'wheel': return '下面传来木轮转动的吱呀声。';
        case 'pawn': return '下面有人在拨算盘。';
        case 'altar': return '下面飘上来一股骨灰味。';
        case 'camp': return '下面有火光，暖暖的。';
        default: break;
    }
    const cells = parseFloor(f).cells;
    const monsters = cells.filter(c => c.kind === 'monster');
    if (monsters.some(c => c.kind === 'monster' && MONSTERS[c.id].elite)) return '下面有很沉的呼吸声。';
    if (monsters.length >= 8) return '下面动静很大，像有一群东西在爬。';
    if (monsters.length <= 3) return '下面很安静。';
    return '下面有爪子挠石头的声音。';
}
