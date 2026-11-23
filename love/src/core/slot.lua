-- 井中轮（老虎机）：和 TypeScript 原型 src/core/slot.ts 一致。
-- 三个转轮的图案全部印在机器上；结果由本局种子决定（随机数和原型逐位相同）。
-- 收下时才给奖励；井蛭在出现的那一刻就咬人。

local M = {}

local bit = require('bit')
local TWO32 = 4294967296

-- 无符号 32 位
local function u32(x) return x % TWO32 end
M.u32 = u32
local function bxor(a, b) return u32(bit.bxor(a, b)) end
M.bxor = bxor
-- 等同于 JS 的 Math.imul(a, b) >>> 0（拆成 16 位两半，避免双精度丢位）
local function imul(a, b)
    a, b = u32(a), u32(b)
    local alo, ahi = a % 65536, math.floor(a / 65536)
    local blo, bhi = b % 65536, math.floor(b / 65536)
    local mid = (ahi * blo + alo * bhi) % 65536
    return (alo * blo + mid * 65536) % TWO32
end
M.imul = imul
local function shr(a, n) return math.floor(a / 2 ^ n) end

M.SYM_NAMES = { blade = '骨刀', hammer = '破壳锤', harpoon = '鱼叉', potion = '血瓶', coin = '金币', leech = '井蛭' }
M.SYM_WEAPON = { blade = 'boneKnife', hammer = 'hammer', harpoon = 'harpoon' }

