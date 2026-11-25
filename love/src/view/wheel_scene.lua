-- 大转盘的场景（制作人 2026-11-25：地图里的转盘要做成拉摇杆、真的会转的转盘）。
-- 画面中间一个八格的大转盘，顶上一个指针，右边一根红头摇杆。拉摇杆（或点"金币 / 生命"按钮）：
-- 摇杆往下一拉，转盘转几圈、越转越慢，停在结果那一格上，那一格亮起来，再结算。
-- 结果在开转之前就由种子定好了（run:wheelPeek），停下来才调 run:wheelSpin 结算，所以顶栏的数值不会提前剧透。
-- 白盒：程序画的，正式美术由 Codex 替换，接口不变。

local fx = require('view.fx')
local wheelMod = require('core.wheel')

local M = {}

local CX, CY, R = 250, 200, 98                  -- 转盘中心和半径（逻辑坐标 640×360）
local LEVER = { x = 372, y = 112, w = 26, h = 150 }
local BTN = { x = 432, w = 150, h = 22 }
local SPIN_TIME, TURNS = 2.6, 4
local N = #wheelMod.SECTORS
local STEP = 2 * math.pi / N

local COLORS = {
    gold = { 0.78, 0.6, 0.2 }, hp = { 0.72, 0.24, 0.3 }, atk = { 0.82, 0.42, 0.24 }, def = { 0.25, 0.45, 0.75 },
    engrave = { 0.52, 0.38, 0.72 }, leech = { 0.22, 0.3, 0.18 }, erase = { 0.36, 0.36, 0.4 },
}
local LABEL = {
    gold = function(s) return '金币', '+' .. s.amount end,
    hp = function(s) return '生命', '+' .. s.amount end,
    atk = function(s) return '攻击', '+' .. s.amount end,
    def = function(s) return '防御', '+' .. s.amount end,
    engrave = function() return '新', '图案' end,
    leech = function(s) return '井蛭', '−' .. s.amount end,
    erase = function() return '擦掉', '图案' end,
}

-- st = { i, ctx, angle, from, to, t, spinning, pay, sector, lever, flash, result, msg, err, tick }
local st = nil

function M.active() return st ~= nil end
function M.busy() return st ~= nil and (st.spinning or st.next ~= nil) end

-- ctx = { price() -> { gold, blood }, hero() -> hero, peek() -> 格（从 1 开始）, apply(pay) -> 结果,
--         after(结果) -> 要接着做的事（函数：停一下以后关掉转盘再做，比如倒下、刻新图案）或 nil（留在转盘前） }
function M.open(i, ctx)
    st = { i = i, ctx = ctx, angle = 0, t = 0, spinning = false, lever = 0, flash = 0, msg = nil, err = false, tick = 0 }
    fx.play('lever')
end

function M.close()
    if st and not st.spinning and not st.next then st = nil end
end

local function easeOut(p) return 1 - (1 - p) ^ 3 end

-- 开转：先看能不能付，再看会停在哪一格，转盘转到那一格以后再结算
function M.spin(pay)
    if not st or st.spinning or st.next then return end
    local price, h = st.ctx.price(), st.ctx.hero()
    if pay == 'gold' and h.gold < price.gold then st.msg, st.err = '金币不够（要 ' .. price.gold .. '）', true; fx.shake(1); return end
    if pay == 'blood' and h.hp <= price.blood then st.msg, st.err = '需要消耗 ' .. price.blood .. ' 点生命，支付后至少要剩 1 点', true; fx.shake(1); return end
    local sector = st.ctx.peek()
    -- 第 k 格的中心在顺时针 (k − 0.5) × 一格 的地方；转盘顺时针转 angle 以后，它要正好转到顶上的指针下面
    local target = -((sector - 0.5) * STEP)
    local base = st.angle
    local delta = (target - base) % (2 * math.pi)
    st.from, st.to = base, base + TURNS * 2 * math.pi + delta
    st.t, st.spinning, st.pay, st.sector, st.msg, st.err, st.flash = 0, true, pay, sector, nil, false, 0
    st.tick = math.floor(base / STEP)
    fx.play('lever')
end

