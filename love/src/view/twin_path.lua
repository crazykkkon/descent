-- “双道”美术样板。图集中的每个图像占一个 32×32 格。
local M = {}
local names = {
    'hero', 'eel', 'frog', 'moss', 'smallPotion', 'redGem',
    'floor1', 'floor2', 'floor3', 'rock', 'ledge', 'exit', 'iron', 'roots', 'lamp',
}
local ground = { 'floor1', 'floor2', 'floor3' }
local image, quads = nil, {}

function M.load()
    image = love.graphics.newImage('assets/art/twin-path.png')
    image:setFilter('nearest', 'nearest')
    for i, name in ipairs(names) do
        quads[name] = love.graphics.newQuad((i - 1) * 32, 0, 32, 32, image:getDimensions())
    end
end

function M.hasSprite(id)
    return quads[id] ~= nil
end

local function draw(name, x, y)
    love.graphics.draw(image, quads[name], x, y)
end

function M.drawCell(run, index, x, y)
    local cell = run.cells[index]
    love.graphics.setColor(1, 1, 1)
    if cell.kind == 'wall' then
        local south = run.cells[index + run.w]
        local stone = 'rock'
        if south and south.kind ~= 'wall' then
            stone = 'ledge'
        elseif index % 17 == 0 then
            stone = 'iron'
        elseif index % 7 == 0 then
            stone = 'roots'
        end
        draw(stone, x, y)
        return true
    end
    if cell.kind ~= 'floor' and cell.kind ~= 'exit' and not M.hasSprite(cell.id) then
        return false
    end
    draw(ground[1 + (index + math.floor((index - 1) / run.w)) % #ground], x, y)
    if cell.kind ~= 'floor' then
        draw(cell.kind == 'exit' and 'exit' or cell.id, x, y)
    end
    return true
end

function M.drawHero(x, y, dead)
    x, y = math.floor(x + 0.5), math.floor(y + 0.5)
    if not dead then
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(image, quads.lamp, x - 9, y - 18, 0, 2, 2)
    end
    local tint = dead and 0.4 or 1
    love.graphics.setColor(tint, tint, tint)
    draw('hero', x, y)
end

return M
