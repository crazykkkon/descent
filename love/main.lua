-- 《坠井者》LÖVE 白盒：第 1 层楼梯口（契约）→ 第 2 层"双道"。
-- 画面分两层：像素层画在 640×360 的逻辑画布上，按整数倍放大（最近邻，不糊）；
-- 中文和数字画在单独的 UI 层，按屏幕分辨率直接绘制，保证清晰。

love.filesystem.setRequirePath('src/?.lua;src/?/init.lua;' .. love.filesystem.getRequirePath())

local config = require('core.config')
local combat = require('core.combat')
local Run = require('core.run')
local rules = require('core.rules')
local contractMod = require('core.contract')
local serialize = require('core.serialize')
local demo = require('data.demo')

-- ---------- 尺寸 ----------
local LW, LH = 640, 360          -- 逻辑画布
local TILE = 32
local MAP_X, MAP_Y = 16, 44      -- 地图在逻辑画布上的位置
local PANEL_X, PANEL_W = 384, 240
local S, OX, OY = 2, 0, 0        -- 放大倍数和黑边偏移
local canvas
local fonts = {}
local FONT_FILE = 'assets/fonts/NotoSansSC-Regular-subset.ttf'
local SAVE_FILE = 'save.lua'
local STEP_TIME = 0.12

-- ---------- 颜色 ----------
local C = {
    bg = { 0.04, 0.06, 0.08 }, panel = { 0.07, 0.11, 0.13 }, line = { 0.14, 0.2, 0.24 },
    floor = { 0.10, 0.15, 0.18 }, wall = { 0.05, 0.08, 0.09 }, wall2 = { 0.07, 0.10, 0.12 },
    monster = { 0.23, 0.12, 0.15 }, item = { 0.11, 0.17, 0.14 }, door = { 0.23, 0.18, 0.11 }, blood = { 0.29, 0.09, 0.13 },
    exit = { 0.07, 0.23, 0.20 }, hero = { 0.94, 0.79, 0.29 }, text = { 0.84, 0.89, 0.91 }, dim = { 0.49, 0.58, 0.61 },
    hp = { 0.88, 0.34, 0.42 }, atk = { 0.91, 0.57, 0.35 }, def = { 0.35, 0.65, 0.91 }, gold = { 0.94, 0.79, 0.29 },
    accent = { 0.37, 0.82, 0.71 }, warn = { 1.0, 0.42, 0.5 }, ok = { 1.0, 0.83, 0.47 },
}

-- ---------- 状态 ----------
local run
local hovered = nil        -- 鼠标所在格子
local msg, msgErr = '', false
local modal = nil          -- { title, lines, buttons }
local walking = nil        -- { path, i, t, from, confirmedFatal, confirmedBreak }
local heroAnim = nil       -- { from, to, t }
local floats = {}          -- 飘字 { text, x, y, t, color }
local pendingSign = false

local function font(px)
    px = math.max(8, math.floor(px + 0.5))
    if not fonts[px] then fonts[px] = love.graphics.newFont(FONT_FILE, px) end
    return fonts[px]
end

local function setColor(c, a) love.graphics.setColor(c[1], c[2], c[3], a or 1) end

-- UI 层文字：坐标和字号都按逻辑像素给，内部换算成屏幕像素
local function text(str, x, y, size, color, align, width)
    love.graphics.setFont(font(size * S))
    setColor(color or C.text)
    if align then
        love.graphics.printf(str, OX + x * S, OY + y * S, (width or 200) * S, align)
    else
        love.graphics.print(str, OX + x * S, OY + y * S)
    end
end

local function relayout()
    local w, h = love.graphics.getDimensions()
    S = math.max(1, math.min(math.floor(w / LW), math.floor(h / LH)))
    OX = math.floor((w - LW * S) / 2)
    OY = math.floor((h - LH * S) / 2)
end

-- ---------- 存档 ----------
local function saveGame()
    if run.status == 'dead' or run.status == 'finished' then
        love.filesystem.remove(SAVE_FILE)
        return
    end
    love.filesystem.write(SAVE_FILE, serialize.dump({ run = run:save() }))
end

local function floors() return { demo.stairs, demo.floor } end

local openStairs, openSummary, openDeath, newGame

local function setMsg(s, err) msg, msgErr = s or '', err or false end

