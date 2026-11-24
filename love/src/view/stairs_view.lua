-- 楼梯口：画成一面井壁上的一两个洞口，各冒出一点不同的东西（扬尘、水滴、雾），
-- 那句不说破的话写在洞口下面。点洞口下楼，"再想想"回到本层。

local M = {}

local parts = {}
M.holes = {}

-- opts：下一层的候选；levels：每个候选的 'loud'|'quiet'|'mid'
function M.open(levels)
    parts = {}
    M.holes = {}
    local n = #levels
    for k = 1, n do
        local cx = n == 2 and (k == 1 and 200 or 440) or 320
        M.holes[k] = { cx = cx, cy = 170, rx = 74, ry = 60, level = levels[k] }
    end
    M.back = { x = 270, y = 318, w = 100, h = 20 }
end

local function spawn(h, dt)
    local rate = h.level == 'loud' and 40 or (h.level == 'quiet' and 3 or 12)
    if love.math.random() < rate * dt then
        if h.level == 'loud' then
            -- 扬尘：从洞里往外飘
            parts[#parts + 1] = { kind = 'dust', x = h.cx + (love.math.random() - 0.5) * h.rx, y = h.cy + h.ry * 0.3, vx = (love.math.random() - 0.5) * 20, vy = -10 - love.math.random() * 20, t = 0, life = 1.2 }
        elseif h.level == 'quiet' then
            -- 水滴：从洞顶往下滴
            parts[#parts + 1] = { kind = 'drop', x = h.cx + (love.math.random() - 0.5) * h.rx, y = h.cy - h.ry * 0.7, vx = 0, vy = 0, t = 0, life = 1.0 }
        else
            -- 雾
            parts[#parts + 1] = { kind = 'mist', x = h.cx + (love.math.random() - 0.5) * h.rx * 1.2, y = h.cy + h.ry * 0.2, vx = (love.math.random() - 0.5) * 6, vy = -6, t = 0, life = 2.0 }
        end
    end
end

function M.update(dt)
    for _, h in ipairs(M.holes) do spawn(h, dt) end
    for k = #parts, 1, -1 do
        local p = parts[k]
        p.t = p.t + dt
        if p.kind == 'drop' then p.vy = p.vy + 120 * dt end
        p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
        if p.t > p.life then table.remove(parts, k) end
    end
end

-- 第几个洞口被点到（逻辑坐标）
function M.hit(lx, ly)
    for k, h in ipairs(M.holes) do
        if ((lx - h.cx) / h.rx) ^ 2 + ((ly - h.cy) / h.ry) ^ 2 <= 1 then return k end
    end
    return nil
end

function M.draw(hoverK, time)
    local g = love.graphics
    -- 井壁
    g.setColor(0.06, 0.07, 0.08); g.rectangle('fill', 0, 0, 640, 360)
    g.setColor(0.10, 0.10, 0.09)
    for y = 0, 360, 18 do
        for x = (y / 18) % 2 * 20, 640, 40 do g.rectangle('fill', x + 1, y + 1, 38, 16, 2, 2) end
    end
    for k, h in ipairs(M.holes) do
        local hov = hoverK == k
        -- 洞口的石框
        g.setColor(0.22, 0.19, 0.15); g.ellipse('fill', h.cx, h.cy, h.rx + 8, h.ry + 8)
        g.setColor(hov and { 0.45, 0.36, 0.22 } or { 0.30, 0.25, 0.19 }); g.ellipse('line', h.cx, h.cy, h.rx + 8, h.ry + 8)
        -- 洞里：越往里越黑
        for s = 0, 5 do
            local f = 1 - s / 6
            g.setColor(0.05 * f, 0.05 * f, 0.06 * f + 0.01)
            g.ellipse('fill', h.cx, h.cy + s * 2, h.rx * (1 - s * 0.12), h.ry * (1 - s * 0.12))
        end
        if hov then g.setColor(0.94, 0.77, 0.42, 0.25 + 0.1 * math.sin(time * 6)); g.ellipse('line', h.cx, h.cy, h.rx + 12, h.ry + 12) end
    end
    for _, p in ipairs(parts) do
        local a = 1 - p.t / p.life
        if p.kind == 'dust' then g.setColor(0.65, 0.58, 0.48, 0.6 * a); g.rectangle('fill', p.x, p.y, 1.5, 1.5)
        elseif p.kind == 'drop' then g.setColor(0.55, 0.75, 0.95, 0.8 * a); g.rectangle('fill', p.x, p.y, 1, 3)
        else g.setColor(0.70, 0.78, 0.80, 0.12 * a); g.circle('fill', p.x, p.y, 6 + p.t * 6) end
    end
    -- "再想想"按钮
    g.setColor(0.11, 0.16, 0.19); g.rectangle('fill', M.back.x, M.back.y, M.back.w, M.back.h, 3, 3)
end

return M
