-- 怪物以脚底为锚点。素材按 1280×720 窗口绘制，每两个素材像素对应一个逻辑像素。
local M = {}
local sprites = {}
local airborne = { bat = true, shriekBat = true, wraith = true, grudgeWraith = true }

function M.load(monsters)
    for id in pairs(monsters) do
        local sprite = love.graphics.newImage('assets/art/monsters/' .. id .. '.png')
        sprite:setFilter('nearest', 'nearest')
        sprites[id] = sprite
    end
end

function M.draw(id, cx, feet, clock, tileIndex)
    local g = love.graphics
    local sprite = sprites[id]
    local w, h = sprite:getDimensions()
    g.setColor(0.035, 0.027, 0.055, 0.62)
    g.ellipse('fill', cx, feet - 0.5, w * 0.18, 1.8)
    local lift = airborne[id] and (1 + math.floor(1 + 0.9 * math.sin(clock * 2.8 + tileIndex))) or 0
    g.setColor(1, 1, 1)
    g.draw(sprite, cx - math.floor(w / 2) * 0.5, feet - lift - h * 0.5, 0, 0.5, 0.5)
end

return M