-- ---------- 地图坐标 ----------
local function tileXY(i)
    local x = (i - 1) % run.w
    local y = (i - 1 - x) / run.w
    return MAP_X + x * TILE, MAP_Y + y * TILE
end

local function tileAt(lx, ly)
    local x = math.floor((lx - MAP_X) / TILE)
    local y = math.floor((ly - MAP_Y) / TILE)
    if x < 0 or y < 0 or x >= run.w or y >= run.h then return nil end
    return y * run.w + x + 1
end

local function float(i, str, color)
    local x, y = tileXY(i)
    floats[#floats + 1] = { text = str, x = x, y = y, t = 0, color = color }
end

-- ---------- 战斗预览 ----------
local function preview(i)
    local c = run.cells[i]
    if c.kind ~= 'monster' then return nil end
    local m = run:monsterAt(i)
    local r = combat.simulate(run.hero, m)
    if not r.canAttack then return { fatal = true, text = '打不动', lose = 0, left = 0, gold = m.gold } end
    if not r.canWin then return { fatal = true, text = '打不死', lose = 0, left = 0, gold = m.gold } end
    local left = run.hero.hp - r.damage
    return { fatal = left <= 0, text = left <= 0 and '会死' or ('剩 ' .. left), lose = r.damage, left = left, gold = m.gold }
end

-- ---------- 弹窗 ----------
local function openModal(title, lines, buttons)
    modal = { title = title, lines = lines, buttons = buttons }
end

local function closeModal() modal = nil end

-- 弹窗布局：返回每个按钮的逻辑矩形
local function modalLayout()
    local w, x = 360, (LW - 360) / 2
    local h = 64 + #modal.lines * 15 + 30
    local y = (LH - h) / 2
    local rects = {}
    local n = #modal.buttons
    local bw = (w - 32 - (n - 1) * 8) / n
    for k = 1, n do
        rects[k] = { x = x + 16 + (k - 1) * (bw + 8), y = y + h - 30, w = bw, h = 20 }
    end
    return x, y, w, h, rects
end

-- ---------- 走路 ----------
local function startWalk(path)
    if #path == 0 then return end
    walking = { path = path, i = 1, t = STEP_TIME }
end

local function afterStop()
    saveGame()
    if run.status == 'dead' then openDeath()
    elseif run.status == 'floorDone' then openSummary() end
end

-- 走下一格；需要确认时停下来弹窗
local function walkStep()
    local cell = walking.path[walking.i]
    local c = run.cells[cell]
    -- 硬打会死的怪：先确认
    if c.kind == 'monster' and not walking.confirmedFatal then
        local p = preview(cell)
        if p and p.fatal then
            local path, rest = walking.path, walking.i
            walking = nil
            local m = config.MONSTERS[c.id]
            openModal('硬打' .. m.name .. '？', { p.text == '会死' and ('这一仗要损失 ' .. p.lose .. ' 生命，你只有 ' .. run.hero.hp .. '。') or (p.text .. '。'), '打下去你会死，这一局就结束了。' }, {
                { label = '算了', primary = true, fn = function() closeModal(); setMsg('没有出手。') end },
                { label = '硬打', danger = true, fn = function()
                    closeModal()
                    local remain = {}
                    for k = rest, #path do remain[#remain + 1] = path[k] end
                    startWalk(remain)
                    walking.confirmedFatal = true
                end },
            })
            return
        end
    end
    -- 签了"不喝血瓶"：喝之前确认
    if rules.isPotion(c) and run:contractActive() and not walking.confirmedBreak then
        local path, rest = walking.path, walking.i
        walking = nil
        local d = run.contract.def
        openModal('喝下这瓶血瓶？', { '你和井签了契约：本层一瓶血瓶都不喝。', '喝下去就毁约：押下的 ' .. d.deposit .. ' 生命不退，攻击 +' .. d.atk .. ' 照样留着。', '守约走到出口，能拿回 ' .. d.refund .. ' 生命和 ' .. d.gold .. ' 金币。' }, {
            { label = '不喝，守约', primary = true, fn = function() closeModal(); setMsg('没有喝。') end },
            { label = '喝（毁约）', danger = true, fn = function()
                closeModal()
                local remain = {}
                for k = rest, #path do remain[#remain + 1] = path[k] end
                startWalk(remain)
                walking.confirmedBreak = true
            end },
        })
        return
    end
    local before = config.copyHero(run.hero)
    local from = run.pos
    local r = run:step(cell)
    if r.msg ~= '' then setMsg(r.msg, not r.ok or run.status == 'dead') end
    if not r.ok then walking = nil; afterStop(); return end
    if run.pos ~= from then heroAnim = { from = from, to = run.pos, t = 0 } end
    local lost = before.hp - run.hero.hp
    if lost > 0 then float(cell, '-' .. lost, C.warn)
    elseif run.hero.hp > before.hp then float(cell, '+' .. (run.hero.hp - before.hp), { 0.5, 1, 0.7 })
    elseif run.hero.atk > before.atk then float(cell, '攻+' .. (run.hero.atk - before.atk), C.atk)
    elseif run.hero.def > before.def then float(cell, '防+' .. (run.hero.def - before.def), C.def) end
    walking.i = walking.i + 1
    walking.confirmedFatal = false
    walking.confirmedBreak = false
    if walking.i > #walking.path or run.status ~= 'playing' then
        walking = nil
        afterStop()
    end
end

local function act(i)
    if walking or modal or run.status ~= 'playing' then return end
    local c = run.cells[i]
    if c.kind == 'wall' or i == run.pos then return end
    local path = run:findPath(i)
    if not path then setMsg('走不过去', true); return end
    startWalk(path)
end

-- ---------- 场景 ----------
function openStairs()
    local c = demo.floor.contract
    local t = contractMod.text(c)
    local dep = contractMod.depositFor(c, run.hero)
    local lines = {
        '下楼之后就回不来了。下楼前，你听到井底传来的回声：',
        '【下一层情报】' .. demo.floor.intel,
        '',
        '楼梯边垂下一枚铁钩，钩上挂着一纸契约：',
        '押　' .. dep .. ' 生命（现在就扣，签后剩 ' .. (run.hero.hp - dep) .. '）',
        '得　' .. t.get,
        '约　' .. t.cond,
        '还　' .. t.reward,
        '下一层可以随时喝血瓶，喝下那一刻就算毁约：押金归井，属性归你。',
    }
    local function down(sign)
        closeModal()
        pendingSign = sign
        run:step(run:findPath(2)[1]) -- 走上楼梯
        run:finishFloor(false, pendingSign)
        setMsg(demo.floor.hint)
        saveGame()
    end
    local buttons = { { label = '不签，下楼', fn = function() down(false) end } }
    if run.hero.hp > dep then
        buttons[#buttons + 1] = { label = '签约（押 ' .. dep .. ' 血），下楼', primary = true, fn = function() down(true) end }
    end
    openModal('楼梯口', lines, buttons)
end

function openSummary()
    local s = run:exitSummary()
    local start = run:floorStartHero()
    local lines = {}
    if s.contract then
        lines[#lines + 1] = s.contract.kept and ('契约守住了：+' .. s.contract.def.refund .. ' 生命，+' .. s.contract.def.gold .. ' 金币')
            or ('契约已毁：押下的 ' .. s.contract.def.deposit .. ' 生命归井')
    else
        lines[#lines + 1] = '没有签契约。'
    end
    local d = run.hero.hp - start.hp
    lines[#lines + 1] = '本层生命变化（不含退还）：' .. (d >= 0 and '+' or '') .. d
    lines[#lines + 1] = '地图上剩下的血瓶 ×' .. s.leftoverPotions .. '：+' .. s.potionGold .. ' 金币'
    openModal(run:floor().name .. ' 完成', lines, {
        { label = '继续', primary = true, fn = function()
            closeModal()
            run:finishFloor(false, false)
            saveGame()
            openModal('白盒到此结束', {
                '这是 LÖVE 版的第一张图（第 2 层"双道"）。',
                '剩余生命 ' .. run.hero.hp .. '，攻 ' .. run.hero.atk .. ' / 防 ' .. run.hero.def .. '，金币 ' .. run.hero.gold .. '。',
                '下一步：扩展到第 1～20 层。',
            }, { { label = '再来一局', primary = true, fn = function() closeModal(); newGame() end } })
        end },
    })
end

function openDeath()
    love.filesystem.remove(SAVE_FILE)
    openModal('你倒下了', { '你倒在了' .. run:floor().name .. '。', '这一局结束了。重新开始要从第 1 层走起。' }, {
        { label = '从第 1 层重新开始', primary = true, fn = function() closeModal(); newGame() end },
    })
end

function newGame()
    run = Run.new(floors(), 'digger', os.time())
    run.hero = config.copyHero(demo.entryHero)
    run.floorStart = run:snapshot()
    floats, walking, heroAnim = {}, nil, nil
    setMsg('')
    openStairs()
end

-- ---------- LÖVE 回调 ----------
function love.load()
    love.graphics.setDefaultFilter('nearest', 'nearest')
    canvas = love.graphics.newCanvas(LW, LH)
    relayout()
    local data = love.filesystem.getInfo(SAVE_FILE) and serialize.load(love.filesystem.read(SAVE_FILE))
    if data and data.run then
        run = Run.load(floors(), data.run)
        if run.floorIndex == 1 then openStairs() else setMsg('继续上一局。') end
    else
        newGame()
    end
    if os.getenv('DESCENT_AUTOTEST') then require('autotest').start() end
end

function love.resize() relayout() end

function love.update(dt)
    if walking and not modal then
        walking.t = walking.t + dt
        if walking.t >= STEP_TIME then walking.t = 0; walkStep() end
    end
    if heroAnim then
        heroAnim.t = heroAnim.t + dt / STEP_TIME
        if heroAnim.t >= 1 then heroAnim = nil end
    end
    for k = #floats, 1, -1 do
        floats[k].t = floats[k].t + dt
        if floats[k].t > 0.9 then table.remove(floats, k) end
    end
    local mx, my = love.mouse.getPosition()
    hovered = tileAt((mx - OX) / S, (my - OY) / S)
end

-- ---------- 绘制：像素层 ----------
local function drawTile(i)
    local c = run.cells[i]
    local x, y = tileXY(i)
    local g = love.graphics
    if c.kind == 'wall' then
        setColor(C.wall); g.rectangle('fill', x, y, TILE, TILE)
        setColor(C.wall2)
        for k = 0, TILE - 1, 6 do g.rectangle('fill', x + k, y + k % 12, 2, 2) end
        return
    end
    local base = C.floor
    if c.kind == 'monster' then base = C.monster
    elseif c.kind == 'item' then base = C.item
    elseif c.kind == 'door' then base = c.door == 'blood' and C.blood or C.door
    elseif c.kind == 'exit' then base = C.exit end
    setColor(base); g.rectangle('fill', x + 1, y + 1, TILE - 2, TILE - 2)
    if c.kind == 'item' then
        if c.id == 'smallPotion' or c.id == 'bigPotion' then
            local s = c.id == 'bigPotion' and 1.25 or 1
            setColor({ 0.62, 0.7, 0.73 }); g.rectangle('fill', x + 14, y + 16 - 9 * s, 4, 3)
            setColor(C.hp); g.rectangle('fill', x + 16 - 6 * s, y + 16 - 6 * s, 12 * s, 14 * s)
        elseif c.id == 'redGem' or c.id == 'blueGem' then
            setColor(c.id == 'redGem' and { 0.89, 0.33, 0.23 } or { 0.18, 0.5, 0.84 })
            g.polygon('fill', x + 16, y + 7, x + 25, y + 16, x + 16, y + 25, x + 7, y + 16)
        end
    elseif c.kind == 'exit' then
        setColor(C.accent); g.polygon('fill', x + 9, y + 10, x + 23, y + 10, x + 16, y + 20)
    end
end

local function drawPixel()
    love.graphics.setCanvas(canvas)
    love.graphics.clear(C.bg[1], C.bg[2], C.bg[3])
    -- 面板底色
    setColor(C.panel)
    love.graphics.rectangle('fill', 8, 6, LW - 16, 30)
    love.graphics.rectangle('fill', PANEL_X - 4, MAP_Y - 4, PANEL_W + 8, LH - MAP_Y - 4)
    setColor(C.line)
    love.graphics.rectangle('line', MAP_X - 2.5, MAP_Y - 2.5, run.w * TILE + 5, run.h * TILE + 5)
    for i = 1, #run.cells do drawTile(i) end
    -- 悬停框
    if hovered and run.cells[hovered].kind ~= 'wall' and not modal then
        local x, y = tileXY(hovered)
        setColor({ 1, 1, 1 }, 0.5); love.graphics.rectangle('line', x + 0.5, y + 0.5, TILE - 1, TILE - 1)
    end
    -- 主角（走路时在两格之间插值）
    local hx, hy = tileXY(run.pos)
    if heroAnim then
        local fx, fy = tileXY(heroAnim.from)
        hx = fx + (hx - fx) * heroAnim.t
        hy = fy + (hy - fy) * heroAnim.t
    end
    setColor(run.status == 'dead' and { 0.4, 0.4, 0.4 } or C.hero)
    love.graphics.circle('fill', hx + 16, hy + 16, 11)
    love.graphics.setCanvas()
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(canvas, OX, OY, 0, S, S)
end

-- ---------- 绘制：UI 层 ----------
local SHORT = { moss = '苔', eel = '鳗', frog = '蛙', beetle = '甲', bat = '蝠', wraith = '魂', crab = '蟹', guardian = '守' }

local function drawUI()
    local h = run.hero
    local atk, def = combat.effectiveStats(h)
    text(run:floor().name, 16, 10, 10, C.accent)
    text('血 ' .. h.hp, 190, 10, 10, C.hp)
    text('攻 ' .. atk, 250, 10, 10, C.atk)
    text('防 ' .. def, 300, 10, 10, C.def)
    text('钥 ' .. h.keys, 350, 10, 10, { 0.85, 0.76, 0.48 })
    text('金 ' .. h.gold, 400, 10, 10, C.gold)
    text('步 ' .. run.steps, 460, 10, 10, C.dim)
    if run:contractActive() then
        text('契约生效中：本层不喝血瓶', 510, 11, 7, C.accent)
    elseif run.contract and run.contract.floorIndex == run.floorIndex then
        text('契约已毁', 510, 11, 7, C.warn)
    end

    -- 格子上的字：怪物名和战损、门、钥匙、金币
    for i, c in ipairs(run.cells) do
        local x, y = tileXY(i)
        if c.kind == 'monster' then
            local p = preview(i)
            text(SHORT[c.id], x, y + 3, 10, { 1, 0.84, 0.86 }, 'center', TILE)
            text(p.fatal and (p.text == '会死' and ('-' .. p.lose) or p.text) or ('-' .. p.lose), x, y + 19, 6.5, p.fatal and C.warn or C.ok, 'center', TILE)
        elseif c.kind == 'door' then
            text(c.door == 'bone' and '门' or '血门', x, y + 5, 9, { 0.95, 0.84, 0.6 }, 'center', TILE)
            text(c.door == 'bone' and '骨钥' or ('-' .. run:floor().bloodCost), x, y + 20, 6, C.dim, 'center', TILE)
        elseif c.kind == 'item' and (c.id == 'key' or c.id == 'gold') then
            text(c.id == 'key' and '钥' or '金', x, y + 8, 11, C.gold, 'center', TILE)
        elseif c.kind == 'exit' then
            text('出口', x, y + 21, 6, C.accent, 'center', TILE)
        end
    end
    for _, f in ipairs(floats) do
        text(f.text, f.x, f.y - f.t * 18, 9, f.color, 'center', TILE)
    end

    -- 右侧信息栏
    local px, py = PANEL_X + 6, MAP_Y + 4
    local i = hovered
    if i and run.cells[i].kind ~= 'wall' and run.cells[i].kind ~= 'floor' and not modal then
        local c = run.cells[i]
        if c.kind == 'monster' then
            local m = run:monsterAt(i)
            local p = preview(i)
            text(m.name, px, py, 11, C.text)
            text('生命 ' .. m.hp .. '　攻击 ' .. m.atk .. '　防御 ' .. m.def, px, py + 18, 7.5, C.text)
            local ty = py + 32
            for k in pairs(m.traits) do
                text('【' .. config.TRAIT_NAMES[k] .. '】' .. config.TRAIT_DESC[k], px, ty, 7, C.dim, 'left', PANEL_W - 12)
                ty = ty + 12
            end
            if p.fatal then
                text(p.text == '会死' and ('预计损失 ' .. p.lose .. '，你会死') or (p.text .. '，硬打会死'), px, ty + 4, 9, C.warn, 'left', PANEL_W - 12)
            else
                text('预计损失', px, ty + 4, 7, C.dim)
                text('打完剩余', px + 110, ty + 4, 7, C.dim)
                text('-' .. p.lose, px, ty + 14, 16, C.warn)
                text(tostring(p.left), px + 110, ty + 14, 16, C.accent)
            end
            text('掉落 ' .. p.gold .. ' 金币', px, ty + 38, 7.5, C.gold)
        elseif c.kind == 'item' then
            text(config.ITEM_NAMES[c.id], px, py, 11, C.text)
            local f = run:floor()
            local gem = f.gem + run.ch.gemBonus
            local eff = ({ smallPotion = '生命 +' .. f.smallPotion, bigPotion = '生命 +' .. f.bigPotion, redGem = '攻击 +' .. gem, blueGem = '防御 +' .. gem, key = '骨钥 +1', gold = '金币 +' .. f.gold })[c.id]
            text(eff, px, py + 18, 8, C.text)
            if rules.isPotion(c) and run:contractActive() then
                text('喝下会毁约：押下的 ' .. run.contract.def.deposit .. ' 生命不退', px, py + 34, 8, C.warn, 'left', PANEL_W - 12)
            end
        elseif c.kind == 'door' then
            text(c.door == 'bone' and '骨门' or '血门', px, py, 11, C.text)
            text(c.door == 'bone' and '消耗 1 把骨钥打开' or ('通过时扣 ' .. run:floor().bloodCost .. ' 生命'), px, py + 18, 8, C.text)
        elseif c.kind == 'exit' then
            text('出口', px, py, 11, C.text)
            text('走到这里结束本层', px, py + 18, 8, C.text)
        end
    else
        text(run:floor().name, px, py, 11, C.text)
        text('鼠标移到格子上看详情，点击行动；点空地直接走过去。方向键 / WASD 也能走。', px, py + 18, 7.5, C.dim, 'left', PANEL_W - 12)
    end
    text(msg, px, LH - 60, 7.5, msgErr and C.warn or C.text, 'left', PANEL_W - 12)
    text('走过不能撤回 · 死了从第 1 层重来', px, LH - 20, 6.5, C.dim, 'left', PANEL_W - 12)

    -- 弹窗
    if modal then
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.rectangle('fill', 0, 0, love.graphics.getDimensions())
        local x, y, w, hh, rects = modalLayout()
        setColor(C.panel); love.graphics.rectangle('fill', OX + x * S, OY + y * S, w * S, hh * S)
        setColor(C.line); love.graphics.rectangle('line', OX + x * S, OY + y * S, w * S, hh * S)
        text(modal.title, x + 16, y + 12, 12, C.accent)
        for k, line in ipairs(modal.lines) do
            text(line, x + 16, y + 30 + (k - 1) * 15, 8, C.text, 'left', w - 32)
        end
        for k, b in ipairs(modal.buttons) do
            local r = rects[k]
            setColor(b.danger and { 0.35, 0.12, 0.16 } or (b.primary and { 0.12, 0.35, 0.3 } or { 0.11, 0.16, 0.19 }))
            love.graphics.rectangle('fill', OX + r.x * S, OY + r.y * S, r.w * S, r.h * S)
            text(b.label, r.x, r.y + 5, 8, C.text, 'center', r.w)
        end
    end
end

function love.draw()
    love.graphics.clear(0, 0, 0)
    drawPixel()
    drawUI()
end

-- ---------- 输入 ----------
function love.mousepressed(mx, my, button)
    if button ~= 1 then return end
    local lx, ly = (mx - OX) / S, (my - OY) / S
    if modal then
        local _, _, _, _, rects = modalLayout()
        for k, r in ipairs(rects) do
            if lx >= r.x and lx <= r.x + r.w and ly >= r.y and ly <= r.y + r.h then modal.buttons[k].fn(); return end
        end
        return
    end
    local i = tileAt(lx, ly)
    if i then act(i) end
end

local DIRS = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 }, w = { 0, -1 }, s = { 0, 1 }, a = { -1, 0 }, d = { 1, 0 } }

function love.keypressed(key)
    if modal then
        if key == 'return' or key == 'space' then
            for _, b in ipairs(modal.buttons) do if b.primary then b.fn(); return end end
        end
        local n = tonumber(key)
        if n and modal.buttons[n] then modal.buttons[n].fn() end
        return
    end
    local d = DIRS[key]
    if d and not walking and run.status == 'playing' then
        local x = (run.pos - 1) % run.w + d[1]
        local y = math.floor((run.pos - 1) / run.w) + d[2]
        if x >= 0 and y >= 0 and x < run.w and y < run.h then
            local t = y * run.w + x + 1
            if run.cells[t].kind ~= 'wall' then startWalk({ t }) end
        end
    end
end

-- 给自动测试用的入口
return {
    getRun = function() return run end,
    getModal = function() return modal end,
    act = act,
    setHover = function(i) hovered = i end,
}
