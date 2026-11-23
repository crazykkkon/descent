-- 双道的石桥与蓄水池。位置与输入仍使用关卡的 32 像素逻辑格。
local M = {}
local g = love.graphics
local tile = 32
local art, tops, fronts = {}, {}, {}
local widths = { miner = 24, eel = 30, frog = 28, moss = 27, smallPotion = 14, redGem = 18 }
local lighting, gallery

function M.load()
    local function load(key)
        local tex = g.newImage('assets/art/twin-path/' .. key .. '.png')
        tex:setFilter('linear', 'nearest')
        art[key] = tex
    end
    for id in pairs(widths) do load(id) end
    for _, id in ipairs({ 'slate', 'masonry', 'cistern', 'exit' }) do load(id) end
    gallery = g.newQuad(85, 40, 540, 170, art.cistern:getDimensions())
    for row = 0, 1 do
        for col = 0, 1 do
            tops[row * 2 + col + 1] = g.newQuad(col * 128, row * 128, 128, 128, art.slate:getDimensions())
        end
    end
    for col = 0, 3 do
        fronts[col + 1] = g.newQuad(col * 64, 0, 64, 88, art.masonry:getDimensions())
    end
    lighting = g.newShader([[
        extern vec2 origin;
        extern number zoom;
        extern vec2 headlamp;
        extern vec2 wallLamp;
        vec4 effect(vec4 tint, Image material, vec2 uv, vec2 screen) {
            vec3 stone = Texel(material, uv).rgb;
            vec2 p = (screen - origin) / zoom;
            float h = exp(-length((p-headlamp)*vec2(0.052,0.074)));
            float w = exp(-length((p-wallLamp)*vec2(0.054,0.066)));
            float pool = h + 0.90*w;
            float ridge = smoothstep(0.24,0.60,max(stone.r,stone.b));
            float seams = smoothstep(0.035,0.22,stone.r);
            vec3 light = stone * vec3(0.83,0.91,1.06);
            light += pool * (stone*vec3(3.2,1.78,0.19) + seams*vec3(0.28,0.12,0.002));
            light += ridge * ridge * pool * vec3(0.95,0.48,0.11);
            return vec4(light*tint.rgb,tint.a);
        }
    ]])
end

function M.hasSprite(id) return widths[id] ~= nil end

local function sprite(id, cx, bottom, width)
    local tex = art[id]
    local size = width / tex:getWidth()
    g.draw(tex, cx - width / 2, bottom - size * tex:getHeight(), 0, size, size)
end

local function shadow(cx, y, radius, direction)
    g.setColor(0.025, 0.028, 0.045, 0.30)
    g.ellipse('fill', cx + direction * 3, y + 0.5, radius * 1.12, radius * 0.32)
    g.setColor(0.014, 0.019, 0.026, 0.65)
    g.ellipse('fill', cx, y, radius * 0.76, radius * 0.19)
end

local function drawBridge(run, ox, oy)
    g.setColor(1,1,1)
    for i, cell in ipairs(run.cells) do
        if cell.kind ~= 'wall' then
            local col, row = (i - 1) % run.w, math.floor((i - 1) / run.w)
            local x, y = ox + col * tile, oy + row * tile
            local below = run.cells[i + run.w]
            if not below or below.kind == 'wall' then
                g.setColor(0.64, 0.64, 0.68)
                g.draw(art.masonry, fronts[col % 4 + 1], x, y + tile, 0, 0.5, 0.23)
            end
            local east = col < run.w - 1 and run.cells[i + 1]
            if east and east.kind == 'wall' then
                g.setColor(0.38, 0.43, 0.53)
                g.draw(art.masonry, fronts[row % 4 + 1], x + tile, y + 3, 0, 0.055, 0.48)
            end
            g.setColor(1, 1, 1)
            g.draw(art.slate, tops[(row % 2) * 2 + col % 2 + 1], x, y, 0, 0.25, 0.25)
        end
    end
end

-- 坐标以地图为原点，用同一组灯位给顶面和立面着色。
function M.drawScene(run, ox, oy, hx, hy, hovered, zoom, vx, vy)
    g.push('all')
    g.translate(vx, vy)
    g.scale(zoom)
    local width, height = run.w * tile, run.h * tile
    local sceneHeight = height + 24
    g.setScissor(vx + ox * zoom, vy + (oy - 3) * zoom, width * zoom, (sceneHeight + 3) * zoom)
    g.setColor(0.66, 0.71, 0.82)
    g.draw(art.cistern, gallery, ox, oy - 3, 0, width / 540, 102 / 170)
    local ledgeY = oy + tile * 3
    g.setColor(0.90, 0.93, 1.0)
    g.draw(art.cistern, ox, ledgeY, 0, width / art.cistern:getWidth(), (sceneHeight - tile*3) / art.cistern:getHeight())

    local dead = run.status == 'dead'
    local lampX, lampY = hx + 22, hy + 12
    g.setShader(lighting)
    lighting:send('origin', {vx, vy})
    lighting:send('zoom', zoom)
    lighting:send('headlamp', dead and {-1000,-1000} or {lampX, lampY})
    lighting:send('wallLamp', {ox + width - 19, oy + 33})
    drawBridge(run, ox, oy)
    g.setShader()

    for i, cell in ipairs(run.cells) do
        local x, y = ox + (i - 1) % run.w * tile, oy + math.floor((i - 1) / run.w) * tile
        local w = widths[cell.id]
        if w then
            local foot = y + (cell.kind == 'monster' and 21 or 26)
            local cx = x + tile / 2
            shadow(cx, foot, w * 0.47, cx >= lampX and 1 or -1)
            g.setColor(1,1,1)
            sprite(cell.id, cx, foot, w)
        elseif cell.kind == 'exit' then
            shadow(x + 16, y + 24, 13, -1)
            g.setColor(1,1,1)
            sprite('exit', x + tile / 2, y + 24, 30)
        end
        if cell.kind == 'monster' or cell.kind == 'exit' then
            g.setColor(0.035, 0.043, 0.061, 0.82)
            g.rectangle('fill', x + 5, y + 20, tile - 10, 10, 2, 2)
        end
        if i == hovered and cell.kind ~= 'wall' then
            g.setColor(0.99, 0.85, 0.55, 0.82)
            g.setLineWidth(0.8)
            g.rectangle('line', x + 1, y + 1, tile - 2, tile - 2)
        end
    end
    shadow(hx + 16, hy + 28, 9, -1)
    local v = dead and 0.45 or 1
    g.setColor(v, v, v)
    sprite('miner', hx + 16, hy + 29, widths.miner)
    g.pop()
end

-- 悬停时展示同一张精灵的细节，地图仍保留格底战损。
function M.drawPortrait(id, cx, bottom, zoom)
    g.push('all')
    g.translate(cx, bottom)
    g.scale(zoom)
    local width = widths[id] * 3.2
    shadow(0, 0, width * 0.37, -1)
    g.setColor(1,1,1)
    sprite(id, 0, 0, width)
    g.pop()
end

return M
