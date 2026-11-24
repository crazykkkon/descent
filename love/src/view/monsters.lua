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

-- fx（可选，战斗反馈用）：{ dx, dy 偏移, flash 闪白 0～1, alpha 透明度, scale 缩放 }
-- 素材原始尺寸（战斗窗口用来算怪的身体边缘：主角冲过去要正好打到它身上）
function M.size(id)
    local sprite = sprites[id]
    if not sprite then return 40, 32 end
    return sprite:getDimensions()
end

function M.draw(id, cx, feet, clock, tileIndex, fx, sizeMultiplier)
    local g = love.graphics
    local sprite = sprites[id]
    local w, h = sprite:getDimensions()
    local alpha = fx and fx.alpha or 1
    local scale = (sizeMultiplier or 1) * (fx and fx.scale or 1)
    cx, feet = cx + (fx and fx.dx or 0), feet + (fx and fx.dy or 0)
    g.setColor(0.035, 0.027, 0.055, 0.62 * alpha)
    g.ellipse('fill', cx, feet - 0.5, w * 0.18 * scale, 1.8)
    local lift = airborne[id] and (1 + math.floor(1 + 0.9 * math.sin(clock * 2.8 + tileIndex))) or 0
    local s = 0.5 * scale
    local x, y = cx - math.floor(w / 2) * s, feet - lift - h * s
    g.setColor(1, 1, 1, alpha)
    g.draw(sprite, x, y, 0, s, s)
    -- 受击闪白：同一张图用加法再叠一层
    if fx and fx.flash and fx.flash > 0 then
        g.setBlendMode('add')
        g.setColor(1, 1, 1, fx.flash * 0.85 * alpha)
        g.draw(sprite, x, y, 0, s, s)
        g.setBlendMode('alpha')
    end
end

return M
