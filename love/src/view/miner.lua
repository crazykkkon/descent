local marks = require('view.weapon_marks')
local M = {}
local sprites = {}
local sideLight = { left = -6, right = 6, up = 0, down = 0 }

function M.load()
    for _, name in ipairs({ 'side', 'front', 'back' }) do
        local image = love.graphics.newImage('assets/art/miner/' .. name .. '.png')
        image:setFilter('linear', 'nearest')
        sprites[name] = image
    end
end

function M.restoreFacing(saved)
    return sideLight[saved] and saved or 'down'
end

function M.lampOffset(facing)
    return 16 + sideLight[facing], facing == 'up' and 4 or 10
end

-- tall：画多高（逻辑像素，默认 28）
-- alpha：透明度（战斗窗口淡入淡出用，不给就是 1）
function M.draw(facing, cx, feet, dead, tall, alpha)
    local image = facing == 'down' and sprites.front or facing == 'up' and sprites.back or sprites.side
    local width, height = image:getDimensions()
    local scale = (tall or 28) / height
    local tint = dead and 0.45 or 1
    love.graphics.setColor(tint, tint, tint, alpha or 1)
    love.graphics.draw(image, cx, feet, 0, facing == 'left' and -scale or scale, scale, width / 2, height)
end

function M.drawOnMap(facing, cx, feet, dead, flash, weapon, glint)
    local g = love.graphics
    g.setColor(0, 0, 0, 0.35)
    g.ellipse('fill', cx, feet - 1, 9, 2)
    local leftHandOnScreen = facing == 'left' or facing == 'down'
    local handX, handY = cx + (leftHandOnScreen and -6 or 6), feet - 9
    if weapon and not dead and facing == 'up' then marks.inHand(weapon, handX, handY, 18, 0.2, false) end
    M.draw(facing, cx, feet, dead, 30)
    if weapon and not dead then
        if facing ~= 'up' then marks.inHand(weapon, handX, handY, 18, 0.2, leftHandOnScreen) end
        marks.glint(handX, handY - 1, glint or 0, 6)
    end
    if flash > 0 then
        g.setBlendMode('add')
        g.setColor(1, 0.2, 0.2, flash * 0.5)
        g.ellipse('fill', cx, feet - 14, 10, 14)
        g.setBlendMode('alpha')
    end
end

return M
