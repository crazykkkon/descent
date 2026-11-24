/**
 * 本局随机数：所有"楼层之间"的随机（断臂转轮、大转盘、诏令、选路线）都由本局种子决定，
 * 退出再进来结果不变。Lua 版用同样的 32 位运算逐位复现（love/src/core/rng.lua）。
 */

/** 第 n 次取数（n 从 0 开始）；key 区分不同的用途，返回 [0, 1) */
export function draw(seed: number, key: number, n: number): number {
    let a = (seed ^ Math.imul(key + 1, 0x9e3779b1) ^ Math.imul(n + 1, 0x85ebca6b)) >>> 0;
    a = Math.imul(a ^ (a >>> 16), 0x7feb352d) >>> 0;
    a = Math.imul(a ^ (a >>> 15), 0x846ca68b) >>> 0;
    return ((a ^ (a >>> 16)) >>> 0) / 4294967296;
}

/** 从 0..n-1 里取一个 */
export function pick(seed: number, key: number, k: number, n: number): number {
    return Math.floor(draw(seed, key, k) * n);
}

/** 价格按 ×1.5 往上涨，取到 5 的倍数：base → … */
export function risingPrice(base: number, times: number): number {
    return Math.round((base * Math.pow(1.5, times)) / 5) * 5;
}

/** 用生命代替金币付：×1.5 */
export function bloodPrice(gold: number): number {
    return Math.ceil(gold * 1.5);
}

/** 半价（锁轴重转），取到 5 的倍数 */
export function halfPrice(gold: number): number {
    return Math.ceil(gold / 2 / 5) * 5;
}
