-- 一局游戏的状态和操作（断臂转轮版）：和原型 src/core/game.ts 的 Run 一致。
-- 没有撤回、没有重开本层：死了就整局重来。
-- 楼层之内完全确定；随机只发生在楼层之间和设施上，全部由本局种子决定。
-- 层号、格子下标、转轮行号在 Lua 里都从 1 开始；随机数的键按原型的 0 开始计算。

local config = require('core.config')
local combat = require('core.combat')
local floorMod = require('core.floor')
local rules = require('core.rules')
local rng = require('core.rng')
local armMod = require('core.arm')
local wheelMod = require('core.wheel')
local decreeMod = require('core.decree')
local metaMod = require('core.meta')

-- 图案的名字（武器名或"赖子"）
local function symName(id) return id == armMod.WILD and armMod.WILD_NAME or config.WEAPONS[id].name end

local Run = {}
Run.__index = Run

Run.PAWN = { keyPrice = 15, pawnGold = 40, redeemRate = 1.2, buyPrice = 60, erasePrice = 20 }
Run.ALTAR_ATK_COST = 3
Run.symName = function(id) return id == 'wild' and '赖子' or config.WEAPONS[id].name end
Run.RENT_STAT_COST = 3

local function copyCells(cells)
    local t = {}
    for i, c in ipairs(cells) do t[i] = floorMod.copyCell(c) end
    return t
end

local function contains(list, v)
    for _, x in ipairs(list or {}) do if x == v then return true end end
    return false
end
Run.contains = contains

-- plan：每层的候选楼层 plan[层] = { 楼层1, 楼层2? }；传一维列表时每层只有一个候选
-- opts.tutorial：新手教程局（没有断臂转轮、没有诏令）
function Run.new(plan, characterId, seed, opts)
    local self = setmetatable({}, Run)
    local p = {}
    for i, x in ipairs(plan) do p[i] = x.map and { x } or x end
    self.plan = p
    self.ch = config.CHARACTERS[characterId or 'digger']
    self.hero = config.copyHero(self.ch.base)
    self.seed = rng.u32(seed or 1)
    self.tutorial = (opts and opts.tutorial) and true or false
    self.arm = (not self.tutorial) and armMod.new() or nil
    -- 图案池（解锁的武器也在里面）和碎片商店里开着的强化（教程局不生效）
    self.pool = {}
    for i, w in ipairs((opts and opts.pool) or config.WEAPON_ORDER) do self.pool[i] = w end
    self.perks = {}
    if not self.tutorial and opts and opts.perks then for k, v in pairs(opts.perks) do self.perks[k] = v end end
    self.revived = false
    self:applyPerks()
    self.picks = { 1 }
    self.totalSteps = 0
    self.wheels = {}
    self.pawned = {}
    self.bought = {}
    self.altarUsed = {}
    self.boonsSeen = {}
    self.decree = nil
    self.decreeOffer = nil
    self.engraveQueue = {}
    self.notes = {}
    self:loadFloor(1)
    return self
end

function Run:floor() return self.plan[self.floorIndex][self.picks[self.floorIndex] or 1] end

-- 下一层的候选（最后一层返回空表）
function Run:nextOptions() return self.plan[self.floorIndex + 1] or {} end

function Run:loadFloor(i)
    self.floorIndex = i
    local p = floorMod.parse(self:floor())
    self.w, self.h, self.cells, self.pos = p.w, p.h, p.cells, p.start
    self.steps = 0
    self.kills = 0
    self.status = 'playing'
    self.rentPaid = false
    self.drank = false
    self.exitTaken = 0   -- 从哪个出口走的（0 = '>'，1 = '<'），决定下一层是哪个候选
    if self.arm then self.arm.spins = 0 end
    -- 溺者复活以后，每进一层扣生命（最少留 1）
    if self.revived and self.ch.drain and i > 1 then self.hero.hp = math.max(1, self.hero.hp - self.ch.drain) end
    self.decreeOffer = (not self.tutorial and not self.decree) and decreeMod.decreeFor(self.seed, i) or nil
    self.floorStart = self:snapshot()
end

