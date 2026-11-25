-- 魔塔式战斗窗口（制作人 2026-11-24 定：每场都弹，画面中间一个战斗窗口，两边一来一回地打，血实时往下掉）。
-- 规则在 core/combat.lua 里已经算完了（combat.simulate 的 log 记了每一下），这里只负责"演"出来：
--   矿工和怪物站在同一块场地上（制作人：不要 VS，要真的打到对方身上），两条大血条和血量数字一下下往下掉；
--   矿工冲到怪身上挥武器（空手就是一拳）；怪按种类出手：扑咬 / 冲撞 / 钳夹，或者喷口水、吐舌头、声波、鬼火、骨刺、光束；
--   挨打的一方闪白（怪）/ 闪红（矿工）、往后一退、窗口震一下；
--   伤害数字大字弹出，先手 / 连击 / 破甲 / 克制 / 腐蚀 / 反伤 / 吸血用不同颜色；
--   打死时顿住一下，怪的头像碎掉；打不过时矿工被一点点耗死。
-- 打完窗口关上，地图上方再出"算准了 / 千钧一发 / 无伤 / 连杀"的大字。
-- 场地与数字取套色木刻方向，数值和招式来自战斗记录。

local fx = require('view.fx')
local feedback = require('view.battle_feedback')

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
local marks = require('view.weapon_marks')

local fight = nil
local parts, slashes, banners = {}, {}, {}
local stage
function M.load()
    stage = love.graphics.newImage('assets/art/battle/cistern.jpg')
    stage:setFilter('linear', 'linear')
