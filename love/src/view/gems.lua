-- 四枚原画使用相同的脚底锚点，井口和正式层都按地图格宽绘制。
local M = {}
local order = { 'redGem', 'blueGem', 'bigRedGem', 'bigBlueGem' }
local atlas, quads = nil, {}

function M.load()
    local g = love.graphics
    atlas = g.newImage('assets/art/items/gems.png', { mipmaps = true })
    atlas:setFilter('linear', 'linear')
    atlas:setMipmapFilter('linear')
    local size = atlas:getHeight()
    for i, id in ipairs(order) do
        quads[id] = g.newQuad((i - 1) * size, 0, size, size, atlas:getDimensions())
    end
end

function M.draw(id, x, y, tile)
    local quad = quads[id]
    if not quad then return end
    local scale = tile / atlas:getHeight()
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(atlas, quad, x, y, 0, scale, scale)
end

return M
