-- 战斗过程的回放和打击反馈（制作人 2026-11-24：确定性战斗更需要好的反馈，让每一次行动都有满足感）。
-- 规则在 core/combat.lua 里已经算完了（combat.simulate 的 log 记了每一下），这里只负责"演"出来：
--   主角出手有武器动作（挥砍 / 突刺 / 锤击）、怪物受击闪白后退、伤害数字弹出、
--   反伤 / 吸血 / 破甲 / 腐蚀 / 先手 / 连击用不同颜色的字、击杀时顿一下再碎掉、
--   连杀和"算准了 / 千钧一发 / 无伤 / 正好"的大字。
-- 白盒阶段全部是程序画的，正式美术由 Codex 替换，接口不变。

local fx = require('view.fx')

local M = {}

local SLOT = 0.17          -- 一下的时长（正常速度）
local MAX_TOTAL = 1.6      -- 一场最长多久（太长就把每一下压短）
local HITSTOP = 0.14       -- 打死那一下顿住多久

local fight = nil          -- 正在演的一场 { log, i, t, slot, ... }
local popups = {}          -- 弹出的字 { text, x, y, t, color, size, life }
local parts = {}           -- 粒子 { x, y, vx, vy, t, life, color, size }
local ghosts = {}          -- 正在碎掉的怪 { id, cx, feet, t }
local slashes = {}         -- 武器动作的残影 { kind, x0, y0, x1, y1, t, color }
local banners = {}         -- 画面上方的大字 { text, sub, t, color }

-- 每种武器的动作和颜色：挥砍（弧）/ 突刺（直线）/ 锤击（冲击圈）
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

-- 特殊效果的字和颜色
local TAG_FX = {
    first = { '先手！', { 1.0, 0.85, 0.35 } },
    double = { '连击', { 1.0, 0.55, 0.4 } },
    pierce = { '破甲', { 1.0, 0.6, 0.25 } },
    anti = { '克制 ×2', { 0.45, 0.9, 1.0 } },
    corrode = { '腐蚀', { 0.6, 0.95, 0.3 } },
}
local C_HERO_LOSS = { 1.0, 0.35, 0.4 }
local C_MON_LOSS = { 1.0, 0.97, 0.9 }
local C_HEAL = { 0.45, 1.0, 0.55 }
local C_THORNS = { 0.8, 0.45, 1.0 }
local C_LIFESTEAL = { 0.95, 0.2, 0.35 }

