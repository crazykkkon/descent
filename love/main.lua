-- 《坠井者》LÖVE 白盒：断臂转轮版（设计方案第二十五章）。
-- 第一次打开是新手教程（第 5 层遇到井底之眼，必死）；之后每局带着断臂转轮，从第 1 层往下走 20 层。
-- 流程：楼梯口（两条楼梯二选一、井租）→ 出口结算 → 下一层；刻图案、转断臂转轮；大转盘、当铺、骨坛、营火；诏令；通关结算。
-- 画面分两层：像素层画在 640×360 的逻辑画布上，按整数倍放大（最近邻，不糊）；
-- 中文和数字画在单独的 UI 层，按屏幕分辨率直接绘制，保证清晰。

love.filesystem.setRequirePath('src/?.lua;src/?/init.lua;' .. love.filesystem.getRequirePath())

local config = require('core.config')
local combat = require('core.combat')
local Run = require('core.run')
local rules = require('core.rules')
local serialize = require('core.serialize')
local floorMod = require('core.floor')
local armMod = require('core.arm')
local wheelMod = require('core.wheel')
local decreeMod = require('core.decree')
local whisperMod = require('core.whisper')
local route = require('core.route')
local miner = require('view.miner')
local fx = require('view.fx')
local armView = require('view.arm_view')
local coach = require('view.coach')
local titleView = require('view.title')

-- ---------- 尺寸 ----------
local LW, LH = 640, 360          -- 逻辑画布
local TILE = 26                  -- 地图 16×11（制作人定），一格 26 逻辑像素
local K = TILE / 40              -- 按原来 40 像素一格画的图形，乘这个缩放
local MAP_X, MAP_Y = 34, 44      -- 地图在逻辑画布上的位置（地图占画面大半）
local PANEL_X, PANEL_W = 482, 154 -- 右侧：断臂转轮
local S, OX, OY = 2, 0, 0        -- 放大倍数和黑边偏移
local canvas
local frame      -- 整帧先画到这里，再加老电视滤镜
local clock = 0
local fonts = {}
local FONT_FILE = 'assets/fonts/NotoSansSC-Regular-subset.ttf'
local SAVE_FILE = 'save.lua'
local META_FILE = 'meta.lua' -- 跨局保存的东西：新手教程打过没有
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
local forcedHover = nil    -- 自动测试指定的悬停格子
local msg, msgErr = '', false
local modal = nil          -- { title, lines, buttons }
local walking = nil        -- { path, i, t, from, confirmedFatal, confirmedBreak }
local facing = 'down'
local heroAnim = nil       -- { from, to, t }
local floats = {}          -- 飘字 { text, x, y, t, color }
local meta = { tutorialDone = false, crt = true, volume = 1, fullscreen = false }
local scene = 'title'      -- 'title' 开局界面 / 'game' 游戏中
local titleSel = 1         -- 开局界面选中的第几项
local facilityOpener

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
    love.filesystem.write(SAVE_FILE, serialize.dump({ run = run:save(), facing = facing }))
end

local openExit, openSummary, openDeath, openVictory, openEngrave, openDecree, openArm, openWheel, openPawn, openAltar, openStall, newGame, loadGame, continueFlow
local spinArm, toggleHold
local hasSave, applySettings, toGame, continueGame, startNewGame, backToTitle, openSettings, openPause, titleItems, titleItemAt, drawTitleUI

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
local MODAL_PER_ROW = 4
local function modalLineH() return #modal.lines > 12 and 12 or 15 end
local function modalLayout()
    local w, x = 440, (LW - 440) / 2
    local n = #modal.buttons
    local rows = math.max(1, math.ceil(n / MODAL_PER_ROW))
    local h = 40 + #modal.lines * modalLineH() + rows * 26 + 10
    local y = math.max(4, (LH - h) / 2)
    local rects = {}
    for k = 1, n do
        local row = math.floor((k - 1) / MODAL_PER_ROW)
        local inRow = math.min(MODAL_PER_ROW, n - row * MODAL_PER_ROW)
        local col = (k - 1) % MODAL_PER_ROW
        local bw = (w - 32 - (inRow - 1) * 8) / inRow
        rects[k] = { x = x + 16 + col * (bw + 8), y = y + h - 10 - (rows - row) * 26, w = bw, h = 20 }
    end
    return x, y, w, h, rects
end

-- ---------- 走路 ----------
local function startWalk(path, onArrive)
    if #path == 0 then return end
    walking = { path = path, i = 1, t = STEP_TIME, onArrive = onArrive }
end

local function afterStop()
    saveGame()
    if run.status == 'dead' then openDeath()
    elseif run.status == 'floorDone' then openSummary()
    else continueFlow() end
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
    -- 走上出口之前问一次（下一层是哪个候选、井租），可以"再想想"
    if c.kind == 'exit' and not walking.confirmedExit and not run:eliteAlive() then
        walking = nil
        openExit(cell)
        return
    end
    local before = config.copyHero(run.hero)
    local from = run.pos
    local r = run:step(cell)
    if r.msg ~= '' then setMsg(r.msg, not r.ok or run.status == 'dead') end
    if not r.ok then walking = nil; afterStop(); return end
    if run.pos ~= from then
        local fx, fy = tileXY(from)
        local tx, ty = tileXY(run.pos)
        if tx ~= fx then facing = tx > fx and 'right' or 'left'
        else facing = ty > fy and 'down' or 'up' end
        heroAnim = { from = from, to = run.pos, t = 0 }
    end
    if c.kind == 'monster' then fx.play('hit'); fx.shake(1.2)
    elseif c.kind == 'item' then fx.play('pick') end
    local lost = before.hp - run.hero.hp
    if lost > 0 then float(cell, '-' .. lost, C.warn)
    elseif run.hero.hp > before.hp then float(cell, '+' .. (run.hero.hp - before.hp), { 0.5, 1, 0.7 })
    elseif run.hero.atk > before.atk then float(cell, '攻+' .. (run.hero.atk - before.atk), C.atk)
    elseif run.hero.def > before.def then float(cell, '防+' .. (run.hero.def - before.def), C.def) end
    walking.i = walking.i + 1
    walking.confirmedFatal = false
    if walking.i > #walking.path or run.status ~= 'playing' then
        local cb = walking.onArrive
        walking = nil
        afterStop()
        if cb and run.status == 'playing' and not modal then cb() end
    end
end

local function act(i)
    if walking or modal or run.status ~= 'playing' then return end
    local c = run.cells[i]
    if c.kind == 'wall' or i == run.pos then return end
    -- 设施（补给摊、大转盘、当铺、骨坛）：走到旁边再打开
    if floorMod.isFacility(c) then
        local function open() facilityOpener(i) end
        for _, n in ipairs(floorMod.neighbors(run.pos, run.w, run.h)) do
            if n == i then open(); return end
        end
        local path = run:findPath(i)
        if not path then setMsg('走不过去', true); return end
        table.remove(path)
        if #path == 0 then open() else startWalk(path, open) end
        return
    end
    local path = run:findPath(i)
    if not path then setMsg('走不过去', true); return end
    startWalk(path)
end

-- ---------- 场景 ----------
local W = function(id) return id == armMod.WILD and armMod.WILD_NAME or config.WEAPONS[id].name end
local SHORTW = { boneKnife = '刀', harpoon = '叉', hammer = '锤', mossBlade = '苔', bellStaff = '铃', saltDagger = '盐', rustSword = '锈', wellHook = '钩', wild = '赖' }

local function weaponLine(id)
    if id == armMod.WILD then return '赖子：能顶替任何武器（不顶替空格），自己不能拿在手上；很难得到' end
    local b = run.arm and run.arm.boons[id]
    local extra = ''
    if b and #b > 0 then
        local names = {}
        for k, x in ipairs(b) do names[k] = config.BOON_NAMES[x] end
        extra = '（骨坛：' .. table.concat(names, '、') .. '）'
    end
    return W(id) .. '：' .. config.WEAPONS[id].desc .. extra
end

local function reelText(r)
    local t = {}
    for k = 1, armMod.SIZE do
        local w = run.arm.reels[r][k]
        t[k] = w and SHORTW[w] or '空'
    end
    return '轮子 ' .. r .. '：' .. table.concat(t, ' · ')
end

local function armReelsText()
    return { reelText(1), reelText(2), reelText(3) }
end

