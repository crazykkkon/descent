-- 《坠井者》LÖVE 白盒：断臂转轮版（设计方案第五、六章）。
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
local decreeMod = require('core.decree')
local whisperMod = require('core.whisper')
local route = require('core.route')
local mapArt = {
    miner = require('view.miner'),
    monsters = require('view.monsters'),
    wellhead = require('view.wellhead'),
    gems = require('view.gems'),
}
local fx = require('view.fx')
local armView = require('view.arm_view')
local marks = require('view.weapon_marks')
local coach = require('view.coach')
local battle = require('view.battle')
local metaMod = require('core.meta')
local titleView = require('view.title')

-- ---------- 尺寸 ----------
local LW, LH = 640, 360          -- 逻辑画布
local TILE = 26                  -- 地图 16×11（制作人定），一格 26 逻辑像素
local K = TILE / 40              -- 按原来 40 像素一格画的图形，乘这个缩放
local MAP_X, MAP_Y = 34, 44      -- 地图在逻辑画布上的位置（地图占画面大半）
local PANEL_X, PANEL_W = 482, 154 -- 右侧：断臂转轮
local S, OX, OY = 2, 0, 0        -- 放大倍数和黑边偏移
local canvas, mapCanvas
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
local hovered = nil        -- 鼠标或键盘当前指向的格子
local keyboardMap, keyTarget = false, nil
local forcedHover = nil    -- 自动测试指定的悬停格子
local msg, msgErr, msgTime = '', false, 0
local modal = nil          -- { title, lines, buttons }
local afterSpinCell = nil   -- 停轮前点地图，停稳后走到最后点的目标
local walking = nil        -- { path, i, t, from, confirmedFatal, confirmedBreak }
local facing = 'down'
local heroAnim = nil       -- { from, to, t }
local floats = {}          -- 飘字 { text, x, y, t, color }
local meta = { tutorialDone = false, crt = true, volume = 1, fullscreen = false }
local scene = 'title'      -- 'title' 开局界面 / 'shop' 碎片商店 / 'game' 游戏中
local runOpts = { depth = 0, unlocks = {} }   -- 这一局的路线选项（深度模式、解锁了什么），存档里也存一份
local titleSel = 1         -- 开局界面选中的第几项
local facilityOpener

local function font(px)
    px = math.max(8, math.floor(px + 0.5))
    if not fonts[px] then fonts[px] = love.graphics.newFont(FONT_FILE, px) end
    return fonts[px]
end

local function setColor(c, a) love.graphics.setColor(c[1], c[2], c[3], a or 1) end

-- UI 层文字：坐标和字号都按逻辑像素给，内部换算成屏幕像素
local function text(str, x, y, size, color, align, width, alpha)
    love.graphics.setFont(font(size * S))
    setColor(color or C.text, alpha)
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
    love.filesystem.write(SAVE_FILE, serialize.dump({ run = run:save(), facing = facing, routeOpts = runOpts }))
end

local openReward
local openExit, openSummary, openDeath, openVictory, openEngrave, openDecree, openArm, openWheel, openPawn, openAltar, openStall, newGame, loadGame, continueFlow
local spinArm, toggleHold
local beginRun, openShop, drawShopUI, shopClick
local hasSave, applySettings, toGame, continueGame, startNewGame, backToTitle, openSettings, openPause, titleItems, titleItemAt, drawTitleUI

local function setMsg(s, err) msg, msgErr, msgTime = s or '', err or false, clock end

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
    afterSpinCell = nil
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
local W = function(id) return id == armMod.WILD and armMod.WILD_NAME or config.WEAPONS[id].name end

-- ---------- 刻图案的场景（制作人：刻图案时把断臂转轮移到画面中间，拨动轮子、直接点要刻的格子） ----------
-- picker = { sym, apply(r, k) -> 结果, after(结果), cancel(), onlyReel, t（0 在右边，1 在中间）, closing, hold, result, offs, flash }
local picker = nil
local PICK_K = 1.45                              -- 移到中间后放大多少
local ARM_CX, ARM_CY = armView.X + 72, armView.Y + 112   -- 手臂（逻辑坐标）的中心
local PICK_CX, PICK_CY = LW / 2, LH / 2 + 14     -- 移到画面的哪里
local PICK_OPEN, PICK_CLOSE, PICK_HOLD = 0.35, 0.3, 0.80

local function ease(t) return t * t * (3 - 2 * t) end
-- 手臂现在的变换：屏幕 = (手臂坐标 − 手臂中心) × k + 中心
local function armXf()
    if not picker then return 1, ARM_CX, ARM_CY end
    local e = ease(math.max(0, math.min(1, picker.t)))
    return 1 + (PICK_K - 1) * e, ARM_CX + (PICK_CX - ARM_CX) * e, ARM_CY + (PICK_CY - ARM_CY) * e
end
local function armToScreen(x, y)
    local k, cx, cy = armXf()
    return (x - ARM_CX) * k + cx, (y - ARM_CY) * k + cy, k
end
local function screenToArm(x, y)
    local k, cx, cy = armXf()
    return (x - cx) / k + ARM_CX, (y - cy) / k + ARM_CY
end

-- 打开刻图案的场景
local function openPicker(opts)
    battle.dismissBanner()
    picker = { sym = opts.sym, apply = opts.apply, after = opts.after, cancel = opts.cancel, onlyReel = opts.onlyReel,
        t = 0, closing = false, hold = 0, offs = { 0, 0, 0 } }
    fx.play('lever')
    setMsg('')
end
local function pickerBusy() return picker ~= nil and (picker.t < 1 or picker.closing) end

-- 摊开的转轮（制作人 2026-11-25：刻图案时转轮移到画面中间、摊开，所有格子一起看，直接点）。
-- 手臂移到中间以后，三个轮子从刻线那一行往上下摊开成一条 5 格的长条：中间 3 格就是平时露出来的那 3 格，
-- 上下各多出来的 1 格是平时藏在后面的。
-- （放在一张表里：main.lua 顶层的局部变量快到 Lua 的 200 个上限了）
local UNF = { cw = 70, ch = 30, gap = 18 }
function UNF.unfold()
    if not picker then return 0 end
    return ease(math.max(0, math.min(1, (picker.t - 0.4) / 0.6)))
end
-- 第 r 个轮子、离刻线 i 格（i = −2～2，0 是刻线那一格，正数往下）：位置（逻辑坐标）和它是第几格
function UNF.rect(r, i)
    local u = UNF.unfold()
    local total = 3 * UNF.cw + 2 * UNF.gap
    local x = LW / 2 - total / 2 + (r - 1) * (UNF.cw + UNF.gap)
    local off = math.abs(i) <= 1 and i or (i > 0 and 1 or -1) * (1 + u)
    local y = LH / 2 + 22 - UNF.ch / 2 + off * UNF.ch
    return x, y, UNF.cw, UNF.ch, ((run.arm.stops[r] - 1 + i) % armMod.SIZE) + 1
end
-- 屏幕上的这一点是哪个轮子的哪一格（摊开以后 5 格都能点）
local function pickerCellAt(lx, ly)
    if not picker or not run.arm or UNF.unfold() < 0.5 then return nil end
    for r = 1, armMod.REELS do
        for i = -2, 2 do
            local x, y, w, h, k = UNF.rect(r, i)
            if lx >= x and lx < x + w and ly >= y and ly < y + h then return r, k, i end
        end
    end
    return nil
end

-- 这个场景里还有没有能刻的空格（赎回只看原来那个轮子）
local function pickerHasBlank()
    if not picker or not run.arm then return false end
    for r = 1, armMod.REELS do
        if not picker.onlyReel or r == picker.onlyReel then
            if armMod.firstBlank(run.arm, r) then return true end
        end
    end
    return false
end

-- 刻到第 r 个轮子第 k 格。只能刻在空格上：有图案的格子不能覆盖，要先去当铺擦掉（制作人定）
local function pickerChoose(r, k)
    if not picker or pickerBusy() then return end
    if picker.onlyReel and r ~= picker.onlyReel then
        setMsg('只能刻回第 ' .. picker.onlyReel .. ' 个轮子。', true)
        fx.shake(1)
        return
    end
    local old = run.arm.reels[r][k]
    if old then
        setMsg('这一格已经有「' .. W(old) .. '」了，不能覆盖。要刻在这里，先去当铺把它擦掉。', true)
        fx.shake(1)
        return
    end
    picker.result = picker.apply(r, k)
    if picker.result.ok then
        picker.flash = { r = r, k = k, t = 0 }
        fx.play('win'); fx.shake(2)
        picker.hold = PICK_HOLD
    end
    picker.closing = true
end

local function pickerCancel()
    if not picker or pickerBusy() then return end
    picker.result = nil
    picker.closing = true
end

local function updatePicker(dt)
    if not picker then return end
    if picker.flash then picker.flash.t = picker.flash.t + dt end
    if not picker.closing then
        picker.t = math.min(1, picker.t + dt / PICK_OPEN)
        return
    end
    if picker.hold > 0 then picker.hold = picker.hold - dt; return end
    picker.t = picker.t - dt / PICK_CLOSE
    if picker.t <= 0 then
        local p = picker
        picker = nil
        if p.result then p.after(p.result) else p.cancel() end
    end
end

local PICK_CANCEL = { x = LW / 2 - 50, y = LH - 26, w = 100, h = 18 }

-- 新手教程第 5 层：走近井底之眼就进一段剧情，然后直接开打（制作人：不要弹"打了会死"，免得玩家不知道该不该打）
local bossScene = false
local function eyeCell()
    for i, c in ipairs(run.cells) do if c.kind == 'monster' and c.id == 'eye' then return i end end
end
local function tutorialBossNear()
    if not run.tutorial or bossScene or run.status ~= 'playing' then return false end
    local e = eyeCell()
    if not e then return false end
    local ex, ey = (e - 1) % run.w, math.floor((e - 1) / run.w)
    local hx, hy = (run.pos - 1) % run.w, math.floor((run.pos - 1) / run.w)
    return math.abs(ex - hx) + math.abs(ey - hy) <= 2
