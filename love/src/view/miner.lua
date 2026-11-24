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

function M.draw(facing, cx, feet, dead)
    local image = facing == 'down' and sprites.front or facing == 'up' and sprites.back or sprites.side
    local width, height = image:getDimensions()
    local scale = 28 / height
    local tint = dead and 0.45 or 1
    love.graphics.setColor(tint, tint, tint)
    love.graphics.draw(image, cx, feet, 0, facing == 'left' and -scale or scale, scale, width / 2, height)
end

return M