-- 依次处理：要刻的图案 → 诏令 → 诏令的消息
function continueFlow()
    if modal or run.status ~= 'playing' then return end
    if #run.notes > 0 then
        local notes = run.notes
        run.notes = {}
        openModal('井神的诏令', notes, { { label = '知道了', primary = true, fn = function() closeModal(); continueFlow() end } })
        return
    end
    if run:pendingEngrave() then openEngrave(); return end
    if run.decreeOffer then openDecree(); return end
end

-- 选刻在哪个轮子；这个轮子刻满了再选覆盖哪一格。onPick(轮子, 格子或 nil)
local function chooseSlot(title, onPick)
    local lines = armReelsText()
    lines[#lines + 1] = '刻在哪个轮子上？要三个轮子都刻了同一把，才可能转出它。'
    local buttons = {}
    for r = 1, armMod.REELS do
        buttons[#buttons + 1] = { label = '刻在轮子 ' .. r, fn = function()
            closeModal()
            if armMod.firstBlank(run.arm, r) then onPick(r, nil); return end
            local l2 = { reelText(r), '轮子 ' .. r .. ' 刻满了。选一格覆盖掉（原来的图案就没了）。' }
            local b2 = {}
            for k = 1, armMod.SIZE do
                local w = run.arm.reels[r][k]
                b2[#b2 + 1] = { label = '覆盖第 ' .. k .. ' 格（' .. (w and W(w) or '空') .. '）', fn = function() closeModal(); onPick(r, k) end }
            end
            b2[#b2 + 1] = { label = '算了', fn = function() closeModal(); continueFlow() end }
            openModal(title, l2, b2)
        end }
    end
    buttons[#buttons + 1] = { label = '算了', fn = function() closeModal(); continueFlow() end }
    openModal(title, lines, buttons)
end

-- 从转轮上挑一格（当掉、擦掉用）。onPick(轮子, 格子)
local function chooseCell(title, onPick)
    local lines = armReelsText()
    local buttons = {}
    for _, c in ipairs(armMod.engravedCells(run.arm)) do
        local r, k = c[1], c[2]
        buttons[#buttons + 1] = { label = '轮子' .. r .. '·' .. k .. ' ' .. W(run.arm.reels[r][k]), fn = function() closeModal(); onPick(r, k) end }
    end
    buttons[#buttons + 1] = { label = '算了', fn = function() closeModal() end }
    openModal(title, lines, buttons)
end

function openEngrave()
    local p = run:pendingEngrave()
    if not p then return end
    local from = ({ elite = '精英倒下了，它身上压着几件东西的印子', mark = '这只怪身上的印记亮了起来', decree = '井神兑现了诏令', wheel = '大转盘吐出一个图案' })[p.from]
    local onlyWild = #p.choices == 1 and p.choices[1] == armMod.WILD
    local lines = { from .. '。刻到断臂转轮的一个轮子上' .. (onlyWild and '：' or '（刻上武器就先拿在手上）：') }
    for _, w in ipairs(p.choices) do lines[#lines + 1] = weaponLine(w) end
    for _, l in ipairs(armReelsText()) do lines[#lines + 1] = l end
    local buttons = {}
    for _, w in ipairs(p.choices) do
        buttons[#buttons + 1] = { label = '刻' .. W(w), primary = #p.choices == 1, fn = function()
            closeModal()
            chooseSlot('刻' .. W(w), function(reel, cell)
                local r = run:engrave(w, reel, cell)
                setMsg(r.msg, not r.ok)
                saveGame()
                continueFlow()
            end)
        end }
    end
    buttons[#buttons + 1] = { label = '不刻', fn = function() closeModal(); run:skipEngrave(); saveGame(); continueFlow() end }
    openModal('刻图案', lines, buttons)
end

function openDecree()
    local d = run.decreeOffer
    if not d then return end
    openModal('井神的诏令·' .. decreeMod.TIER_NAMES[d.tier], {
        '井壁上浮出一行字：',
        '「' .. d.text .. '」',
        '期限：从这一层起，' .. decreeMod.SPAN .. ' 层之内。',
        '完成：从三把武器里选一把刻上去' .. (d.tier == 'silver' and '，再加生命 +' .. decreeMod.SILVER_BONUS_HP or '') .. '。',
        '做不到：攻击 −' .. decreeMod.PENALTY[d.tier] .. '。也可以不接。',
    }, {
        { label = '不接', fn = function() closeModal(); run:refuseDecree(); saveGame(); continueFlow() end },
        { label = '接下', primary = true, fn = function() closeModal(); setMsg(run:acceptDecree().msg); saveGame(); continueFlow() end },
    })
end

-- 断臂转轮：直接在右侧操作（不弹窗）
local armHeld = { false, false, false }
local armDrag = nil   -- 拨动 { reel, y0, off }

local function pct(x) return math.floor(x * 1000 + 0.5) / 10 .. '%' end

-- 右侧转轮下面那行说明
local function armHint()
    local arm = run.arm
    if armMod.empty(arm) then return '转轮还是空的。打败带「印」的怪或精英，就能往上刻武器。' end
    local anyHeld = armHeld[1] or armHeld[2] or armHeld[3]
    local list = armMod.holdOdds(arm, anyHeld and armHeld or nil, config.WEAPON_ORDER)
    local parts = {}
    for _, o in ipairs(list) do parts[#parts + 1] = (o.target and W(o.target) or '空手') .. ' ' .. pct(o.p) end
    if #parts == 0 then return anyHeld and '锁住的图案连不成一线，重转也没用。' or '中间一行现在连不成任何武器。' end
    return (anyHeld and '锁住后重转：' or '中间一行连成：') .. table.concat(parts, '，')
end

function spinArm(pay)
    if not run.arm or run.status ~= 'playing' or walking or modal or armView.busy() then return end
    local anyHeld = armHeld[1] or armHeld[2] or armHeld[3]
    local held = { armHeld[1], armHeld[2], armHeld[3] }
    local r = run:armSpin(pay, anyHeld and held or nil)
    if not r.ok then setMsg(r.msg, true); return end
    armView.startSpin(held, r.faces)
    armHeld = { false, false, false }
    setMsg(r.msg)
    saveGame()
end

function toggleHold(k)
    if not run.arm or modal then return end
    armHeld[k] = not armHeld[k]
end

function openArm() end

-- 出口通向哪里：下一层有两个候选时，'>' 通向第一个、'<' 通向第二个
local function exitDest(c)
    local opts = run:nextOptions()
    if #opts == 0 then return nil end
    return opts[math.min(#opts, (c.to or 0) + 1)]
end
-- 出口的样子和那句不说破的话（按通向的那一层有多吵：扬尘 / 滴水 / 起雾）
local function exitLevel(c)
    local f = exitDest(c)
    return f and whisperMod.level(f) or 'mid'
end
local function exitWords(c)
    local f = exitDest(c)
    return f and whisperMod.whisper(f) or '井底的出口。外面有风。'
end
local EXIT_LOOK = { loud = '扬着尘的出口', quiet = '滴着水的出口', mid = '起着雾的出口' }
local function twoExits()
    for _, c in ipairs(run.cells) do if c.kind == 'exit' and c.to == 1 then return true end end
    return false
end

-- 走上出口（已经确认过）
local function stepOntoExit(cell)
    local path = run:findPath(cell)
    if not path then setMsg('走不过去', true); return end
    startWalk(path)
    walking.confirmedExit = true
end

-- 走上出口前问一次
function openExit(cell)
    local c = run.cells[cell]
    local lines = { exitWords(c), '下楼之后就回不来了。' }
    if twoExits() then lines[#lines + 1] = '这一层有两个出口，各通向不同的下一层。' end
    local due = run:rentDue()
    if due > 0 then lines[#lines + 1] = '收租的井神坐在洞口：下楼前要交 ' .. due .. ' 金币（你有 ' .. run.hero.gold .. '）。' end
    openModal(twoExits() and EXIT_LOOK[exitLevel(c)] or '出口', lines, {
        { label = '再想想', fn = function() closeModal(); setMsg('留在本层。想好了再走到出口。') end },
        { label = '往下走', primary = true, fn = function() closeModal(); stepOntoExit(cell) end },
    })
end

local function openRent(thenFn)
    local due = run:rentDue()
    local function pay(m)
        local r = run:payRent(m)
        if not r.ok then setMsg(r.msg, true); return end
        closeModal()
        thenFn()
    end
    local buttons = {
        { label = '用 3 点攻击抵', fn = function() pay('atk') end },
        { label = '用 3 点防御抵', fn = function() pay('def') end },
    }
    if run.hero.gold >= due then buttons[#buttons + 1] = { label = '交 ' .. due .. ' 金币', primary = true, fn = function() pay('gold') end } end
    openModal('井租', {
        '收租的井神伸出手：要下楼，先交 ' .. due .. ' 金币的井租。',
        '你有 ' .. run.hero.gold .. ' 金币。' .. (run.hero.gold >= due and '' or '金币不够，只能用属性抵。'),
        '交不上可以用 3 点攻击或防御抵（永久减少）。',
    }, buttons)
end

local function nextFloor(sell)
    if run:rentDue() > 0 then openRent(function() nextFloor(sell) end); return end
    closeModal()
    run:finishFloor(sell)
    armHeld = { false, false, false }
    floats, walking, heroAnim = {}, nil, nil
    saveGame()
    if run.status == 'finished' then openVictory(); return end
    setMsg('')
    continueFlow()
end

function openSummary()
    local s = run:exitSummary()
    local start = run:floorStartHero()
    local lines = {}
    local d = run.hero.hp - start.hp
    lines[#lines + 1] = '本层生命变化：' .. (d >= 0 and '+' or '') .. d
    local gains = {}
    for _, g in ipairs({ { '攻击', run.hero.atk - start.atk }, { '防御', run.hero.def - start.def }, { '金币', run.hero.gold - start.gold } }) do
        if g[2] ~= 0 then gains[#gains + 1] = g[1] .. ' ' .. (g[2] > 0 and '+' or '') .. g[2] end
    end
    lines[#lines + 1] = '本层换到：' .. (#gains > 0 and table.concat(gains, '，') or '没有')
    if s.leftoverPotions > 0 then lines[#lines + 1] = '地图上剩下的血瓶 ×' .. s.leftoverPotions .. '：+' .. s.potionGold .. ' 金币' end
    if run.decree then lines[#lines + 1] = '诏令：' .. run.decree.def.text .. '（第 ' .. run.decree['until'] .. ' 层前）' end
    local buttons = { { label = '下楼', primary = true, fn = function() nextFloor(false) end } }
    if s.keys > 0 then
        table.insert(buttons, 1, { label = '卖掉 ' .. s.keys .. ' 把骨钥（+' .. s.keyGold .. '）', fn = function() nextFloor(true) end })
    end
    openModal(run:floor().name .. ' 完成', lines, buttons)
end

-- 大转盘
function openWheel(i)
    local lines = { '盘面八格，每格机会一样（各 12.5%）：' }
    local t = {}
    for k, s in ipairs(wheelMod.SECTORS) do t[k] = s.text end
    lines[#lines + 1] = table.concat(t, '、')
    local price = run:wheelPrice(i)
    lines[#lines + 1] = '转一次：' .. price.gold .. ' 金币，或 ' .. price.blood .. ' 生命（每转一次 ×1.5）'
    lines[#lines + 1] = '你有 ' .. run.hero.gold .. ' 金币、' .. run.hero.hp .. ' 生命。'
    local function spin(pay)
        local r = run:wheelSpin(i, pay)
        if not r.ok then setMsg(r.msg, true); return end
        setMsg(r.msg, run.status == 'dead')
        saveGame()
        closeModal()
        if run.status == 'dead' then openDeath(); return end
        if run:pendingEngrave() then continueFlow() else openWheel(i) end
    end
    openModal('大转盘', lines, {
        { label = '金币 ' .. price.gold, primary = true, fn = function() spin('gold') end },
        { label = '生命 ' .. price.blood, danger = true, fn = function() spin('blood') end },
        { label = '离开', fn = function() closeModal() end },
    })
end

-- 当铺
function openPawn(i)
    local f = run:floor()
    local lines = { '当铺不收攻击和防御。你有 ' .. run.hero.gold .. ' 金币、' .. run.hero.keys .. ' 把骨钥。' }
    for _, l in ipairs(armReelsText()) do lines[#lines + 1] = l end
    for j, p in ipairs(run.pawned) do lines[#lines + 1] = '当着的：' .. W(p.weapon) .. '（原来在轮子 ' .. p.reel .. '），赎回 ' .. run:redeemPrice(j) .. ' 金（每过一层涨 20%）' end
    for k, w in ipairs(f.shop or {}) do lines[#lines + 1] = '卖：' .. weaponLine(w) .. '　' .. run:shopPrice(w) .. ' 金' .. (run:sold(i, k) and '（已卖出）' or '') end
    local function after(r)
        setMsg(r.msg, not r.ok)
        saveGame()
        openPawn(i)
    end
    local buttons = {}
    if run.hero.keys > 0 then buttons[#buttons + 1] = { label = '卖骨钥 +' .. Run.PAWN.keyPrice, fn = function() after(run:pawnSellKey(i)) end } end
    if not armMod.empty(run.arm) then
        buttons[#buttons + 1] = { label = '当掉一格 +' .. Run.PAWN.pawnGold, fn = function() chooseCell('当掉哪一格？', function(r, k) after(run:pawnCell(i, r, k)) end) end }
        buttons[#buttons + 1] = { label = '擦掉一格 −' .. Run.PAWN.erasePrice, fn = function() chooseCell('擦掉哪一格？', function(r, k) after(run:pawnErase(i, r, k)) end) end }
    end
    for j, p in ipairs(run.pawned) do
        buttons[#buttons + 1] = { label = '赎' .. W(p.weapon) .. ' −' .. run:redeemPrice(j), fn = function()
            if armMod.firstBlank(run.arm, p.reel) then after(run:pawnRedeem(i, j)); return end
            local l2 = { reelText(p.reel), '轮子 ' .. p.reel .. ' 刻满了。选一格覆盖。' }
            local b2 = {}
            for k = 1, armMod.SIZE do b2[#b2 + 1] = { label = '覆盖第 ' .. k .. ' 格', fn = function() closeModal(); after(run:pawnRedeem(i, j, k)) end } end
            b2[#b2 + 1] = { label = '算了', fn = function() closeModal(); openPawn(i) end }
            openModal('赎回' .. W(p.weapon), l2, b2)
        end }
    end
    for k, w in ipairs(f.shop or {}) do
        if not run:sold(i, k) then
            buttons[#buttons + 1] = { label = '买' .. W(w) .. ' −' .. run:shopPrice(w), fn = function()
                chooseSlot('买' .. W(w), function(reel, cell) after(run:pawnBuy(i, k, reel, cell)) end)
            end }
        end
    end
    buttons[#buttons + 1] = { label = '离开', primary = true, fn = function() closeModal() end }
    openModal('当铺', lines, buttons)
end

-- 骨坛：先选特性，再选武器，最后选献什么
function openAltar(i, boon, weapon)
    local used = Run.contains(run.altarUsed, run.floorIndex .. ':' .. i)
    if used then
        openModal('骨坛', { '这座骨坛已经用过了。' }, { { label = '离开', primary = true, fn = function() closeModal() end } })
        return
    end
    local lines = { '献 3 点攻击或 1 把骨钥，把你这一局杀过的怪的本事移到转轮上的一把武器上。' }
    local buttons = {}
    if not boon then
        if #run.boonsSeen == 0 then lines[#lines + 1] = '你这一局还没杀过带特性的怪（溺魂、回声蝠、裂岩蟹、盐蚀蛞蝓）。' end
        for _, b in ipairs(run.boonsSeen) do
            lines[#lines + 1] = config.BOON_NAMES[b] .. '：' .. config.BOON_DESC[b]
            buttons[#buttons + 1] = { label = config.BOON_NAMES[b], fn = function() openAltar(i, b) end }
        end
    elseif not weapon then
        lines[#lines + 1] = '移「' .. config.BOON_NAMES[boon] .. '」到哪一把上？'
        local seen = {}
        for _, c in ipairs(armMod.engravedCells(run.arm)) do
            local w = run.arm.reels[c[1]][c[2]]
            if w ~= armMod.WILD and not seen[w] then
                seen[w] = true
                buttons[#buttons + 1] = { label = W(w), fn = function() openAltar(i, boon, w) end }
            end
        end
        if not next(seen) then lines[#lines + 1] = '转轮上还没有武器图案。' end
    else
        lines[#lines + 1] = '把「' .. config.BOON_NAMES[boon] .. '」移到' .. W(weapon) .. '上。献什么？'
        local function offer(pay)
            local r = run:altarOffer(i, pay, boon, weapon)
            setMsg(r.msg, not r.ok)
            saveGame()
            closeModal()
        end
        buttons[#buttons + 1] = { label = '献 3 点攻击', fn = function() offer('atk') end }
        if run.hero.keys > 0 then buttons[#buttons + 1] = { label = '献 1 把骨钥', primary = true, fn = function() offer('key') end } end
    end
    buttons[#buttons + 1] = { label = '离开', fn = function() closeModal() end }
    openModal('骨坛', lines, buttons)
end

function openStall(i)
    local offers = run:floor().stall or {}
    local lines = { '火边的摊主不说话，只指了指木板上的价签。每样只卖一次。', '你有 ' .. run.hero.gold .. ' 金币。' }
    local buttons = {}
    for k, o in ipairs(offers) do
        local sold = run:sold(i, k)
        lines[#lines + 1] = Run.stallText(o) .. '：' .. o.price .. ' 金' .. (sold and '（已买）' or '')
        if not sold then
            buttons[#buttons + 1] = { label = Run.stallText(o) .. '（' .. o.price .. '）', fn = function()
                local r = run:stallBuy(i, k)
                setMsg(r.msg, not r.ok)
                saveGame()
                openStall(i)
            end }
        end
    end
    buttons[#buttons + 1] = { label = '离开', primary = true, fn = function() closeModal() end }
    openModal('补给摊', lines, buttons)
end

local function openFacility(i)
    local k = run.cells[i].kind
    if k == 'wheel' then openWheel(i)
    elseif k == 'pawn' then openPawn(i)
    elseif k == 'altar' then openAltar(i)
    else openStall(i) end
end
facilityOpener = openFacility

function openVictory()
    love.filesystem.remove(SAVE_FILE)
    local h = run.hero
    openModal('你走到了井底', {
        '二十层，一层不落。',
        '剩余生命 ' .. h.hp .. '，攻 ' .. h.atk .. ' / 防 ' .. h.def .. '，金币 ' .. h.gold .. (h.weapon and ('，手上是' .. W(h.weapon)) or '') .. '。',
        '总步数 ' .. run.totalSteps .. '。',
        '（第 20 层 Boss 站位战还是占位，正式版会换掉。）',
    }, { { label = '再来一局', primary = true, fn = function() closeModal(); newGame() end } })
end

local function saveMeta() love.filesystem.write(META_FILE, serialize.dump(meta)) end

function openDeath()
    love.filesystem.remove(SAVE_FILE)
    if run.tutorial then
        meta.tutorialDone = true
        saveMeta()
        openModal('……', {
            '那东西只睁了一下眼，你就被甩回了黑暗里。',
            '你在井口醒来。右臂没了，断口处长出一个空空的转轮。',
            '转轮上什么都没有。打败带印记的怪、打败精英，就能往上面刻武器的图案。',
            '这一次，从第 1 层重新往下走。',
        }, { { label = '再下井', primary = true, fn = function() closeModal(); newGame() end } })
        return
    end
    openModal('你倒下了', { '你倒在了' .. run:floor().name .. '。', '这一局结束了。重新开始要从第 1 层走起，地图会换，转轮上的图案也会清空。' }, {
        { label = '从第 1 层重新开始', primary = true, fn = function() closeModal(); newGame() end },
    })
end

local function planFor(seed, tutorial)
    return tutorial and route.tutorial(seed) or route.build(seed)
end

function newGame(seed)
    seed = seed or tonumber(os.getenv('DESCENT_SEED') or '') or os.time()
    local tutorial = not meta.tutorialDone
    run = Run.new(planFor(seed, tutorial), 'digger', seed, { tutorial = tutorial })
    facing = 'down'
    floats, walking, heroAnim = {}, nil, nil
    armHeld = { false, false, false }
    saveGame()
    if tutorial then
        openModal('坠井', {
            '你失足掉进了一口很深的井。',
            '往下走，找出口。画面下方会一步步告诉你怎么走。',
        }, { { label = '往下走', primary = true, fn = function() closeModal(); setMsg('') end } })
    else
        setMsg('')
        continueFlow()
    end
end

function loadGame(data)
    facing = miner.restoreFacing(data.facing)
    run = Run.load(planFor(data.run.seed, data.run.tutorial), data.run)
    setMsg('继续上一局。')
    if run.status == 'floorDone' then openSummary() else continueFlow() end
end

-- ---------- LÖVE 回调 ----------
local function makeFrame()
    local w, h = love.graphics.getDimensions()
    frame = love.graphics.newCanvas(w, h)
end

function love.load()
    love.graphics.setDefaultFilter('nearest', 'nearest')
    miner.load()
    fx.load()
    fx.loadShader()
    fx.loadLight()
    canvas = love.graphics.newCanvas(LW, LH)
    relayout()
    makeFrame()
    local m = love.filesystem.getInfo(META_FILE) and serialize.load(love.filesystem.read(META_FILE))
    if m then
        meta = m
        if meta.crt == nil then meta.crt = true end
    end
    if meta.volume == nil then meta.volume = 1 end
    applySettings()
    scene = 'title'   -- 先到开局界面：继续游戏 / 开始游戏 / 设置 / 退出
    if os.getenv('DESCENT_AUTOTEST') then require('autotest').start() end
end

function love.resize()
    relayout()
    makeFrame()
end

-- 墙缝滴水的位置：下面是空地的墙（每层算一次）
local dripCache = { floor = nil, spots = {} }
local function dripSpots()
    local key = tostring(run.floorIndex) .. ':' .. tostring(run.picks[run.floorIndex])
    if dripCache.floor == key then return dripCache.spots end
    local spots = {}
    for i, c in ipairs(run.cells) do
        local below = i + run.w
        if c.kind == 'wall' and below <= #run.cells and run.cells[below].kind ~= 'wall' then
            local x, y = tileXY(i)
            spots[#spots + 1] = { x + 4 + love.math.random(0, TILE - 8), y + TILE - 2 }
        end
    end
    dripCache = { floor = key, spots = spots }
    fx.clearDrips()
    return spots
end

local updateHold -- 长按方向键连续走（定义在输入部分）
local lastMouse = { x = -1, y = -1 }

function love.update(dt)
    clock = clock + dt
    if scene == 'title' then
        fx.update(dt)
        if not modal then
            local mx, my = love.mouse.getPosition()
            local k = titleItemAt((mx - OX) / S, (my - OY) / S)
            if k and (mx ~= lastMouse.x or my ~= lastMouse.y) then titleSel = k end
            lastMouse.x, lastMouse.y = mx, my
        end
        return
    end
    updateHold(dt)
    fx.update(dt)
    armView.update(dt)
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
    fx.updateDrips(dt, dripSpots())
    local mx, my = love.mouse.getPosition()
    hovered = forcedHover or tileAt((mx - OX) / S, (my - OY) / S)
end

-- ---------- 绘制：像素层 ----------
-- 斜俯视的立体感：地面有一道前沿（厚度），墙往上凸，有顶面和正面
local function shade(c, k) return { c[1] * k, c[2] * k, c[3] * k } end

local function drawTile(i)
    local c = run.cells[i]
    local x, y = tileXY(i)
    local g = love.graphics
    local front, lift = math.floor(TILE * 0.3), math.floor(TILE * 0.15)   -- 墙的正面高度、往上凸多少
    if c.kind == 'wall' then
        -- 正面（砖缝）
        setColor({ 0.17, 0.14, 0.11 }); g.rectangle('fill', x, y + TILE - front, TILE, front)
        setColor({ 0.12, 0.10, 0.08 })
        g.rectangle('fill', x, y + TILE - math.floor(front / 2), TILE, 1)
        g.rectangle('fill', x + math.floor(TILE / 3), y + TILE - front, 1, math.floor(front / 2)); g.rectangle('fill', x + math.floor(TILE * 0.72), y + TILE - math.floor(front / 2), 1, math.floor(front / 2))
        -- 顶面
        setColor({ 0.27, 0.23, 0.19 }); g.rectangle('fill', x, y - lift, TILE, TILE - front + lift)
        setColor({ 0.33, 0.29, 0.23 }); g.rectangle('fill', x, y - lift, TILE, 2)
        setColor({ 0.22, 0.19, 0.15 })
        for k = 0, TILE - 1, 7 do g.rectangle('fill', x + k + (i % 3) * 2, y + (k % 10) - 2, 2, 1) end
        return
    end
    local base = C.floor
    if c.kind == 'monster' then base = C.monster
    elseif c.kind == 'item' then base = C.item
    elseif c.kind == 'door' then base = c.door == 'blood' and C.blood or C.door
    elseif c.kind == 'exit' then base = C.exit
    elseif floorMod.isFacility(c) then base = C.door end
    -- 前沿（厚度）和顶面
    local lip = math.max(3, math.floor(TILE * 0.17))
    setColor(shade(base, 0.55)); g.rectangle('fill', x + 1, y + TILE - lip, TILE - 2, lip - 1, 2, 2)
    setColor(base); g.rectangle('fill', x + 1, y + 1, TILE - 2, TILE - lip, 3, 3)
    setColor(shade(base, 1.25)); g.rectangle('fill', x + 2, y + 1, TILE - 4, 1)
    local cx, cy = x + TILE / 2, y + TILE / 2 - 2
    if c.kind == 'monster' then
        -- 怪物脚下的影子
        setColor({ 0, 0, 0 }, 0.35); g.ellipse('fill', cx, y + TILE - lip - 3, 8, 2)
    elseif c.kind == 'item' then
        if c.id == 'smallPotion' or c.id == 'bigPotion' then
            local s = (c.id == 'bigPotion' and 1.3 or 1) * K
            setColor({ 0, 0, 0 }, 0.3); g.ellipse('fill', cx, cy + 9 * s, 7 * s, 2)
            setColor({ 0.62, 0.7, 0.73 }); g.rectangle('fill', cx - 2 * s, cy - 10 * s, 4 * s, 3 * s)
            setColor(C.hp); g.rectangle('fill', cx - 6 * s, cy - 7 * s, 12 * s, 15 * s, 2, 2)
            setColor({ 1, 0.7, 0.75 }); g.rectangle('fill', cx - 4 * s, cy - 5 * s, 2, 6 * s)
        elseif c.id == 'redGem' or c.id == 'blueGem' then
            local s = K
            setColor({ 0, 0, 0 }, 0.3); g.ellipse('fill', cx, cy + 10 * s, 8 * s, 2)
            setColor(c.id == 'redGem' and { 0.89, 0.33, 0.23 } or { 0.18, 0.5, 0.84 })
            g.polygon('fill', cx, cy - 10 * s, cx + 10 * s, cy, cx, cy + 10 * s, cx - 10 * s, cy)
            setColor({ 1, 1, 1 }, 0.45); g.polygon('fill', cx, cy - 10 * s, cx + 4 * s, cy - 4 * s, cx, cy, cx - 4 * s, cy - 4 * s)
        end
    elseif c.kind == 'exit' then
        -- 往下的台阶（越往下越暗）
        for k = 0, 3 do
            setColor(shade(C.exit, 1.3 - k * 0.22))
            g.rectangle('fill', x + 4 + k * 2, y + 3 + k * 4, TILE - 8 - k * 4, 3)
        end
    end
end

-- 出口的样子：通向的那一层吵（扬尘往上飘）、安静（往下滴水）、说不准（雾慢慢散开）
local function drawExitFx(i, level)
    local g = love.graphics
    local x, y = tileXY(i)
    local cx = x + TILE / 2
    if level == 'loud' then
        for k = 0, 5 do
            local t = (clock * 0.7 + k / 6) % 1
            local px = cx + math.sin(k * 2.3 + clock * 1.7) * (TILE * 0.32)
            setColor({ 0.68, 0.60, 0.50 }, 0.85 * (1 - t))
            g.rectangle('fill', math.floor(px), math.floor(y + TILE * 0.6 - t * TILE * 0.9), 2, 2)
        end
    elseif level == 'quiet' then
        for k = 0, 2 do
            local t = (clock * 0.8 + k / 3) % 1
            local px = x + TILE * (0.3 + 0.2 * k)
            setColor({ 0.55, 0.75, 0.95 }, 0.8 * (1 - t * 0.6))
            g.rectangle('fill', math.floor(px), math.floor(y - 2 + t * TILE * 0.7), 1, 3)
        end
    else
        for k = 0, 2 do
            local t = (clock * 0.25 + k / 3) % 1
            setColor({ 0.78, 0.84, 0.86 }, 0.18 * math.sin(t * math.pi))
            g.ellipse('fill', cx + (k - 1) * 5 + t * 4, y + TILE * 0.45 - t * 6, TILE * (0.3 + 0.25 * t), TILE * (0.12 + 0.08 * t))
        end
    end
end

local armTexts = {}
local function drawPixel()
    local g = love.graphics
    g.setCanvas(canvas)
    g.clear(C.bg[1], C.bg[2], C.bg[3])
    armTexts = {}
    -- 顶栏底色
    setColor(C.panel); g.rectangle('fill', 0, 0, LW, 30)
    -- 左边的深度条：1～20 层
    for d = 1, 20 do
        local y = MAP_Y + (d - 1) * 14
        local now = d == run.floorIndex
        local col = d < run.floorIndex and { 0.16, 0.24, 0.20 } or (now and { 0.85, 0.64, 0.25 } or { 0.10, 0.13, 0.15 })
        setColor(col); g.rectangle('fill', 8, y, 18, 12, 2, 2)
        if (d == 9 or d == 17) and not run.tutorial then setColor({ 0.79, 0.55, 0.23 }); g.rectangle('line', 8.5, y + 0.5, 17, 11, 2, 2) end
        if (d == 10 or d == 19) and not run.tutorial then setColor({ 0.88, 0.4, 0.45 }); g.circle('fill', 23, y + 3, 1.5) end
        if d == 20 and not run.tutorial then setColor({ 0.5, 0.15, 0.2 }); g.rectangle('fill', 8, y + 10, 18, 2) end
    end
    -- 地图：一行一行画（墙会盖住上一行的下沿，看起来是立着的）
    for i = 1, #run.cells do
        if run.cells[i].kind ~= 'wall' then drawTile(i) end
        if i % run.w == 0 then
            for k = i - run.w + 1, i do if run.cells[k].kind == 'wall' then drawTile(k) end end
        end
    end
    -- 悬停框
    if hovered and run.cells[hovered].kind ~= 'wall' and not modal then
        local x, y = tileXY(hovered)
        setColor({ 1, 0.9, 0.6 }, 0.6); g.rectangle('line', x + 0.5, y + 0.5, TILE - 1, TILE - 4, 3, 3)
    end
    fx.drawDrips()
    for i, c in ipairs(run.cells) do if c.kind == 'exit' then drawExitFx(i, exitLevel(c)) end end
    -- 主角（走路时在两格之间插值）
    local hx, hy = tileXY(run.pos)
    if heroAnim then
        local fx0, fy0 = tileXY(heroAnim.from)
        hx = fx0 + (hx - fx0) * heroAnim.t
        hy = fy0 + (hy - fy0) * heroAnim.t
    end
    setColor({ 0, 0, 0 }, 0.35); g.ellipse('fill', hx + TILE / 2, hy + TILE - 5, 7, 2)
    miner.draw(facing, hx + TILE / 2, hy + TILE - 4, run.status == 'dead', 22)
    -- 矿灯：主角附近暖、远处冷暗（最暗也看得清格子）
    fx.lamp(MAP_X, MAP_Y - 4, run.w * TILE, run.h * TILE + 4, hx + TILE / 2, hy + TILE / 2 - 4, 170)
    -- 断臂转轮（机械小臂）
    if run.arm then
        armView.draw(run.arm, armHeld, armDrag and armDrag.reel, armDrag and armDrag.off or 0, function(x, y, w, h, sym, mid, alpha, top, bottom)
            armTexts[#armTexts + 1] = { x = x, y = y, w = w, h = h, sym = sym, mid = mid, alpha = alpha, top = top, bottom = bottom }
        end)
    end
    g.setCanvas()
end

-- ---------- 绘制：UI 层 ----------
local SHORT = { moss = '苔', eel = '鳗', frog = '蛙', beetle = '甲', bat = '蝠', wraith = '魂', crab = '蟹', guardian = '守', rat = '鼠', slug = '蝓', priest = '祭', gatekeeper = '门', eye = '眼' }

local FACILITY_GLYPH = {
    stall = { '摊', '补给', '补给摊', '火边的补给摊，花金币买生命、攻击或防御。' },
    wheel = { '盘', '转盘', '大转盘', '盘面八格全部公开：金币、生命、攻防、新图案，也有井蛭和擦掉图案。' },
    pawn = { '当', '当铺', '当铺', '卖骨钥、当掉或赎回武器图案、买图案、擦图案。不收攻防。' },
    altar = { '坛', '骨坛', '骨坛', '献 3 点攻击或 1 把骨钥，把杀过的怪的本事移到一把武器上。' },
}

local function inRect(lx, ly, x, y, w, h) return lx >= x and lx <= x + w and ly >= y and ly <= y + h end
local function rect(c, x, y, w, h, a, r)
    setColor(c, a)
    love.graphics.rectangle('fill', OX + x * S, OY + y * S, w * S, h * S, (r or 0) * S, (r or 0) * S)
end

-- 一个数值：小图标 + 数字，变化时跳一下
local function stat(key, label, value, x, color)
    local k, up = fx.watch(key, value)
    rect(color, x, 10, 6, 6, 1, 1)
    local col = up == nil and C.text or (up and { 0.6, 1, 0.7 } or C.warn)
    text(label, x + 9, 8, 7, C.dim)
    text(tostring(value), x + 9 + (#label > 0 and 14 or 0), 6 - (k - 1) * 6, 10 * k, col)
end

-- 悬停卡片的内容
local function hoverLines(i)
    local c = run.cells[i]
    if c.kind == 'monster' then
        local m = run:monsterAt(i)
        local p = preview(i)
        local base = config.MONSTERS[c.id]
        local L = { { m.name, 10, C.text }, { '生命 ' .. m.hp .. '  攻 ' .. m.atk .. '  防 ' .. m.def, 7, C.dim } }
        if m.atk ~= base.atk then L[#L + 1] = { '群居：攻击 ' .. base.atk .. ' → ' .. m.atk, 7, C.warn } end
        if m.def ~= base.def then L[#L + 1] = { '被庇护：防御 ' .. base.def .. ' → ' .. m.def, 7, C.warn } end
        for k in pairs(m.traits) do L[#L + 1] = { config.TRAIT_NAMES[k] .. '：' .. config.TRAIT_DESC[k], 6.5, C.dim } end
        if p.fatal then L[#L + 1] = { p.text == '会死' and ('预计 −' .. p.lose .. '，你会死') or (p.text .. '，硬打会死'), 8.5, C.warn }
        else L[#L + 1] = { '预计 −' .. p.lose .. '，打完剩 ' .. p.left, 8.5, C.ok } end
        L[#L + 1] = { '掉落 ' .. p.gold .. ' 金', 6.5, C.gold }
        if run:marked(i) then L[#L + 1] = { '印：打败后可刻' .. config.WEAPONS[config.MARK_WEAPON[c.id]].name, 6.5, C.ok } end
        return L
    elseif c.kind == 'item' then
        local f = run:floor()
        local gem = f.gem + run.ch.gemBonus
        local eff = ({ smallPotion = '生命 +' .. f.smallPotion, bigPotion = '生命 +' .. f.bigPotion, redGem = '攻击 +' .. gem, blueGem = '防御 +' .. gem, key = '骨钥 +1', gold = '金币 +' .. f.gold })[c.id]
        return { { config.ITEM_NAMES[c.id], 10, C.text }, { eff, 8, C.text } }
    elseif c.kind == 'door' then
        return { { c.door == 'bone' and '骨门' or '血门', 10, C.text }, { c.door == 'bone' and '消耗 1 把骨钥' or ('通过时扣 ' .. run:floor().bloodCost .. ' 生命'), 7.5, C.text } }
    elseif c.kind == 'exit' then
        if run:eliteAlive() then return { { '出口', 10, C.text }, { '精英还活着，出口被封住了', 7.5, C.text } } end
        return { { twoExits() and EXIT_LOOK[exitLevel(c)] or '出口', 10, C.text }, { exitWords(c), 7.5, { 0.78, 0.84, 0.86 } }, { '走上去前会问你一次，还能回头', 6.5, C.dim } }
    elseif floorMod.isFacility(c) then
        local g = FACILITY_GLYPH[c.kind]
        return { { g[3], 10, C.text }, { g[4], 6.5, C.dim } }
    end
    return nil
end

local function drawTooltip(i)
    local L = hoverLines(i)
    if not L then return end
    local x, y = tileXY(i)
    local w = 150
    local h = 8
    for _, l in ipairs(L) do h = h + (l[2] >= 9 and 14 or (l[2] >= 7.5 and 12 or (#l[1] > 40 and 20 or 11))) end
    local tx = x + TILE + 4
    if tx + w > PANEL_X - 4 then tx = x - w - 4 end
    local ty = math.max(32, math.min(y - 4, LH - h - 26))
    rect({ 0.05, 0.07, 0.08 }, tx, ty, w, h, 0.94, 4)
    setColor({ 0.4, 0.33, 0.2 }); love.graphics.rectangle('line', OX + tx * S, OY + ty * S, w * S, h * S, 4 * S, 4 * S)
    local yy = ty + 5
    for _, l in ipairs(L) do
        text(l[1], tx + 6, yy, l[2], l[3], 'left', w - 12)
        yy = yy + (l[2] >= 9 and 14 or (l[2] >= 7.5 and 12 or (#l[1] > 40 and 20 or 11)))
    end
end

local SYMW = { boneKnife = '刀', harpoon = '叉', hammer = '锤', mossBlade = '苔', bellStaff = '铃', saltDagger = '盐', rustSword = '锈', wellHook = '钩', wild = '赖' }

local function drawArmUI()
    if not run.arm then return end
    local g = love.graphics
    text('断臂转轮', armView.X + 10, armView.Y + 26, 8, { 0.96, 0.85, 0.6 })
    -- 轮子上的图案（大字，一眼认得出；只画在窗口里）
    for _, t in ipairs(armTexts) do
        g.setScissor(OX + t.x * S, OY + t.top * S, t.w * S, (t.bottom - t.top) * S)
        local col = t.sym == armMod.WILD and C.ok or (t.sym and (t.mid and { 1, 0.96, 0.88 } or { 0.62, 0.62, 0.6 }) or { 0.3, 0.32, 0.33 })
        setColor(col, t.alpha)
        love.graphics.setFont(font((t.sym and (t.mid and 15 or 12) or 10) * S))
        love.graphics.printf(t.sym and SYMW[t.sym] or '·', OX + t.x * S, OY + (t.y + (t.mid and 4 or 6)) * S, t.w * S, 'center')
        g.setScissor()
    end
    for r = 1, 3 do
        local lx, ly, lw = armView.lockRect(r)
        text(armHeld[r] and '已锁' or '锁', lx, ly + 2, 6.5, armHeld[r] and { 0.15, 0.1, 0.02 } or { 0.85, 0.75, 0.55 }, 'center', lw)
    end
    local price = run:armPrice(armHeld)
    local anyHeld = armHeld[1] or armHeld[2] or armHeld[3]
    text((anyHeld and '拉杆重转 ' or '拉杆 ') .. price.gold .. ' 金（R）', armView.X + 10, armView.Y + 160, 7.5, { 0.96, 0.85, 0.6 })
    local b = armView.BLOOD
    text('用血转 ' .. price.blood, b.x, b.y + 4, 7, { 1, 0.85, 0.88 }, 'center', b.w)
    text(armHint(), PANEL_X + 2, armView.Y + 222, 6.5, C.dim, 'left', PANEL_W)
    if not meta.dragged then text('按住轮子上下拨动看整圈', PANEL_X + 2, armView.Y + 258, 6, { 0.42, 0.48, 0.5 }, 'left', PANEL_W) end
    -- 连成一线：大字跳一下
    local kind, t = armView.flashInfo()
    if kind == 'win' and run.hero.weapon then
        local k = 1 + 0.6 * math.max(0, 1 - t / 0.25)
        text(config.WEAPONS[run.hero.weapon].name .. '！', armView.X - 20, armView.Y + 112 - (k - 1) * 10, 13 * k, C.ok, 'center', 170)
    elseif kind == 'lose' then
        text('空手……', armView.X - 20, armView.Y + 112, 12, C.dim, 'center', 170)
    end
end

local function drawModal()
    if modal then
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.rectangle('fill', 0, 0, love.graphics.getDimensions())
        local x, y, w, hh, rects = modalLayout()
        setColor(C.panel); love.graphics.rectangle('fill', OX + x * S, OY + y * S, w * S, hh * S)
        setColor(C.line); love.graphics.rectangle('line', OX + x * S, OY + y * S, w * S, hh * S)
        text(modal.title, x + 16, y + 12, 12, C.accent)
        for k, line in ipairs(modal.lines) do
            text(line, x + 16, y + 30 + (k - 1) * modalLineH(), #modal.lines > 12 and 7 or 8, C.text, 'left', w - 32)
        end
        for k, b in ipairs(modal.buttons) do
            local r = rects[k]
            setColor(b.danger and { 0.35, 0.12, 0.16 } or (b.primary and { 0.12, 0.35, 0.3 } or { 0.11, 0.16, 0.19 }))
            love.graphics.rectangle('fill', OX + r.x * S, OY + r.y * S, r.w * S, r.h * S)
            text(b.label, r.x, r.y + 5, 8, C.text, 'center', r.w)
        end
    end
end

local function drawUI()
    do
        local h = run.hero
        local atk, def = combat.effectiveStats(h)
        text(run:floor().name, MAP_X, 7, 10, C.accent)
        stat('hp', '', h.hp, 190, C.hp)
        stat('atk', '攻', atk, 250, C.atk)
        stat('def', '防', def, 300, C.def)
        stat('keys', '钥', h.keys, 350, { 0.85, 0.76, 0.48 })
        stat('gold', '金', h.gold, 396, C.gold)
        local wname = h.weapon and config.WEAPONS[h.weapon].name or (run.arm and '空手' or '')
        text(wname, 452, 8, 8.5, h.weapon and C.atk or C.dim)
        if h.boons then
            local names = {}
            for k, b in ipairs(h.boons) do names[k] = config.BOON_NAMES[b] end
            text(table.concat(names, '·'), 452, 20, 6, C.accent)
        end
        if run.decree then
            text('诏令：' .. run.decree.def.text .. (run.decree.def.kind == 'killTrait' and ('（' .. run.decree.progress .. '/' .. run.decree.def.n .. '）') or '') .. '，第 ' .. run.decree['until'] .. ' 层前', MAP_X, 31, 6.5, C.ok)
        end
        -- 深度条的数字
        for d = 1, 20 do text(tostring(d), 8, MAP_Y + (d - 1) * 14 + 2, 5.5, d == run.floorIndex and { 0.1, 0.07, 0.02 } or { 0.45, 0.52, 0.55 }, 'center', 18) end
        -- 格子上的字；怪物头上挂"掉多少血"的牌子
        for i, c in ipairs(run.cells) do
            local x, y = tileXY(i)
            if c.kind == 'monster' then
                local p = preview(i)
                text(SHORT[c.id], x, y + 5, 10, { 1, 0.86, 0.88 }, 'center', TILE)
                local tag = p.fatal and (p.text == '会死' and '会死' or p.text) or ('−' .. p.lose)
                local tw = math.max(16, #tag * 2.1 + 6)
                rect(p.fatal and { 0.75, 0.2, 0.25 } or { 0.94, 0.77, 0.42 }, x + (TILE - tw) / 2, y - 5, tw, 8, 1, 4)
                text(tag, x - 4, y - 5, 5.5, p.fatal and { 1, 0.95, 0.95 } or { 0.12, 0.08, 0.02 }, 'center', TILE + 8)
                if run:marked(i) then text('印', x + TILE - 7, y + 1, 5.5, C.ok) end
            elseif c.kind == 'door' then
                text(c.door == 'bone' and '门' or '血门', x, y + 3, 8, { 0.95, 0.84, 0.6 }, 'center', TILE)
                text(c.door == 'bone' and '骨钥' or ('−' .. run:floor().bloodCost), x - 4, y + 14, 5, C.dim, 'center', TILE + 8)
            elseif c.kind == 'item' and (c.id == 'key' or c.id == 'gold') then
                text(c.id == 'key' and '钥' or '金', x, y + 5, 10, C.gold, 'center', TILE)
            elseif c.kind == 'exit' then
                text('出口', x - 4, y + TILE - 11, 5, { 0.8, 1, 0.9 }, 'center', TILE + 8)
            elseif floorMod.isFacility(c) then
                local g = FACILITY_GLYPH[c.kind]
                text(g[1], x, y + 3, 10, C.gold, 'center', TILE)
                text(g[2], x - 4, y + 15, 5, C.dim, 'center', TILE + 8)
            end
        end
        for _, f in ipairs(floats) do
            text(f.text, f.x - 10, f.y - f.t * 16, 8, f.color, 'center', TILE + 20)
        end
        drawArmUI()
        if hovered and not modal and not walking and run.cells[hovered].kind ~= 'wall' and run.cells[hovered].kind ~= 'floor' then drawTooltip(hovered) end
        -- 底部：消息和提示
        -- 底部：教程局是教学提示条；正式局只显示刚发生的事（不再有楼层提示和小字说明）
        local tip, age = coach.current(run, clock)
        if tip and not msgErr then
            local x, y, w, hh = MAP_X, LH - 28, PANEL_X - MAP_X - 8, 25
            local glow = math.max(0, 1 - age / 0.6)
            rect({ 0.06, 0.12, 0.11 }, x, y, w, hh, 0.95, 4)
            setColor({ 0.37 + 0.5 * glow, 0.82, 0.71 }, 0.6 + 0.4 * glow)
            love.graphics.setLineWidth(1 + glow * 2)
            love.graphics.rectangle('line', OX + x * S, OY + y * S, w * S, hh * S, 4 * S, 4 * S)
            love.graphics.setLineWidth(1)
            rect(C.accent, x + 5, y + 7, 20, 11, 1, 3)
            text('教学', x + 5, y + 8, 6, { 0.04, 0.1, 0.09 }, 'center', 20)
            text(tip, x + 30, y + 3, 7, C.text, 'left', w - 36)
        elseif msg ~= '' then
            text(msg, MAP_X, LH - 22, 7.5, msgErr and C.warn or C.text, 'left', PANEL_X - MAP_X - 8)
        end
    end

    drawModal()
end

function love.draw()
    if scene == 'title' then
        love.graphics.setCanvas(canvas)
        titleView.draw(LW, LH, clock)
        love.graphics.setCanvas()
    else
        drawPixel()
    end
    love.graphics.setCanvas(frame)
    love.graphics.clear(0, 0, 0)
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(canvas, OX, OY, 0, S, S)
    if scene == 'title' then drawTitleUI(); drawModal() else drawUI() end
    love.graphics.setCanvas()
    love.graphics.clear(0, 0, 0)
    fx.drawCRT(frame, meta.crt)
end

-- ---------- 开局界面、设置、暂停 ----------
function hasSave() return love.filesystem.getInfo(SAVE_FILE) ~= nil end

function applySettings()
    love.audio.setVolume(meta.volume or 1)
    if love.window.getFullscreen() ~= (meta.fullscreen or false) then
        love.window.setFullscreen(meta.fullscreen or false, 'desktop')
        relayout()
        makeFrame()
    end
end

function toGame() scene = 'game'; fx.resetWatch() end

function continueGame()
    local data = hasSave() and serialize.load(love.filesystem.read(SAVE_FILE))
    if data and data.run and data.run.picks then
        toGame()
        loadGame(data)
    else
        toGame()
        newGame()
    end
end

function startNewGame()
    love.filesystem.remove(SAVE_FILE)
    closeModal()
    walking, heroAnim = nil, nil
    toGame()
    newGame()
end

function backToTitle()
    if run and run.status == 'playing' then saveGame() end
    closeModal()
    walking, heroAnim = nil, nil
    scene = 'title'
    titleSel = 1
end

local VOLUMES = { 0, 0.25, 0.5, 0.75, 1 }

-- 设置：老电视滤镜、全屏、音量、重新走新手教程。back：关掉设置后回到哪里
function openSettings(back)
    local function reopen() openSettings(back) end
    local vol = meta.volume or 1
    local buttons = {
        { label = '老电视滤镜：' .. (meta.crt and '开' or '关'), fn = function() meta.crt = not meta.crt; saveMeta(); reopen() end },
        { label = '全屏：' .. (meta.fullscreen and '开' or '关'), fn = function() meta.fullscreen = not meta.fullscreen; saveMeta(); applySettings(); reopen() end },
        { label = '音量：' .. math.floor(vol * 100 + 0.5) .. '%', fn = function()
            local nxt = VOLUMES[1]
            for k, v in ipairs(VOLUMES) do if v > vol + 0.01 then nxt = v; break end end
            meta.volume = nxt; saveMeta(); applySettings(); fx.play('pick'); reopen()
        end },
        { label = '重新走新手教程', fn = function()
            openModal('重新走新手教程？', { '会从新手教程的第 1 层开始，当前这一局的进度会清掉。' }, {
                { label = '算了', primary = true, fn = reopen },
                { label = '重新走', danger = true, fn = function() meta.tutorialDone = false; saveMeta(); startNewGame() end },
            })
        end },
        { label = '返回', primary = true, fn = back },
    }
    openModal('设置', { '老电视滤镜也可以在游戏里按 F2 开关。' }, buttons)
    modal.onEscape = back
end

function openPause()
    openModal('暂停', { '进度会自动保存。' }, {
        { label = '继续', primary = true, fn = closeModal },
        { label = '设置', fn = function() openSettings(openPause) end },
        { label = '回到开局界面', fn = backToTitle },
        { label = '退出游戏', danger = true, fn = function() if run and run.status == 'playing' then saveGame() end; love.event.quit() end },
    })
    modal.onEscape = closeModal
end

-- 开局界面的菜单
function titleItems()
    local items = {}
    if hasSave() then items[#items + 1] = { label = '继续游戏', fn = continueGame } end
    items[#items + 1] = { label = hasSave() and '重新开始' or '开始游戏', fn = function()
        if not hasSave() then startNewGame(); return end
        openModal('重新开始？', { '当前这一局的进度会清掉，从第 1 层重新往下走。' }, {
            { label = '算了', primary = true, fn = closeModal },
            { label = '重新开始', danger = true, fn = startNewGame },
        })
        modal.onEscape = closeModal
    end }
    items[#items + 1] = { label = '设置', fn = function() openSettings(closeModal) end }
    items[#items + 1] = { label = '退出游戏', fn = function() love.event.quit() end }
    return items
end

local TITLE_X, TITLE_Y0, TITLE_DY = 58, 168, 26
function titleItemAt(lx, ly)
    for k = 1, #titleItems() do
        local y = TITLE_Y0 + (k - 1) * TITLE_DY
        if lx >= TITLE_X - 8 and lx <= TITLE_X + 130 and ly >= y - 4 and ly <= y + 18 then return k end
    end
end

function drawTitleUI()
    text('坠井者', TITLE_X - 4, 62, 40, { 0.95, 0.86, 0.62 })
    text('D E S C E N T', TITLE_X, 116, 8, { 0.55, 0.62, 0.64 })
    local items = titleItems()
    titleSel = math.max(1, math.min(#items, titleSel))
    for k, it in ipairs(items) do
        local y = TITLE_Y0 + (k - 1) * TITLE_DY
        local on = k == titleSel and not modal
        if on then
            rect({ 0.85, 0.64, 0.25 }, TITLE_X - 8, y - 2, 3, 18, 1, 1)
            rect({ 0.85, 0.64, 0.25 }, TITLE_X - 4, y - 3, 130, 20, 0.12, 3)
        end
        text(it.label, TITLE_X + 4, y, 12, on and { 1, 0.86, 0.5 } or { 0.72, 0.76, 0.76 })
    end
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
    if scene == 'title' then
        local k = titleItemAt(lx, ly)
        if k then titleSel = k; titleItems()[k].fn() end
        return
    end
    if run.arm and run.status == 'playing' and not walking then
        if inRect(lx, ly, armView.leverRect()) then spinArm('gold'); return end
        local b = armView.BLOOD
        if inRect(lx, ly, b.x, b.y, b.w, b.h) then spinArm('blood'); return end
        for r = 1, armMod.REELS do
            local x, y, w, h = armView.reelRect(r)
            if inRect(lx, ly, x, y, w, h) then
                armDrag = { reel = r, y0 = ly, off = 0 }
                -- 拨过一次就不再显示"按住轮子上下拨动"
                if not meta.dragged then meta.dragged = true; saveMeta() end
                return
            end
            if inRect(lx, ly, armView.lockRect(r)) then toggleHold(r); return end
        end
    end
    local i = tileAt(lx, ly)
    if i then act(i) end
end

function love.mousemoved(mx, my)
    if armDrag then
        local ly = (my - OY) / S
        armDrag.off = math.floor((ly - armDrag.y0) / armView.CELL_H + 0.5)
    end
end

-- 松手：转轮弹回转到的那一格
function love.mousereleased() armDrag = nil end

local DIRS = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 }, w = { 0, -1 }, s = { 0, 1 }, a = { -1, 0 }, d = { 1, 0 } }

-- 长按方向键连续走：按下先走一格，按住 HOLD_DELAY 秒后每走完一格接着走下一格。
-- 只穿过空地和道具；前面是怪物、门、出口或设施时停下，要再按一次才会打 / 开 / 走上去，免得一路冲进战斗。
local HOLD_DELAY = 0.2
local hold = nil            -- { key, d, t }
local fakeDown = {}         -- 自动测试用：假装按住的键
local function keyDown(k) return fakeDown[k] or love.keyboard.isDown(k) end

local function dirTarget(d)
    local x = (run.pos - 1) % run.w + d[1]
    local y = math.floor((run.pos - 1) / run.w) + d[2]
    if x < 0 or y < 0 or x >= run.w or y >= run.h then return nil end
    return y * run.w + x + 1
end

function updateHold(dt)
    if not hold then return end
    if not keyDown(hold.key) or modal or run.status ~= 'playing' then hold = nil; return end
    hold.t = hold.t + dt
    if hold.t < HOLD_DELAY or walking or heroAnim or armView.busy() then return end
    local t = dirTarget(hold.d)
    local c = t and run.cells[t]
    if not c or c.kind == 'wall' then return end
    if c.kind == 'floor' or c.kind == 'item' then act(t) else hold = nil end
end

function love.keyreleased(key)
    if hold and hold.key == key then hold = nil end
end

function love.keypressed(key)
    if key == 'f2' then
        meta.crt = not meta.crt
        love.filesystem.write(META_FILE, serialize.dump(meta))
        if modal and modal.title == '设置' then modal.buttons[1].fn() end
        return
    end
    -- Esc：弹窗里是"返回 / 关掉"，游戏中打开暂停
    if key == 'escape' then
        if modal then
            if modal.onEscape then modal.onEscape() end
        elseif scene == 'game' then
            hold = nil
            openPause()
        end
        return
    end
    if scene == 'title' and not modal then
        local items = titleItems()
        if key == 'up' or key == 'w' then titleSel = (titleSel - 2) % #items + 1
        elseif key == 'down' or key == 's' then titleSel = (titleSel % #items) + 1
        elseif key == 'return' or key == 'space' then items[titleSel].fn() end
        return
    end
    -- F9：重新走一遍新手教程（试玩用；已经打过教程的存档默认不会再进教程）
    if key == 'f9' then
        meta.tutorialDone = false
        saveMeta()
        love.filesystem.remove(SAVE_FILE)
        closeModal()
        walking, hold = nil, nil
        toGame()
        newGame()
        return
    end
    if modal then
        if key == 'return' or key == 'space' then
            for _, b in ipairs(modal.buttons) do if b.primary then b.fn(); return end end
        end
        local n = tonumber(key)
        if n and modal.buttons[n] then modal.buttons[n].fn() end
        return
    end
    if key == 'r' and run.arm and run.status == 'playing' and not walking then spinArm('gold'); return end
    local d = DIRS[key]
    if d and run.status == 'playing' then
        hold = { key = key, d = d, t = 0 }
        if not walking then
            local t = dirTarget(d)
            if t and run.cells[t].kind ~= 'wall' then act(t) end
        end
    end
end

-- 给自动测试用的入口
return {
    getRun = function() return run end,
    getModal = function() return modal end,
    busy = function() return walking ~= nil or armView.busy() end,
    act = act,
    newGame = function(seed, tutorial)
        closeModal()
        scene = 'game'
        meta.tutorialDone = not tutorial
        newGame(seed)
    end,
    spinArm = function(pay) spinArm(pay) end,
    continue = function() continueFlow() end,
    toggleHold = function(k) toggleHold(k) end,
    dragReel = function(r, off) armDrag = off and { reel = r, y0 = 0, off = off } or nil end,
    getMeta = function() return meta end,
    setHover = function(i) forcedHover = i; hovered = i end,
    exitTo = function(k) -- 第 k 个出口的格子（0 = '>'，1 = '<'）
        for i, c in ipairs(run.cells) do if c.kind == 'exit' and c.to == k then return i end end
    end,
    setCRT = function(on) meta.crt = on end,
    getScene = function() return scene end,
    openSettings = function() openSettings(closeModal) end,
    openPause = function() openPause() end,
    closeModal = function() closeModal() end,
    -- 自动测试：按下 / 松开一个键（down = true 按下，false 松开）
    pressKey = function(key, down)
        fakeDown[key] = down or nil
        if down then love.keypressed(key) else love.keyreleased(key) end
    end,
}