end
local function openBossScene()
    bossScene = true
    walking = nil
    openModal('井底', {
        '出口前那团黑影动了一下。',
        '一只比整口井还大的眼睛睁开了，直直地盯着你。',
        '没有路可以绕过去。',
    }, { { label = '迎上去', primary = true, fn = function()
        closeModal()
        local path = run:findPath(eyeCell())
        if path then startWalk(path); walking.bossFight = true end
    end } })
end

-- ---------- 击杀反馈（制作人：特别是击杀反馈；算出刚好能打死时要有"算准了"的满足感） ----------
-- fatalSeen：这一层里曾经"打不动 / 打不死 / 会死"的怪（格子）。后来把它打死了 = 算准了（先去拿宝石、绕路备战再回来）
-- （放在一张表里：main.lua 顶层的局部变量快到 Lua 的 200 个上限了）
local KF = { fatalSeen = {}, fatalKey = nil, combo = { n = 0, at = -99, floor = nil }, scanKey = nil }
-- 大转盘的场景（放在这张表里，顶层局部变量快到上限了）
KF.wheel = require('view.wheel_scene')
function KF.scan()
    local key = run.seed .. ':' .. run.floorIndex
    if KF.fatalKey ~= key then KF.fatalSeen, KF.fatalKey = {}, key end
    local sk = key .. ':' .. run.steps .. ':' .. run.hero.atk .. ':' .. run.hero.def .. ':' .. run.hero.hp .. ':' .. tostring(run.hero.weapon)
    if sk == KF.scanKey then return end
    KF.scanKey = sk
    for i, c in ipairs(run.cells) do
        if c.kind == 'monster' then
            local p = preview(i)
            if p and p.fatal then KF.fatalSeen[i] = true end
        end
    end
end

-- threat：这只怪能不能伤到你（它的攻击高过你的防御）；伤不到你的"无伤"不值得夸
function KF.onKill(cell, monId, before, fought, threat)
    local combo = KF.combo
    local x, y = tileXY(cell)
    battle.kill(monId, x + TILE / 2, y + TILE - 4, TILE)
    local loss = before.hp - run.hero.hp
    -- 连杀：4 秒之内接着打死下一只
    if combo.floor == run.floorIndex and clock - combo.at <= 4 then combo.n = combo.n + 1 else combo.n = 1 end
    combo.at, combo.floor = clock, run.floorIndex
    -- 只挑最值得夸的一句；连杀写在下面一行（没有别的可夸时，连杀自己当大字）
    local main, sub, color
    if KF.fatalSeen[cell] then
        main, sub, color = '算准了！', '刚才还打不过它', { 1, 0.85, 0.35 }
        fx.play('perfect'); fx.shake(4)
    elseif loss > 0 and run.hero.hp <= math.max(10, math.floor(before.hp / 10)) then
        main, sub, color = '千钧一发！', '只剩 ' .. run.hero.hp .. ' 血', { 1, 0.45, 0.45 }
        fx.play('perfect', 0.8)
    elseif loss <= 0 and fought and threat then
        main, color = '无伤！', { 0.55, 1, 0.7 }
        fx.play('combo', 1.2)
    end
    if combo.n >= 2 then
        local c = '连杀 ×' .. combo.n
        if main then sub = (sub and (sub .. '　·　') or '') .. c
        else main, color = c, combo.n >= 4 and { 1, 0.5, 0.3 } or { 1, 0.8, 0.45 } end
        fx.play('combo', 1 + 0.12 * math.min(combo.n, 8))
    end
    if main then battle.banner(main, sub, color) else fx.shake(2) end
end

