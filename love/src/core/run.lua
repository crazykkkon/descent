-- 一局游戏的状态和操作：移动、交互、契约、出口结算、存档。
-- 和 TypeScript 原型 src/core/game.ts 的 Run 一致（含井中轮、井租、精英武器三选一）。
-- 没有撤回、没有重开本层：死了就整局重来。

local config = require('core.config')
local combat = require('core.combat')
local floorMod = require('core.floor')
local rules = require('core.rules')
local contract = require('core.contract')
local slot = require('core.slot')

local Run = {}
Run.__index = Run

local function copyCells(cells)
    local t = {}
    for i, c in ipairs(cells) do t[i] = floorMod.copyCell(c) end
    return t
end

local function contains(list, v)
    for _, x in ipairs(list) do if x == v then return true end end
    return false
end

-- floors：楼层定义列表（1 开始）；seed：本局随机种子
function Run.new(floors, characterId, seed)
    local self = setmetatable({}, Run)
    self.floors = floors
    self.ch = config.CHARACTERS[characterId or 'digger']
    self.hero = config.copyHero(self.ch.base)
    self.seed = slot.u32(seed or 1)
    self.slots = {}           -- 井中轮状态，键是 '层:格子'
    self.pendingWeapons = nil -- 精英倒下后等着三选一的武器
    self.stallBought = {}     -- 补给摊上买过的货，键是 '层:第几样'（原型的层号从 0 开始）
    self.totalSteps = 0
    self.contract = nil -- { def, floorIndex, broken }
    self:loadFloor(1)
    return self
end

function Run:floor() return self.floors[self.floorIndex] end

function Run:loadFloor(i)
    self.floorIndex = i
    local p = floorMod.parse(self.floors[i])
    self.w, self.h, self.cells, self.pos = p.w, p.h, p.cells, p.start
    self.steps = 0
    self.kills = 0
    self.status = 'playing'
    self.rentPaid = false
    self.floorStart = self:snapshot()
end

function Run:snapshot()
    return { hero = config.copyHero(self.hero), cells = copyCells(self.cells), pos = self.pos, steps = self.steps, kills = self.kills }
end

function Run:restore(s)
    self.hero = config.copyHero(s.hero)
    self.cells = copyCells(s.cells)
    self.pos, self.steps, self.kills = s.pos, s.steps, s.kills
    self.status = 'playing'
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

-- ---------- 契约 ----------

-- 楼梯口挂出的契约（作用在下一层）
function Run:offeredContract()
    local nf = self.floors[self.floorIndex + 1]
    return nf and nf.contract or nil
end

-- 本层的契约是否还在守约中
function Run:contractActive()
    local c = self.contract
    return c ~= nil and c.floorIndex == self.floorIndex and not c.broken
end

-- ---------- 武器 ----------

-- 换上新武器；旧武器当场卖掉换金币
function Run:equip(id)
    local old = self.hero.weapon
    self.hero.weapon = id
    if old and old ~= id then
        local w = config.WEAPONS[old]
        self.hero.gold = self.hero.gold + w.sell
        return '换上' .. config.WEAPONS[id].name .. '，旧的' .. w.name .. '卖了 ' .. w.sell .. ' 金币'
    end
    return '拿到' .. config.WEAPONS[id].name
end

