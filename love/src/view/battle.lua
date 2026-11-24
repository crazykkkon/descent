-- 魔塔式战斗窗口（制作人 2026-11-24 定：每场都弹，画面中间一个战斗窗口，两边一来一回地打，血实时往下掉）。
-- 规则在 core/combat.lua 里已经算完了（combat.simulate 的 log 记了每一下），这里只负责"演"出来：
--   矿工和怪物站在同一块场地上（制作人：不要 VS，要真的打到对方身上），两条大血条和血量数字一下下往下掉；
--   矿工冲到怪身上挥武器（空手就是一拳）；怪按种类出手：扑咬 / 冲撞 / 钳夹，或者喷口水、吐舌头、声波、鬼火、骨刺、光束；
--   挨打的一方闪白（怪）/ 闪红（矿工）、往后一退、窗口震一下；
--   伤害数字大字弹出，先手 / 连击 / 破甲 / 克制 / 腐蚀 / 反伤 / 吸血用不同颜色；
--   打死时顿住一下，怪的头像碎掉；打不过时矿工被一点点耗死。
-- 打完窗口关上，地图上方再出"算准了 / 千钧一发 / 无伤 / 连杀"的大字。
-- 白盒阶段全部是程序画的，正式美术由 Codex 替换，接口不变。

local fx = require('view.fx')

local M = {}

local SLOT = 0.34          -- 一下的时长（正常速度）：冲过去、打中、退回来
local MAX_TOTAL = 3.0      -- 一场最长多久（下数多就把每一下压短）
local HIT = 0.5            -- 一下里打中的时刻（占这一下的比例）
local HITSTOP = 0.18       -- 打死 / 倒下那一下顿住多久
local OPEN, CLOSE, HOLD = 0.16, 0.18, 0.45   -- 窗口打开、关上、打完停一下看结果
local LONG, HEAD, TAIL = 16, 8, 6   -- 超过 LONG 下的长仗：演开头 HEAD 下，中间快进一下，再演最后 TAIL 下
local SKIP_SLOTS = 3                -- 快进那一下占几个"一下"的时长

-- 窗口位置（逻辑坐标 640×360）
local WX, WY, WW, WH = 100, 58, 440, 236
local HERO_CX, MON_CX, FEET = WX + 112, WX + WW - 112, WY + 150
local MON_SCALE = 4
-- 矿工素材（侧面）上：前手的位置、身体前沿（相对脚底中心，逻辑像素，按 96 高算）
local HAND_X, HAND_Y, HERO_FRONT = 16, -33, 26
local WEAPON_SCALE = 1.7

local fight = nil
local popups, parts, slashes, banners = {}, {}, {}, {}

local WEAPON_FX = {
    none = { 'slash', { 0.95, 0.93, 0.88 } },
    boneKnife = { 'slash', { 0.98, 0.95, 0.85 } },
    harpoon = { 'thrust', { 0.65, 0.85, 1.0 } },
    hammer = { 'smash', { 1.0, 0.65, 0.3 } },
    mossBlade = { 'slash', { 0.55, 0.95, 0.6 } },
    bellStaff = { 'smash', { 0.95, 0.85, 0.5 } },
    saltDagger = { 'thrust', { 0.85, 0.95, 1.0 } },
    rustSword = { 'slash', { 0.95, 0.5, 0.35 } },
    wellHook = { 'slash', { 0.95, 0.8, 0.4 } },
    lamp = { 'smash', { 1.0, 0.9, 0.55 } },
    twinHook = { 'slash', { 0.85, 0.75, 1.0 } },
}
-- 怪物怎么出手：近身（扑咬 bite / 冲撞 charge / 钳夹 claw）冲到矿工身上；远程（口水 spit / 舌头 tongue /
-- 声波 wave / 鬼火 wisp / 骨刺 bolt / 光束 beam）站在原地放出来，飞到矿工身上那一刻算打中
local MON_STYLE = {
    moss = { 'spit', { 0.55, 0.85, 0.3 } }, thornMoss = { 'spit', { 0.62, 0.9, 0.25 } },
    slug = { 'spit', { 0.88, 0.92, 0.35 } },
    eel = { 'bite' }, spikeEel = { 'bite' }, rat = { 'bite' },
    frog = { 'tongue', { 0.92, 0.45, 0.52 } }, armorFrog = { 'tongue', { 0.86, 0.4, 0.46 } },
    beetle = { 'charge' }, ironBeetle = { 'charge' }, guardian = { 'charge' }, gatekeeper = { 'charge' },
    bat = { 'wave', { 0.7, 0.85, 1.0 } }, shriekBat = { 'wave', { 0.85, 0.7, 1.0 } },
    wraith = { 'wisp', { 0.55, 0.5, 1.0 } }, grudgeWraith = { 'wisp', { 0.8, 0.4, 0.95 } },
    crab = { 'claw' }, shardCrab = { 'claw' },
    priest = { 'bolt', { 0.95, 0.92, 0.8 } },
    eye = { 'beam', { 1.0, 0.25, 0.2 } },
}
local RANGED = { spit = true, tongue = true, wave = true, wisp = true, bolt = true, beam = true }
local function styleOf(id) return MON_STYLE[id] or { 'bite' } end