end

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
    parts, slashes = {}, {}
    o.log = compress(o.log)
    local n = math.max(1, #o.log + SKIP_SLOTS - 1)
    local slot = math.min(SLOT, MAX_TOTAL / n) / (o.speed or 1)
    fight = { o = o, log = o.log, i = 0, t = 0, slot = slot, stop = 0, phase = 'open', pt = 0,
        hhp = o.heroHp, hshow = o.heroHp, hmax = math.max(o.heroHp, 1), mhp = o.monHp, mshow = o.monHp, mmax = math.max(o.monHp, 1), round = 0,
        readouts = feedback.new(), heroFlash = 0, monFlash = 0, shake = 0, monDead = false, heroDead = false,
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
-- 吸血能抵销本战后续的损伤，规则只结算非负的净战损。
local function visibleHp(value, maximum) return math.max(0, math.min(value, maximum)) end
function M.heroHp() return fight and visibleHp(fight.hhp, fight.hmax) or nil end
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
    for k = math.max(1, f.i + (f.fired and 1 or 0)), #f.log do
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
    f.phase, f.pt, f.stop, f.contact = 'close', 0, 0, nil
    f.readouts, parts, slashes = feedback.new(), {}, {}
end

local function impact(f, e)
    local previousMhp = f.mhp
    f.mhp = e.mhp
    f.hhp = f.hhp - e.loss
    local tags = {}
    for _, t in ipairs(e.tags) do tags[t] = true end
    feedback.hit(f.readouts, e, tags, previousMhp)
    if e.who == 'skip' then
        f.round = f.round + e.rounds
        fx.play('thud', 0.7)
        return
    end
    if e.who == 'hero' then
        f.round = f.round + 1
        local wfx = WEAPON_FX[f.o.weapon or 'none'] or WEAPON_FX.none
        slashes[#slashes + 1] = { kind = wfx[1], x = f.monFront + 6, y = FEET - 34, t = 0, color = wfx[2] }
        f.monFlash = e.hit > 0 and 0.85 or 0.35
        if e.hit > 0 then
            burst(MON_CX, FEET - 40, wfx[2], tags.kill and 26 or 8, tags.kill and 120 or 60)
            fx.play(f.o.weapon == 'hammer' and 'hammer' or 'hit', 0.95 + love.math.random() * 0.12)
        else
            -- 破不了防：一下打在硬壳上
            burst(MON_CX, FEET - 40, { 0.6, 0.6, 0.65 }, 4, 40)
            fx.play('guard')
        end
        f.shake = tags.kill and 6 or (e.hit == 0 and 1 or 2)
    else
        f.heroFlash = e.hit > 0 and 1 or 0.35
        local st = styleOf(f.o.mon.id)
        local hx = HERO_CX + HERO_FRONT - 6
        if st[1] == 'bite' or st[1] == 'claw' then
            slashes[#slashes + 1] = { kind = st[1], x = hx, y = FEET - 40, t = 0, color = { 1, 0.9, 0.85 } }
        elseif st[1] == 'charge' then
            slashes[#slashes + 1] = { kind = 'smash', x = hx, y = FEET - 34, t = 0, color = { 1, 0.85, 0.6 } }
        else
            burst(hx, FEET - 38, st[2], 12, 80)
        end
        burst(HERO_CX, FEET - 40, { 0.9, 0.3, 0.3 }, e.hit > 0 and 6 or 2, 50)
        fx.play(e.hit > 0 and 'thud' or 'guard', 0.95 + love.math.random() * 0.1)
        f.shake = e.hit > 0 and 3 or 1
    end
    local dir = e.who == 'hero' and 1 or -1
    local heavy = tags.kill or tags.dead or (dir == 1 and f.o.weapon == 'hammer')
    f.contact = { x = dir == 1 and f.monFront + 9 or HERO_CX + HERO_FRONT - 7,
        y = FEET - 37, dir = dir, t = 0, heavy = heavy, guard = e.hit == 0 }
    f.stop = math.min(f.slot * 0.16, heavy and 0.055 or 0.032)
    if tags.kill then
        f.stop, f.monDead = HITSTOP, true
        burst(MON_CX, FEET - 40, { 0.6, 0.15, 0.2 }, 14, 90)
        fx.play('kill')
    end
    if tags.dead then
        f.stop, f.heroDead = HITSTOP, true
        burst(HERO_CX, FEET - 40, { 0.8, 0.1, 0.15 }, 20, 90)
        fx.play('lose')
    end
end

function M.update(dt)
    if fight then
        local f = fight
        f.heroFlash = math.max(0, f.heroFlash - dt * 5)
        f.monFlash = math.max(0, f.monFlash - dt * 5)
        f.shake = math.max(0, f.shake - dt * 20)
        feedback.update(f.readouts, dt)
        if f.contact then
            f.contact.t = f.contact.t + dt
            if f.contact.t > 0.16 then f.contact = nil end
        end
        -- 浅色残条追上即时血量
        f.hshow = f.hshow + (f.hhp - f.hshow) * math.min(1, dt * 8)
        f.mshow = f.mshow + (f.mhp - f.mshow) * math.min(1, dt * 8)
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
                if e and not f.fired and f.t >= f.slot * HIT then
                    f.fired = true
                    impact(f, e)
                    if f.stop > 0 then f.t = f.slot * HIT end
                end
                if f.stop <= 0 and f.t >= len then
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
    local recoil = e.hit == 0 and 3 or 10
    local knock = f.fired and recoil * math.max(0, 1 - (p - HIT) / 0.35) or 0
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

-- 从脚底变形：预备时微蹲，出手时前倾，受击时向后折一下。
local function stance(G, cx, p, attacker, dir, guarded)
    if not p then return end
    local wind = math.max(0, 1 - math.abs(p - 0.23) / 0.23)
    local strike = math.max(0, 1 - math.abs(p - HIT) / 0.22)
    local recoil = p >= HIT and math.max(0, 1 - (p - HIT) / 0.36) or 0
    local lean, squash
    if attacker then
        lean, squash = dir * (0.055 * wind - 0.09 * strike), 0.045 * wind
    else
        local weight = guarded and 0.40 or 1
        lean, squash = dir * 0.12 * recoil * weight, 0.055 * recoil * weight
    end
    G.translate(cx, FEET)
    G.shear(lean, 0)
    G.scale(1 + squash, 1 - squash)
    G.translate(-cx, -FEET)
end

-- 矿工手上的武器（白盒：程序画的，正式美术换成帧动画）
local function drawWeapon(G, f, x, p, hero, a)
    local shape = WEAPON_SHAPE[f.o.weapon or 'none'] or 'blade'
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
    local size = 49
    if shape == 'spear' then
        ang = swing and (-0.15 + 0.15 * ext) or -0.5
        G.translate(ext * 9, 0)
        size = 68
    end
    marks.inHand(f.o.weapon, 0, 0, size, ang + math.rad(56), false, a)
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
            local reach = ease((p - 0.3) / (HIT - 0.3))
            tx, ty = ex + (tx - ex) * reach, ey + (ty - ey) * reach
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
        local x, y = lerp(q); y = y + math.sin(q * 4 * math.pi) * 5
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
        G.translate(-(g.OX + (g.LW / 2) * g.S), -(g.OY + (WY + WH / 2) * g.S))
        -- 墨青底板，赭金细边。页眉和数字不随出拳晃动。
        g.rect({ 0.035, 0.075, 0.085 }, WX, WY, WW, WH, a)
        g.rect({ 0.74, 0.52, 0.28 }, WX, WY, WW, 1, a)
        g.rect({ 0.42, 0.34, 0.23 }, WX, WY + WH - 2, WW, 2, a)
        g.text('战斗', WX + 16, WY + 5, 13, { 1, 0.88, 0.66 }, nil, nil, a)
        local title, titleColor = '第 ' .. math.max(1, f.round) .. ' 回合', { 0.86, 0.84, 0.71 }
        if f.phase == 'hold' or f.phase == 'close' then
            if f.heroDead then title, titleColor = '你倒下了', { 1, 0.5, 0.39 }
            elseif f.monDead then title, titleColor = '击败', { 1, 0.82, 0.4 } end
        elseif f.log[f.i] and f.log[f.i].who == 'skip' then title = '快进 · ' .. f.log[f.i].rounds .. ' 回合' end
        g.text(title, WX + 104, WY + 9, 9, titleColor, 'center', WW - 208, a)
        g.text('点一下跳过', WX + WW - 92, WY + 10, 7.5, { 0.71, 0.75, 0.69 }, 'right', 78, a)
        G.push(); G.translate(g.OX, g.OY); G.scale(g.S, g.S)
        G.setColor(0.70, 0.73, 0.72, a)
        G.draw(stage, WX + 7, WY + 31, 0, (WW - 14) / stage:getWidth(), 134 / stage:getHeight())
        G.pop()
        -- 头像（素材按 nearest 放大）
        local hdx, mdx, p, e = offsets(f)
        G.push(); G.translate(g.OX, g.OY); G.scale(g.S, g.S)
        G.translate(sx, sy)
        local heroTurn = e and e.who == 'hero'
        local guarded = e and e.hit == 0
        G.setColor(0.025, 0.045, 0.04, a * 0.48)
        G.ellipse('fill', HERO_CX + hdx, FEET, 23, 3.5)
        local function drawHero()
            if not f.heroDead or f.stop > 0 then
                G.push()
                stance(G, HERO_CX + hdx, p, heroTurn, 1, guarded)
                g.miner(HERO_CX + hdx, FEET, f.heroDead, 96, a)
                if not f.heroDead then drawWeapon(G, f, HERO_CX + hdx, p, heroTurn, a) end
                if f.heroFlash > 0 then
                    G.setBlendMode('add')
                    g.miner(HERO_CX + hdx, FEET, false, 96, f.heroFlash * 0.55 * a)
                    G.setBlendMode('alpha')
                end
                G.pop()
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
                G.push()
                stance(G, MON_CX + mdx, p, not heroTurn, -1, guarded)
                g.monster(f.o.mon.id, MON_CX + mdx, FEET, { scale = MON_SCALE, flash = f.monFlash, alpha = a })
                G.pop()
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
        if f.contact then
            local c = f.contact
            local progress = c.t / 0.16
            local size = (c.guard and 0.60 or c.heavy and 1.35 or 1) * (1 + progress * 0.4)
            G.push()
            G.translate(c.x, c.y); G.scale(c.dir * size, size)
            -- 木刻刀痕由接触点向外炸开，中心白光只停留几帧。
            for k = 1, 7 do
                G.rotate(math.pi * 2 / 7)
                local near = 3 + progress * 11
                local far = near + (k % 3 == 0 and 19 or 13) * (1 - progress)
                G.setColor(c.guard and 0.65 or 1, c.guard and 0.87 or 0.68, c.guard and 0.91 or 0.27, (1 - progress) * a)
                G.polygon('fill', near, -2.4, far, -1, near + 2, 1.5)
            end
            G.setColor(1, 0.96, 0.8, math.max(0, 1 - progress * 1.8) * a)
            G.polygon('fill', -8, 2, -2, -2, 4, -10, 3, -2, 10, 0, 3, 3, -2, 10, -2, 4)
            G.pop()
        end
        for _, pt in ipairs(parts) do
            G.setColor(pt.color[1], pt.color[2], pt.color[3], (1 - pt.t / pt.life) * a)
            G.rectangle('fill', pt.x, pt.y, pt.size, pt.size)
        end
        G.pop()
        -- 数字立即结算，浅色的尾条短暂保留命中前的血量。
        local function vitals(x, name, stats, value, trail, maximum, color, right)
            local w, y = 191, WY + 200
            local function fill(v) return w * math.min(1, math.max(0, v / maximum)) end
            local align = right and 'right' or 'left'
            g.text(name, x, WY + 169, 11, { 0.98, 0.91, 0.77 }, align, w, a)
            g.text(stats, x, WY + 187, 7.5, { 0.70, 0.76, 0.72 }, align, w, a)
            g.rect({ 0.16, 0.22, 0.22 }, x, y, w, 7, a)
            g.rect({ 0.97, 0.83, 0.59 }, x, y, fill(trail), 7, a)
            g.rect(color, x, y, fill(value), 7, a)
            g.text(visibleHp(value, maximum) .. ' / ' .. maximum, x, WY + 210, 10, { 1, 0.93, 0.79 }, align, w, a)
        end
        local monName = f.o.mon.name .. (f.o.mon.traits ~= '' and ('　' .. f.o.mon.traits) or '')
        vitals(WX + 16, f.o.hero.name, f.o.hero.line, f.hhp, f.hshow, f.hmax, { 0.87, 0.64, 0.28 }, false)
        vitals(WX + WW - 207, monName, f.o.mon.line, f.mhp, f.mshow, f.mmax, { 0.82, 0.32, 0.23 }, true)
        feedback.draw(g, f.readouts.hero, WX + 70, WY + 76, HERO_CX, WY + 151, a)
        feedback.draw(g, f.readouts.mon, WX + WW - 70, WY + 76, MON_CX, WY + 151, a)
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

function M.dismissBanner() banners = {} end

function M.clear() parts, slashes, banners = {}, {}, {} end

return M