-- 和原型逐位相同的三选一（原型的层号从 0 开始）
function Run:rollWeaponChoices()
    local pool = {}
    for _, w in ipairs(config.WEAPON_ORDER) do if w ~= self.hero.weapon then pool[#pool + 1] = w end end
    local out, n = {}, 0
    while #out < 3 and #out < #pool do
        n = n + 1
        local x = slot.imul(slot.bxor(self.seed, (self.floorIndex - 1) * 7919 + n * 104729), 2654435761)
        local w = pool[x % #pool + 1]
        if not contains(out, w) then out[#out + 1] = w end
    end
    return out
end

function Run:chooseWeapon(id)
    if not self.pendingWeapons or not contains(self.pendingWeapons, id) then return '' end
    self.pendingWeapons = nil
    return self:equip(id)
end

-- ---------- 井中轮 ----------

function Run:slotState(i)
    local key = self.floorIndex .. ':' .. i
    if not self.slots[key] then self.slots[key] = slot.newState() end
    return self.slots[key]
end

-- 下一次转的价格；hold：锁轴重转（半价）
function Run:slotPrice(i, hold)
    local base = slot.spinPrice(self:slotState(i).spins)
    local gold = hold and slot.holdPrice(base) or base
    return { gold = gold, blood = slot.bloodPrice(gold) }
end

local function any(t) for i = 1, 3 do if t[i] then return true end end return false end
local function all(t) for i = 1, 3 do if not t[i] then return false end end return true end

-- 转一次。held 不为空时是锁轴重转：放弃当前结果，锁住的转轮不变，其余重转。
-- 不锁轴时如果机器上还有没收下的结果，先自动收下。返回 { ok, msg, result, fresh, bite }
function Run:slotSpin(i, pay, held)
    local c = self.cells[i]
    if self.status ~= 'playing' or not c or c.kind ~= 'slot' then return { ok = false, msg = '' } end
    if not contains(floorMod.neighbors(self.pos, self.w, self.h), i) then return { ok = false, msg = '站在井中轮旁边才能用它' } end
    local st = self:slotState(i)
    local hold = held ~= nil and any(held)
    if hold and (not st.pending or all(held)) then return { ok = false, msg = '要锁住一两个转轮，留至少一个重转' } end
    if not hold and st.pending then self:slotCollect(i) end
    local price = self:slotPrice(i, hold)
    if pay == 'gold' then
        if self.hero.gold < price.gold then return { ok = false, msg = '金币不够（要 ' .. price.gold .. '）' } end
        self.hero.gold = self.hero.gold - price.gold
    else
        if self.hero.hp <= price.blood then return { ok = false, msg = '生命不够押（要 ' .. price.blood .. '）' } end
        self.hero.hp = self.hero.hp - price.blood
    end
    local result, fresh = slot.roll(slot.SLOTS[c.id], st, self.seed, (self.floorIndex - 1) * 1000 + (i - 1), hold and held or nil)
    st.spins = st.spins + 1
    st.pending = result
    local bite = slot.leechBite(result, fresh)
    self.hero.hp = self.hero.hp - bite
    if self.hero.hp <= 0 then
        self.hero.hp = 0
        self.status = 'dead'
        return { ok = true, msg = '你倒下了。井蛭吸干了你最后一点血', result = result, fresh = fresh, bite = bite }
    end
    return { ok = true, msg = bite > 0 and ('井蛭咬掉了 ' .. bite .. ' 生命') or '', result = result, fresh = fresh, bite = bite }
end

-- 收下机器上当前的结果；返回说明文字列表
function Run:slotCollect(i)
    local c = self.cells[i]
    local st = self:slotState(i)
    if not c or c.kind ~= 'slot' or not st.pending then return {} end
    local p = slot.payout(st.pending)
    st.pending = nil
    local lines = {}
    for k, l in ipairs(p.lines) do lines[k] = l end
    if p.gems > 0 then self.hero.atk = self.hero.atk + p.gems * (self:floor().gem + self.ch.gemBonus) end
    self.hero.hp = self.hero.hp + p.hp
    self.hero.gold = self.hero.gold + p.gold
    if p.weapon then lines[#lines + 1] = self:equip(p.weapon) end
    return lines
end

-- ---------- 补给摊 ----------

function Run.stallText(o)
    if o.id == 'atk' then return '攻击 +' .. o.amount
    elseif o.id == 'def' then return '防御 +' .. o.amount
    elseif o.id == 'hp' then return '生命 +' .. o.amount end
    return '骨钥 ×' .. o.amount
end

function Run:stallSold(k)
    return self.stallBought[(self.floorIndex - 1) .. ':' .. (k - 1)] == true
end

-- 在第 i 格的补给摊买第 k 样货（k 从 1 开始）
function Run:stallBuy(i, k)
    local c = self.cells[i]
    local o = self:floor().stall and self:floor().stall[k]
    if self.status ~= 'playing' or not c or c.kind ~= 'stall' or not o then return { ok = false, msg = '' } end
    if not contains(floorMod.neighbors(self.pos, self.w, self.h), i) then return { ok = false, msg = '站在补给摊旁边才能买东西' } end
    if self:stallSold(k) then return { ok = false, msg = '这样已经买过了' } end
    if self.hero.gold < o.price then return { ok = false, msg = '金币不够（要 ' .. o.price .. '）' } end
    self.hero.gold = self.hero.gold - o.price
    if o.id == 'atk' then self.hero.atk = self.hero.atk + o.amount
    elseif o.id == 'def' then self.hero.def = self.hero.def + o.amount
    elseif o.id == 'hp' then self.hero.hp = self.hero.hp + o.amount
    else self.hero.keys = self.hero.keys + o.amount end
    self.stallBought[(self.floorIndex - 1) .. ':' .. (k - 1)] = true
    return { ok = true, msg = '买下' .. Run.stallText(o) .. '，花了 ' .. o.price .. ' 金币' }
end

-- ---------- 移动和交互 ----------

-- 往相邻格子走一步（或和它交互）。返回 { ok, msg }
function Run:step(i)
    if self.status ~= 'playing' then return { ok = false, msg = '' } end
    if not contains(floorMod.neighbors(self.pos, self.w, self.h), i) then return { ok = false, msg = '' } end
    local c = self.cells[i]
    if c.kind == 'wall' then return { ok = false, msg = '' } end
    if c.kind == 'slot' then return { ok = false, msg = '站在井中轮旁边才能用它' } end
    if c.kind == 'stall' then return { ok = false, msg = '站在补给摊旁边才能买东西' } end
    if c.kind == 'exit' and self:eliteAlive() then return { ok = false, msg = '精英守卫还活着，出口被封住了' } end

    if c.kind == 'floor' or c.kind == 'exit' then
        self.pos = i
        self.steps = self.steps + 1
        if c.kind == 'exit' then self.status = 'floorDone' end
        return { ok = true, msg = '' }
    end

    local r = rules.interact(c, self.hero, self:floor(), self.ch, true, c.kind == 'monster' and self:monsterAt(i) or nil)
    if not r.ok then return { ok = false, msg = r.reason } end
    -- 喝下血瓶的那一刻就毁约
    local breaks = rules.isPotion(c) and self:contractActive()
    if breaks then self.contract.broken = true end
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
        msg = '击败' .. m.name .. '，损失 ' .. lost .. ' 生命，获得 ' .. m.gold .. ' 金币'
        -- 精英倒下：三选一拿武器
        if m.elite and self:floor().eliteReward then self.pendingWeapons = self:rollWeaponChoices() end
    else
        self.pos = i
        if c.kind == 'item' then msg = '获得' .. config.ITEM_NAMES[c.id]
        elseif c.door == 'bone' then msg = '打开骨门'
        else msg = '穿过血门，损失 ' .. lost .. ' 生命' end
        if breaks then msg = msg .. '。契约已毁：押下的 ' .. self.contract.def.deposit .. ' 生命归井了' end
    end
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

-- 走到目标格子（目标是怪物 / 道具 / 门 / 出口时，最后一步和它交互）
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

-- ---------- 战斗预览和格子信息 ----------

-- 第 i 格怪物这一刻的真实属性（算上相邻的井鼠、骸骨祭司）
function Run:monsterAt(i)
    local c = self.cells[i]
    assert(c.kind == 'monster', '不是怪物')
    return config.monsterInContext(config.MONSTERS[c.id], floorMod.adjacentMonsters(self.cells, self.w, self.h, i))
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
    local ct = nil
    if self.contract and self.contract.floorIndex == self.floorIndex then
        ct = { def = self.contract.def, kept = not self.contract.broken }
    end
    return {
        contract = ct,
        leftoverPotions = leftover,
        potionGold = leftover * config.EXIT.leftoverPotionGold,
        keys = self.hero.keys,
        keyGold = self.hero.keys * config.EXIT.keySellGold,
    }
end

-- 本层出口要交的井租（交过了就是 0）
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
    elseif method == 'atk' then self.hero.atk = self.hero.atk - 3
    else self.hero.def = self.hero.def - 3 end
    self.rentPaid = true
    return { ok = true, msg = '' }
end

-- 结算后进入下一层；sign：签下楼梯口挂出的契约（作用在下一层）
function Run:finishFloor(sellKeys, sign)
    if self.status ~= 'floorDone' then return end
    if self:rentDue() > 0 then return end
    local s = self:exitSummary()
    self.hero.gold = self.hero.gold + s.potionGold
    if s.contract then
        if s.contract.kept then
            self.hero.hp = self.hero.hp + s.contract.def.refund
            self.hero.gold = self.hero.gold + (s.contract.def.gold or 0)
        end
        self.contract = nil
    end
    local offer = self:offeredContract()
    if sign and offer and self.hero.hp > contract.depositFor(offer, self.hero) then
        local deposit = contract.depositFor(offer, self.hero)
        self.hero.hp = self.hero.hp - deposit
        self.hero.atk = self.hero.atk + (offer.atk or 0)
        self.hero.def = self.hero.def + (offer.def or 0)
        local def = {}
        for k, v in pairs(offer) do def[k] = v end
        def.deposit = deposit
        self.contract = { def = def, floorIndex = self.floorIndex + 1, broken = false }
    end
    if sellKeys then
        self.hero.gold = self.hero.gold + s.keyGold
        self.hero.keys = 0
    end
    self.totalSteps = self.totalSteps + self.steps
    if self.floorIndex >= #self.floors then self.status = 'finished'
    else self:loadFloor(self.floorIndex + 1) end
end

-- ---------- 存档 ----------

function Run:save()
    return {
        characterId = self.ch.id,
        floorIndex = self.floorIndex,
        current = self:snapshot(),
        floorStart = self.floorStart,
        totalSteps = self.totalSteps,
        status = self.status,
        contract = self.contract,
        seed = self.seed,
        rentPaid = self.rentPaid,
        slots = self.slots,
        pendingWeapons = self.pendingWeapons,
        stallBought = self.stallBought,
    }
end

function Run.load(floors, s)
    local run = Run.new(floors, s.characterId, s.seed)
    run:loadFloor(s.floorIndex)
    run.floorStart = s.floorStart
    run:restore(s.current)
    run.totalSteps = s.totalSteps
    run.status = s.status
    run.contract = s.contract
    run.rentPaid = s.rentPaid or false
    run.slots = s.slots or {}
    run.pendingWeapons = s.pendingWeapons
    run.stallBought = s.stallBought or {}
    return run
end

return Run