-- 矿工手上拿的东西：形状和长度（空手就是拳头）
local WEAPON_SHAPE = {
    none = 'fist', boneKnife = 'blade', mossBlade = 'blade', saltDagger = 'blade', rustSword = 'blade',
    harpoon = 'spear', hammer = 'hammer', bellStaff = 'hammer', lamp = 'hammer', wellHook = 'hook', twinHook = 'hook',
}
-- 打中那一刻，武器（拳头）伸出身体前沿多远：主角冲到正好用它打到怪身上
local REACH = { fist = 20, blade = 20, spear = 44, hammer = 20, hook = 20 }

local TAG_FX = {
    first = { '先手！', { 1.0, 0.85, 0.35 } },
    double = { '连击', { 1.0, 0.55, 0.4 } },
    pierce = { '破甲', { 1.0, 0.6, 0.25 } },
    anti = { '克制 ×2', { 0.45, 0.9, 1.0 } },
    corrode = { '腐蚀', { 0.6, 0.95, 0.3 } },
}
local C_MON_LOSS = { 1.0, 0.97, 0.9 }
local C_HERO_LOSS = { 1.0, 0.35, 0.4 }
local C_HEAL = { 0.45, 1.0, 0.55 }
local C_THORNS = { 0.8, 0.45, 1.0 }
local C_LIFESTEAL = { 0.95, 0.2, 0.35 }

