-- 本局随机数：和原型 src/core/rng.ts 逐位相同（32 位无符号运算用 LuaJIT 的 bit 库和拆半乘法复现）。

local bit = require('bit')
local M = {}
local TWO32 = 4294967296

local function u32(x) return x % TWO32 end
M.u32 = u32
local function bxor(a, b) return u32(bit.bxor(a, b)) end
M.bxor = bxor
-- 等同于 JS 的 Math.imul(a, b) >>> 0
local function imul(a, b)
    a, b = u32(a), u32(b)
    local alo, ahi = a % 65536, math.floor(a / 65536)
    local blo, bhi = b % 65536, math.floor(b / 65536)
    local mid = (ahi * blo + alo * bhi) % 65536
    return (alo * blo + mid * 65536) % TWO32
end
M.imul = imul
local function shr(a, n) return math.floor(a / 2 ^ n) end

-- 第 n 次取数（n 从 0 开始）；key 区分不同用途；返回 [0, 1)
function M.draw(seed, key, n)
    local a = bxor(bxor(seed, imul(key + 1, 0x9e3779b1)), imul(n + 1, 0x85ebca6b))
    a = imul(bxor(a, shr(a, 16)), 0x7feb352d)
    a = imul(bxor(a, shr(a, 15)), 0x846ca68b)
    return bxor(a, shr(a, 16)) / TWO32
end

-- 从 0..n-1 里取一个
function M.pick(seed, key, k, n) return math.floor(M.draw(seed, key, k) * n) end

-- JS Math.round：.5 往上
local function round(x) return math.floor(x + 0.5) end

function M.risingPrice(base, times) return round(base * 1.5 ^ times / 5) * 5 end
function M.bloodPrice(gold) return math.ceil(gold * 1.5) end
function M.halfPrice(gold) return math.ceil(gold / 2 / 5) * 5 end

return M
