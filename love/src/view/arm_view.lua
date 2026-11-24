-- 断臂转轮的画面：画成接在矿工断口上的铜铁机械小臂，三个竖转轮嵌在小臂里，旁边一根拉杆。
-- 像素层（逻辑坐标）画手臂、轮子底色、拉杆；字由 main.lua 的 UI 层画（调用 drawText）。
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
function M.startSpin(held, faces)
    local kind = armMod.outcome(faces)
    anim = { t = 0, held = { held[1], held[2], held[3] }, faces = faces, kind = kind, clicked = {} }
    fx.play('lever')
end

function M.busy() return anim ~= nil end

function M.update(dt)
    if flash then
        flash.t = flash.t + dt
        if flash.t > 0.8 then flash = nil end
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
    local last = LEVER_T + SPIN + 2 * STAGGER
    if not anim.done and anim.t >= last then
        anim.done = true
        if anim.kind == 'weapon' then
            fx.play('win'); fx.shake(3.5); flash = { t = 0, kind = 'win' }
        elseif anim.kind == 'empty' then
            fx.play('lose'); fx.shake(2); flash = { t = 0, kind = 'lose' }
        end
    end
    if anim.t > last + 0.25 then anim = nil end
end

-- 这个轮子现在还要多滚几格（小数，滚动中有拖影）
local function rolling(r)
    if not anim or anim.held[r] then return 0 end
    local stopAt = LEVER_T + SPIN + (r - 1) * STAGGER
    if anim.t < LEVER_T then return 10 + r * 4 end
    local p = math.min(1, (anim.t - LEVER_T) / (stopAt - LEVER_T))
    return (1 - p) ^ 2 * (10 + r * 4)
end
M.rolling = rolling

-- 拉杆角度：0 = 竖着，1 = 压到底
local function leverDown()
    if not anim then return 0 end
    if anim.t < LEVER_T then return anim.t / LEVER_T end
    return math.max(0, 1 - (anim.t - LEVER_T) / 0.25)
end

-- 像素层：手臂、轮子窗口、锁扣、拉杆。drawCellText(x, y, w, h, sym, isMid, alpha) 由调用方在 UI 层画字
function M.draw(arm, held, dragReel, dragOff, drawCellText)
    local g = love.graphics
    local x0, y0 = M.X, M.Y
    -- 上臂（从画面上方伸下来，接在断口）
    g.setColor(0.42, 0.36, 0.30); g.rectangle('fill', x0 + 44, y0 - 10, 44, 26, 6, 6)
    g.setColor(0.55, 0.47, 0.38); g.rectangle('fill', x0 + 44, y0 - 10, 44, 6)
    -- 铆钉环（断口）
    g.setColor(0.36, 0.28, 0.17); g.rectangle('fill', x0 + 36, y0 + 12, 60, 10, 3, 3)
    g.setColor(0.78, 0.62, 0.36)
    for k = 0, 5 do g.circle('fill', x0 + 42 + k * 10, y0 + 17, 1.5) end
    -- 小臂（铜壳）
    g.setColor(0.29, 0.23, 0.14); g.rectangle('fill', x0 + 2, y0 + 22, 128, 170, 14, 14)
    g.setColor(0.45, 0.35, 0.21); g.rectangle('fill', x0, y0 + 20, 128, 164, 14, 14)
    g.setColor(0.56, 0.44, 0.27); g.rectangle('fill', x0 + 4, y0 + 24, 120, 6, 4, 4)
    -- 壳上的铆钉
    g.setColor(0.72, 0.58, 0.34)
    for _, p in ipairs({ { 8, 34 }, { 120, 34 }, { 8, 176 }, { 120, 176 } }) do g.circle('fill', x0 + p[1], y0 + p[2], 2) end
    -- 轮子窗口
    local fl = flash and flash.t < 0.8 and flash or nil
    for r = 1, 3 do
        local rx, ry, rw, rh = M.reelRect(r)
        g.setColor(0.10, 0.08, 0.06); g.rectangle('fill', rx - 2, ry - 2, rw + 4, rh + 4, 4, 4)
        g.setColor(0.06, 0.07, 0.08); g.rectangle('fill', rx, ry, rw, rh, 3, 3)
        -- 中间一格亮一点
        g.setColor(held[r] and { 0.30, 0.23, 0.08 } or { 0.13, 0.17, 0.17 })
        g.rectangle('fill', rx, ry + M.CELL_H, rw, M.CELL_H)
        -- 锁扣
        local lx, ly, lw, lh = M.lockRect(r)
        g.setColor(held[r] and { 0.78, 0.58, 0.20 } or { 0.24, 0.19, 0.12 })
        g.rectangle('fill', lx, ly, lw, lh, 3, 3)
        g.setColor(held[r] and { 0.95, 0.78, 0.35 } or { 0.40, 0.32, 0.20 })
        g.rectangle('line', lx + 0.5, ly + 0.5, lw - 1, lh - 1, 3, 3)
    end
    -- 中奖线
    local lx0 = reelX(1) - 4
    local lw = M.REEL_W * 3 + M.GAP * 2 + 8
    if fl and fl.kind == 'win' then
        local a = 0.55 * (1 - fl.t / 0.8)
        g.setColor(1.0, 0.82, 0.35, a); g.rectangle('fill', lx0, M.REELS_Y + M.CELL_H - 2, lw, M.CELL_H + 4)
    elseif fl and fl.kind == 'lose' then
        g.setColor(0.4, 0.4, 0.45, 0.4 * (1 - fl.t / 0.8)); g.rectangle('fill', lx0, M.REELS_Y + M.CELL_H - 2, lw, M.CELL_H + 4)
    end
    g.setColor(0.94, 0.77, 0.42); g.setLineWidth(1)
    g.rectangle('line', lx0 + 0.5, M.REELS_Y + M.CELL_H - 1.5, lw - 1, M.CELL_H + 3)
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
    g.setColor(0.33, 0.11, 0.14); g.rectangle('fill', M.BLOOD.x, M.BLOOD.y, M.BLOOD.w, M.BLOOD.h, 3, 3)

    -- 轮子上的图案（交给 UI 层画字）：带小数偏移，滚动时画拖影
    for r = 1, 3 do
        local rx, ry, rw = M.reelRect(r)
        local off = rolling(r) + ((dragReel == r) and dragOff or 0)
        local center = arm.stops[r] - off
        local base = math.floor(center)
        local frac = center - base
        for row = -2, 2 do
            local k = (base + row - 1) % armMod.SIZE + 1
            local cy = ry + (row + 1 - frac) * M.CELL_H
            if cy > ry - M.CELL_H * 0.6 and cy < ry + M.CELL_H * 2.6 then
                local isMid = math.abs(cy - (ry + M.CELL_H)) < M.CELL_H * 0.5
                local moving = rolling(r) > 0.05
                drawCellText(rx, cy, rw, M.CELL_H, arm.reels[r][k], isMid and not moving, moving and 0.55 or 1, ry, ry + M.CELL_H * 3)
                if moving then drawCellText(rx, cy - M.CELL_H * 0.35, rw, M.CELL_H, arm.reels[r][k], false, 0.25, ry, ry + M.CELL_H * 3) end
            end
        end
    end
end

-- 结果出来那一下的大字（UI 层）
function M.flashInfo()
    if flash then return flash.kind, flash.t end
    return nil
end

return M