function Run:snapshot()
    return { hero = config.copyHero(self.hero), cells = copyCells(self.cells), pos = self.pos, steps = self.steps, kills = self.kills }
end

function Run:restore(s)
    self.hero = config.copyHero(s.hero)
    self.cells = copyCells(s.cells)
    self.pos, self.steps, self.kills = s.pos, s.steps, s.kills
end

function Run:floorStartHero() return config.copyHero(self.floorStart.hero) end

function Run:monstersLeft()
    local n = 0
    for _, c in ipairs(self.cells) do if c.kind == 'monster' then n = n + 1 end end
    return n
end

function Run:eliteAlive()
    for _, c in ipairs(self.cells) do if rules.isElite(c) then return true end end
    return false
end

-- ---------- 断臂转轮 ----------

-- 把手上的武器换成 id（nil = 空手），带上骨坛移来的特性
function Run:hold(id)
    if id then
        self.hero.weapon = id
        local b = self.arm and self.arm.boons[id]
        self.hero.boons = (b and #b > 0) and config.copyList(b) or nil
    else
        self.hero.weapon, self.hero.boons = nil, nil
    end
end

function Run:checkHold()
    if not self.arm then return end
    if self.hero.weapon and not armMod.has(self.arm, self.hero.weapon) then self:hold(nil) end
end

function Run:pendingEngrave() return self.engraveQueue[1] end

-- 精英、诏令给的三选一（不含手上这把）；和原型逐位相同
-- 开局强化（碎片商店）
function Run:applyPerks()
    local function v(id) return metaMod.perkValue(id, self.perks[id] or 0) end
    self.hero.atk = self.hero.atk + v('atk')
    self.hero.def = self.hero.def + v('def')
    self.hero.hp = self.hero.hp + v('hp')
    self.hero.keys = self.hero.keys + v('keys')
    self.hero.gold = self.hero.gold + v('gold')
    -- 旧印子：开局随机刻一个武器图案（不落在中间一行）
    if v('engrave') > 0 and self.arm then
        local w = self.pool[rng.pick(self.seed, 9900, 0, #self.pool) + 1]
        armMod.engraveCell(self.arm, rng.pick(self.seed, 9900, 1, 3) + 1, w)
    end
end

function Run:rollWeaponChoices(salt)
    salt = salt or 0
    local pool = {}
    for _, w in ipairs(self.pool) do if w ~= self.hero.weapon then pool[#pool + 1] = w end end
    local out, n = {}, 0
    while #out < 3 and #out < #pool do
        n = n + 1
        local x = rng.imul(rng.bxor(self.seed, (self.floorIndex - 1) * 7919 + salt * 131 + n * 104729), 2654435761)
        local w = pool[x % #pool + 1]
        if not contains(out, w) then out[#out + 1] = w end
    end
    -- 很小的机会第三个换成赖子
    if #out == 3 and rng.draw(self.seed, 9100 + (self.floorIndex - 1) * 10 + salt, 0) < armMod.WILD_CHANCE then out[3] = armMod.WILD end
    return out
end

-- 这个轮子刻满了（又没指定格子）时的提示
function Run:fullReel(reel, cell)
    if not self.arm or not reel or reel < 1 or reel > armMod.REELS then return { ok = false, msg = '' } end
    -- 只能刻在空格上；有图案的格子要先去当铺擦掉（制作人定）
    if not cell and not armMod.firstBlank(self.arm, reel) then return { ok = false, msg = '第 ' .. reel .. ' 个轮子刻满了。要刻在这个轮子上，先去当铺擦掉一格' } end
    local old = cell and self.arm.reels[reel][cell]
    if old then return { ok = false, msg = '这一格已经有' .. symName(old) .. '了，不能覆盖。要刻在这里，先去当铺把它擦掉' } end
    return nil
end

-- 把等待中的图案刻到第 reel 个轮子上（刻满时要指定格子）；刻上不等于拿到，要转到才换成它
function Run:engrave(id, reel, cell)
    local p = self.engraveQueue[1]
    if not self.arm or not p or not contains(p.choices, id) then return { ok = false, msg = '' } end
    local full = self:fullReel(reel, cell)
    if full then return full end
    local k = armMod.engraveCell(self.arm, reel, id, cell)
    if not k then return { ok = false, msg = '' } end
    table.remove(self.engraveQueue, 1)
    self:checkHold()
    return { ok = true, msg = '把' .. symName(id) .. '刻在第 ' .. reel .. ' 个轮子的第 ' .. k .. ' 格，转到它才拿得到' }
end

function Run:skipEngrave() table.remove(self.engraveQueue, 1) end

-- held 里锁住的轮子越多越贵（锁一个 ×2，锁两个 ×3）
function Run:armPrice(held)
    local base = rng.risingPrice(armMod.BASE_PRICE, self.arm and self.arm.spins or 0)
    -- 润滑油（碎片商店）：每层第一次半价
    if self.perks.halfSpin and (self.arm and self.arm.spins or 0) == 0 then base = base / 2 end
    local n = 0
    for r = 1, 3 do if held and held[r] then n = n + 1 end end
    local gold = math.floor(base * armMod.HOLD_MULTIPLIER[math.min(n, 2)] / 5 + 0.5) * 5
    return { gold = gold, blood = rng.bloodPrice(gold) }
end

local function anyHeld(t) return t and (t[1] or t[2] or t[3]) and true or false end
local function allHeld(t) return t[1] and t[2] and t[3] and true or false end

-- 转断臂转轮；held[i] 为 true 的轮子锁住不动（锁得越多越贵）。返回 { ok, msg, faces }
function Run:armSpin(pay, held)
    local arm = self.arm
    if self.status ~= 'playing' or not arm then return { ok = false, msg = '' } end
    if armMod.empty(arm) then return { ok = false, msg = '转轮上还没有刻任何图案' } end
    local hold = anyHeld(held)
    if hold and allHeld(held) then return { ok = false, msg = '要锁住一两个轮子，留至少一个重转' } end
    local price = self:armPrice(held)
    if pay == 'gold' then
        if self.hero.gold < price.gold then return { ok = false, msg = '金币不够（要 ' .. price.gold .. '）' } end
        self.hero.gold = self.hero.gold - price.gold
    else
        if self.hero.hp <= price.blood then return { ok = false, msg = '生命不够（要 ' .. price.blood .. '）' } end
        self.hero.hp = self.hero.hp - price.blood
    end
    local faces = armMod.roll(arm, self.seed, (self.floorIndex - 1) * 1000 + 999, hold and held or nil)
    arm.spins = arm.spins + 1
    local kind, id = armMod.outcome(faces)
    if kind == 'weapon' then
        local same = self.hero.weapon == id
        self:hold(id)
        local name = config.WEAPONS[id].name
        return { ok = true, msg = same and ('三个轮子都停在' .. name .. '上，还是它') or ('三个轮子都停在' .. name .. '上，换成了' .. name), faces = faces }
    elseif kind == 'empty' then
        self:hold(nil)
        return { ok = true, msg = '三个轮子都停在空格上，手里空了', faces = faces }
    end
    return { ok = true, msg = '没有连成一线，手上的武器不变', faces = faces }
end

-- ---------- 设施 ----------

function Run:nextTo(i) return contains(floorMod.neighbors(self.pos, self.w, self.h), i) end

local FACILITY_NAMES = { stall = '补给摊', wheel = '大转盘', pawn = '当铺', altar = '骨坛' }

function Run:checkFacility(i, kind)
    local c = self.cells[i]
    if self.status ~= 'playing' or not c or c.kind ~= kind then return { ok = false, msg = '' } end
    if not self:nextTo(i) then return { ok = false, msg = '站在' .. FACILITY_NAMES[kind] .. '旁边才能用它' } end
    return nil
end

function Run:pay(gold)
    if self.hero.gold < gold then return { ok = false, msg = '金币不够（要 ' .. gold .. '）' } end
    self.hero.gold = self.hero.gold - gold
    return nil
end

function Run:sold(i, k) return self.bought[self.floorIndex .. ':' .. i .. ':' .. k] == true end
function Run:markSold(i, k) self.bought[self.floorIndex .. ':' .. i .. ':' .. k] = true end

function Run.stallText(o)
    if o.id == 'atk' then return '攻击 +' .. o.amount
    elseif o.id == 'def' then return '防御 +' .. o.amount
    elseif o.id == 'hp' then return '生命 +' .. o.amount end
    return '骨钥 ×' .. o.amount
end

-- 补给摊（营火层）：买第 k 样（k 从 1 开始）
function Run:stallBuy(i, k)
    local o = self:floor().stall and self:floor().stall[k]
    local bad = self:checkFacility(i, 'stall') or ((not o) and { ok = false, msg = '' }) or nil
    if bad then return bad end
    if self:sold(i, k) then return { ok = false, msg = '这样已经买过了' } end
    local unpaid = self:pay(o.price)
    if unpaid then return unpaid end
    if o.id == 'atk' then self.hero.atk = self.hero.atk + o.amount
    elseif o.id == 'def' then self.hero.def = self.hero.def + o.amount
    elseif o.id == 'hp' then self.hero.hp = self.hero.hp + o.amount
    else self.hero.keys = self.hero.keys + o.amount end
    self:markSold(i, k)
    return { ok = true, msg = '买下' .. Run.stallText(o) .. '，花了 ' .. o.price .. ' 金币' }
end

function Run:wheelState(i)
    local key = self.floorIndex .. ':' .. i
    if not self.wheels[key] then self.wheels[key] = { spins = 0, draws = 0 } end
    return self.wheels[key]
end

function Run:wheelPrice(i)
    local gold = wheelMod.price(self:wheelState(i).spins)
    return { gold = gold, blood = rng.bloodPrice(gold) }
end

-- 转大转盘：返回 { ok, msg, sector }（sector 从 1 开始）
function Run:wheelSpin(i, pay)
    local bad = self:checkFacility(i, 'wheel')
    if bad then return bad end
    local st = self:wheelState(i)
    local price = self:wheelPrice(i)
    if pay == 'gold' then
        local unpaid = self:pay(price.gold)
        if unpaid then return unpaid end
    else
        if self.hero.hp <= price.blood then return { ok = false, msg = '生命不够（要 ' .. price.blood .. '）' } end
        self.hero.hp = self.hero.hp - price.blood
    end
    local key = (self.floorIndex - 1) * 1000 + (i - 1)
    local n = st.draws
    st.draws = st.draws + 1
    local sector = wheelMod.stop(self.seed, key, n)
    st.spins = st.spins + 1
    local s = wheelMod.SECTORS[sector]
    local msg = '停在「' .. s.text .. '」'
    local h = self.hero
    if s.prize == 'gold' then h.gold = h.gold + s.amount
    elseif s.prize == 'hp' then h.hp = h.hp + s.amount
    elseif s.prize == 'atk' then h.atk = h.atk + s.amount
    elseif s.prize == 'def' then h.def = h.def + s.amount
    elseif s.prize == 'engrave' then
        local all = self.pool
        local w
        if rng.draw(self.seed, key + 700, n) < armMod.WILD_CHANCE then w = armMod.WILD
        else w = all[rng.pick(self.seed, key + 500, n, #all) + 1] end
        if self.arm then
            self.engraveQueue[#self.engraveQueue + 1] = { from = 'wheel', choices = { w } }
            msg = msg .. '：' .. symName(w)
        end
    elseif s.prize == 'leech' then
        h.hp = h.hp - s.amount
        if h.hp <= 0 then
            h.hp = 0
            self.status = 'dead'
            return { ok = true, msg = '你倒下了。井蛭吸干了你最后一点血', sector = sector }
        end
    elseif s.prize == 'erase' then
        local cells = self.arm and armMod.engravedCells(self.arm) or {}
        if #cells == 0 then
            msg = msg .. '：转轮上没有图案，什么也没擦掉'
        else
            local c = cells[rng.pick(self.seed, key + 600, n, #cells) + 1]
            local r, k = c[1], c[2]
            msg = msg .. '：第 ' .. r .. ' 个轮子第 ' .. k .. ' 格的' .. symName(self.arm.reels[r][k]) .. '没了'
            self.arm.reels[r][k] = false
            self:checkHold()
        end
    end
    return { ok = true, msg = msg, sector = sector }
end

-- 当铺：卖一把骨钥
function Run:pawnSellKey(i)
    local bad = self:checkFacility(i, 'pawn')
    if bad then return bad end
    if self.hero.keys <= 0 then return { ok = false, msg = '你没有骨钥' } end
    self.hero.keys = self.hero.keys - 1
    self.hero.gold = self.hero.gold + Run.PAWN.keyPrice
    return { ok = true, msg = '卖了一把骨钥，得 ' .. Run.PAWN.keyPrice .. ' 金币' }
end

-- 当铺：当掉转轮上的一格
function Run:pawnCell(i, reel, cell)
    local bad = self:checkFacility(i, 'pawn')
    if bad then return bad end
    local w = self.arm and self.arm.reels[reel] and self.arm.reels[reel][cell]
    if not w then return { ok = false, msg = '这一格是空的' } end
    self.arm.reels[reel][cell] = false
    self.pawned[#self.pawned + 1] = { weapon = w, reel = reel, floor = self.floorIndex }
    self.hero.gold = self.hero.gold + Run.PAWN.pawnGold
    self:checkHold()
    return { ok = true, msg = '当掉了' .. symName(w) .. '，得 ' .. Run.PAWN.pawnGold .. ' 金币' }
end

-- 赎回当掉的第 j 件现在要多少钱（每过一层涨 20%）
function Run:redeemPrice(j)
    local p = self.pawned[j]
    return math.ceil(Run.PAWN.pawnGold * Run.PAWN.redeemRate ^ (self.floorIndex - p.floor))
end

-- 赎回当掉的第 j 件，刻回原来那个轮子（刻满时指定格子）
function Run:pawnRedeem(i, j, cell)
    local bad = self:checkFacility(i, 'pawn')
    if bad then return bad end
    local p = self.pawned[j]
    if not p or not self.arm then return { ok = false, msg = '' } end
    local full = self:fullReel(p.reel, cell)
    if full then return full end
    local unpaid = self:pay(self:redeemPrice(j))
    if unpaid then return unpaid end
    armMod.engraveCell(self.arm, p.reel, p.weapon, cell)
    table.remove(self.pawned, j)
    self:checkHold()
    return { ok = true, msg = '赎回了' .. symName(p.weapon) }
end

-- 当铺：买第 k 个武器图案刻到第 reel 个轮子上（k 从 1 开始）
function Run:pawnBuy(i, k, reel, cell)
    local bad = self:checkFacility(i, 'pawn')
    if bad then return bad end
    local w = self:floor().shop and self:floor().shop[k]
    if not w or not self.arm then return { ok = false, msg = '' } end
    if self:sold(i, k) then return { ok = false, msg = '这样已经买过了' } end
    local full = self:fullReel(reel, cell)
    if full then return full end
    local price = self:shopPrice(w)
    local unpaid = self:pay(price)
    if unpaid then return unpaid end
    armMod.engraveCell(self.arm, reel, w, cell)
    self:markSold(i, k)
    self:checkHold()
    return { ok = true, msg = '花 ' .. price .. ' 金币刻上了' .. symName(w) }
end

-- 当铺里一件图案的价格（赖子贵得多）
function Run:shopPrice(w)
    return w == armMod.WILD and armMod.WILD_PRICE or Run.PAWN.buyPrice
end

function Run:pawnErase(i, reel, cell)
    local bad = self:checkFacility(i, 'pawn')
    if bad then return bad end
    local w = self.arm and self.arm.reels[reel] and self.arm.reels[reel][cell]
    if not w then return { ok = false, msg = '这一格是空的' } end
    local unpaid = self:pay(Run.PAWN.erasePrice)
    if unpaid then return unpaid end
    self.arm.reels[reel][cell] = false
    self:checkHold()
    return { ok = true, msg = '擦掉了第 ' .. reel .. ' 个轮子第 ' .. cell .. ' 格的' .. symName(w) }
end

-- 骨坛：献 3 点攻击或 1 把骨钥，把一种特性移到转轮上的一把武器上（每座用一次）
function Run:altarOffer(i, pay, boon, weapon)
    local bad = self:checkFacility(i, 'altar')
    if bad then return bad end
    local key = self.floorIndex .. ':' .. i
    if contains(self.altarUsed, key) then return { ok = false, msg = '这座骨坛已经用过了' } end
    if not contains(self.boonsSeen, boon) then return { ok = false, msg = '这一局还没杀过带「' .. config.BOON_NAMES[boon] .. '」的怪' } end
    if not self.arm or not armMod.has(self.arm, weapon) then return { ok = false, msg = '转轮上没有这把武器' } end
    local list = self.arm.boons[weapon] or {}
    self.arm.boons[weapon] = list
    if contains(list, boon) then return { ok = false, msg = config.WEAPONS[weapon].name .. '已经有「' .. config.BOON_NAMES[boon] .. '」了' } end
    if pay == 'key' then
        if self.hero.keys <= 0 then return { ok = false, msg = '你没有骨钥' } end
        self.hero.keys = self.hero.keys - 1
    else
        self.hero.atk = self.hero.atk - Run.ALTAR_ATK_COST
    end
    list[#list + 1] = boon
    self.altarUsed[#self.altarUsed + 1] = key
    if self.hero.weapon == weapon then self:hold(weapon) end
    return { ok = true, msg = config.WEAPONS[weapon].name .. '得到了「' .. config.BOON_NAMES[boon] .. '」' }
end

-- ---------- 诏令 ----------

function Run:acceptDecree()
    if not self.decreeOffer then return { ok = false, msg = '' } end
    self.decree = { def = self.decreeOffer, ['until'] = self.floorIndex + decreeMod.SPAN - 1, progress = 0 }
    self.decreeOffer = nil
    return { ok = true, msg = '接下' .. decreeMod.TIER_NAMES[self.decree.def.tier] .. '诏令：' .. self.decree.def.text }
end

function Run:refuseDecree() self.decreeOffer = nil end

function Run:completeDecree()
    local d = self.decree
    self.engraveQueue[#self.engraveQueue + 1] = { from = 'decree', choices = self:rollWeaponChoices(1) }
    if d.def.tier == 'silver' then self.hero.hp = self.hero.hp + decreeMod.SILVER_BONUS_HP end
    self.notes[#self.notes + 1] = '诏令完成：' .. d.def.text .. '。' .. (d.def.tier == 'silver' and ('生命 +' .. decreeMod.SILVER_BONUS_HP .. '，') or '') .. '可以刻一把武器'
    self.decree = nil
end

function Run:settleDecree()
    local d = self.decree
    if not d then return end
    local def = d.def
    local met = (def.kind == 'noPotion' and not self.drank)
        or (def.kind == 'clear' and self:monstersLeft() == 0)
        or (def.kind == 'noLoss' and self.hero.hp >= self.floorStart.hero.hp)
        or (def.kind == 'gold' and self.hero.gold >= def.n)
    if met then self:completeDecree(); return end
    if self.floorIndex >= d['until'] then
        local lose = decreeMod.PENALTY[def.tier]
        self.hero.atk = self.hero.atk - lose
        self.notes[#self.notes + 1] = '诏令逾期：' .. def.text .. '。攻击 −' .. lose
        self.decree = nil
    end
end

-- ---------- 移动和交互 ----------

-- 往相邻格子走一步（或和它交互）。打败怪物后站到它的格子上。返回 { ok, msg }
function Run:step(i)
    if self.status ~= 'playing' then return { ok = false, msg = '' } end
    if not contains(floorMod.neighbors(self.pos, self.w, self.h), i) then return { ok = false, msg = '' } end
    local c = self.cells[i]
    if c.kind == 'wall' then return { ok = false, msg = '' } end
    if floorMod.isFacility(c) then return { ok = false, msg = '站在旁边才能用它' } end
    if c.kind == 'exit' and self:eliteAlive() then return { ok = false, msg = '精英守卫还活着，出口被封住了' } end

    if c.kind == 'floor' or c.kind == 'exit' then
        self.pos = i
        self.steps = self.steps + 1
        if c.kind == 'exit' then self.status = 'floorDone'; self.exitTaken = c.to end
        return { ok = true, msg = '' }
    end

    local r = rules.interact(c, self.hero, self:floor(), self.ch, true, c.kind == 'monster' and self:monsterAt(i) or nil)
    if not r.ok then return { ok = false, msg = r.reason } end
    if rules.isPotion(c) then self.drank = true end
    if r.fatal and self.ch.revive and not self.revived then
        -- 溺者：倒下时复活一次，怪还在
        self.revived = true
        self.hero.hp = self.ch.revive
        self.steps = self.steps + 1
        return { ok = true, msg = '你倒下了……又从水里爬了起来，生命 ' .. self.ch.revive .. '。之后每进一层扣 ' .. (self.ch.drain or 0) .. ' 生命' }
    end
    if r.fatal then
        self.hero = r.hero
        self.steps = self.steps + 1
        self.status = 'dead'
        return { ok = true, msg = '你倒下了。' .. r.reason }
    end
    local lost = self.hero.hp - r.hero.hp
    self.hero = r.hero
    self.steps = self.steps + 1
    local msg
    if c.kind == 'monster' then
        self.kills = self.kills + 1
        local m = config.MONSTERS[c.id]
        msg = '击败' .. m.name .. '，' .. (lost >= 0 and ('损失 ' .. lost) or ('回复 ' .. -lost)) .. ' 生命，获得 ' .. m.gold .. ' 金币'
        local boon = config.MONSTER_BOON[c.id]
        if boon and not contains(self.boonsSeen, boon) then self.boonsSeen[#self.boonsSeen + 1] = boon end
        if self.arm then
            if m.elite and self:floor().eliteReward then
                self.engraveQueue[#self.engraveQueue + 1] = { from = 'elite', choices = self:rollWeaponChoices() }
            end
            if contains(self:floor().marks, i) and config.MARK_WEAPON[c.id] then
                self.engraveQueue[#self.engraveQueue + 1] = { from = 'mark', choices = { config.MARK_WEAPON[c.id] } }
            end
        end
        if self.decree and decreeMod.killCounts(self.decree.def, m) then
            self.decree.progress = self.decree.progress + 1
            if self.decree.progress >= self.decree.def.n then self:completeDecree() end
        end
    else
        if c.kind == 'item' then msg = '获得' .. config.ITEM_NAMES[c.id]
        elseif c.door == 'bone' then msg = '打开骨门'
        else msg = '穿过血门，损失 ' .. lost .. ' 生命' end
    end
    self.pos = i
    self.cells[i] = { kind = 'floor' }
    return { ok = true, msg = msg }
end

-- 只经过空地的最短路线；返回从下一格到目标的格子列表（找不到返回 nil）
function Run:findPath(target)
    local prev = { [self.pos] = -1 }
    local queue, head = { self.pos }, 1
    while head <= #queue do
        local cur = queue[head]
        head = head + 1
        for _, n in ipairs(floorMod.neighbors(cur, self.w, self.h)) do
            if prev[n] == nil then
                if n == target then
                    local path = { n }
                    local p = cur
                    while p ~= self.pos do
                        table.insert(path, 1, p)
                        p = prev[p]
                    end
                    return path
                end
                if self.cells[n].kind == 'floor' then
                    prev[n] = cur
                    queue[#queue + 1] = n
                end
            end
        end
    end
    return nil
end

function Run:tapCell(target)
    if self.status ~= 'playing' or target == self.pos then return { ok = false, msg = '' } end
    local path = self:findPath(target)
    if not path then return { ok = false, msg = '走不过去' } end
    local last = { ok = true, msg = '' }
    for _, cell in ipairs(path) do
        last = self:step(cell)
        if not last.ok then break end
    end
    return last
end

-- 方向键移动一步
function Run:move(dx, dy)
    local x = (self.pos - 1) % self.w + dx
    local y = math.floor((self.pos - 1) / self.w) + dy
    if x < 0 or y < 0 or x >= self.w or y >= self.h then return { ok = false, msg = '' } end
    return self:step(y * self.w + x + 1)
end

-- ---------- 战斗预览和格子信息 ----------

function Run:monsterAt(i)
    local c = self.cells[i]
    assert(c.kind == 'monster', '不是怪物')
    return config.monsterInContext(config.MONSTERS[c.id], floorMod.adjacentMonsters(self.cells, self.w, self.h, i), self:floor().power)
end

function Run:marked(i)
    return self.arm ~= nil and contains(self:floor().marks, i) and self.cells[i].kind == 'monster'
end

function Run:preview(i)
    local c = self.cells[i]
    if c.kind ~= 'monster' then return nil end
    return combat.simulate(self.hero, self:monsterAt(i))
end

-- ---------- 出口 ----------

function Run:exitSummary()
    local leftover = 0
    for _, c in ipairs(self.cells) do if rules.isPotion(c) then leftover = leftover + 1 end end
    return {
        leftoverPotions = leftover,
        potionGold = leftover * config.EXIT.leftoverPotionGold,
        keys = self.hero.keys,
        keyGold = self.hero.keys * config.EXIT.keySellGold,
    }
end

function Run:rentDue()
    local f = self:floor()
    if f.rent and not self.rentPaid then return f.rent end
    return 0
end

-- method：'gold' | 'atk' | 'def'
function Run:payRent(method)
    local due = self:rentDue()
    if due == 0 then return { ok = true, msg = '' } end
    if method == 'gold' then
        if self.hero.gold < due then return { ok = false, msg = '金币不够' } end
        self.hero.gold = self.hero.gold - due
    elseif method == 'atk' then self.hero.atk = self.hero.atk - Run.RENT_STAT_COST
    else self.hero.def = self.hero.def - Run.RENT_STAT_COST end
    self.rentPaid = true
    return { ok = true, msg = '' }
end

-- 结算后进入下一层；下一层有两个候选时，走的是哪个出口就去哪个（'>' 第一个，'<' 第二个）
function Run:finishFloor(sellKeys)
    local choice = (self.exitTaken or 0) + 1
    if self.status ~= 'floorDone' then return end
    if self:rentDue() > 0 then return end
    local s = self:exitSummary()
    self.hero.gold = self.hero.gold + s.potionGold
    if sellKeys then
        self.hero.gold = self.hero.gold + s.keyGold
        self.hero.keys = 0
    end
    self:settleDecree()
    self.totalSteps = self.totalSteps + self.steps
    if self.floorIndex >= #self.plan then self.status = 'finished'; return end
    local opts = self.plan[self.floorIndex + 1]
    self.picks[self.floorIndex + 1] = math.max(1, math.min(#opts, choice))
    self:loadFloor(self.floorIndex + 1)
end

-- ---------- 存档 ----------

function Run:save()
    return {
        characterId = self.ch.id, seed = self.seed, tutorial = self.tutorial, picks = self.picks,
        floorIndex = self.floorIndex, current = self:snapshot(), floorStart = self.floorStart,
        totalSteps = self.totalSteps, status = self.status, rentPaid = self.rentPaid,
        arm = self.arm, wheels = self.wheels, pawned = self.pawned, bought = self.bought,
        altarUsed = self.altarUsed, boonsSeen = self.boonsSeen, decree = self.decree,
        decreeOffer = self.decreeOffer, engraveQueue = self.engraveQueue, drank = self.drank,
        exitTaken = self.exitTaken, pool = self.pool, perks = self.perks, revived = self.revived,
    }
end

function Run.load(plan, s)
    local run = Run.new(plan, s.characterId, s.seed, { tutorial = s.tutorial })
    run.picks = {}
    for k, v in pairs(s.picks) do run.picks[k] = v end
    run:loadFloor(s.floorIndex)
    run.floorStart = s.floorStart
    run:restore(s.current)
    run.totalSteps = s.totalSteps
    run.status = s.status
    run.rentPaid = s.rentPaid or false
    run.arm = s.arm
    run.wheels = s.wheels or {}
    run.pawned = s.pawned or {}
    run.bought = s.bought or {}
    run.altarUsed = s.altarUsed or {}
    run.boonsSeen = s.boonsSeen or {}
    run.decree = s.decree
    run.decreeOffer = s.decreeOffer
    run.engraveQueue = s.engraveQueue or {}
    run.drank = s.drank or false
    run.exitTaken = s.exitTaken or 0
    if s.pool then run.pool = {}; for i, w in ipairs(s.pool) do run.pool[i] = w end end
    run.perks = s.perks or {}
    run.revived = s.revived or false
    return run
end

return Run