local function popup(text, x, y, color, size, w)
    popups[#popups + 1] = { text = text, x = x, y = y, t = 0, color = color, size = size or 14, life = 0.9, w = w or 100 }
end
local function burst(x, y, color, n, speed)
    for _ = 1, n do
        local a = love.math.random() * math.pi * 2
        local v = speed * (0.4 + love.math.random() * 0.8)
        parts[#parts + 1] = { x = x, y = y, vx = math.cos(a) * v, vy = math.sin(a) * v - 30, t = 0, life = 0.4 + love.math.random() * 0.35, color = color, size = 1 + love.math.random(0, 3) }
    end
end

-- 开始一场。o = { log, heroHp, monHp, weapon, hero = { name, line }, mon = { id, name, line, traits }, speed, dies, onDone }
-- log 里每一下：{ who, hit, mhp, loss, tags }（tags 多一个 'dead'：矿工在这一下倒下）
-- 长仗（比如高血量被一点点耗死）：中间那段并成一条快进，血条一口气滑过去，最后几下照常演，矿工在最后倒下
local function compress(log)
    if #log <= LONG then return log end
    local out = {}
    for k = 1, HEAD do out[#out + 1] = log[k] end
    local loss, rounds, last = 0, 0, nil
    for k = HEAD + 1, #log - TAIL do
        local e = log[k]
        loss = loss + e.loss
        if e.who == 'hero' then rounds = rounds + 1 end
        last = e
    end
    out[#out + 1] = { who = 'skip', hit = 0, mhp = last.mhp, loss = loss, rounds = rounds, tags = {} }
    for k = #log - TAIL + 1, #log do out[#out + 1] = log[k] end
    return out
end

function M.start(o)
    o.log = compress(o.log)
    local n = math.max(1, #o.log + SKIP_SLOTS - 1)
    local slot = math.min(SLOT, MAX_TOTAL / n) / (o.speed or 1)
    fight = { o = o, log = o.log, i = 0, t = 0, slot = slot, stop = 0, phase = 'open', pt = 0,
        hhp = o.heroHp, hshow = o.heroHp, hmax = math.max(o.heroHp, 1), mhp = o.monHp, mshow = o.monHp, mmax = math.max(o.monHp, 1), round = 0,
        heroFlash = 0, monFlash = 0, shake = 0, monDead = false, heroDead = false,
        monFront = MON_CX - (o.monW or 40) * MON_SCALE / 4 }
    fx.play('lever', 0.7)
end

-- 自动测试用：停在某一下的某一刻（p = 0～1），截图看动作
function M.pose(o, who, p)
    o.log = { { who = who, hit = 5, mhp = o.monHp, loss = who == 'mon' and 5 or 0, tags = {} } }
    o.onDone = function() end
    M.start(o)
    local f = fight
    f.phase, f.i, f.t, f.fired, f.frozen = 'fight', 1, p * f.slot, p >= HIT, true
    if who == 'dead' then f.heroDead, f.phase = true, 'hold' end
end

function M.active() return fight ~= nil end
-- 打到一半时主角还剩多少血（顶栏跟着往下掉）
function M.heroHp() return fight and math.max(0, fight.hhp) or nil end
-- 地图上不再演（都在窗口里），留着接口
function M.heroOffset() return 0, 0, 0 end
function M.monster() return nil end
function M.monCell() return nil end

local function finish()
    local f = fight
    fight = nil
    f.o.onDone()
end

-- 跳过：剩下的几下一次结算完，直接看结果
function M.skip()
    if not fight then return end
    local f = fight
    if f.phase == 'close' then return end
    for k = math.max(1, f.i), #f.log do
        local e = f.log[k]
        f.mhp = e.mhp
        f.hhp = f.hhp - e.loss
        for _, t in ipairs(e.tags) do
            if t == 'kill' then f.monDead = true end
            if t == 'dead' then f.heroDead = true end
        end
    end
    f.i = #f.log + 1
    f.mshow, f.hshow = f.mhp, f.hhp
    f.phase, f.pt = 'close', 0
end

local function impact(f, e)
    f.mhp = e.mhp
    f.hhp = f.hhp - e.loss
    local tags = {}
    for _, t in ipairs(e.tags) do tags[t] = true end
    local my, hy = FEET - 50, FEET - 50
    if e.who == 'skip' then
        f.round = f.round + e.rounds
        popup('…… 又打了 ' .. e.rounds .. ' 回合 ……', (HERO_CX + MON_CX) / 2, WY + 62, { 0.85, 0.8, 0.65 }, 11, 240)
        if e.loss > 0 then popup('−' .. e.loss, HERO_CX, hy - 12, C_HERO_LOSS, 18) end
        fx.play('thud', 0.7)
        return
    end
    if e.who == 'hero' then
        f.round = f.round + 1
        local wfx = WEAPON_FX[f.o.weapon or 'none'] or WEAPON_FX.none
        slashes[#slashes + 1] = { kind = wfx[1], x = f.monFront + 6, y = FEET - 34, t = 0, color = wfx[2] }
        f.monFlash = 1
        if e.hit > 0 then
            popup('−' .. e.hit, MON_CX + (love.math.random() - 0.5) * 16, my - 12, tags.anti and TAG_FX.anti[2] or C_MON_LOSS, tags.kill and 26 or 19)
            burst(MON_CX, FEET - 40, wfx[2], tags.kill and 26 or 8, tags.kill and 120 or 60)
            fx.play('hit', 0.9 + love.math.random() * 0.25)
        else
            -- 破不了防：一下打在硬壳上
            popup('0', MON_CX + (love.math.random() - 0.5) * 16, my - 12, { 0.6, 0.65, 0.7 }, 17)
            burst(MON_CX, FEET - 40, { 0.6, 0.6, 0.65 }, 4, 40)
            fx.play('click', 0.7)
        end
        f.shake = tags.kill and 6 or 2
        if tags.thorns then popup('−' .. (e.loss > 0 and e.loss or 3) .. ' 反伤', HERO_CX, hy - 30, C_THORNS, 11) end
        if tags.drain then popup('+' .. -e.loss .. ' 吸血', HERO_CX, hy - 30, C_HEAL, 11) end
    else
        f.heroFlash = 1
        local st = styleOf(f.o.mon.id)
        local hx = HERO_CX + HERO_FRONT - 6
        if st[1] == 'bite' or st[1] == 'claw' then
            slashes[#slashes + 1] = { kind = st[1], x = hx, y = FEET - 40, t = 0, color = { 1, 0.9, 0.85 } }
        elseif st[1] == 'charge' then
            slashes[#slashes + 1] = { kind = 'smash', x = hx, y = FEET - 34, t = 0, color = { 1, 0.85, 0.6 } }
        else
            burst(hx, FEET - 38, st[2], 12, 80)
        end
        if e.hit > 0 then popup('−' .. e.hit, HERO_CX + (love.math.random() - 0.5) * 16, hy - 12, C_HERO_LOSS, 18)
        else popup('格挡', HERO_CX, hy - 12, { 0.6, 0.75, 0.85 }, 13) end
        burst(HERO_CX, FEET - 40, { 0.9, 0.3, 0.3 }, e.hit > 0 and 6 or 2, 50)
        fx.play('thud', 0.9 + love.math.random() * 0.2)
        f.shake = e.hit > 0 and 3 or 1
        if tags.lifesteal then popup('吸血', MON_CX, my - 34, C_LIFESTEAL, 11) end
        if tags.spikes then popup('−3 反伤', MON_CX, my - 34, C_THORNS, 11) end
    end
    local tx = e.who == 'hero' and MON_CX or HERO_CX
    local ty = (e.who == 'hero' and my or hy) - 44
    for _, t in ipairs({ 'first', 'double', 'pierce', 'corrode' }) do
        if tags[t] then popup(TAG_FX[t][1], tx, ty, TAG_FX[t][2], 11); ty = ty - 14 end
    end
    if tags.kill then
        f.stop, f.monDead = HITSTOP, true
        burst(MON_CX, FEET - 40, { 0.6, 0.15, 0.2 }, 14, 90)
        fx.play('kill'); fx.shake(3)
    end
    if tags.dead then
        f.stop, f.heroDead = HITSTOP, true
        burst(HERO_CX, FEET - 40, { 0.8, 0.1, 0.15 }, 20, 90)
        fx.play('lose'); fx.shake(3)
    end
end

function M.update(dt)
    if fight then
        local f = fight
        f.heroFlash = math.max(0, f.heroFlash - dt * 5)
        f.monFlash = math.max(0, f.monFlash - dt * 5)
        f.shake = math.max(0, f.shake - dt * 20)
        -- 血量数字滚动着追上去
        f.hshow = f.hshow + (f.hhp - f.hshow) * math.min(1, dt * 14)
        f.mshow = f.mshow + (f.mhp - f.mshow) * math.min(1, dt * 14)
        if f.phase == 'open' then
            f.pt = f.pt + dt
            if f.pt >= OPEN then f.phase, f.i, f.t = 'fight', 1, 0 end
        elseif f.phase == 'fight' then
            if f.frozen then
                -- 定格（自动测试）
            elseif f.stop > 0 then
                f.stop = f.stop - dt
            else
                f.t = f.t + dt
                local e = f.log[f.i]
                local len = (e and e.who == 'skip') and f.slot * SKIP_SLOTS or f.slot
                if e and not f.fired and f.t >= f.slot * HIT then f.fired = true; impact(f, e) end
                if f.t >= len then
                    f.i, f.t, f.fired = f.i + 1, 0, false
                    if f.i > #f.log then f.phase, f.pt = 'hold', 0 end
                end
            end
        elseif f.phase == 'hold' then
            if not f.frozen then f.pt = f.pt + dt end
            if f.pt >= HOLD then f.phase, f.pt = 'close', 0 end
        elseif f.phase == 'close' then
            f.pt = f.pt + dt
            if f.pt >= CLOSE then finish() end
        end
    end
    for k = #popups, 1, -1 do popups[k].t = popups[k].t + dt; if popups[k].t > popups[k].life then table.remove(popups, k) end end
    for k = #parts, 1, -1 do
        local p = parts[k]
        p.t = p.t + dt
        p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
        p.vy = p.vy + 200 * dt
        if p.t > p.life then table.remove(parts, k) end
    end
    for k = #slashes, 1, -1 do slashes[k].t = slashes[k].t + dt; if slashes[k].t > 0.2 then table.remove(slashes, k) end end
    for k = #banners, 1, -1 do banners[k].t = banners[k].t + dt; if banners[k].t > 1.4 then table.remove(banners, k) end end
end

-- 地图上：打死以后格子上碎一下（窗口关上以后）
function M.kill(_, cx, feet)
    burst(cx, feet - 10, { 0.95, 0.9, 0.8 }, 10, 60)
end

-- 地图上方的大字：连杀、算准了……（同一时间只留一条）
function M.banner(text, sub, color)
    banners = { { text = text, sub = sub, t = 0, color = color } }
end

function M.drawPixel() end

local function ease(x) x = math.max(0, math.min(1, x)); return x * x * (3 - 2 * x) end
-- 冲过去（越跑越快）→ 打中时贴在对方身上 → 停一下 → 退回原位
local function lunge(p, D)
    if p < HIT then return D * (p / HIT) ^ 2 end
    if p < 0.66 then return D end
    return D * (1 - ease((p - 0.66) / 0.34))
end

-- 这一下双方的位移：hdx（矿工）、mdx（怪），和这一下进行到哪了（p）
local function offsets(f)
    local e = f.log[f.i]
    if f.phase ~= 'fight' or not e or e.who == 'skip' then return 0, 0, nil, e end
    local p = math.min(1, f.t / f.slot)
    local knock = f.fired and 9 * math.max(0, 1 - (p - HIT) / 0.35) or 0
    if e.who == 'hero' then
        local shape = WEAPON_SHAPE[f.o.weapon or 'none'] or 'blade'
        local D = f.monFront - (HERO_CX + HERO_FRONT + REACH[shape] - 12)
        return lunge(p, D), knock, p, e
    end
    local st = styleOf(f.o.mon.id)
    if RANGED[st[1]] then
        -- 远程：先往后蓄一下，再往前一探把东西放出来
        local lean = p < 0.15 and 5 * ease(p / 0.15) or -8 * math.max(0, 1 - (p - 0.15) / 0.4)
        return -knock, lean, p, e
    end
    local D = f.monFront - (HERO_CX + HERO_FRONT - 4)
    return -knock, -lunge(p, D), p, e
end

-- 矿工手上的武器（白盒：程序画的，正式美术换成帧动画）
local function drawWeapon(G, f, x, p, hero, a)
    local shape = WEAPON_SHAPE[f.o.weapon or 'none'] or 'blade'
    local col = (WEAPON_FX[f.o.weapon or 'none'] or WEAPON_FX.none)[2]
    local px, py = x + HAND_X, FEET + HAND_Y
    local swing = hero and p or nil
    -- 角度：举起（−1.3）→ 打中时劈下（0.5）→ 收回（−0.4）；矛和拳头是往前直刺
    local ang, ext = -0.4, 0
    if swing then
        if swing < HIT - 0.15 then ang = -0.4 - 0.9 * ease(swing / (HIT - 0.15))
        elseif swing < HIT then ang = -1.3 + 1.8 * ease((swing - (HIT - 0.15)) / 0.15)
        elseif swing < 0.7 then ang = 0.5
        else ang = 0.5 - 0.9 * ease((swing - 0.7) / 0.3) end
        if swing < HIT - 0.12 then ext = 0
        elseif swing < HIT then ext = ease((swing - (HIT - 0.12)) / 0.12)
        elseif swing < 0.7 then ext = 1
        else ext = 1 - ease((swing - 0.7) / 0.3) end
    end
    G.push()
    G.translate(px, py)
    if shape == 'fist' then
        if ext <= 0 then G.pop(); return end
        -- 一拳打出去：袖子伸长，拳头砸在怪身上
        local len = 2 + ext * 20
        G.setColor(0.12, 0.08, 0.06, a); G.rectangle('fill', -1, -4.5, len + 2, 9, 3, 3)
        G.setColor(0.36, 0.24, 0.16, a); G.rectangle('fill', 0, -3.5, len, 7, 2, 2)
        G.setColor(0.12, 0.08, 0.06, a); G.rectangle('fill', len - 1, -6.5, 13, 13, 3, 3)
        G.setColor(0.68, 0.45, 0.25, a); G.rectangle('fill', len, -5.5, 11, 11, 3, 3)
        G.setColor(0.85, 0.62, 0.38, a); G.rectangle('fill', len + 7, -4.5, 2.5, 9, 1, 1)
        G.pop(); return
    end
    G.scale(WEAPON_SCALE, WEAPON_SCALE)
    local DARK = { 0.08, 0.05, 0.04 }
    local function outline(mode, ...)
        G.setColor(DARK[1], DARK[2], DARK[3], a); G.setLineWidth(0.9)
        if mode == 'poly' then G.polygon('line', ...) else G.rectangle('line', ...) end
    end
    if shape == 'spear' then
        ang = swing and (-0.15 + 0.15 * ext) or -0.5
        G.rotate(ang)
        local back = swing and ext * 8 or 0
        G.setColor(DARK[1], DARK[2], DARK[3], a); G.setLineWidth(3); G.line(-10 + back, 0, 20 + back, 0)
        G.setColor(0.55, 0.4, 0.25, a); G.setLineWidth(1.6); G.line(-10 + back, 0, 20 + back, 0)
        G.setColor(col[1], col[2], col[3], a)
        G.polygon('fill', 19 + back, -3.5, 28 + back, 0, 19 + back, 3.5)
        outline('poly', 19 + back, -3.5, 28 + back, 0, 19 + back, 3.5)
        G.setLineWidth(1); G.pop(); return
    end
    G.rotate(ang)
    if shape == 'blade' then
        G.setColor(0.35, 0.24, 0.16, a); G.rectangle('fill', -3, -1.5, 6, 3); outline('rect', -3, -1.5, 6, 3)
        G.setColor(0.6, 0.5, 0.35, a); G.rectangle('fill', 2, -3, 2, 6); outline('rect', 2, -3, 2, 6)
        G.setColor(col[1], col[2], col[3], a)
        G.polygon('fill', 4, -2, 18, -1.2, 21, 0, 18, 1.2, 4, 2)
        outline('poly', 4, -2, 18, -1.2, 21, 0, 18, 1.2, 4, 2)
    elseif shape == 'hammer' then
        G.setColor(DARK[1], DARK[2], DARK[3], a); G.setLineWidth(3); G.line(-3, 0, 15, 0)
        G.setColor(0.55, 0.4, 0.25, a); G.setLineWidth(1.6); G.line(-3, 0, 15, 0)
        G.setColor(col[1] * 0.75, col[2] * 0.75, col[3] * 0.75, a); G.rectangle('fill', 13, -6, 7, 12, 1, 1)
        outline('rect', 13, -6, 7, 12, 1, 1)
        G.setColor(col[1], col[2], col[3], a); G.rectangle('fill', 14, -5, 2, 10)
    else -- hook
        G.setColor(DARK[1], DARK[2], DARK[3], a); G.setLineWidth(3); G.line(-3, 0, 14, 0)
        G.setColor(0.55, 0.4, 0.25, a); G.setLineWidth(1.6); G.line(-3, 0, 14, 0)
        G.setColor(DARK[1], DARK[2], DARK[3], a); G.setLineWidth(3.4)
        G.arc('line', 'open', 14, 5, 5, -math.pi / 2, math.pi * 0.6)
        G.setColor(col[1], col[2], col[3], a); G.setLineWidth(2)
        G.arc('line', 'open', 14, 5, 5, -math.pi / 2, math.pi * 0.6)
    end
    G.setLineWidth(1)
    G.pop()
end

-- 怪物的远程招式：口水 / 舌头 / 声波 / 鬼火 / 骨刺 / 光束（近身招式靠扑过去，这里不画）
local function drawMonAttack(G, f, p, hdx, mdx, a)
    local st = styleOf(f.o.mon.id)
    local kind, col = st[1], st[2] or { 1, 1, 1 }
    if not RANGED[kind] then return end
    local mx, my = f.monFront + mdx + 6, FEET - 30
    local tx, ty = HERO_CX + hdx + HERO_FRONT - 8, FEET - 40
    local function lerp(q) return mx + (tx - mx) * q, my + (ty - my) * q end
    local q = (p - 0.15) / (HIT - 0.15)
    if kind == 'tongue' then
        local ext = p < 0.2 and 0 or p < HIT and ease((p - 0.2) / (HIT - 0.2)) or p < 0.62 and 1 or 1 - ease((p - 0.62) / 0.2)
        if ext <= 0 then return end
        local ex, ey = lerp(ext)
        ey = ey - math.sin(ext * math.pi) * 6
        G.setColor(col[1], col[2], col[3], a); G.setLineWidth(3.5)
        G.line(mx, my, (mx + ex) / 2, (my + ey) / 2 - 4, ex, ey)
        G.circle('fill', ex, ey, 4)
        G.setLineWidth(1)
        return
    end
    if kind == 'beam' then
        local ex, ey = MON_CX + mdx, FEET - 40
        if p < 0.3 then
            G.setBlendMode('add'); G.setColor(col[1], col[2], col[3], a * 0.8)
            G.circle('fill', ex, ey, 3 + 10 * (p / 0.3)); G.setBlendMode('alpha')
        elseif p < 0.66 then
            local w = 7 * (1 - (p - 0.3) / 0.36) + 1.5
            G.setBlendMode('add')
            G.setColor(col[1], col[2], col[3], a * 0.85); G.setLineWidth(w); G.line(ex, ey, tx, ty)
            G.setColor(1, 0.95, 0.85, a); G.setLineWidth(w * 0.35); G.line(ex, ey, tx, ty)
            G.setBlendMode('alpha'); G.setLineWidth(1)
        end
        return
    end
    if q < 0 or q > 1 then return end
    if kind == 'spit' then
        -- 一口口水：抛物线飞过去，后面拖着几滴
        for k = 3, 0, -1 do
            local qq = q - k * 0.07
            if qq > 0 then
                local x, y = lerp(qq)
                y = y - math.sin(qq * math.pi) * 22
                G.setColor(col[1], col[2], col[3], a * (1 - k * 0.22))
                G.circle('fill', x, y, k == 0 and 4.5 or 3 - k * 0.6)
            end
        end
        local x, y = lerp(q); y = y - math.sin(q * math.pi) * 22
        G.setColor(1, 1, 1, a * 0.7); G.circle('fill', x - 1.2, y - 1.5, 1.3)
    elseif kind == 'wave' then
        G.setLineWidth(2)
        for k = 0, 2 do
            local qq = q - k * 0.12
            if qq > 0 then
                local x, y = lerp(qq)
                G.setColor(col[1], col[2], col[3], a * (1 - k * 0.3))
                G.arc('line', 'open', x + 8, y, 6 + qq * 10, math.pi - 0.8, math.pi + 0.8)
            end
        end
        G.setLineWidth(1)
    elseif kind == 'wisp' then
        local x, y = lerp(q); y = y + math.sin(q * 14) * 5
        G.setBlendMode('add')
        G.setColor(col[1], col[2], col[3], a * 0.5); G.circle('fill', x, y, 8)
        G.setColor(col[1], col[2], col[3], a); G.circle('fill', x, y, 4)
        G.setBlendMode('alpha')
    elseif kind == 'bolt' then
        local x, y = lerp(q)
        G.push(); G.translate(x, y); G.rotate(q * 12)
        G.setColor(col[1], col[2], col[3], a); G.rectangle('fill', -6, -1.5, 12, 3, 1, 1)
        G.circle('fill', -6, 0, 2.2); G.circle('fill', 6, 0, 2.2)
        G.pop()
    end
end

-- 画窗口（UI 层）。g = { text, rect, monster(id, cx, feet, fx), miner(cx, feet, dead, tall), S, OX, OY, LW, LH }
function M.drawUI(g)
    local G = love.graphics
    -- 窗口外：粒子以外的东西都在窗口里
    if fight then
        local f = fight
        local a = 1
        if f.phase == 'open' then a = f.pt / OPEN elseif f.phase == 'close' then a = 1 - f.pt / CLOSE end
        local sc = 0.92 + 0.08 * a
        local sx = (love.math.random() - 0.5) * f.shake
        local sy = (love.math.random() - 0.5) * f.shake
        -- 地图压暗
        g.rect({ 0.01, 0.02, 0.03 }, 0, 0, g.LW, g.LH, 0.65 * a)
        G.push()
        G.translate(g.OX + (g.LW / 2) * g.S, g.OY + (WY + WH / 2) * g.S)
        G.scale(sc, sc)
        G.translate(-(g.OX + (g.LW / 2) * g.S) + sx * g.S, -(g.OY + (WY + WH / 2) * g.S) + sy * g.S)
        -- 窗口和两张卡片
        g.rect({ 0.05, 0.07, 0.08 }, WX, WY, WW, WH, 0.97 * a, 8)
        G.setColor(0.30, 0.25, 0.19, a); G.setLineWidth(2 * g.S)
        G.rectangle('line', g.OX + WX * g.S, g.OY + WY * g.S, WW * g.S, WH * g.S, 8 * g.S, 8 * g.S)
        G.setLineWidth(1)
        -- 同一块场地：后面是井壁，脚下一条石地，矿灯在左边、怪那边发暗红
        g.rect({ 0.035, 0.045, 0.055 }, WX + 18, WY + 40, WW - 36, FEET - WY - 22, a, 6)
        G.push(); G.translate(g.OX, g.OY); G.scale(g.S, g.S)
        -- 井壁的砖缝（整齐的几排，很暗）
        G.setColor(0.075, 0.085, 0.095, a)
        G.setLineWidth(0.6)
        for row = 0, 5 do
            local y = WY + 44 + row * 18
            if y < FEET - 6 then
                G.line(WX + 20, y, WX + WW - 20, y)
                for bx = WX + 20 + (row % 2) * 14, WX + WW - 22, 28 do G.line(bx, y, bx, math.min(y + 18, FEET - 2)) end
            end
        end
        G.setLineWidth(1)
        -- 矿灯的暖光、怪那边的暗红：一圈圈叠起来，边缘是软的
        G.setBlendMode('add')
        for k = 1, 6 do
            local r = k / 6
            G.setColor(0.2, 0.14, 0.05, 0.05 * a); G.ellipse('fill', HERO_CX, FEET - 36, 100 * r, 62 * r)
            G.setColor(0.2, 0.03, 0.05, 0.045 * a); G.ellipse('fill', MON_CX, FEET - 36, 100 * r, 62 * r)
        end
        G.setBlendMode('alpha')
        G.setColor(0.13, 0.1, 0.08, a); G.rectangle('fill', WX + 18, FEET - 2, WW - 36, 16)
        G.setColor(0.2, 0.16, 0.12, a); G.rectangle('fill', WX + 18, FEET - 2, WW - 36, 2)
        G.pop()
        g.text('战　斗', 0, WY + 6, 11, { 0.94, 0.77, 0.42 }, 'center', g.LW, a)
        g.text('第 ' .. math.max(1, f.round) .. ' 回合', 0, WY + 22, 7.5, { 0.75, 0.7, 0.58 }, 'center', g.LW, a)
        -- 头像（素材按 nearest 放大）
        local hdx, mdx, p, e = offsets(f)
        G.push(); G.translate(g.OX, g.OY); G.scale(g.S, g.S)
        local heroTurn = e and e.who == 'hero'
        local function drawHero()
            if not f.heroDead or f.stop > 0 then
                g.miner(HERO_CX + hdx, FEET, f.heroDead, 96, a)
                if not f.heroDead then drawWeapon(G, f, HERO_CX + hdx, p, heroTurn, a) end
                if f.heroFlash > 0 then
                    G.setBlendMode('add'); G.setColor(1, 0.15, 0.15, f.heroFlash * 0.45 * a)
                    G.ellipse('fill', HERO_CX + hdx, FEET - 45, 34, 46); G.setBlendMode('alpha')
                end
            else
                -- 倒下：躺平、变暗
                -- 绕脚底转 90°：头朝左躺在地上（素材 96 高、约 82 宽，往上抬半个身宽）
                G.push(); G.translate(HERO_CX + 44, FEET - 41); G.rotate(-math.pi / 2)
                g.miner(0, 0, true, 96, a * 0.7)
                G.pop()
            end
        end
        local function drawMon()
            if not f.monDead or f.stop > 0 then
                g.monster(f.o.mon.id, MON_CX + mdx, FEET, { scale = MON_SCALE, flash = f.monFlash, alpha = a })
            end
        end
        if heroTurn then drawMon(); drawHero() else drawHero(); drawMon() end
        if e and e.who == 'mon' and p then drawMonAttack(G, f, p, hdx, mdx, a) end
        -- 武器动作
        for _, s in ipairs(slashes) do
            local p = s.t / 0.2
            G.setColor(s.color[1], s.color[2], s.color[3], (1 - p) * a)
            G.setLineWidth(3)
            if s.kind == 'bite' then
                -- 上下两排牙合上
                local c = 10 * (1 - p)
                for k = -2, 2 do
                    G.polygon('fill', s.x + k * 5 - 2, s.y - c - 6, s.x + k * 5 + 2, s.y - c - 6, s.x + k * 5, s.y - c)
                    G.polygon('fill', s.x + k * 5 - 2, s.y + c + 6, s.x + k * 5 + 2, s.y + c + 6, s.x + k * 5, s.y + c)
                end
            elseif s.kind == 'claw' then
                for k = -1, 1 do
                    G.line(s.x + 10 + k * 6, s.y - 14, s.x - 8 + k * 6 + p * 4, s.y + 12)
                end
            elseif s.kind == 'slash' then
                local a0 = -2.6 + p * 1.8
                G.arc('line', 'open', s.x, s.y, 34, a0, a0 + 1.7)
                G.arc('line', 'open', s.x, s.y, 26, a0 + 0.2, a0 + 1.5)
            elseif s.kind == 'thrust' then
                G.line(s.x - 50 + p * 20, s.y + 4, s.x + 16 + p * 20, s.y - 4)
            else
                G.circle('line', s.x, s.y, 8 + p * 34)
                G.circle('line', s.x, s.y, 4 + p * 20)
            end
            G.setLineWidth(1)
        end
        for _, pt in ipairs(parts) do
            G.setColor(pt.color[1], pt.color[2], pt.color[3], (1 - pt.t / pt.life) * a)
            G.rectangle('fill', pt.x, pt.y, pt.size, pt.size)
        end
        G.pop()
        -- 名字、属性
        g.text(f.o.hero.name, WX + 18, WY + 180, 10, { 0.95, 0.92, 0.85 }, 'center', 176, a)
        g.text(f.o.hero.line, WX + 18, WY + 194, 7, { 0.6, 0.66, 0.68 }, 'center', 176, a)
        g.text(f.o.mon.name .. (f.o.mon.traits ~= '' and ('　' .. f.o.mon.traits) or ''), WX + WW - 194, WY + 180, 10, { 1, 0.85, 0.86 }, 'center', 176, a)
        g.text(f.o.mon.line, WX + WW - 194, WY + 194, 7, { 0.6, 0.66, 0.68 }, 'center', 176, a)
        -- 血条和数字（数字滚动）
        local function bar(x, val, max, col, right)
            local w = 176
            g.rect({ 0.16, 0.08, 0.09 }, x, WY + 214, w, 8, a, 4)
            g.rect(col, x, WY + 214, w * math.max(0, math.min(1, val / max)), 8, a, 4)
            local num = tostring(math.max(0, math.floor(val + 0.5)))
            g.text(num .. ' / ' .. max, x, WY + 204, 7.5, { 0.95, 0.95, 0.95 }, right and 'right' or 'left', w, a)
        end
        bar(WX + 18, f.hshow, f.hmax, { 0.94, 0.72, 0.3 })
        bar(WX + WW - 194, f.mshow, f.mmax, { 0.85, 0.25, 0.3 }, true)
        if f.monDead and f.phase ~= 'fight' then g.text('击败！', MON_CX - 60, WY + 46, 18, { 1, 0.85, 0.4 }, 'center', 120, a) end
        if f.heroDead and f.phase ~= 'fight' then g.text('你倒下了', HERO_CX - 60, WY + 46, 16, { 1, 0.35, 0.4 }, 'center', 120, a) end
        g.text('点一下跳过', WX, WY + WH - 14, 6.5, { 0.42, 0.48, 0.5 }, 'right', WW - 12, a)
        -- 伤害数字（带描边）
        for _, p in ipairs(popups) do
            local pop = p.t < 0.12 and (1.7 - 0.7 * p.t / 0.12) or 1
            local pa = (p.t > p.life - 0.3 and (p.life - p.t) / 0.3 or 1) * a
            local size = p.size * pop
            local y = p.y - math.min(p.t, 0.6) * 26 - size / 2
            for _, o in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
                g.text(p.text, p.x - p.w / 2 + o[1], y + o[2], size, { 0.05, 0.03, 0.03 }, 'center', p.w, pa * 0.9)
            end
            g.text(p.text, p.x - p.w / 2, y, size, p.color, 'center', p.w, pa)
        end
        G.pop()
    else
        -- 窗口关上以后，地图上的碎片
        G.push(); G.translate(g.OX, g.OY); G.scale(g.S, g.S)
        for _, pt in ipairs(parts) do
            G.setColor(pt.color[1], pt.color[2], pt.color[3], 1 - pt.t / pt.life)
            G.rectangle('fill', pt.x, pt.y, pt.size, pt.size)
        end
        G.pop()
    end
    -- 大字（窗口关上以后）
    for _, b in ipairs(banners) do
        local pop = b.t < 0.15 and (1.8 - 0.8 * b.t / 0.15) or 1
        local ba = b.t > 1.0 and (1.4 - b.t) / 0.4 or 1
        local y = 74 - math.min(b.t, 1.4) * 6
        for _, o in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do g.text(b.text, o[1], y + o[2], 17 * pop, { 0.05, 0.03, 0.02 }, 'center', g.LW, ba * 0.9) end
        g.text(b.text, 0, y, 17 * pop, b.color, 'center', g.LW, ba)
        if b.sub then g.text(b.sub, 0, y + 22, 7.5, { 0.85, 0.85, 0.8 }, 'center', g.LW, ba) end
    end
end

function M.clear() popups, parts, slashes, banners = {}, {}, {}, {} end

return M