local function popup(text, x, y, color, size, life)
    popups[#popups + 1] = { text = text, x = x, y = y, t = 0, color = color, size = size or 9, life = life or 0.9 }
end
local function burst(x, y, color, n, speed)
    for k = 1, n do
        local a = love.math.random() * math.pi * 2
        local v = speed * (0.4 + love.math.random() * 0.8)
        parts[#parts + 1] = { x = x, y = y, vx = math.cos(a) * v, vy = math.sin(a) * v - 20, t = 0, life = 0.35 + love.math.random() * 0.3, color = color, size = 1 + love.math.random(0, 2) }
    end
end

-- 开始演一场。o = { tile = function(cell) -> x, y, TILE }, heroCell, monCell, log, weapon, monHp, heroHp, speed(1 / 2.5), onDone }
function M.start(o)
    local n = math.max(1, #o.log)
    local slot = math.min(SLOT, MAX_TOTAL / n) / (o.speed or 1)
    local hx, hy = o.tile(o.heroCell)
    local mx, my = o.tile(o.monCell)
    local len = math.sqrt((mx - hx) ^ 2 + (my - hy) ^ 2)
    fight = {
        log = o.log, i = 1, t = 0, slot = slot, stop = 0, o = o,
        hx = hx, hy = hy, mx = mx, my = my, dx = (mx - hx) / len, dy = (my - hy) / len,
        mhp = o.monHp, mmax = o.monHp, hhp = o.heroHp, fired = false, size = o.size,
    }
end

function M.active() return fight ~= nil end
-- 打到一半时主角还剩多少血（顶栏跟着往下掉）；不在打就返回 nil
function M.heroHp() return fight and fight.hhp or nil end
-- 正在打的是哪一格（这一格的掉血牌先不画）
function M.monCell() return fight and fight.o.monCell or nil end

-- 跳过：剩下的几下一次结算完
function M.skip()
    if not fight then return end
    local f = fight
    local lossMon, lossHero = 0, 0
    for k = f.i, #f.log do
        local e = f.log[k]
        if e.who == 'hero' then lossMon = lossMon + e.hit else lossHero = lossHero + e.loss end
        f.mhp = e.mhp
    end
    if lossMon > 0 then popup('−' .. lossMon, f.mx + f.size / 2, f.my - 4, C_MON_LOSS, 10) end
    if lossHero ~= 0 then popup((lossHero > 0 and '−' or '+') .. math.abs(lossHero), f.hx + f.size / 2, f.hy - 4, lossHero > 0 and C_HERO_LOSS or C_HEAL, 9) end
    fight = nil
    f.o.onDone()
end

-- 这一下打到的那一刻：字、闪、震、声音
local function impact(f, e)
    local s = f.size
    local mcx, mcy = f.mx + s / 2, f.my + s * 0.35
    local hcx, hcy = f.hx + s / 2, f.hy + s * 0.35
    f.mhp = e.mhp
    f.hhp = f.hhp - e.loss
    local tags = {}
    for _, t in ipairs(e.tags) do tags[t] = true end
    if e.who == 'hero' then
        local wfx = WEAPON_FX[f.o.weapon or 'none'] or WEAPON_FX.none
        slashes[#slashes + 1] = { kind = wfx[1], x = mcx, y = mcy, dx = f.dx, dy = f.dy, t = 0, color = wfx[2] }
        f.monFlash = 1
        popup('−' .. e.hit, mcx + (love.math.random() - 0.5) * 6, mcy - 18, tags.anti and TAG_FX.anti[2] or C_MON_LOSS, tags.kill and 17 or 12)
        burst(mcx, mcy, wfx[2], tags.kill and 14 or 5, tags.kill and 70 or 40)
        fx.play('hit', 0.9 + love.math.random() * 0.25)
        fx.shake(tags.kill and 3.5 or 1.2)
        if tags.thorns then popup('−' .. (e.loss > 0 and e.loss or 3) .. ' 反伤', hcx, hcy - 14, C_THORNS, 7) end
        if tags.drain then popup('+' .. -e.loss .. ' 吸血', hcx, hcy - 14, C_HEAL, 7) end
    else
        f.heroFlash = 1
        if e.hit > 0 then popup('−' .. e.hit, hcx + (love.math.random() - 0.5) * 6, hcy - 16, C_HERO_LOSS, 11) else popup('格挡', hcx, hcy - 16, { 0.6, 0.75, 0.85 }, 8) end
        burst(hcx, hcy, { 0.9, 0.3, 0.3 }, e.hit > 0 and 4 or 2, 35)
        fx.play('thud', 0.9 + love.math.random() * 0.2)
        fx.shake(e.hit > 0 and 1.6 or 0.5)
        if tags.lifesteal then popup('吸血', mcx, mcy - 16, C_LIFESTEAL, 7) end
        if tags.spikes then popup('−3 反伤', mcx, mcy - 16, C_THORNS, 7) end
    end
    -- 先手 / 连击 / 破甲 / 腐蚀：写在挨打的那一方头上
    local tx, ty = e.who == 'hero' and mcx or hcx, (e.who == 'hero' and mcy or hcy) - 32
    for _, t in ipairs({ 'first', 'double', 'pierce', 'corrode' }) do
        if tags[t] then popup(TAG_FX[t][1], tx, ty, TAG_FX[t][2], 7); ty = ty - 9 end
    end
    if tags.kill then f.stop = HITSTOP; fx.play('kill') end
end

function M.update(dt)
    -- 演出中的一场
    if fight then
        local f = fight
        if f.stop > 0 then
            f.stop = f.stop - dt
        else
            f.t = f.t + dt
            local e = f.log[f.i]
            if e and not f.fired and f.t >= f.slot * 0.45 then f.fired = true; impact(f, e) end
            if f.t >= f.slot then
                f.i = f.i + 1
                f.t = 0
                f.fired = false
                if f.i > #f.log then
                    fight = nil
                    f.o.onDone()
                end
            end
        end
        if f.monFlash then f.monFlash = math.max(0, f.monFlash - dt * 6) end
        if f.heroFlash then f.heroFlash = math.max(0, f.heroFlash - dt * 6) end
    end
    for k = #popups, 1, -1 do popups[k].t = popups[k].t + dt; if popups[k].t > popups[k].life then table.remove(popups, k) end end
    for k = #parts, 1, -1 do
        local p = parts[k]
        p.t = p.t + dt
        p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
        p.vy = p.vy + 160 * dt
        if p.t > p.life then table.remove(parts, k) end
    end
    for k = #ghosts, 1, -1 do ghosts[k].t = ghosts[k].t + dt; if ghosts[k].t > 0.5 then table.remove(ghosts, k) end end
    for k = #slashes, 1, -1 do slashes[k].t = slashes[k].t + dt; if slashes[k].t > 0.18 then table.remove(slashes, k) end end
    for k = #banners, 1, -1 do banners[k].t = banners[k].t + dt; if banners[k].t > 1.4 then table.remove(banners, k) end end
end

-- 主角这一刻往哪偏（出手时扑向怪，挨打时往后一缩）
function M.heroOffset()
    if not fight then return 0, 0, 0 end
    local f = fight
    local e = f.log[f.i]
    if not e then return 0, 0, 0 end
    local p = math.min(1, f.t / f.slot)
    local k = math.sin(p * math.pi)
    if e.who == 'hero' then return f.dx * 7 * k, f.dy * 7 * k, f.heroFlash or 0 end
    return -f.dx * 2 * k, -f.dy * 2 * k, f.heroFlash or 0
end

-- 怪物这一刻往哪偏、闪多白（挨打时后退一下，出手时扑向主角）
function M.monster(cell)
    if not fight or fight.o.monCell ~= cell then return nil end
    local f = fight
    local e = f.log[f.i]
    local p = e and math.min(1, f.t / f.slot) or 0
    local k = math.sin(p * math.pi)
    local dx, dy = 0, 0
    if e and e.who == 'mon' then dx, dy = -f.dx * 6 * k, -f.dy * 6 * k
    elseif e and f.fired then dx, dy = f.dx * 3 * k, f.dy * 3 * k end
    return { dx = dx, dy = dy, flash = f.monFlash or 0, hp = f.mhp, max = f.mmax }
end

-- 打死以后：怪碎掉（缩小、发白、碎片四散）
function M.kill(id, cx, feet, size)
    ghosts[#ghosts + 1] = { id = id, cx = cx, feet = feet, t = 0 }
    burst(cx, feet - size * 0.4, { 0.95, 0.9, 0.8 }, 16, 90)
    burst(cx, feet - size * 0.4, { 0.6, 0.15, 0.2 }, 8, 60)
end

-- 大字：连杀、算准了、千钧一发……
function M.banner(text, sub, color)
    -- 同一时间只留一条，新的顶掉旧的
    banners = { { text = text, sub = sub, t = 0, color = color } }
end

-- 像素层：武器动作、粒子、碎掉的怪、怪的血条。drawMonster(id, cx, feet, fx) 由调用方提供
function M.drawPixel(drawMonster)
    local g = love.graphics
    for _, gh in ipairs(ghosts) do
        local p = gh.t / 0.5
        drawMonster(gh.id, gh.cx, gh.feet, { scale = 1 - p * 0.6, alpha = 1 - p, flash = 1 - p, dy = -p * 4 })
    end
    for _, s in ipairs(slashes) do
        local p = s.t / 0.18
        g.setColor(s.color[1], s.color[2], s.color[3], 1 - p)
        g.setLineWidth(2)
        if s.kind == 'slash' then
            -- 斜着一道弧
            local a0 = -2.4 + p * 1.6
            g.arc('line', 'open', s.x - s.dx * 4, s.y - s.dy * 4, 10, a0, a0 + 1.6)
            g.arc('line', 'open', s.x - s.dx * 4, s.y - s.dy * 4, 7, a0 + 0.2, a0 + 1.4)
        elseif s.kind == 'thrust' then
            -- 直着刺进去
            g.line(s.x - s.dx * (14 - p * 6), s.y - s.dy * (14 - p * 6), s.x + s.dx * (4 + p * 6), s.y + s.dy * (4 + p * 6))
        else
            -- 砸下去的冲击圈
            g.circle('line', s.x, s.y, 3 + p * 12)
            g.circle('line', s.x, s.y, 1 + p * 7)
        end
        g.setLineWidth(1)
    end
    for _, pt in ipairs(parts) do
        g.setColor(pt.color[1], pt.color[2], pt.color[3], 1 - pt.t / pt.life)
        g.rectangle('fill', math.floor(pt.x), math.floor(pt.y), pt.size, pt.size)
    end
    -- 正在打的怪头上的血条
    if fight then
        local f = fight
        local w = f.size - 6
        local x, y = f.mx + 3, f.my - 9
        g.setColor(0.1, 0.05, 0.06, 0.9); g.rectangle('fill', x - 1, y - 1, w + 2, 4)
        g.setColor(0.85, 0.2, 0.25); g.rectangle('fill', x, y, w * math.max(0, f.mhp) / f.mmax, 2)
    end
end

-- UI 层：弹出的伤害数字、效果字、大字。text(str, x, y, size, color, align, width)
function M.drawUI(text, LW)
    for _, p in ipairs(popups) do
        local pop = p.t < 0.12 and (1.7 - 0.7 * p.t / 0.12) or 1
        local a = p.t > p.life - 0.3 and (p.life - p.t) / 0.3 or 1
        local size = p.size * pop
        local col = { p.color[1], p.color[2], p.color[3] }
        local y = p.y - math.min(p.t, 0.6) * 22 - size / 2
        -- 先画一圈深色描边，数字压在地图上也看得清
        for _, o in ipairs({ { -0.7, 0 }, { 0.7, 0 }, { 0, -0.7 }, { 0, 0.7 } }) do
            text(p.text, p.x - 30 + o[1], y + o[2], size, { 0.05, 0.03, 0.03 }, 'center', 60, a * 0.9)
        end
        text(p.text, p.x - 30, y, size, col, 'center', 60, a)
    end
    for k, b in ipairs(banners) do
        local pop = b.t < 0.15 and (1.8 - 0.8 * b.t / 0.15) or 1
        local a = b.t > 1.0 and (1.4 - b.t) / 0.4 or 1
        local y = 74 + (k - 1) * 30 - math.min(b.t, 1.4) * 6
        for _, o in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do text(b.text, o[1], y + o[2], 17 * pop, { 0.05, 0.03, 0.02 }, 'center', LW, a * 0.9) end
        text(b.text, 0, y, 17 * pop, b.color, 'center', LW, a)
        if b.sub then text(b.sub, 0, y + 22, 7.5, { 0.85, 0.85, 0.8 }, 'center', LW, a) end
    end
end

-- 自动测试 / 设置"跳过"时清掉残留的效果
function M.clear() popups, parts, ghosts, slashes, banners = {}, {}, {}, {}, {} end

return M
