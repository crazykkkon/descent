-- 画面和声音的效果：程序生成的音效、画面震动、老电视（CRT）滤镜、矿灯光照、墙缝滴水、数字跳动。
-- 全部是白盒阶段的占位做法：正式美术和音效出来后替换，接口不变。

local M = {}

-- ---------- 音效（程序生成，不需要素材文件） ----------
local sounds = {}
local RATE = 22050

local function makeSound(seconds, fn)
    local n = math.floor(seconds * RATE)
    local sd = love.sound.newSoundData(n, RATE, 16, 1)
    for i = 0, n - 1 do
        local t = i / RATE
        local v = fn(t, i / n)
        sd:setSample(i, math.max(-1, math.min(1, v)))
    end
    return love.audio.newSource(sd, 'static')
end

local function noise() return love.math.random() * 2 - 1 end

function M.load()
    local ok = pcall(function()
        -- 轮子"咔"地停下
        sounds.click = makeSound(0.06, function(t, p) return noise() * (1 - p) ^ 3 * 0.5 + math.sin(t * 2 * math.pi * 1800) * (1 - p) ^ 4 * 0.3 end)
        -- 拉杆
        sounds.lever = makeSound(0.18, function(t, p) return math.sin(t * 2 * math.pi * (220 - 120 * p)) * (1 - p) * 0.35 + noise() * (1 - p) ^ 2 * 0.15 end)
        -- 连成一线：上行的三个音
        sounds.win = makeSound(0.55, function(t, p)
            local f = t < 0.12 and 523 or (t < 0.24 and 659 or 784)
            return (math.sin(t * 2 * math.pi * f) + 0.4 * math.sin(t * 2 * math.pi * f * 2)) * (1 - p) ^ 1.5 * 0.3
        end)
        -- 三个空格：闷响
        sounds.lose = makeSound(0.3, function(t, p) return math.sin(t * 2 * math.pi * (110 - 50 * p)) * (1 - p) ^ 2 * 0.45 end)
        -- 打怪
        sounds.hit = makeSound(0.12, function(t, p) return noise() * (1 - p) ^ 2 * 0.35 + math.sin(t * 2 * math.pi * 140) * (1 - p) * 0.3 end)
        -- 捡东西
        sounds.pick = makeSound(0.14, function(t, p) return math.sin(t * 2 * math.pi * (880 + 440 * p)) * (1 - p) * 0.22 end)
        -- 滴水
        sounds.drip = makeSound(0.09, function(t, p) return math.sin(t * 2 * math.pi * (1400 - 700 * p)) * (1 - p) ^ 2 * 0.08 end)
    end)
    M.soundOk = ok
end

function M.play(name)
    local s = sounds[name]
    if not s then return end
    pcall(function() s:stop(); s:play() end)
end

-- ---------- 画面震动 ----------
local shake = 0
function M.shake(amount) shake = math.max(shake, amount) end
function M.shakeOffset()
    if shake <= 0.01 then return 0, 0 end
    return (love.math.random() * 2 - 1) * shake, (love.math.random() * 2 - 1) * shake
end

-- ---------- 数字跳动 ----------
local bumps, last = {}, {}
-- 每帧报上数值；变了就跳一下。返回放大倍数和这次是变大还是变小
function M.watch(key, value)
    if last[key] ~= nil and last[key] ~= value then bumps[key] = { t = 0.35, up = value > last[key] } end
    last[key] = value
    local b = bumps[key]
    if not b then return 1, nil end
    return 1 + 0.35 * (b.t / 0.35), b.up
end
function M.resetWatch() last, bumps = {}, {} end

-- 每帧调用：震动和数字跳动慢慢消失
function M.update(dt)
    shake = math.max(0, shake - dt * 18)
    for k, b in pairs(bumps) do
        b.t = b.t - dt
        if b.t <= 0 then bumps[k] = nil end
    end
end

-- ---------- 老电视滤镜 ----------
local crtShader
local CRT_CODE = [[
extern vec2 size;
extern float strength;
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
    vec2 c = uv - 0.5;
    vec2 cuv = uv + c * dot(c, c) * 0.06 * strength;            // 轻微的弧面
    if (cuv.x < 0.0 || cuv.y < 0.0 || cuv.x > 1.0 || cuv.y > 1.0) return vec4(0.0, 0.0, 0.0, 1.0);
    float off = 0.0005 * strength;                                 // 一点点色差（太大会让小字发虚）
    vec3 col = vec3(Texel(tex, cuv + vec2(off, 0.0)).r, Texel(tex, cuv).g, Texel(tex, cuv - vec2(off, 0.0)).b);
    float scan = 0.5 + 0.5 * sin(cuv.y * size.y * 3.14159);      // 扫描线
    col *= 1.0 - 0.10 * strength * (1.0 - scan);
    float vig = smoothstep(0.85, 0.25, length(c));                 // 四角暗一点
    col *= mix(1.0, vig, 0.35 * strength);
    return vec4(col, 1.0) * color;
}
]]