local CH = { ['刀'] = 'blade', ['锤'] = 'hammer', ['叉'] = 'harpoon', ['瓶'] = 'potion', ['金'] = 'coin', ['蛭'] = 'leech' }
local function R(s)
    local t = {}
    for w in s:gmatch('%S+') do t[#t + 1] = CH[w] end
    return t
end

M.SLOTS = {
    risky = {
        id = 'risky', name = '骨轮', desc = '武器多，井蛭也多',
        reels = { R('刀 刀 锤 叉 蛭 蛭 金 瓶'), R('刀 锤 锤 叉 蛭 蛭 金 瓶'), R('刀 锤 叉 叉 蛭 蛭 金 瓶') },
    },
    steady = {
        id = 'steady', name = '苔轮', desc = '血瓶和金币多，武器很少（三连骨刀极难，但两把骨刀能换赤晶）',
        reels = { R('瓶 瓶 瓶 金 金 刀 蛭 金'), R('瓶 瓶 金 金 金 刀 蛭 瓶'), R('瓶 瓶 金 金 瓶 刀 蛭 金') },
    },
}

M.LEECH_BITE = 15
M.LEECH_TRIPLE = 60
M.POTION_HP = 40
M.COIN_GOLD = 15

-- 第 n 次转（从 0 开始）的价格：20 → 30 → 45 → 70 → 105 …（JS Math.round：.5 往上）
function M.spinPrice(spins)
    return math.floor(20 * 1.5 ^ spins / 5 + 0.5) * 5
end

-- 血注：用生命代替金币，价格 × 1.5
function M.bloodPrice(gold) return math.ceil(gold * 1.5) end

-- 锁轴重转的价格（半价，取到 5 的倍数）
function M.holdPrice(base) return math.ceil(base / 2 / 5) * 5 end

function M.newState() return { spins = 0, draws = 0, pending = nil } end

local function draw(seed, key, n)
    local a = bxor(bxor(seed, imul(key + 1, 0x9e3779b1)), imul(n + 1, 0x85ebca6b))
    a = imul(bxor(a, shr(a, 16)), 0x7feb352d)
    a = imul(bxor(a, shr(a, 15)), 0x846ca68b)
    return bxor(a, shr(a, 16)) / TWO32
end

-- 转一次；held：锁住的转轮（{true,false,false}），锁住的保持 st.pending 里的图案
function M.roll(def, st, seed, key, held)
    held = held or { false, false, false }
    local result, fresh = {}, {}
    for i = 1, 3 do
        if held[i] and st.pending then
            result[i], fresh[i] = st.pending[i], false
        else
            local reel = def.reels[i]
            result[i] = reel[math.floor(draw(seed, key, st.draws) * #reel) + 1]
            st.draws = st.draws + 1
            fresh[i] = true
        end
    end
    return result, fresh
end

local function count(r, s)
    local n = 0
    for _, x in ipairs(r) do if x == s then n = n + 1 end end
    return n
end

-- 奖励：{ gems, hp, gold, weapon?, lines }
function M.payout(r)
    local p = { gems = 0, hp = 0, gold = 0, lines = {} }
    for _, s in ipairs({ 'blade', 'hammer', 'harpoon' }) do
        local n = count(r, s)
        if n == 3 then
            p.weapon = M.SYM_WEAPON[s]
            p.lines[#p.lines + 1] = '三连' .. M.SYM_NAMES[s] .. '：得到武器「' .. M.SYM_NAMES[s] .. '」'
        elseif n == 2 then
            p.gems = p.gems + 1
            p.lines[#p.lines + 1] = '两个' .. M.SYM_NAMES[s] .. '：得到一颗赤晶'
        end
    end
    local np, nc = count(r, 'potion'), count(r, 'coin')
    if np >= 2 then
        p.hp = p.hp + np * M.POTION_HP
        p.lines[#p.lines + 1] = np .. ' 个血瓶：+' .. np * M.POTION_HP .. ' 生命'
    end
    if nc >= 2 then
        p.gold = p.gold + nc * M.COIN_GOLD
        p.lines[#p.lines + 1] = nc .. ' 个金币：+' .. nc * M.COIN_GOLD .. ' 金币'
    end
    if #p.lines == 0 then p.lines[1] = '什么都没有' end
    return p
end

-- 新出现的井蛭咬人：每只 15，三只全新的井蛭 60
function M.leechBite(r, fresh)
    local n, allFresh = 0, true
    for i = 1, 3 do
        if r[i] == 'leech' and fresh[i] then n = n + 1 end
        if not fresh[i] then allFresh = false end
    end
    if count(r, 'leech') == 3 and allFresh then return M.LEECH_TRIPLE end
    return n * M.LEECH_BITE
end

local function share(reel, s) return count(reel, s) / #reel end

function M.tripleWeaponOdds(def)
    local p = 0
    for _, s in ipairs({ 'blade', 'hammer', 'harpoon' }) do
        p = p + share(def.reels[1], s) * share(def.reels[2], s) * share(def.reels[3], s)
    end
    return p
end

function M.machineOdds(def)
    local noLeech = 1
    for _, reel in ipairs(def.reels) do noLeech = noLeech * (1 - share(reel, 'leech')) end
    return { weapon = M.tripleWeaponOdds(def), anyLeech = 1 - noLeech }
end

-- 锁轴时给玩家看的概率说明
function M.holdHint(def, pending, held)
    local heldSyms = {}
    for i = 1, 3 do if held[i] then heldSyms[#heldSyms + 1] = pending[i] end end
    if #heldSyms == 0 then return '' end
    local target = heldSyms[1]
    for _, s in ipairs(heldSyms) do
        if s ~= target then return '锁住的图案不一样，重转凑不成三连；只能指望另一个转轮出好东西。' end
    end
    if target == 'leech' then return '锁住井蛭不会让它再咬你，但它也不会变成别的。' end
    local all, none = 1, 1
    for i = 1, 3 do
        if not held[i] then
            local e = share(def.reels[i], target)
            all, none = all * e, none * (1 - e)
        end
    end
    local function pct(x) return (math.floor(x * 1000 + 0.5) / 10) .. '%' end
    local name = M.SYM_NAMES[target]
    if M.SYM_WEAPON[target] then
        if #heldSyms == 2 then
            return '重转剩下那个转轮，凑成三连' .. name .. '（得到武器）的概率 ' .. pct(all) .. '；没中也还保有两个' .. name .. '（一颗赤晶）。'
        end
        return '重转另外两个转轮：凑成三连' .. name .. '的概率 ' .. pct(all) .. '，至少再出一个' .. name .. '（两个能换赤晶）的概率 ' .. pct(1 - none) .. '。'
    end
    if #heldSyms == 2 then
        return '已经有两个' .. name .. '了，重转剩下那个转轮，再出一个' .. name .. '的概率 ' .. pct(all) .. '。'
    end
    return '重转另外两个转轮，至少再出一个' .. name .. '（凑够两个才有奖励）的概率 ' .. pct(1 - none) .. '。'
end

return M
