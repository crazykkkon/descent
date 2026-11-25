-- 断臂转轮的画面：画成接在矿工断口上的铜铁机械小臂，三个竖转轮嵌在小臂里，旁边一根拉杆。
-- 像素层（逻辑坐标）画手臂、轮子底色、拉杆；印记由 UI 层按屏幕分辨率绘制。
-- 动画：拉杆下压 → 轮子带拖影滚动 → 一个个"咔"地停下 → 连成一线时画面一震、中奖线发金光。

local armMod = require('core.arm')
local fx = require('view.fx')

local M = {}

-- 手臂的位置（逻辑坐标）
M.X, M.Y = 486, 44
M.REEL_W, M.CELL_H, M.GAP = 30, 24, 6
M.REELS_X, M.REELS_Y = M.X + 14, M.Y + 50
M.LEVER_X, M.LEVER_Y = M.X + 128, M.Y + 64     -- 拉杆的转轴
M.BLOOD = { x = M.X + 10, y = M.Y + 200, w = 132, h = 16 }

local SPIN = 0.42       -- 第一个轮子停下的时间（拉杆之后）
local STAGGER = 0.16    -- 后面每个轮子晚多久停
local LEVER_T = 0.18

-- 动画状态
local anim = nil        -- { t, held, faces, kind, clicked = {}, done }
local flash = nil       -- { t, kind }

local function reelX(r) return M.REELS_X + (r - 1) * (M.REEL_W + M.GAP) end
function M.reelRect(r) return reelX(r), M.REELS_Y, M.REEL_W, M.CELL_H * 3 end
function M.lockRect(r) return reelX(r), M.REELS_Y + M.CELL_H * 3 + 6, M.REEL_W, 12 end
function M.leverRect() return M.LEVER_X - 8, M.LEVER_Y - 34, 20, 76 end

-- 开始转动的动画（规则已经在 run:armSpin 里算完了）
function M.startSpin(held, faces, before, stops, message)
    local travel = {}
    local last = LEVER_T
    for r = 1, 3 do
        travel[r] = (2 + r) * armMod.SIZE + (stops[r] - before.stops[r]) % armMod.SIZE
        if not held[r] then last = LEVER_T + SPIN + (r - 1) * STAGGER end
    end
    local kind, target = armMod.outcome(faces)
    anim = { t = 0, held = held, kind = kind, target = target, before = before, travel = travel,
        last = last, message = message, clicked = {} }
    flash = nil
    fx.play('lever')
end

function M.busy() return anim ~= nil end
function M.displayHeld(selected)
    return anim and anim.held or selected
end
function M.reset() anim, flash = nil, nil end
function M.displayHero(hero)
    if anim then return anim.before end
    return hero
end

function M.update(dt)
    if flash then
        flash.t = flash.t + dt
        if flash.t > 1.0 then flash = nil end
    end
    if not anim then return end
    anim.t = anim.t + dt
    for r = 1, 3 do
        if not anim.held[r] and not anim.clicked[r] and anim.t >= LEVER_T + SPIN + (r - 1) * STAGGER then
            anim.clicked[r] = true
            fx.play('click')
            fx.shake(0.6)
        end
    end
    local last = anim.last
    if anim.t >= last then
        if anim.kind == 'weapon' then
            fx.play('win'); fx.shake(3.5); flash = { t = 0, kind = 'win', weapon = anim.target }
        elseif anim.kind == 'empty' then
            fx.play('lose'); fx.shake(2); flash = { t = 0, kind = 'lose' }
        else
            flash = { t = 0, kind = 'keep' }
        end
        local message = anim.message
        anim = nil
        return message
    end
end

-- 这个轮子现在还要多滚几格（小数，滚动中有拖影）
local function rolling(r)
    if not anim or anim.held[r] then return 0 end
    local stopAt = LEVER_T + SPIN + (r - 1) * STAGGER
    if anim.t < LEVER_T then return anim.travel[r] end
    local p = math.min(1, (anim.t - LEVER_T) / (stopAt - LEVER_T))
    return (1 - p) ^ 2 * anim.travel[r]
end
M.rolling = rolling

