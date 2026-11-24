local M = {}
local map, potion

function M.load()
    map = love.graphics.newImage('assets/art/wellhead/map.png')
    potion = love.graphics.newImage('assets/art/wellhead/potion.png')
    map:setFilter('linear', 'nearest')
end

function M.drawMap(x, y, w, h)
    local g = love.graphics
    g.setColor(1, 1, 1)
    g.draw(map, x, y, 0, w / map:getWidth(), h / map:getHeight())
end

function M.drawObject(c, x, y, tile)
    local g = love.graphics
    local cx, cy = x + tile / 2, y + tile / 2
    -- 石缝属于画面。靠近路线边缘的短刻线标明实际格子的边界。
    g.setColor(0.10, 0.17, 0.18, 0.62)
    g.rectangle('fill', x, y + tile - 4, 1, 3)
    if c.kind == 'exit' then
        g.setColor(0.04, 0.14, 0.16)
        g.rectangle('fill', x + 2, y + 1, tile - 4, tile - 2)
        for i = 0, 3 do
            g.setColor(0.92 - i * 0.13, 0.75 - i * 0.09, 0.41)
            g.rectangle('fill', x + 5 + i, y + 3 + i * 4, tile - 10 - i * 2, 2)
        end
    elseif c.kind == 'item' then
        if c.id == 'smallPotion' then
            g.setColor(1, 1, 1)
            g.draw(potion, cx, cy + 9, 0, 0.43, 0.43, potion:getWidth() / 2, potion:getHeight())
        elseif c.id == 'redGem' or c.id == 'blueGem' then
            g.setColor(0.05, 0.14, 0.16)
            g.polygon('fill', cx, cy - 8, cx + 7, cy + 1, cx, cy + 9, cx - 7, cy + 1)
            if c.id == 'redGem' then
                g.setColor(0.86, 0.24, 0.12)
            else
                g.setColor(0.27, 0.76, 0.81)
            end
            g.polygon('fill', cx, cy - 6, cx + 5, cy + 1, cx, cy + 6, cx - 5, cy + 1)
            g.setColor(1, 0.9, 0.68)
            g.polygon('fill', cx, cy - 6, cx - 1, cy, cx - 4, cy + 1)
        end
    end
end
return M
