-- 开局界面的背景（像素层）：往下看的一口深井，井壁一圈圈往下退，一个矿工慢慢往下坠。
-- 白盒阶段程序画的，正式美术由 Codex 替换，接口不变：M.draw(LW, LH, clock)。

local miner = require('view.miner')

local M = {}

local RINGS = 9

function M.draw(LW, LH, clock)
    local g = love.graphics
    local cx, cy = LW * 0.64, LH * 0.56
    g.setColor(0.03, 0.04, 0.05); g.rectangle('fill', 0, 0, LW, LH)
    -- 井壁：从外往里一圈圈画，越往里越小越暗；整体慢慢往下"流"，像在往下坠
    local flow = (clock * 0.35) % 1
    for k = 0, RINGS do
        local d = (RINGS - k + flow) / RINGS          -- 1 = 最外圈，0 = 井底
        local r = 14 + d ^ 1.8 * 300
        local light = 0.10 + 0.32 * d ^ 1.2
        g.setColor(0.30 * light / 0.42, 0.25 * light / 0.42, 0.19 * light / 0.42)
        g.ellipse('fill', cx, cy, r, r * 0.62)
        -- 石缝：每圈几道
        g.setColor(0.08, 0.07, 0.06, 0.6 * d)
        for s = 0, 11 do
            local a = s / 12 * math.pi * 2 + k * 0.4
            g.rectangle('fill', cx + math.cos(a) * r * 0.97, cy + math.sin(a) * r * 0.6, 2, 2)
        end
        -- 内侧一圈更暗的阴影，让每一圈看起来是一节井壁
        g.setColor(0, 0, 0, 0.25)
        g.ellipse('fill', cx, cy + r * 0.04, r * 0.93, r * 0.57)
    end
    -- 井底：一点冷光
    g.setColor(0.01, 0.02, 0.03); g.ellipse('fill', cx, cy, 16, 10)
    g.setColor(0.35, 0.65, 0.75, 0.25 + 0.1 * math.sin(clock * 2)); g.ellipse('fill', cx, cy, 5, 3)
    -- 坠落的矿工：从井口往井底掉，越来越小，掉到底再从上面来一次
    local p = (clock / 5) % 1
    local scale = 1 - p * 0.85
    local mx = cx + math.sin(clock * 0.9) * 30 * scale
    local my = cy - 120 * (1 - p) ^ 1.5 + 10
    g.push()
    g.translate(mx, my)
    g.rotate(math.sin(clock * 1.3) * 0.5 + p * 2)
    g.scale(scale, scale)
    miner.draw('down', 0, 14, false, 26)
    g.pop()
    -- 从上面落下的水滴
    for k = 0, 5 do
        local t = (clock * 0.5 + k / 6) % 1
        local x = cx + math.sin(k * 7.1) * 140 * (1 - t)
        local y = 10 + t * (cy - 10)
        g.setColor(0.55, 0.75, 0.95, 0.6 * (1 - t))
        g.rectangle('fill', math.floor(x), math.floor(y), 1, 3)
    end
    -- 左边压暗，给菜单留出地方
    for k = 0, 23 do
        g.setColor(0.02, 0.03, 0.04, 0.85 * (1 - k / 24))
        g.rectangle('fill', k * 10, 0, 10, LH)
    end
end

return M