function M.update(dt)
    if not st then return end
    if st.lever > 0 or st.spinning then
        -- 摇杆：拉下去 0.15 秒，慢慢弹回来
        if st.spinning and st.t < 0.15 then st.lever = math.min(1, st.t / 0.15)
        else st.lever = math.max(0, st.lever - dt * 2) end
    end
    if st.flash > 0 then st.flash = st.flash + dt end
    -- 停下来以后要接着做事（倒下、刻新图案）：先让人看清停在哪一格，再关掉
    if st.next then
        st.wait = st.wait - dt
        if st.wait <= 0 then local f = st.next; st = nil; f() end
        return
    end
    if not st.spinning then return end
    st.t = st.t + dt
    local p = math.min(1, st.t / SPIN_TIME)
    st.angle = st.from + (st.to - st.from) * easeOut(p)
    -- 每转过一格"咔"一声
    local tick = math.floor(st.angle / STEP)
    if tick ~= st.tick then st.tick = tick; fx.play('click', 0.9 + 0.3 * (1 - p)) end
    if p >= 1 then
        st.spinning = false
        st.angle = st.to % (2 * math.pi)
        st.flash = 0.001
        local res = st.ctx.apply(st.pay)
        st.result = res
        st.msg, st.err = res.msg, not res.ok
        local s = wheelMod.SECTORS[st.sector]
        if s.prize == 'leech' then fx.play('lose'); fx.shake(3) else fx.play('win'); fx.shake(2) end
        local nxt = st.ctx.after(res)
        if nxt then st.next, st.wait = nxt, 1.1 end
    end
end

-- 停下来以后可以点一下跳过剩下的转动
function M.skip()
    if st and st.spinning then st.t = SPIN_TIME end
end

local function inRect(x, y, r) return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h end
local function buttons()
    local price = st.ctx.price()
    return {
        { id = 'gold', label = '花 ' .. price.gold .. ' 金币转一次', x = BTN.x, y = 150, w = BTN.w, h = BTN.h, primary = true },
        { id = 'blood', label = '花 ' .. price.blood .. ' 点生命转一次', x = BTN.x, y = 180, w = BTN.w, h = BTN.h },
        { id = 'leave', label = '离开（Esc）', x = BTN.x, y = 226, w = BTN.w, h = BTN.h },
    }
end

function M.click(lx, ly)
    if not st then return end
    if st.spinning then M.skip(); return end
    if st.next then st.wait = 0; return end
    if inRect(lx, ly, LEVER) or (lx - (LEVER.x + LEVER.w / 2)) ^ 2 + (ly - LEVER.y) ^ 2 < 14 ^ 2 then M.spin('gold'); return end
    for _, b in ipairs(buttons()) do
        if inRect(lx, ly, b) then
            if b.id == 'leave' then M.close() else M.spin(b.id) end
            return
        end
    end
end

function M.key(k)
    if not st then return false end
    if k == 'escape' then M.close(); return true end
    if st.next then st.wait = 0; return true end
    if k == 'space' or k == 'return' then if st.spinning then M.skip() else M.spin('gold') end; return true end
    return true
end

