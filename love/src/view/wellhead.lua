local gems = require('view.gems')
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
    if c.kind == 'item' then
        if c.id == 'smallPotion' then
            g.setColor(1, 1, 1)
            g.draw(potion, cx, cy + 9, 0, 0.43, 0.43, potion:getWidth() / 2, potion:getHeight())
        else
            gems.draw(c.id, x, y, tile)
        end
    end
end
return M
