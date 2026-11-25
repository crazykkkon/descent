-- 一套印记共用于轮盘、刻印预览、地图持握和战斗动作。
local M = {}
local atlas, quads = nil, {}
local order = { 'boneKnife', 'harpoon', 'hammer', 'mossBlade', 'bellStaff', 'saltDagger',
    'rustSword', 'wellHook', 'lamp', 'twinHook', 'wild' }
local CELL = 96

function M.load()
    atlas = love.graphics.newImage('assets/art/arm/marks.png', { mipmaps = true })
    atlas:setFilter('linear', 'linear')
    atlas:setMipmapFilter('linear')
    for i, id in ipairs(order) do
        quads[id] = love.graphics.newQuad((i - 1) % 4 * CELL, math.floor((i - 1) / 4) * CELL,
            CELL, CELL, atlas:getDimensions())
    end
end

-- 由调用者设置颜色（可做滚动拖影及空格的浅色预览）。
function M.icon(id, x, y, size)
    love.graphics.draw(atlas, quads[id], x, y, 0, size / CELL, size / CELL, CELL / 2, CELL / 2)
end

-- 原画上握把约在 (34, 70)，刀尖朝右上。翻转围绕手掌进行。
function M.inHand(id, x, y, size, rotation, mirror, alpha)
    if not id then return end
    local g = love.graphics
    g.push()
    g.translate(x, y)
    if mirror then g.scale(-1, 1) end
    g.setColor(1, 1, 1, alpha or 1)
    g.draw(atlas, quads[id], 0, 0, rotation, size / CELL, size / CELL, 34, 70)
    g.pop()
end

function M.glint(x, y, strength, size)
    if strength <= 0 then return end
    local g = love.graphics
    g.push()
    g.translate(x, y)
    g.scale(size, size)
    g.setColor(1, 0.85, 0.53, strength)
    g.polygon('fill', -1, 0, -0.22, -0.15, 0, -1, 0.19, -0.19, 1, 0, 0.18, 0.16, 0, 1, -0.16, 0.18)
    g.pop()
end

function M.cut(x, y, w, h, t)
    local g = love.graphics
    local p = math.min(1, t / 0.24)
    local a = math.max(0, 1 - t / 0.54)
    local x0, y0 = x + 0.21 * w, y + 0.82 * h
    local tx, ty = x0 + 0.60 * w * p, y0 - 0.64 * h * p
    g.setColor(1, 0.76, 0.38, a * 0.95)
    g.polygon('fill', x0, y0, tx - 0.05 * w, ty, tx, ty - 0.03 * h, tx, ty + 0.06 * h)
    M.glint(tx, ty, a, w * 0.13)
end

return M