-- g = { text, rect, S, OX, OY, LW, LH, clock }
function M.draw(g)
    if not st then return end
    local G = love.graphics
    g.rect({ 0.01, 0.02, 0.03 }, 0, 0, g.LW, g.LH, 0.92)
    g.text('大转盘', 0, 12, 13, { 1, 0.9, 0.6 }, 'center', g.LW)
    g.text('每格停中的概率都是 12.5%。在这里每多转一次，花费就上涨约五成。', 0, 32, 7.5, { 0.6, 0.66, 0.68 }, 'center', g.LW)

    G.push(); G.translate(g.OX, g.OY); G.scale(g.S, g.S)
    -- 底座和外圈
    G.setColor(0.12, 0.09, 0.06); G.circle('fill', CX, CY, R + 12)
    G.setColor(0.55, 0.4, 0.2); G.setLineWidth(3); G.circle('line', CX, CY, R + 9); G.setLineWidth(1)
    -- 外圈的小灯：停下来以后一闪一闪
    for k = 0, 23 do
        local a = k / 24 * 2 * math.pi
        local on = st.spinning and ((k + math.floor(st.t * 12)) % 2 == 0) or (st.flash > 0 and (k + math.floor(st.flash * 8)) % 2 == 0)
        G.setColor(on and 1 or 0.45, on and 0.85 or 0.35, on and 0.45 or 0.18)
        G.circle('fill', CX + math.cos(a) * (R + 9), CY + math.sin(a) * (R + 9), 1.8)
    end
    -- 八格：从顶上开始顺时针，整体转 angle
    for k, s in ipairs(wheelMod.SECTORS) do
        local a0 = -math.pi / 2 + (k - 1) * STEP + st.angle
        local col = COLORS[s.prize] or { 0.5, 0.5, 0.5 }
        local lit = (not st.spinning) and st.flash > 0 and k == st.sector
        local m = lit and (1.15 + 0.25 * math.sin(st.flash * 12)) or ((k % 2 == 0) and 0.85 or 1)
        G.setColor(col[1] * m, col[2] * m, col[3] * m)
        G.arc('fill', CX, CY, R, a0, a0 + STEP, 16)
        G.setColor(0.1, 0.07, 0.05); G.setLineWidth(1.5)
        G.line(CX, CY, CX + math.cos(a0) * R, CY + math.sin(a0) * R)
        G.setLineWidth(1)
    end
    G.pop()
    -- 格子上的字（不跟着转字的方向，免得倒过来看不清）
    for k, s in ipairs(wheelMod.SECTORS) do
        local mid = -math.pi / 2 + (k - 0.5) * STEP + st.angle
        local tx, ty = CX + math.cos(mid) * R * 0.64, CY + math.sin(mid) * R * 0.64
        local a, b = LABEL[s.prize](s)
        local lit = (not st.spinning) and st.flash > 0 and k == st.sector
        local c = lit and { 1, 1, 0.9 } or { 0.98, 0.95, 0.88 }
        g.text(a, tx - 20, ty - 9, 7.5, c, 'center', 40)
        g.text(b, tx - 20, ty + 1, 8, c, 'center', 40)
    end
    G.push(); G.translate(g.OX, g.OY); G.scale(g.S, g.S)
    -- 中间的轴
    G.setColor(0.3, 0.22, 0.12); G.circle('fill', CX, CY, 16)
    G.setColor(0.7, 0.55, 0.3); G.circle('fill', CX, CY, 9)
    G.setColor(0.95, 0.85, 0.6); G.circle('fill', CX - 2, CY - 2, 3)
    -- 顶上的指针
    G.setColor(0.08, 0.05, 0.03); G.polygon('fill', CX - 11, CY - R - 16, CX + 11, CY - R - 16, CX, CY - R + 10)
    G.setColor(0.95, 0.3, 0.25); G.polygon('fill', CX - 8, CY - R - 14, CX + 8, CY - R - 14, CX, CY - R + 6)
    -- 摇杆：一根轨道、一根杆、红头；拉的时候往下走
    local lx = LEVER.x + LEVER.w / 2
    G.setColor(0.18, 0.13, 0.08); G.rectangle('fill', LEVER.x + 7, LEVER.y, LEVER.w - 14, LEVER.h, 4, 4)
    G.setColor(0.4, 0.3, 0.16); G.rectangle('fill', LEVER.x, LEVER.y + LEVER.h - 18, LEVER.w, 18, 3, 3)
    local ky = LEVER.y + st.lever * (LEVER.h - 34)
    G.setColor(0.6, 0.6, 0.62); G.setLineWidth(4); G.line(lx, LEVER.y + LEVER.h - 12, lx, ky); G.setLineWidth(1)
    G.setColor(0.45, 0.06, 0.06); G.circle('fill', lx, ky, 12)
    G.setColor(0.9, 0.2, 0.18); G.circle('fill', lx, ky, 10)
    G.setColor(1, 0.75, 0.7); G.circle('fill', lx - 3, ky - 3, 3)
    G.pop()
    g.text('拉', LEVER.x - 4, LEVER.y + LEVER.h + 4, 7, { 0.85, 0.75, 0.55 }, 'center', LEVER.w + 8)

    -- 右边：价格按钮、身上的钱和血、结果
    local h, mx, my = st.ctx.hero(), love.mouse.getPosition()
    local lmx, lmy = (mx - g.OX) / g.S, (my - g.OY) / g.S
    g.text('你有 ' .. h.gold .. ' 金币、' .. h.hp .. ' 生命', BTN.x, 128, 7.5, { 0.75, 0.75, 0.72 }, 'left', BTN.w)
    for _, b in ipairs(buttons()) do
        local hover = not st.spinning and inRect(lmx, lmy, b)
        local bg = b.primary and { 0.16, 0.42, 0.34 } or (b.id == 'blood' and { 0.45, 0.13, 0.16 } or { 0.11, 0.16, 0.19 })
        g.rect(hover and { bg[1] * 1.3, bg[2] * 1.3, bg[3] * 1.3 } or bg, b.x, b.y, b.w, b.h, st.spinning and 0.4 or 0.95, 4)
        g.text(b.label, b.x, b.y + 6, 8, { 0.95, 0.95, 0.92 }, 'center', b.w, st.spinning and 0.5 or 1)
    end
    if st.spinning then
        g.text('转盘转动中，点击可加快停转。', BTN.x, 262, 7.5, { 0.6, 0.66, 0.68 }, 'left', BTN.w + 40)
    elseif st.msg then
        local col = st.err and { 1, 0.45, 0.45 } or { 1, 0.88, 0.5 }
        g.text(st.msg, BTN.x - 10, 262, 8, col, 'left', 200)
    end
end

return M