-- 拉杆角度：0 = 竖着，1 = 压到底
local function leverDown()
    if not anim then return 0 end
    if anim.t < LEVER_T then return anim.t / LEVER_T end
    return math.max(0, 1 - (anim.t - LEVER_T) / 0.25)
end

-- 像素层：手臂、轮子窗口、锁扣、拉杆。drawCell(x, y, w, h, sym, isMid, alpha) 由调用方在 UI 层画图标
-- offs：每个轮子另外拨过几格（刻图案时拨开看的位置，松手不弹回）；可以不给。noControls：刻图案时不画"用血转"按钮
function M.draw(arm, held, dragReel, dragOff, drawCell, offs, noControls)
    local g = love.graphics
    local x0, y0 = M.X, M.Y
    -- 上臂（从画面上方伸下来，接在断口）
    g.setColor(0.42, 0.36, 0.30); g.rectangle('fill', x0 + 44, y0 - 10, 44, 26, 6, 6)
    g.setColor(0.55, 0.47, 0.38); g.rectangle('fill', x0 + 44, y0 - 10, 44, 6)
    -- 铆钉环（断口）
    g.setColor(0.36, 0.28, 0.17); g.rectangle('fill', x0 + 36, y0 + 12, 60, 10, 3, 3)
    g.setColor(0.78, 0.62, 0.36)
    for k = 0, 5 do g.circle('fill', x0 + 42 + k * 10, y0 + 17, 1.5) end
    -- 铜壳的亮面、包边和氧化的接缝，随放大的手臂一起绘制。
    g.push()
    g.translate(x0, y0)
    g.setColor(0.09, 0.12, 0.13)
    g.polygon('fill', 0, 33, 12, 19, 115, 19, 130, 32, 130, 174, 112, 192, 16, 192, 0, 176)
    g.setColor(0.36, 0.26, 0.17)
    g.polygon('fill', 2, 33, 13, 21, 114, 21, 127, 33, 127, 172, 112, 188, 17, 188, 2, 174)
    g.setColor(0.59, 0.41, 0.23)
    g.polygon('fill', 3, 33, 14, 22, 113, 22, 123, 32, 117, 40, 10, 40)
    g.setColor(0.83, 0.62, 0.34)
    g.polygon('fill', 3, 34, 14, 22, 108, 22, 95, 24, 15, 25, 5, 39)
    g.setColor(0.23, 0.22, 0.17)
    g.polygon('fill', 4, 170, 12, 176, 111, 176, 123, 163, 123, 173, 111, 185, 18, 185)
    g.setColor(0.23, 0.30, 0.26)
    g.line(4, 47, 8, 43, 46, 43)
    g.line(49, 43, 116, 43, 123, 36)
    g.setColor(0.71, 0.54, 0.30)
    for _, x in ipairs({ 8, 119 }) do
        for _, y in ipairs({ 35, 176 }) do
            g.circle('fill', x, y, 2)
            g.setColor(0.18, 0.17, 0.13)
            g.line(x - 1, y + 1, x + 1, y - 1)
            g.setColor(0.71, 0.54, 0.30)
        end
    end
    g.pop()
    -- 轮子窗口
    local fl = flash and flash.t < 0.8 and flash or nil
    for r = 1, 3 do
        local rx, ry, rw, rh = M.reelRect(r)
        g.setColor(0.10, 0.08, 0.06); g.rectangle('fill', rx - 2, ry - 2, rw + 4, rh + 4, 4, 4)
        g.setColor(0.08, 0.13, 0.14); g.rectangle('fill', rx, ry, rw, rh, 3, 3)
        g.setColor(0.42, 0.40, 0.28); g.rectangle('fill', rx, ry, rw, 1)
        g.setColor(0.12, 0.19, 0.19)
        for row = 1, 2 do g.rectangle('fill', rx + 2, ry + row * M.CELL_H, rw - 4, 1) end
        -- 中间一格亮一点
        g.setColor(held[r] and { 0.30, 0.23, 0.08 } or { 0.13, 0.17, 0.17 })
        g.rectangle('fill', rx, ry + M.CELL_H, rw, M.CELL_H)
        -- 锁扣
        if not noControls then
            local lx, ly, lw, lh = M.lockRect(r)
            g.setColor(held[r] and { 0.78, 0.58, 0.20 } or { 0.24, 0.19, 0.12 })
            g.rectangle('fill', lx, ly, lw, lh, 3, 3)
            g.setColor(held[r] and { 0.95, 0.78, 0.35 } or { 0.40, 0.32, 0.20 })
            g.rectangle('line', lx + 0.5, ly + 0.5, lw - 1, lh - 1, 3, 3)
        end
    end
    -- 中奖线
    local lx0 = reelX(1) - 4
    local lw = M.REEL_W * 3 + M.GAP * 2 + 8
    if fl and fl.kind == 'win' then
        local a = 0.48 * (1 - fl.t / 0.8)
        g.setColor(1.0, 0.82, 0.35, a); g.rectangle('fill', lx0, M.REELS_Y + M.CELL_H - 2, lw, M.CELL_H + 4)
    elseif fl and fl.kind == 'lose' then
        g.setColor(0.4, 0.4, 0.45, 0.4 * (1 - fl.t / 0.8)); g.rectangle('fill', lx0, M.REELS_Y + M.CELL_H - 2, lw, M.CELL_H + 4)
    end
    g.setColor(0.94, 0.77, 0.42); g.setLineWidth(1)
    g.rectangle('line', lx0 + 0.5, M.REELS_Y + M.CELL_H - 1.5, lw - 1, M.CELL_H + 3)
    local midY = M.REELS_Y + M.CELL_H * 1.5
    g.polygon('fill', lx0 - 5, midY - 3, lx0, midY, lx0 - 5, midY + 3)
    g.polygon('fill', lx0 + lw + 5, midY - 3, lx0 + lw, midY, lx0 + lw + 5, midY + 3)
    -- 拉杆
    local d = leverDown()
    local ang = -0.25 + d * 1.6
    local len = 44
    local kx = M.LEVER_X + math.sin(ang) * len
    local ky = M.LEVER_Y - math.cos(ang) * len
    g.setColor(0.30, 0.24, 0.16); g.rectangle('fill', M.LEVER_X - 5, M.LEVER_Y - 6, 10, 18, 3, 3)
    g.setColor(0.62, 0.56, 0.48); g.setLineWidth(3); g.line(M.LEVER_X, M.LEVER_Y, kx, ky); g.setLineWidth(1)
    g.setColor(0.55, 0.16, 0.12); g.circle('fill', kx, ky + 1, 6)
    g.setColor(0.80, 0.25, 0.18); g.circle('fill', kx, ky, 6)
    g.setColor(1.0, 0.6, 0.5); g.circle('fill', kx - 2, ky - 2, 1.5)
    -- 用血转的按钮
    if not noControls then g.setColor(0.33, 0.11, 0.14); g.rectangle('fill', M.BLOOD.x, M.BLOOD.y, M.BLOOD.w, M.BLOOD.h, 3, 3) end

    -- 轮子上的印记（交给 UI 层画图标）：带小数偏移，滚动时画拖影
    for r = 1, 3 do
        local rx, ry, rw = M.reelRect(r)
        local off = rolling(r) + ((dragReel == r) and dragOff or 0) + (offs and offs[r] or 0)
        local center = arm.stops[r] - off
        local base = math.floor(center)
        local frac = center - base
        for row = -2, 2 do
            local k = (base + row - 1) % armMod.SIZE + 1
            local cy = ry + (row + 1 - frac) * M.CELL_H
            if cy > ry - M.CELL_H * 0.6 and cy < ry + M.CELL_H * 2.6 then
                local isMid = math.abs(cy - (ry + M.CELL_H)) < M.CELL_H * 0.5
                local moving = rolling(r) > 0.05
                drawCell(rx, cy, rw, M.CELL_H, arm.reels[r][k], isMid and not moving, moving and 0.55 or 1, ry, ry + M.CELL_H * 3)
                if moving then drawCell(rx, cy - M.CELL_H * 0.35, rw, M.CELL_H, arm.reels[r][k], false, 0.25, ry, ry + M.CELL_H * 3) end
            end
        end
    end
end

-- 结果出来那一下的大字（UI 层）
function M.flashInfo()
    if flash then return flash.kind, flash.t, flash.weapon end
    return nil
end

return M