local function walkStep()
    local cell = walking.path[walking.i]
    local c = run.cells[cell]
    -- 走上出口之前问一次（下一层是哪个候选、井租），可以"再想想"
    if c.kind == 'exit' and not walking.confirmedExit and not run:eliteAlive() then
        walking = nil
        openExit(cell)
        return
    end
    -- 打怪：每场都弹战斗窗口，一来一回演完再结算（制作人定：魔塔式，每场都弹）。
    -- 每一下的伤害由 combat.simulate 的记录给出（结果和结算一样）；打不过的仗也演，在矿工倒下的那一下停。
    if c.kind == 'monster' and walking.fought ~= cell and (meta.battleSpeed or 1) > 0 then
        local m = run:monsterAt(cell)
        local log = {}
        local r0 = combat.simulate(run.hero, m, log)
        local _, def = combat.effectiveStats(run.hero)
        local hurts = math.max(m.atk - def, 0) > 0 or m.traits.thorns
        if not r0.canAttack and hurts then
            -- 破不了防：你每下打出 0，它一下下把你耗死
            log = {}
            local cur, lost = def, 0
            local firstMon = m.traits.firstStrike and not (run.hero.weapon and config.WEAPONS[run.hero.weapon].noFirstStrike)
            local function monHit(tag)
                local h = math.max(m.atk - cur, 0)
                lost = lost + h
                log[#log + 1] = { who = 'mon', hit = h, mhp = m.hp, loss = h, tags = { tag } }
                if m.traits.corrode then cur = cur - config.CORRODE_DEF end
            end
            if firstMon then monHit('first') end
            while lost < run.hero.hp and #log < 100000 do
                local t = m.traits.thorns and config.THORNS_DAMAGE or 0
                lost = lost + t
                log[#log + 1] = { who = 'hero', hit = 0, mhp = m.hp, loss = t, tags = t > 0 and { 'thorns' } or {} }
                if lost >= run.hero.hp then break end
                monHit()
                if m.traits.double and lost < run.hero.hp then monHit('double') end
            end
        end
        if (r0.canAttack or hurts) and #log > 0 then
            -- 打不过：在矿工倒下的那一下停
            local lost = 0
            for k, e in ipairs(log) do
                lost = lost + e.loss
                if lost >= run.hero.hp then
                    for j = #log, k + 1, -1 do log[j] = nil end
                    local tags = {}
                    for _, t in ipairs(e.tags) do if t ~= 'kill' then tags[#tags + 1] = t end end
                    tags[#tags + 1] = 'dead'
                    e.tags = tags
                    break
                end
            end
            walking.waitBattle = true
            local tx, ty = tileXY(cell)
            local hx, hy = tileXY(run.pos)
            if tx ~= hx then facing = tx > hx and 'right' or 'left' else facing = ty > hy and 'down' or 'up' end
            local w = run.hero.weapon
            local atk = combat.effectiveStats(run.hero)
            local traits = {}
            for k in pairs(m.traits) do traits[#traits + 1] = config.TRAIT_NAMES[k] end
            battle.start({
                log = log, weapon = w, monHp = m.hp, monW = mapArt.monsters.size(c.id), heroHp = run.hero.hp, speed = meta.battleSpeed or 1,
                hero = { name = run.ch.name, line = '攻 ' .. atk .. ' · 防 ' .. def .. (w and (' · ' .. W(w)) or '') },
                mon = { id = c.id, name = m.name, line = '攻 ' .. m.atk .. ' · 防 ' .. m.def, traits = table.concat(traits, ' ') },
                onDone = function() if walking then walking.waitBattle = false; walking.fought = cell; walking.t = STEP_TIME end end,
            })
            return
        end
    end
    local before = config.copyHero(run.hero)
    local from = run.pos
    local monId = c.kind == 'monster' and c.id or nil
    local fought = walking.fought == cell
    local threat = monId and run:monsterAt(cell).atk > select(2, combat.effectiveStats(run.hero))
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
    if c.kind == 'monster' and not fought then fx.play('hit'); fx.shake(1.2)
    elseif c.kind == 'item' then fx.play('pick') end
    local lost = before.hp - run.hero.hp
    -- 打死了：怪碎掉，再看看这一仗值不值得夸
    if monId and run.cells[cell].kind == 'floor' then KF.onKill(cell, monId, before, fought, threat) end
    if monId and fought then
        -- 演过了，伤害数字已经弹过，不再飘一次
    elseif lost > 0 then float(cell, '-' .. lost, C.warn)
    elseif run.hero.hp > before.hp then float(cell, '+' .. (run.hero.hp - before.hp), { 0.5, 1, 0.7 })
    elseif run.hero.atk > before.atk then float(cell, '攻+' .. (run.hero.atk - before.atk), C.atk)
    elseif run.hero.def > before.def then float(cell, '防+' .. (run.hero.def - before.def), C.def) end
    walking.i = walking.i + 1
    walking.confirmedFatal = false
    walking.fought = nil
    if not walking.bossFight and tutorialBossNear() then
        saveGame()
        openBossScene()
        return
    end
    if walking.i > #walking.path or run.status ~= 'playing' then
        local cb = walking.onArrive
        walking = nil
        afterStop()
        if cb and run.status == 'playing' and not modal then cb() end
    end
end

local function act(i)
    if walking or modal or picker or KF.wheel.active() or run.status ~= 'playing' then return end
    if armView.busy() then
        afterSpinCell = i
        return
    end
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
local SHORTW = { boneKnife = '刀', harpoon = '叉', hammer = '锤', mossBlade = '苔', bellStaff = '铃', saltDagger = '盐', rustSword = '锈', wellHook = '钩', lamp = '灯', twinHook = '双钩', wild = '赖' }

local function weaponLine(id)
    if id == armMod.WILD then return '赖子是万能图案，可以配合任意一种武器。中线有空格或全是赖子时，转不出武器。' end
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
    if run.rewardOffer then openReward(); return end
    if run:pendingEngrave() then openEngrave(); return end
    if run.decreeOffer then openDecree(); return end
end

-- 打败精英后的三选一（制作人：让每场战斗都成为构筑的一部分）
function openReward()
    local o = run.rewardOffer
    if not o then return end
    local names = {}
    for k, w in ipairs(o.choices) do names[k] = W(w) end
    local function pick(kind)
        closeModal()
        local r = run:chooseReward(kind)
        if r.msg ~= '' then setMsg(r.msg); fx.play('pick') end
        saveGame()
        continueFlow()
    end
    openModal('精英的战利品', {
        '从以下三项中选一项。',
        '攻击提高 ' .. o.atk .. ' 点，持续到本局结束。',
        '刻一个图案：从 ' .. table.concat(names, '、') .. ' 里挑一个刻到断臂转轮上。',
        '花 ' .. o.cost .. ' 金币恢复 ' .. o.heal .. ' 点生命，花费为现有金币的一半。',
    }, {
        { label = '攻击 +' .. o.atk, fn = function() pick('atk') end },
        { label = '刻图案', primary = true, fn = function() pick('engrave') end },
        { label = '生命 +' .. o.heal .. '（−' .. o.cost .. ' 金）', fn = function() pick('heal') end },
    })
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
    battle.dismissBanner()
    -- 剧情二「第一道印子」（Codex 写，跨局只出一次）：正式局第一次打完架能刻图案时，先于刻图案窗口
    if not run.tutorial and not meta.storyMarkSeen and (p.from == 'mark' or p.from == 'elite') then
        meta.storyMarkSeen = true
        KF.saveMeta()
        openModal('第一道印子', {
            '矿灯照过怪物倒下的地方，一道印子还在发亮。你把断臂凑近，一格空白的铜面暖了起来。',
            '你挪开手，那道印子也跟着挪了半寸。',
            '「能带走的是这道印。想握住那把武器，还得靠这三只轮子。」',
        }, { { label = '看看图案', primary = true, fn = function() closeModal(); openEngrave() end } })
        return
    end
    local from = ({ elite = '守卫倒下后，地上留下几道武器的印记', mark = '怪物身上的印记亮了起来', decree = '井神兑现了诏令', wheel = '大转盘吐出一个图案' })[p.from]
    local lines = { from .. '。', '先选图案，再点空格刻下。拉杆后，只要三个相同的武器图案停在中间的刻线上，你就能拿到那把武器。' }
    for _, w in ipairs(p.choices) do lines[#lines + 1] = weaponLine(w) end
    local buttons = {}
    for _, w in ipairs(p.choices) do
        buttons[#buttons + 1] = { label = '刻' .. W(w), mark = w, primary = #p.choices == 1, fn = function()
            closeModal()
            openPicker({
                sym = w,
                apply = function(r, k) return run:engrave(w, r, k) end,
                after = function(res) setMsg(res.msg, not res.ok); saveGame(); continueFlow() end,
                cancel = function() openEngrave() end,
            })
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
        '期限到第 ' .. (run.floorIndex + decreeMod.SPAN - 1) .. ' 层结束。',
        '完成后获得一个武器图案，可刻入转轮' .. (d.tier == 'silver' and '，并恢复 ' .. decreeMod.SILVER_BONUS_HP .. ' 点生命' or '') .. '。',
        '逾期未完成，攻击 −' .. decreeMod.PENALTY[d.tier] .. '。拒绝诏令没有惩罚。',
    }, {
        { label = '不接', fn = function() closeModal(); run:refuseDecree(); saveGame(); continueFlow() end },
        { label = '接下', primary = true, fn = function() closeModal(); setMsg(run:acceptDecree().msg); saveGame(); continueFlow() end },
    })
end

-- 断臂转轮：直接在右侧操作（不弹窗）
local armHeld = { false, false, false }
local armDrag = nil   -- 拨动 { reel, y0, off, moved, picker }


local function pct(x) return math.floor(x * 1000 + 0.5) / 10 .. '%' end

-- 右侧转轮下面那行说明
local function armHint()
    local arm = run.arm
    if armMod.empty(arm) then return '转轮上还没有图案。击败带「印」的怪物可获得武器图案。' end
    local anyHeld = armHeld[1] or armHeld[2] or armHeld[3]
    local list = armMod.holdOdds(arm, anyHeld and armHeld or nil, run.pool)
    local parts = {}
    for _, o in ipairs(list) do parts[#parts + 1] = (o.target and W(o.target) or '空手') .. ' ' .. pct(o.p) end
    if #parts == 0 then return anyHeld and '这样锁轮无法凑齐图案。试试解锁。' or '目前的图案组合转不出武器。' end
    return (anyHeld and '锁轮后重转概率：' or '本次拉杆概率：') .. table.concat(parts, '，')
end

function spinArm(pay)
    if not run.arm or run.status ~= 'playing' or walking or modal or picker or KF.wheel.active() or armView.busy() then return end
    local anyHeld = armHeld[1] or armHeld[2] or armHeld[3]
    local held = { armHeld[1], armHeld[2], armHeld[3] }
    local before = config.copyHero(run.hero)
    before.stops = config.copyList(run.arm.stops)
    local r = run:armSpin(pay, anyHeld and held or nil)
    if not r.ok then setMsg(r.msg, true); return end
    local resultText = r.msg
    if run.hero.weapon and (r.faces[1] == armMod.WILD or r.faces[2] == armMod.WILD or r.faces[3] == armMod.WILD)
        and armMod.outcome(r.faces) == 'weapon' then
        resultText = '赖子补齐了图案，转出' .. W(run.hero.weapon)
    end
    armView.startSpin(held, r.faces, before, run.arm.stops, resultText)
    armHeld = { false, false, false }
    setMsg('')
    saveGame()
end

function toggleHold(k)
    if not run.arm or modal or armView.busy() then return end
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
    local lines = { exitWords(c), '下楼后无法返回本层。' }
    if twoExits() then lines[#lines + 1] = '两处楼梯通向不同的房间，只能选一条路。' end
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
        { label = '用 ' .. Run.RENT_STAT_COST .. ' 点攻击抵租', fn = function() pay('atk') end },
        { label = '用 ' .. Run.RENT_STAT_COST .. ' 点防御抵租', fn = function() pay('def') end },
    }
    if run.hero.gold >= due then buttons[#buttons + 1] = { label = '交 ' .. due .. ' 金币', primary = true, fn = function() pay('gold') end } end
    openModal('井租', {
        '收租的井神伸出手：要下楼，先交 ' .. due .. ' 金币的井租。',
        '你有 ' .. run.hero.gold .. ' 金币。' .. (run.hero.gold >= due and '' or '金币不足。'),
        '也可以抵扣井租。选择攻击或防御后，该属性本局减少 ' .. Run.RENT_STAT_COST .. ' 点。',
    }, buttons)
end

local function nextFloor(sell, note)
    if run:rentDue() > 0 then openRent(function() nextFloor(sell, note) end); return end
    closeModal()
    local spun = run.arm and run.arm.spins > 0
    run:finishFloor(sell)
    hovered, keyTarget = nil, nil
    armHeld = { false, false, false }
    floats, walking, heroAnim = {}, nil, nil
    saveGame()
    if run.status == 'finished' then openVictory(); return end
    -- 每层转轮价格重新算（上一层转过才提一句）
    local msg = spun and ('新的一层：断臂转轮的价格回到 ' .. run:armPrice().gold .. ' 金。') or ''
    if note then msg = note .. (msg ~= '' and '　' .. msg or '') end
    setMsg(msg)
    continueFlow()
end

-- 走出出口以后直接下楼（制作人 2026-11-25：每层的总结不要了）。
-- 地图上剩下的血瓶照样在出口折成金币（规则里算），只在底部提一句；骨钥要卖去当铺。
function openSummary()
    local s = run:exitSummary()
    nextFloor(false, s.leftoverPotions > 0 and ('地图上剩下的 ' .. s.leftoverPotions .. ' 瓶血瓶换了 ' .. s.potionGold .. ' 金币。') or nil)
end

-- 大转盘：真的转盘（制作人 2026-11-25：拉摇杆、真的会转）。画面和动画在 view/wheel_scene.lua，规则还是 run:wheelSpin
function openWheel(i)
    KF.wheel.open(i, {
        price = function() return run:wheelPrice(i) end,
        hero = function() return run.hero end,
        peek = function() return run:wheelPeek(i) end,
        apply = function(pay)
            local r = run:wheelSpin(i, pay)
            if r.ok then saveGame() end
            setMsg(r.msg, not r.ok or run.status == 'dead')
            return r
        end,
        after = function()
            if run.status == 'dead' then return function() openDeath() end end
            if run:pendingEngrave() then return function() continueFlow() end end
            return nil
        end,
    })
end

-- 当铺
function openPawn(i)
    local f = run:floor()
    local lines = { '在这里可以典当或赎回图案，也能卖骨钥。你有 ' .. run.hero.gold .. ' 金币、' .. run.hero.keys .. ' 把骨钥。' }
    for _, l in ipairs(armReelsText()) do lines[#lines + 1] = l end
    for j, p in ipairs(run.pawned) do lines[#lines + 1] = '待赎图案：' .. W(p.weapon) .. '（原来在轮子 ' .. p.reel .. '），赎回 ' .. run:redeemPrice(j) .. ' 金（每过一层涨 20%）' end
    for k, w in ipairs(f.shop or {}) do lines[#lines + 1] = '在售图案：' .. weaponLine(w) .. '　' .. run:shopPrice(w) .. ' 金' .. (run:sold(i, k) and '（已卖出）' or '') end
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
            if run.hero.gold < run:redeemPrice(j) then setMsg('金币不够', true); return end
            closeModal()
            openPicker({
                sym = p.weapon, onlyReel = p.reel,
                apply = function(_, k) return run:pawnRedeem(i, j, k) end,
                after = after,
                cancel = function() openPawn(i) end,
            })
        end }
    end
    for k, w in ipairs(f.shop or {}) do
        if not run:sold(i, k) then
            buttons[#buttons + 1] = { label = '买' .. W(w) .. ' −' .. run:shopPrice(w), fn = function()
                if run.hero.gold < run:shopPrice(w) then setMsg('金币不够', true); return end
                closeModal()
                openPicker({
                    sym = w,
                    apply = function(r, c) return run:pawnBuy(i, k, r, c) end,
                    after = after,
                    cancel = function() openPawn(i) end,
                })
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
    local lines = { '献 ' .. Run.ALTAR_ATK_COST .. ' 点攻击或 1 把骨钥，为转轮上的一种武器附加特性。可选特性来自你本局击败的怪物。' }
    local buttons = {}
    if not boon then
        if #run.boonsSeen == 0 then lines[#lines + 1] = '还没有可用的特性。击败溺魂、回声蝠、裂岩蟹或盐蚀蛞蝓后再来。' end
        for _, b in ipairs(run.boonsSeen) do
            lines[#lines + 1] = config.BOON_NAMES[b] .. '：' .. config.BOON_DESC[b]
            buttons[#buttons + 1] = { label = config.BOON_NAMES[b], fn = function() openAltar(i, b) end }
        end
    elseif not weapon then
        lines[#lines + 1] = '要让哪把武器获得「' .. config.BOON_NAMES[boon] .. '」？'
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
        buttons[#buttons + 1] = { label = '献 ' .. Run.ALTAR_ATK_COST .. ' 点攻击', fn = function() offer('atk') end }
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

local function saveMeta() love.filesystem.write(META_FILE, serialize.dump(meta)) end
KF.saveMeta = saveMeta   -- 给前面定义的函数用（openEngrave 在 saveMeta 之前）

-- 一局结束：按走到第几层折算灵魂碎片（越深越值钱），记进跨局存档
local function awardShards(won)
    local depth = run.tutorial and 0 or (runOpts.depth or 0)
    local n = metaMod.shardsFor(run.floorIndex, won, depth)
    meta.shards = (meta.shards or 0) + n
    meta.best = math.max(meta.best or 0, won and 20 or run.floorIndex)
    if won then
        meta.cleared = true
        meta.clearedDepth = math.max(meta.clearedDepth or -1, depth)
    end
    saveMeta()
    return n
end
local function shardLine(n) return '本次带回 ' .. n .. ' 块灵魂碎片。现有 ' .. meta.shards .. ' 块，可在主菜单的「碎片商店」使用。' end

function openVictory()
    love.filesystem.remove(SAVE_FILE)
    local h = run.hero
    local n = awardShards(true)
    openModal('你走到了井底', {
        '走过二十层，你终于来到了井底。本次试玩到此结束。',
        '剩余生命 ' .. h.hp .. '，攻 ' .. h.atk .. ' / 防 ' .. h.def .. '，金币 ' .. h.gold .. (h.weapon and ('，手上是' .. W(h.weapon)) or '') .. '。',
        shardLine(n),
    }, {
        { label = '返回主菜单', fn = function() backToTitle() end },
        { label = '再来一局', primary = true, fn = function() closeModal(); beginRun() end },
    })
end

function openDeath()
    love.filesystem.remove(SAVE_FILE)
    if run.tutorial and run.floorIndex < #run.plan then
        -- 教程还没走到井底就倒下了：教程不算走完，从教程第 1 层重来（制作人定）
        openModal('你倒下了', {
            '你倒在了' .. run:floor().name .. '。',
            '这次得从井口重新出发。',
            '开打之前，先用攻防算一算这一仗要掉多少血。',
        }, {
            { label = '返回主菜单', fn = function() backToTitle() end },
            { label = '重新走教程', primary = true, fn = function() closeModal(); beginRun() end },
        })
        return
    end
    if run.tutorial then
        meta.tutorialDone = true
        local n = awardShards(false)
        local after = {
            { label = '去碎片商店', fn = function() closeModal(); backToTitle(); openShop() end },
            { label = '再下井', primary = true, fn = function() closeModal(); beginRun() end },
        }
        local shardText = '你身上还沾着一点发光的东西——' .. n .. ' 块灵魂碎片。走完的楼层越多，能带回的碎片就越多。'
        if meta.storyArmSeen then
            -- 重走教程：剧情只演一次，这里只给结算
            openModal('……', { '你又在井口醒来。断口上的三只铜轮还在。', shardText }, after)
            return
        end
        meta.storyArmSeen = true
        saveMeta()
        -- 剧情一「袖子里的响声」（Codex 写，跨局只出一次）：两页，第二页带碎片结算和原来的两个按钮
        openModal('袖子里的响声', {
            '你在井口醒来。矿灯歪了。你抬右手去扶，碰到盔沿的却是一截冰凉的拉杆。',
            '右臂没了。断口上并排长着三只铜轮。',
            '「……井底下，谁给我装了台老虎机？」',
        }, { { label = '低头看一眼', primary = true, fn = function()
            closeModal()
            openModal('袖子里的响声', {
                '一道刻线横穿三只铜轮。你扣住一只轮子，再拉动摇杆。只有另外两只转了起来。',
                '铜壳上刻着三个一样的刀印。旁边是一只握刀的手。',
                '「懂了。三个刀印都停在这条线上，我手里就能多把刀。」',
                shardText,
            }, after)
        end } })
        return
    end
    local n = awardShards(false)
    openModal('你倒下了', { '你倒在了' .. run:floor().name .. '。', shardLine(n), '重新开始要从第 1 层走起，地图会换，转轮上的图案也会清空。' }, {
        { label = '返回主菜单', fn = function() backToTitle() end },
        { label = '从第 1 层重新开始', primary = true, fn = function() closeModal(); beginRun() end },
    })
end

local function planFor(seed, tutorial, ropts)
    return tutorial and route.tutorial(seed) or route.build(seed, ropts)
end

-- 已经解锁的东西（列表）和开着的强化（id → 等级）
local function unlockList()
    local out = {}
    for _, u in ipairs(metaMod.UNLOCKS) do if meta.unlocks and meta.unlocks[u.id] then out[#out + 1] = u.id end end
    return out
end
local function activePerks()
    local out = {}
    for _, p in ipairs(metaMod.PERKS) do
        local lv = meta.perks and meta.perks[p.id] or 0
        if lv > 0 and not (meta.perkOff and meta.perkOff[p.id]) then out[p.id] = lv end
    end
    return out
end

-- opts：{ character, depth }（新手教程不看这些）
function newGame(seed, opts)
    afterSpinCell = nil
    armView.reset()
    -- 自动测试默认用种子 6：第 4、5 层就有大转盘，四种设施都能走到
    seed = seed or tonumber(os.getenv('DESCENT_SEED') or '') or (os.getenv('DESCENT_AUTOTEST') and 6) or os.time()
    opts = opts or {}
    local tutorial = not meta.tutorialDone
    local character = tutorial and 'digger' or (opts.character or 'digger')
    runOpts = { depth = tutorial and 0 or (opts.depth or 0), unlocks = unlockList() }
    run = Run.new(planFor(seed, tutorial, runOpts), character, seed,
        { tutorial = tutorial, perks = activePerks(), pool = metaMod.weaponPool(runOpts.unlocks) })
    hovered, keyTarget, keyboardMap = nil, nil, false
    facing = 'down'
    floats, walking, heroAnim = {}, nil, nil
    bossScene = false
    armHeld = { false, false, false }
    saveGame()
    if tutorial then
        openModal('坠井', {
            '脚下一滑，你跌进了井里。矿灯还亮着。',
            '沿石道寻找通往下一层的楼梯。指向怪物或道具，可以在地图下方查看详情。',
        }, { { label = '往下走', primary = true, fn = function() closeModal(); setMsg('') end } })
    else
        setMsg('')
        continueFlow()
    end
end

function loadGame(data)
    afterSpinCell = nil
    armView.reset()
    hovered, keyTarget, keyboardMap = nil, nil, false
    facing = mapArt.miner.restoreFacing(data.facing)
    runOpts = data.routeOpts or { depth = 0, unlocks = {} }
    run = Run.load(planFor(data.run.seed, data.run.tutorial, runOpts), data.run)
    bossScene = false
    setMsg('继续上一局。')
    if run.status == 'floorDone' then openSummary() else continueFlow() end
end

-- ---------- LÖVE 回调 ----------
local function makeFrame()
    local w, h = love.graphics.getDimensions()
    frame = love.graphics.newCanvas(w, h)
    -- 地图格仍为 26 个逻辑像素。保留怪物贴图在默认 2 倍窗口中的像素细节。
    if not mapCanvas or mapCanvas:getDPIScale() ~= S then
        mapCanvas = S == 1 and canvas or love.graphics.newCanvas(LW, LH, { dpiscale = S })
    end
end

function love.load()
    love.graphics.setDefaultFilter('nearest', 'nearest')
    marks.load()
    mapArt.miner.load()
    battle.load()
    mapArt.wellhead.load()
    mapArt.gems.load()
    mapArt.monsters.load(config.MONSTERS)
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
    local result = armView.update(dt)
    if result then setMsg(result) end
    if afterSpinCell and not armView.busy() then
        local target = afterSpinCell
        afterSpinCell = nil
        act(target)
    end
    updatePicker(dt)
    KF.wheel.update(dt)
    battle.update(dt)
    if scene == 'game' and run and run.status == 'playing' and not battle.active() then KF.scan() end
    if walking and not modal and not walking.waitBattle then
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
    if forcedHover then hovered = forcedHover
    elseif keyboardMap then hovered = keyTarget
    else hovered = tileAt((mx - OX) / S, (my - OY) / S) end
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
    if c.kind == 'item' then
        if c.id == 'smallPotion' or c.id == 'bigPotion' then
            local s = (c.id == 'bigPotion' and 1.3 or 1) * K
            setColor({ 0, 0, 0 }, 0.3); g.ellipse('fill', cx, cy + 9 * s, 7 * s, 2)
            setColor({ 0.62, 0.7, 0.73 }); g.rectangle('fill', cx - 2 * s, cy - 10 * s, 4 * s, 3 * s)
            setColor(C.hp); g.rectangle('fill', cx - 6 * s, cy - 7 * s, 12 * s, 15 * s, 2, 2)
            setColor({ 1, 0.7, 0.75 }); g.rectangle('fill', cx - 4 * s, cy - 5 * s, 2, 6 * s)
        else
            mapArt.gems.draw(c.id, x, y, TILE)
        end
    end
end

-- 出口的样子：通向的那一层吵（扬尘往上飘）、安静（往下滴水）、说不准（雾慢慢散开）
local function drawExitFx(i, level)
    local g = love.graphics
    local x, y = tileXY(i)
    local cx = x + TILE / 2
    -- 近处的踏鼻最宽最亮，沿两侧石壁往井底收窄。
    local warm = run.tutorial and run.floorIndex == 1
    g.setColor(0.07, 0.14, 0.16)
    g.polygon('fill', x + 1, y + 2, x + TILE - 1, y + 2, x + TILE - 3, y + TILE - 2, x + 3, y + TILE - 2)
    g.setColor(0.19, 0.32, 0.32)
    g.polygon('fill', x + 2, y + 3, x + 8, y + 6, x + 5, y + TILE - 4, x + 3, y + TILE - 3)
    for step = 0, 3 do
        local width = 9 + 3 * step
        local depth = 0.54 + 0.15 * step
        g.setColor((warm and 0.98 or 0.49) * depth, (warm and 0.80 or 0.84) * depth, (warm and 0.48 or 0.76) * depth)
        g.rectangle('fill', cx - width / 2, y + 5 + step * 5, width, 2)
    end
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

local armCells = {}
local function drawPixel()
    local g = love.graphics
    g.setCanvas(mapCanvas)
    g.clear(C.bg[1], C.bg[2], C.bg[3])
    armCells = {}
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
    if run.tutorial and run.floorIndex == 1 then
        mapArt.wellhead.drawMap(MAP_X, MAP_Y, run.w * TILE, run.h * TILE)
        for i, c in ipairs(run.cells) do
            if c.kind ~= 'wall' then
                local x, y = tileXY(i)
                mapArt.wellhead.drawObject(c, x, y, TILE)
            end
        end
    else
        -- 地图：一行一行画（墙会盖住上一行的下沿，看起来是立着的）
        for i = 1, #run.cells do
            if run.cells[i].kind ~= 'wall' then drawTile(i) end
            if i % run.w == 0 then
                for k = i - run.w + 1, i do if run.cells[k].kind == 'wall' then drawTile(k) end end
            end
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
    local bdx, bdy, bflash = battle.heroOffset()
    hx, hy = hx + bdx, hy + bdy
    local heroFeet = hy + TILE - 4
    local function drawMiner()
        local kind, t, prize = armView.flashInfo()
        local glint = run.hero.weapon == prize and kind == 'win' and math.max(0, 1 - math.abs(t - 0.22) / 0.22) or 0
        mapArt.miner.drawOnMap(facing, hx + TILE / 2, heroFeet, run.status == 'dead', bflash, armView.displayHero(run.hero).weapon, glint)
    end
    -- 地面画完才画角色。按脚底从远到近绘制，移动经过相邻怪物时也遵循这个顺序。
    local minerDrawn = false
    for i, c in ipairs(run.cells) do
        if c.kind == 'monster' then
            local x, y = tileXY(i)
            local feet = y + TILE - 5
            if not minerDrawn and feet > heroFeet then
                drawMiner()
                minerDrawn = true
            end
            mapArt.monsters.draw(c.id, x + TILE / 2, feet, clock, i, battle.monster(i), 1.4)
        end
    end
    if not minerDrawn then drawMiner() end
    -- 矿灯：主角附近暖、远处冷暗（最暗也看得清格子）
    fx.lamp(MAP_X, MAP_Y - 4, run.w * TILE, run.h * TILE + 4, hx + TILE / 2, hy + TILE / 2 - 4, 170)
    -- 断臂转轮（机械小臂）。刻图案时整条手臂移到画面中间、放大，其余压暗
    if run.arm then
        local k, cx, cy = armXf()
        if picker then
            setColor({ 0.01, 0.02, 0.03 }, 0.72 * ease(math.max(0, math.min(1, picker.t)))); g.rectangle('fill', 0, 0, LW, LH)
        end
        g.push()
        g.translate(cx, cy); g.scale(k, k); g.translate(-ARM_CX, -ARM_CY)
        local held = picker and { false, false, false } or armView.displayHeld(armHeld)
        armView.draw(run.arm, held, armDrag and armDrag.reel, armDrag and armDrag.off or 0, function(x, y, w, h, sym, mid, alpha, top, bottom)
            armCells[#armCells + 1] = { x = x, y = y, w = w, h = h, sym = sym, mid = mid, alpha = alpha, top = top, bottom = bottom }
        end, picker and picker.offs, picker ~= nil)
        g.pop()
    end
    g.setCanvas()
end

-- ---------- 绘制：UI 层 ----------

local FACILITY_GLYPH = {
    stall = { '摊', '补给', '补给摊', '火边的补给摊，花金币买生命、攻击或防御。' },
    wheel = { '盘', '转盘', '大转盘', '转盘有八格。可能转到奖励，也可能被井蛭吸血，或失去一个图案。' },
    pawn = { '当', '当铺', '当铺', '卖骨钥、当掉或赎回武器图案、买图案、擦图案。不收攻防。' },
    altar = { '坛', '骨坛', '骨坛', '献 ' .. Run.ALTAR_ATK_COST .. ' 点攻击或 1 把骨钥，可将击败过的怪物特性赋予一种已刻的武器。' },
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

-- 和教学、事件反馈共用地图下方的空间。第一行回答这次行动的结果，第二行保留属性和特性。
local function cellDetails(i)
    local c = run.cells[i]
    if c.kind == 'monster' then
        local m = run:monsterAt(i)
        local p = preview(i)
        if run.tutorial and c.id == 'eye' then return m.name, '它在看着你。' end
        local base = config.powered(config.MONSTERS[c.id], run:floor().power)
        local stats = { '生命 ' .. m.hp .. '　攻 ' .. m.atk .. '　防 ' .. m.def }
        if m.atk ~= base.atk then stats[#stats + 1] = '群居：攻击 ' .. base.atk .. ' → ' .. m.atk end
        if m.def ~= base.def then stats[#stats + 1] = '被庇护：防御 ' .. base.def .. ' → ' .. m.def end
        for k in pairs(m.traits) do stats[#stats + 1] = config.TRAIT_NAMES[k] .. '：' .. config.TRAIT_DESC[k] end
        -- 不给预计掉血（制作人定：玩家自己算）；只给数值、特性、掉落
        local result = '掉落 ' .. m.gold .. ' 金币'
        if run:marked(i) then result = result .. '　　印：可刻入「' .. config.WEAPONS[config.MARK_WEAPON[c.id]].name .. '」图案' end
        return m.name, result, table.concat(stats, '　'), false
    elseif c.kind == 'item' then
        local f = run:floor()
        local gem = f.gem + run.ch.gemBonus
        local big = config.BIG_GEM + run.ch.gemBonus
        local effect = ({ smallPotion = '生命 +' .. f.smallPotion, bigPotion = '生命 +' .. f.bigPotion, redGem = '攻击 +' .. gem, blueGem = '防御 +' .. gem,
            bigRedGem = '攻击 +' .. big, bigBlueGem = '防御 +' .. big, key = '骨钥 +1', gold = '金币 +' .. f.gold })[c.id]
        return config.ITEM_NAMES[c.id], effect
    elseif c.kind == 'door' then
        if c.door == 'bone' then
            return '骨门', run.ch.boneDoorHp and ('撬开时扣 ' .. run.ch.boneDoorHp .. ' 生命') or '消耗 1 把骨钥打开'
        end
        return '血门', '通过时扣 ' .. run:floor().bloodCost .. ' 生命'
    elseif c.kind == 'exit' then
        if run:eliteAlive() then return '出口', '精英还活着，出口被封住了' end
        return twoExits() and EXIT_LOOK[exitLevel(c)] or '出口', exitWords(c), '走到楼梯口后，可以选择下楼或留在本层'
    elseif floorMod.isFacility(c) then
        local g = FACILITY_GLYPH[c.kind]
        return g[3], g[4]
    end
end

local function detailText(str, x, y, size, color, width)
    local f = font(size * S)
    love.graphics.setFont(f)
    setColor(color)
    love.graphics.print(str, OX + x * S, OY + y * S, 0, math.min(1, width * S / f:getWidth(str)), 1)
end

local function drawCellDetails(i)
    local name, result, extra, fatal = cellDetails(i)
    if not name then return false end
    local x, y, w = MAP_X, LH - 28, run.w * TILE
    rect(C.panel, x, y, w, 25, 1, 3)
    rect(fatal and C.warn or C.accent, x, y + 2, 1.5, 21)
    local row = extra and y + 1 or y + 6
    text(name, x + 6, row, 9, C.accent)
    local offset = 14 + font(9 * S):getWidth(name) / S
    detailText(result, x + offset, row + 1, 8, fatal and C.warn or C.text, w - offset - 5)
    if extra then detailText(extra, x + 6, y + 13, 7.5, C.dim, w - 12) end
    return true
end

local function drawPickerUI()
    local e = ease(math.max(0, math.min(1, picker.t)))
    local u = UNF.unfold()
    -- 顶栏也压暗，标题写在上面
    rect({ 0.01, 0.02, 0.03 }, 0, 0, LW, 46, 0.92 * e)
    local col = picker.sym == armMod.WILD and C.ok or { 1, 0.9, 0.6 }
    local title = picker.flash and ('已刻入「' .. W(picker.sym) .. '」') or ('把「' .. W(picker.sym) .. '」刻在哪一格？')
    local ty = 10 - (1 - e) * 20
    local tw = font(13 * S):getWidth(title) / S
    local tx = (LW - tw + 23) / 2
    setColor({ 1, 1, 1 })
    marks.icon(picker.sym, OX + (tx - 13) * S, OY + (ty + 9) * S, 23 * S)
    text(title, tx, ty, 13, col)
    if picker.flash then
        local hint = picker.sym == armMod.WILD and '中线上的赖子能替代武器图案。' or '图案已刻好。拉杆后，中线凑齐三个相同的武器图案即可装备。'
        text(hint, 0, 32 - (1 - e) * 20, 7.5, C.text, 'center', LW)
    elseif pickerHasBlank() then
        text(picker.onlyReel and ('请选择第 ' .. picker.onlyReel .. ' 轮的空格，赎回的图案只能刻回原轮。') or '每轮有五格。点空格刻入图案，已有图案的格子不能覆盖。',
            0, 32 - (1 - e) * 20, 7.5, C.dim, 'center', LW)
    else
        text((picker.onlyReel and ('第 ' .. picker.onlyReel .. ' 个轮子') or '转轮') .. '已满。可以去当铺擦掉旧图案，腾出空格。', 0, 32 - (1 - e) * 20, 8, C.warn, 'center', LW)
    end
    -- 让玩家在刻入的瞬间仍能核对手里实际拿着什么。
    local weapon = run.hero.weapon
    if weapon then
        setColor({ 1, 1, 1 })
        marks.icon(weapon, OX + 15 * S, OY + 21 * S, 17 * S)
    end
    text('手中 · ' .. (weapon and W(weapon) or '空手'), weapon and 26 or 12, 16, 7.5, C.text)
    if u > 0 then
        -- 铜底板：从手臂的轮子窗口里摊开来
        local x0 = UNF.rect(1, 0)
        local x3, _, w3 = UNF.rect(3, 0)
        local _, yTop = UNF.rect(1, -2)
        local _, yBot, _, hBot = UNF.rect(1, 2)
        rect({ 0.2, 0.13, 0.07 }, x0 - 16, yTop - 22, x3 + w3 - x0 + 32, yBot + hBot - yTop + 32, 0.97 * u, 8)
        rect({ 0.45, 0.32, 0.16 }, x0 - 14, yTop - 20, x3 + w3 - x0 + 28, 2, 0.9 * u)
        -- 刻线：中间那一行（转到这一行连成同一把武器才拿得到）
        local _, ym, _, hm = UNF.rect(1, 0)
        rect({ 0.94, 0.77, 0.42 }, x0 - 12, ym - 1.5, x3 + w3 - x0 + 24, hm + 3, 0.22 * u, 4)
        text('刻线', x0 - 42, ym + hm / 2 - 4, 7, { 0.94, 0.77, 0.42 }, 'center', 24, u)
        for r = 1, armMod.REELS do
            local cx = UNF.rect(r, 0)
            local only = not picker.onlyReel or r == picker.onlyReel
            text('第 ' .. r .. ' 轮', cx, yTop - 16, 7, only and { 0.96, 0.85, 0.6 } or C.dim, 'center', UNF.cw, u)
            for i = -2, 2 do
                local x, y, w, h, k = UNF.rect(r, i)
                local a = (math.abs(i) <= 1) and u or u * u
                local sym = run.arm.reels[r][k]
                local ok = only and not sym
                rect(sym and { 0.13, 0.11, 0.09 } or { 0.06, 0.07, 0.08 }, x + 1, y + 1, w - 2, h - 2, a, 3)
                if sym then
                    local c = sym == armMod.WILD and C.ok or (i == 0 and { 1, 0.96, 0.88 } or { 0.78, 0.76, 0.7 })
                    setColor(c, a)
                    marks.icon(sym, OX + (x + 13) * S, OY + (y + h / 2) * S, 20 * S)
                    text(W(sym), x + 22, y + 10, 7.5, c, 'left', w - 24, a)
                else
                    text('空', x, y + 9, 8, only and { 0.55, 0.6, 0.6 } or { 0.3, 0.32, 0.33 }, 'center', w, a)
                end
                if not ok then rect({ 0, 0, 0 }, x + 1, y + 1, w - 2, h - 2, 0.35 * a, 3) end
            end
        end
    end
    if not picker.closing then
        -- 鼠标所在的格子：能刻是金框，不能刻是红框
        local mx, my = love.mouse.getPosition()
        local r, k, i = pickerCellAt((mx - OX) / S, (my - OY) / S)
        if r then
            local x, y, w, h = UNF.rect(r, i)
            local ok = (not picker.onlyReel or r == picker.onlyReel) and not run.arm.reels[r][k]
            if ok then
                love.graphics.setColor(0.92, 0.77, 0.53, 0.40)
                marks.icon(picker.sym, OX + (x + 13) * S, OY + (y + h / 2) * S, 18 * S)
            end
            setColor(ok and { 1, 0.85, 0.4 } or C.warn)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle('line', OX + x * S, OY + y * S, w * S, h * S, 3 * S, 3 * S)
            love.graphics.setLineWidth(1)
        end
        if msgErr and msg ~= '' then text(msg, 0, PICK_CANCEL.y - 16, 7.5, C.warn, 'center', LW) end
        local b = PICK_CANCEL
        rect({ 0.11, 0.16, 0.19 }, b.x, b.y, b.w, b.h, 0.95, 4)
        text('返回（Esc）', b.x, b.y + 4, 7.5, C.text, 'center', b.w)
    end
    -- 刻上的那一格闪一下
    if picker.flash and picker.flash.t < 0.6 and u > 0 then
        local f = picker.flash
        for i = -2, 2 do
            local x, y, w, h, k = UNF.rect(f.r, i)
            if k == f.k then marks.cut(OX + x * S, OY + y * S, w * S, h * S, f.t) end
        end
    end
end

local function drawArmUI()
    if not run.arm then return end
    local g = love.graphics
    local tx, ty, k = armToScreen(armView.X + 10, armView.Y + 26)
    text('断臂转轮', tx, ty, 8 * k, { 0.96, 0.85, 0.6 })
    -- 轮窗中的图案按当前分辨率绘制。刻图案时跟着手臂一起移动、放大
    for _, t in ipairs(armCells) do
        local sx, sy = armToScreen(t.x, t.y)
        local _, top = armToScreen(t.x, t.top)
        local _, bottom = armToScreen(t.x, t.bottom)
        g.setScissor(OX + sx * S, OY + top * S, t.w * k * S, (bottom - top) * S)
        local cx, cy = OX + (sx + t.w * k / 2) * S, OY + (sy + t.h * k / 2) * S
        local unit = k * S
        if t.sym then
            local tone = t.mid and 1 or 0.80
            g.setColor(tone, tone, tone, t.alpha)
            marks.icon(t.sym, cx, cy, 24 * unit)
        else
            g.setColor(0.39, 0.43, 0.38, t.alpha)
            g.line(cx - 2 * unit, cy + unit, cx, cy - unit, cx + 2 * unit, cy + unit)
        end
        g.setScissor()
    end
    if picker then drawPickerUI(); return end
    local shownHeld = armView.displayHeld(armHeld)
    for r = 1, 3 do
        local lx, ly, lw = armView.lockRect(r)
        text(shownHeld[r] and '已锁' or '锁', lx, ly + 2, 6.5, shownHeld[r] and { 0.15, 0.1, 0.02 } or { 0.85, 0.75, 0.55 }, 'center', lw)
    end
    local price = run:armPrice(armHeld)
    local anyHeld = armHeld[1] or armHeld[2] or armHeld[3]
    text((anyHeld and '拉杆重转 ' or '拉杆 ') .. price.gold .. ' 金（R）', armView.X + 10, armView.Y + 160, 7.5, { 0.96, 0.85, 0.6 })
    local b = armView.BLOOD
    text('花 ' .. price.blood .. ' 生命', b.x, b.y + 4, 7, { 1, 0.85, 0.88 }, 'center', b.w)
    text(armHint(), PANEL_X + 2, armView.Y + 222, 6.5, C.dim, 'left', PANEL_W)
    if not meta.dragged then text('按住轮子上下拨动看整圈', PANEL_X + 2, armView.Y + 258, 6, { 0.42, 0.48, 0.5 }, 'left', PANEL_W) end
    local kind, t, prize = armView.flashInfo()
    if kind then
        local a = math.min(1, (1 - t) / 0.2)
        local label = kind == 'win' and ('转出 · ' .. W(prize)) or (kind == 'lose' and '三个空格 · 空手' or '未连成 · 武器保留')
        rect({ 0.12, 0.13, 0.11 }, armView.X + 10, armView.Y + 141, 109, 15, a, 2)
        text(label, armView.X + 10, armView.Y + 142, 8, kind == 'win' and C.ok or C.text, 'center', 109, a)
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
            if b.mark then
                local tw = font(8 * S):getWidth(b.label) / S
                local tx = r.x + (r.w - tw + 19) / 2
                setColor({ 1, 1, 1 })
                marks.icon(b.mark, OX + (tx - 11) * S, OY + (r.y + r.h / 2) * S, 18 * S)
                text(b.label, tx, r.y + 5, 8, C.text)
            else
                text(b.label, r.x, r.y + 5, 8, C.text, 'center', r.w)
            end
        end
    end
end

local function drawUI()
    do
        local h = run.hero
        local shown = armView.displayHero(h)
        local atk, def = combat.effectiveStats(shown)
        text(run:floor().name .. ((runOpts.depth or 0) > 0 and ('　深度 ' .. runOpts.depth) or ''), MAP_X, 7, 10, C.accent)
        stat('hp', '', battle.heroHp() or h.hp, 190, C.hp)
        stat('atk', '攻', atk, 250, C.atk)
        stat('def', '防', def, 300, C.def)
        stat('keys', '钥', h.keys, 350, { 0.85, 0.76, 0.48 })
        stat('gold', '金', h.gold, 396, C.gold)
        local wname = shown.weapon and W(shown.weapon) or (run.arm and '空手' or '')
        if shown.weapon then
            setColor({ 1, 1, 1 })
            marks.icon(shown.weapon, OX + 458 * S, OY + 14 * S, 17 * S)
        end
        text(wname, shown.weapon and 470 or 452, 8, 8.5, shown.weapon and C.atk or C.dim)
        if shown.boons then
            local names = {}
            for k, b in ipairs(shown.boons) do names[k] = config.BOON_NAMES[b] end
            text(table.concat(names, '·'), 452, 20, 6, C.accent)
        end
        if run.decree then
            text('诏令：' .. run.decree.def.text .. (run.decree.def.kind == 'killTrait' and ('（' .. run.decree.progress .. '/' .. run.decree.def.n .. '）') or '') .. '，第 ' .. run.decree['until'] .. ' 层前', MAP_X, 31, 6.5, C.ok)
        end
        -- 深度条的数字
        for d = 1, 20 do text(tostring(d), 8, MAP_Y + (d - 1) * 14 + 2, 5.5, d == run.floorIndex and { 0.1, 0.07, 0.02 } or { 0.45, 0.52, 0.55 }, 'center', 18) end
        -- 印记、门和设施等格子标记
        for i, c in ipairs(picker and {} or run.cells) do  -- 刻图案时地图上的字不画（地图被压暗了）
            local x, y = tileXY(i)
            if c.kind == 'monster' then
                -- 不挂"掉多少血"的牌子（制作人定）：指着它在地图下方看生命 / 攻 / 防，自己算
                if run:marked(i) then text('印', x + TILE - 7, y + 1, 5.5, C.ok) end
            elseif c.kind == 'door' then
                text(c.door == 'bone' and '门' or '血门', x, y + 3, 8, { 0.95, 0.84, 0.6 }, 'center', TILE)
                text(c.door == 'bone' and '骨钥' or ('−' .. run:floor().bloodCost), x - 4, y + 14, 5, C.dim, 'center', TILE + 8)
            elseif c.kind == 'item' and (c.id == 'key' or c.id == 'gold') then
                text(c.id == 'key' and '钥' or '金', x, y + 5, 10, C.gold, 'center', TILE)
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
        local tip, age = coach.current(run, clock)
        local recentError = msgErr and clock - msgTime < 1.5
        local details = hovered and not picker and not modal and not walking and not recentError and drawCellDetails(hovered)
        if not details and not picker and not modal and not walking and not recentError and not battle.active() and clock - msgTime > 1.2 and not (tip and age < 4) then
            -- 走到怪物旁边：下方也显示它的生命 / 攻 / 防（制作人：鼠标指着或者靠近了都显示）；面朝的那只优先
            local near
            local hx, hy = tileXY(run.pos)
            for _, n in ipairs(floorMod.neighbors(run.pos, run.w, run.h)) do
                if run.cells[n].kind == 'monster' then
                    local tx, ty = tileXY(n)
                    local dir = tx ~= hx and (tx > hx and 'right' or 'left') or (ty > hy and 'down' or 'up')
                    if not near or dir == facing then near = n end
                end
            end
            details = near and drawCellDetails(near)
        end
        if not details and tip and not recentError then
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
        elseif not details and msg ~= '' and not picker then
            text(msg, MAP_X, LH - 22, 7.5, msgErr and C.warn or C.text, 'left', PANEL_X - MAP_X - 8)
        end
    end

    if scene == 'game' then
        battle.drawUI({ text = text, rect = rect, font = font, S = S, OX = OX, OY = OY, LW = LW, LH = LH,
            monster = function(id, cx, feet, f) mapArt.monsters.draw(id, cx, feet, clock, 0, f) end,
            miner = function(cx, feet, dead, tall, a) mapArt.miner.draw('right', cx, feet, dead, tall, a) end })
        KF.wheel.draw({ text = text, rect = rect, S = S, OX = OX, OY = OY, LW = LW, LH = LH })
    end
    drawModal()
end

function love.draw()
    local sceneCanvas = mapCanvas
    if scene == 'title' or scene == 'shop' then
        sceneCanvas = canvas
        love.graphics.setCanvas(canvas)
        titleView.draw(LW, LH, clock)
        love.graphics.setCanvas()
    else
        drawPixel()
    end
    love.graphics.setCanvas(frame)
    love.graphics.clear(0, 0, 0)
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(sceneCanvas, OX, OY, 0, S, S)
    if scene == 'title' then drawTitleUI(); drawModal()
    elseif scene == 'shop' then drawShopUI(); drawModal()
    else drawUI() end
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
    closeModal()
    beginRun()
end

-- 开始一局：解锁了别的角色或深度模式时，先选角色、再选深度
function beginRun()
    love.filesystem.remove(SAVE_FILE)
    walking, heroAnim = nil, nil
    local function go(opts) closeModal(); toGame(); newGame(nil, opts) end
    if not meta.tutorialDone then go({}); return end
    local chars = { 'digger' }
    for _, id in ipairs({ 'scavenger', 'drowned' }) do if meta.unlocks and meta.unlocks[id] then chars[#chars + 1] = id end end
    local maxDepth = (meta.unlocks and meta.unlocks.depth) and math.min(metaMod.MAX_DEPTH, (meta.clearedDepth or -1) + 1) or 0
    local function chooseDepth(character)
        if maxDepth <= 0 then go({ character = character }); return end
        local lines = { '每通关一个深度，就能挑战下一级。',
            '从第 ' .. (route.DEPTH_FROM + 1) .. ' 层起，深度每提高一级，怪物就额外增强 ' .. metaMod.DEPTH_POWER .. ' 级。',
            '深度 1：结算时多得 25% 碎片。',
            '深度 2：多得 50% 碎片。从开局起，血瓶恢复量降至普通模式的 ' .. route.DEPTH_POTION .. '%。',
            '深度 3：多得 75% 碎片。血瓶恢复量仍为 ' .. route.DEPTH_POTION .. '%，井租和补给摊价格另涨约五成。' }
        local buttons = { { label = '普通', primary = true, fn = function() go({ character = character, depth = 0 }) end } }
        for d = 1, maxDepth do buttons[#buttons + 1] = { label = '深度 ' .. d, fn = function() go({ character = character, depth = d }) end } end
        openModal('选深度', lines, buttons)
        modal.onEscape = closeModal
    end
    if #chars == 1 then chooseDepth('digger'); return end
    local lines = {}
    for _, id in ipairs(chars) do
        local c = config.CHARACTERS[id]
        lines[#lines + 1] = c.name .. '：生命 ' .. c.base.hp .. '，攻 ' .. c.base.atk .. '，防 ' .. c.base.def .. '。' .. c.desc
    end
    local buttons = {}
    for _, id in ipairs(chars) do buttons[#buttons + 1] = { label = config.CHARACTERS[id].name, primary = id == 'digger', fn = function() closeModal(); chooseDepth(id) end } end
    openModal('选角色', lines, buttons)
    modal.onEscape = closeModal
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
        { label = '战斗动画：' .. (({ [0] = '跳过', [1] = '正常', [2.5] = '快' })[meta.battleSpeed or 1] or '正常'), fn = function()
            local v = meta.battleSpeed or 1
            meta.battleSpeed = v == 1 and 2.5 or (v == 2.5 and 0 or 1)
            saveMeta(); reopen()
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
        { label = '返回主菜单', fn = backToTitle },
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
    if meta.tutorialDone then items[#items + 1] = { label = '碎片商店', fn = function() openShop() end } end
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
    if meta.tutorialDone then
        text('灵魂碎片 ' .. (meta.shards or 0) .. (meta.best and meta.best > 0 and ('　·　最深到过第 ' .. meta.best .. ' 层') or ''), TITLE_X, LH - 30, 8, { 0.62, 0.82, 0.86 })
    end
end

-- ---------- 碎片商店（制作人：首页有一个碎片商店，买加攻、加血之类，不想要可以关掉，用掉的碎片不退；碎片也能解锁东西） ----------
local shopMsg, shopMsgErr = '', false
local SHOP = { lx = 24, rx = 330, w = 286, y0 = 70, rowH = 36 }
local SHOP_BACK = { x = LW / 2 - 44, y = LH - 22, w = 88, h = 16 }

function openShop()
    closeModal()
    scene = 'shop'
    shopMsg, shopMsgErr = '', false
end

local function spend(cost)
    if (meta.shards or 0) < cost then shopMsg, shopMsgErr = '碎片不够（要 ' .. cost .. '，你有 ' .. (meta.shards or 0) .. '）', true; return false end
    meta.shards = meta.shards - cost
    return true
end

-- 商店里所有能点的地方：{ x, y, w, h, label, fn, style }（画和点共用一份）
local function shopButtons()
    local out = {}
    meta.perks = meta.perks or {}
    meta.perkOff = meta.perkOff or {}
    meta.unlocks = meta.unlocks or {}
    for i, p in ipairs(metaMod.PERKS) do
        local y = SHOP.y0 + (i - 1) * SHOP.rowH
        local lv = meta.perks[p.id] or 0
        if lv < #p.costs then
            local cost = p.costs[lv + 1]
            out[#out + 1] = { x = SHOP.lx + SHOP.w - 70, y = y + 4, w = 66, h = 15, label = (lv == 0 and '买 ' or '升级 ') .. cost, style = 'buy', fn = function()
                if not spend(cost) then return end
                meta.perks[p.id] = lv + 1
                meta.perkOff[p.id] = nil
                shopMsg, shopMsgErr = p.name .. '：' .. p.desc(p.values[lv + 1]), false
                fx.play('pick'); saveMeta()
            end }
        end
        if lv > 0 then
            local off = meta.perkOff[p.id]
            out[#out + 1] = { x = SHOP.lx + SHOP.w - 70, y = y + 20, w = 66, h = 13, label = off and '已停用 · 启用' or '已启用 · 停用', style = off and 'off' or 'on', fn = function()
                meta.perkOff[p.id] = (not off) or nil
                shopMsg, shopMsgErr = p.name .. (off and '已启用，下局生效。' or '已停用。等级保留，可随时重新启用。'), false
                saveMeta()
            end }
        end
    end
    for i, u in ipairs(metaMod.UNLOCKS) do
        local y = SHOP.y0 + (i - 1) * SHOP.rowH
        if not meta.unlocks[u.id] then
            local locked = u.needsClear and not meta.cleared
            out[#out + 1] = { x = SHOP.rx + SHOP.w - 70, y = y + 4, w = 66, h = 15, label = locked and '通关后才能买' or ('解锁 ' .. u.cost), style = locked and 'locked' or 'buy', fn = function()
                if locked then shopMsg, shopMsgErr = '先通关一次（走到第 20 层并打败井底之眼）。', true; return end
                if not spend(u.cost) then return end
                meta.unlocks[u.id] = true
                shopMsg, shopMsgErr = '解锁了「' .. u.name .. '」。', false
                fx.play('win'); saveMeta()
            end }
        end
    end
    out[#out + 1] = { x = SHOP_BACK.x, y = SHOP_BACK.y, w = SHOP_BACK.w, h = SHOP_BACK.h, label = '返回（Esc）', style = 'back', fn = function() scene = 'title' end }
    return out
end

function shopClick(lx, ly)
    for _, b in ipairs(shopButtons()) do
        if lx >= b.x and lx <= b.x + b.w and ly >= b.y and ly <= b.y + b.h then b.fn(); return true end
    end
    return false
end

function drawShopUI()
    rect({ 0.02, 0.03, 0.04 }, 0, 0, LW, LH, 0.78)
    text('灵魂碎片商店', SHOP.lx, 12, 15, { 0.95, 0.86, 0.62 })
    text('碎片 ' .. (meta.shards or 0), LW - 160, 16, 11, { 0.62, 0.86, 0.92 }, 'right', 136)
    text('强化在开局时生效。停用保留等级，已花的碎片不退还。', SHOP.lx, 50, 7.5, C.dim)
    text('解锁 · 一次买断，永久有效', SHOP.rx, 50, 7.5, C.dim)
    for i, p in ipairs(metaMod.PERKS) do
        local y = SHOP.y0 + (i - 1) * SHOP.rowH
        local lv = (meta.perks or {})[p.id] or 0
        local off = (meta.perkOff or {})[p.id]
        rect({ 0.07, 0.10, 0.12 }, SHOP.lx, y, SHOP.w, SHOP.rowH - 3, 0.92, 4)
        text(p.name, SHOP.lx + 6, y + 3, 9.5, lv > 0 and not off and { 1, 0.88, 0.55 } or C.text)
        for k = 1, #p.costs do rect(k <= lv and (off and { 0.4, 0.4, 0.4 } or C.ok) or { 0.2, 0.24, 0.26 }, SHOP.lx + 62 + (k - 1) * 9, y + 7, 6, 6, 1, 1) end
        local now = lv > 0 and ('现在：' .. p.desc(p.values[lv]) .. (off and '（已停用）' or '')) or '未购买'
        local nxt = lv < #p.costs and ('　下一级：' .. p.desc(p.values[lv + 1])) or '　已满级'
        text(now .. nxt, SHOP.lx + 6, y + 19, 6.5, C.dim, 'left', SHOP.w - 84)
    end
    for i, u in ipairs(metaMod.UNLOCKS) do
        local y = SHOP.y0 + (i - 1) * SHOP.rowH
        local got = (meta.unlocks or {})[u.id]
        rect({ 0.07, 0.10, 0.12 }, SHOP.rx, y, SHOP.w, SHOP.rowH - 3, 0.92, 4)
        text(u.name, SHOP.rx + 6, y + 3, 9.5, got and { 1, 0.88, 0.55 } or C.text)
        if got then text('已解锁', SHOP.rx + SHOP.w - 70, y + 6, 8, C.ok, 'center', 66) end
        text(u.desc, SHOP.rx + 6, y + 16, 6, C.dim, 'left', SHOP.w - 80)
    end
    local mx, my = love.mouse.getPosition()
    local lx, ly = (mx - OX) / S, (my - OY) / S
    for _, b in ipairs(shopButtons()) do
        local hover = lx >= b.x and lx <= b.x + b.w and ly >= b.y and ly <= b.y + b.h and not modal
        local col = ({ buy = { 0.12, 0.35, 0.3 }, on = { 0.30, 0.24, 0.10 }, off = { 0.14, 0.16, 0.18 }, locked = { 0.12, 0.13, 0.15 }, back = { 0.11, 0.16, 0.19 } })[b.style]
        rect(col, b.x, b.y, b.w, b.h, hover and 1 or 0.85, 3)
        text(b.label, b.x, b.y + (b.h >= 15 and 3 or 2), b.h >= 15 and 7.5 or 6, b.style == 'locked' and C.dim or C.text, 'center', b.w)
    end
    if shopMsg ~= '' then text(shopMsg, SHOP.lx, LH - 38, 7.5, shopMsgErr and C.warn or C.ok, 'left', LW - 2 * SHOP.lx) end
end

-- ---------- 输入 ----------
function love.mousepressed(mx, my, button)
    keyboardMap, keyTarget = false, nil
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
    if scene == 'shop' then shopClick(lx, ly); return end
    if KF.wheel.active() then KF.wheel.click(lx, ly); return end
    if battle.active() then battle.skip(); return end
    -- 刻图案的场景：转轮摊开了，直接点要刻的格子
    if picker then
        if pickerBusy() then return end
        local b = PICK_CANCEL
        if inRect(lx, ly, b.x, b.y, b.w, b.h) then pickerCancel(); return end
        local r, k = pickerCellAt(lx, ly)
        if r then pickerChoose(r, k) end
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
    keyboardMap, keyTarget = false, nil
    if armDrag then
        local ly = (my - OY) / S
        if armDrag.picker then
            local _, ay = screenToArm((mx - OX) / S, ly)
            if math.abs(ay - armDrag.y0) > 3 then armDrag.moved = true end
            armDrag.off = math.floor((ay - armDrag.y0) / armView.CELL_H + 0.5)
        else
            armDrag.off = math.floor((ly - armDrag.y0) / armView.CELL_H + 0.5)
        end
    end
end

-- 松手：平时转轮弹回转到的那一格；刻图案时停在拨到的位置，没拨动就是点了这一格
function love.mousereleased(mx, my)
    local d = armDrag
    armDrag = nil
    if d and d.picker and picker then
        if d.moved then
            picker.offs[d.reel] = picker.offs[d.reel] + d.off
        else
            local r, k = pickerCellAt((mx - OX) / S, (my - OY) / S)
            if r then pickerChoose(r, k) end
        end
    end
end

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
    if c.kind == 'floor' or c.kind == 'item' then
        act(t)
    else
        keyboardMap, keyTarget = true, t
        hold = nil
    end
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
        elseif picker then
            pickerCancel()
        elseif KF.wheel.active() then
            KF.wheel.close()
        elseif scene == 'game' then
            hold = nil
            openPause()
        elseif scene == 'shop' then
            scene = 'title'
        end
        return
    end
    if scene == 'shop' then return end
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
    if picker then return end
    if KF.wheel.active() then KF.wheel.key(key); return end
    if battle.active() then battle.skip(); return end
    if key == 'r' and run.arm and run.status == 'playing' and not walking then
        keyboardMap, keyTarget = true, nil
        spinArm('gold')
        return
    end
    local d = DIRS[key]
    if d and run.status == 'playing' then
        keyboardMap, keyTarget = true, nil
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
    busy = function() return walking ~= nil or armView.busy() or pickerBusy() or battle.active() or KF.wheel.busy() end,
    wheelOpen = function() return KF.wheel.active() end,
    wheelSpin = function(pay) KF.wheel.spin(pay) end,
    wheelClose = function() KF.wheel.close() end,
    setBattleSpeed = function(v) meta.battleSpeed = v end,
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
    -- 自动测试：跨局存档清零（碎片、强化、解锁）
    battlePose = function(id, weapon, who, p)
        local m = config.MONSTERS[id]
        battle.pose({ weapon = weapon, monHp = m.hp, heroHp = 200, speed = 1, monW = mapArt.monsters.size(id),
            hero = { name = '掘井人', line = '攻 10 · 防 10' }, mon = { id = id, name = m.name, line = '攻 ' .. m.atk .. ' · 防 ' .. m.def, traits = '' } }, who, p)
    end,
    battleClear = function() battle.skip() end,
    resetMeta = function() meta = { tutorialDone = false, crt = meta.crt, volume = 1, fullscreen = false } end,
    openShop = function() openShop() end,
    shopBuy = function(label) for _, b in ipairs(shopButtons()) do if b.label:find(label, 1, true) == 1 then b.fn(); return b.label end end end,
    shopMsg = function() return shopMsg end,
    beginRun = function() beginRun() end,
    inPicker = function() return picker ~= nil end,
    -- 自动测试：第 r 个轮子第 row 格（0 上、1 刻线、2 下；−1、3 是摊开后多出来的上下两格）在屏幕上的位置（真实像素）
    pickerCellScreen = function(r, row)
        local x, y, w, h = UNF.rect(r, row - 1)
        return OX + (x + w / 2) * S, OY + (y + h / 2) * S
    end,
    pickerReady = function() return picker ~= nil and not pickerBusy() end,
    -- 自动测试：刻在第 r 个轮子的空格上；这个轮子刻满了就换一个有空格的；都满了就不刻
    pickCell = function(r)
        if not picker then return end
        r = picker.onlyReel or r
        for i = 0, 2 do
            local rr = picker.onlyReel or ((r - 1 + i) % 3 + 1)
            local k = armMod.blankFor(run.arm, rr)
            if k then pickerChoose(rr, k); return end
        end
        pickerCancel()
    end,
    openSettings = function() openSettings(closeModal) end,
    openPause = function() openPause() end,
    closeModal = function() closeModal() end,
    -- 自动测试：按下 / 松开一个键（down = true 按下，false 松开）
    pressKey = function(key, down)
        fakeDown[key] = down or nil
        if down then love.keypressed(key) else love.keyreleased(key) end
    end,
}
