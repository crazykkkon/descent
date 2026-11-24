-- 每次命中只占受击一方的一条数字轨道。附带的反伤、吸血另占一行。
local config = require('core.config')
local M = {}

local paper = { 1, 0.94, 0.75 }
local vermilion = { 1, 0.49, 0.36 }
local mint = { 0.54, 0.94, 0.72 }
local lilac = { 0.88, 0.68, 1 }
local steel = { 0.73, 0.85, 0.85 }
local techniques = { first = '先手', double = '连击', pierce = '破甲', anti = '克制 ×2', corrode = '腐蚀' }
local digitFonts = {}
local LIFE = 0.59

local function damage(side, value, label, heavy)
    side.hit = { value = value == 0 and '0' or '−' .. value, color = value == 0 and steel or side.color,
        label = label, heavy = heavy, t = 0 }
end

local function effect(side, label, value, color)
    side.effects[#side.effects + 1] = { label = label, value = value, color = color }
    side.age = 0
end

function M.new()
    return { hero = { color = vermilion, effects = {} }, mon = { color = paper, effects = {} } }
end

function M.hit(readouts, e, tags, previousMhp)
    local h, m = readouts.hero, readouts.mon
    if e.who == 'skip' then
        h.hit, m.hit, h.effects, m.effects = nil, nil, {}, {}
        for _, pair in ipairs({ { h, -e.loss }, { m, e.mhp - previousMhp } }) do
            local side, net = pair[1], pair[2]
            if net ~= 0 then
                damage(side, math.abs(net), '合计', false)
                if net > 0 then side.hit.value, side.hit.color = '+' .. net, mint end
            end
        end
        return
    end
    local heroTurn = e.who == 'hero'
    local target = heroTurn and m or h
    local labels = {}
    if e.hit == 0 then labels[1] = heroTurn and '未破防' or '格挡' end
    for _, key in ipairs(e.tags) do
        if techniques[key] then labels[#labels + 1] = techniques[key] end
    end
    damage(target, e.hit, table.concat(labels, ' · '), heroTurn and tags.kill or not heroTurn and tags.dead)
    local source = heroTurn and h or m
    source.effects = {}
    if tags.thorns or tags.spikes then effect(source, '反伤', '−' .. config.THORNS_DAMAGE, lilac) end
    if tags.drain then effect(h, '吸血', '+' .. math.floor(e.hit / 4), mint) end
    if tags.lifesteal then
        local healed = e.mhp - previousMhp + (tags.spikes and config.THORNS_DAMAGE or 0)
        if healed > 0 then effect(m, '吸血', '+' .. healed, mint) end
    end
end

function M.update(readouts, dt)
    for _, side in pairs(readouts) do
        if side.hit then
            side.hit.t = side.hit.t + dt
            if side.hit.t >= LIFE then side.hit = nil end
        end
        if side.age then
            side.age = side.age + dt
            if side.age >= LIFE then side.age, side.effects = nil, {} end
        end
    end
end

local outline = { {-1,-1}, {0,-1}, {1,-1}, {-1,0}, {1,0}, {-1,1}, {0,1}, {1,1} }
local function digits(g, hit, x, y, alpha)
    local G, s = love.graphics, g.S
    local px = (hit.heavy and 33 or 27) * s
    if not digitFonts[px] then digitFonts[px] = G.newFont('assets/fonts/impact-digits.otf', px) end
    local font = digitFonts[px]
    G.setFont(font)
    local kick = math.max(0, 1 - hit.t / 0.13)
    local scale = math.min(1, 92 * s / font:getWidth(hit.value)) * (1 + 0.24 * kick * kick)
    local ox, oy = font:getWidth(hit.value) / 2, font:getHeight() / 2
    local function printAt(dx, dy)
        G.print(hit.value, g.OX + (x + dx) * s, g.OY + (y + dy) * s, 0, scale, scale, ox, oy, -0.08, 0)
    end
    G.setColor(0.035, 0.085, 0.09, alpha)
    printAt(1.6, 3)
    for _, o in ipairs(outline) do printAt(o[1] * 1.2, o[2] * 1.2) end
    G.setColor(hit.color[1], hit.color[2], hit.color[3], alpha)
    printAt(0, 0)
end

function M.draw(g, side, x, y, effectX, effectY, a)
    local hit = side.hit
    if hit then
        local alpha = a * math.min(1, (LIFE - hit.t) / 0.15)
        local lift = 8 * math.min(1, hit.t / 0.22) + 4 * hit.t
        digits(g, hit, x, y - lift, alpha)
        if hit.label ~= '' then
            local w = math.max(56, math.min(148, g.font(8 * g.S):getWidth(hit.label) / g.S + 12))
            g.rect({ 0.035, 0.09, 0.1 }, x - w / 2, y + 16 - lift, w, 13, alpha * 0.94)
            g.text(hit.label, x - w / 2, y + 15 - lift, 8, hit.color, 'center', w, alpha)
        end
    end
    local count = #side.effects
    for k, e in ipairs(side.effects) do
        local cx = effectX + (k - (count + 1) / 2) * 59
        local alpha = a * math.min(1, (LIFE - side.age) / 0.15)
        g.rect({ 0.035, 0.09, 0.1 }, cx - 28, effectY, 56, 13, alpha * 0.95)
        g.text(e.label .. ' ' .. e.value, cx - 28, effectY - 1, 8, e.color, 'center', 56, alpha)
    end
end

return M