function M.loadShader()
    local ok, s = pcall(love.graphics.newShader, CRT_CODE)
    if ok then crtShader = s end
end

-- 把整帧画到 frame 上，再用滤镜贴到屏幕
function M.drawCRT(frame, on)
    local w, h = love.graphics.getDimensions()
    local ox, oy = M.shakeOffset()
    love.graphics.setColor(1, 1, 1)
    if on and crtShader then
        crtShader:send('size', { w, h })
        crtShader:send('strength', 1.0)
        love.graphics.setShader(crtShader)
    end
    love.graphics.draw(frame, ox, oy)
    love.graphics.setShader()
end

-- ---------- 矿灯光照 ----------
local lightImg
function M.loadLight()
    local n = 128
    local data = love.image.newImageData(n, n)
    for y = 0, n - 1 do
        for x = 0, n - 1 do
            local d = math.sqrt((x - n / 2) ^ 2 + (y - n / 2) ^ 2) / (n / 2)
            local k = math.max(0, math.min(1, (d - 0.12) / 0.88))
            k = k * k * (3 - 2 * k)
            -- 中间不变暗，越远越暗、越冷；最暗也保持 62%，保证格子看得清
            local r = 1 - 0.40 * k
            local g = 1 - 0.36 * k
            local b = 1 - 0.26 * k
            data:setPixel(x, y, r, g, b, 1)
        end
    end
    lightImg = love.graphics.newImage(data)
    lightImg:setFilter('linear', 'linear')
end

-- 矿灯：地图范围里，以 (cx, cy) 为中心乘上一张光照图（越远越暗、越冷），再在中间补一点暖光
function M.lamp(mapX, mapY, mapW, mapH, cx, cy, radius)
    if not lightImg then return end
    local g = love.graphics
    g.push('all')
    g.setScissor(mapX, mapY, mapW, mapH)
    g.setBlendMode('multiply', 'premultiplied')
    local s = radius * 2 / lightImg:getWidth()
    -- 光照图盖不到的地方：最暗
    g.setColor(0.60, 0.64, 0.74, 1)
    local x0, y0 = cx - radius, cy - radius
    g.rectangle('fill', mapX, mapY, mapW, math.max(0, y0 - mapY))
    g.rectangle('fill', mapX, y0 + radius * 2, mapW, math.max(0, mapY + mapH - (y0 + radius * 2)))
    g.rectangle('fill', mapX, y0, math.max(0, x0 - mapX), radius * 2)
    g.rectangle('fill', x0 + radius * 2, y0, math.max(0, mapX + mapW - (x0 + radius * 2)), radius * 2)
    g.setColor(1, 1, 1, 1)
    g.draw(lightImg, x0, y0, 0, s, s)
    -- 暖色光晕
    g.setBlendMode('add')
    g.setColor(1.0, 0.72, 0.35, 0.07)
    g.circle('fill', cx, cy, radius * 0.35)
    g.setColor(1.0, 0.72, 0.35, 0.05)
    g.circle('fill', cx, cy, radius * 0.6)
    g.pop()
end

-- ---------- 墙缝滴水 ----------
local drips, dripTimer = {}, 0
-- spots：可以滴水的位置列表 { {x, y}, ... }（墙的下沿，下面是空地）
function M.updateDrips(dt, spots)
    dripTimer = dripTimer - dt
    if dripTimer <= 0 and #spots > 0 then
        dripTimer = 0.35 + love.math.random() * 0.5
        local s = spots[love.math.random(#spots)]
        drips[#drips + 1] = { x = s[1], y = s[2], t = 0 }
    end
    for k = #drips, 1, -1 do
        drips[k].t = drips[k].t + dt
        if drips[k].t > 0.9 then table.remove(drips, k) end
    end
end
function M.drawDrips()
    for _, d in ipairs(drips) do
        if d.t < 0.6 then
            local y = d.y + (d.t / 0.6) ^ 2 * 12
            love.graphics.setColor(0.55, 0.75, 0.95, 0.75)
            love.graphics.rectangle('fill', d.x, y, 1, 2)
        else
            local p = (d.t - 0.6) / 0.3
            love.graphics.setColor(0.55, 0.75, 0.95, 0.5 * (1 - p))
            love.graphics.ellipse('line', d.x + 0.5, d.y + 13, 1 + p * 4, 0.5 + p * 1.2)
        end
    end
end
function M.clearDrips() drips = {} end

return M
