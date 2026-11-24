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
local msg, msgErr = '', false
local modal = nil          -- { title, lines, buttons }
local walking = nil        -- { path, i, t, from, confirmedFatal, confirmedBreak }
local facing = 'down'
local heroAnim = nil       -- { from, to, t }
local floats = {}          -- 飘字 { text, x, y, t, color }
local meta = { tutorialDone = false }
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

local openStairs, openSummary, openDeath, openVictory, openEngrave, openDecree, openArm, openWheel, openPawn, openAltar, openStall, newGame, loadGame, continueFlow
local spinArm, toggleHold, ARM_SPIN, ARM_BLOOD, SPIN_TIME

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
    -- 走上楼梯之前：楼梯口（两条楼梯二选一、井租），可以"再想想"
    if c.kind == 'exit' and not walking.confirmedStairs and not run:eliteAlive() then
        walking = nil
        openStairs()
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
local armAnim = nil   -- 转动动画 { t }
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
    if not run.arm or run.status ~= 'playing' or walking or modal then return end
    local anyHeld = armHeld[1] or armHeld[2] or armHeld[3]
    local r = run:armSpin(pay, anyHeld and { armHeld[1], armHeld[2], armHeld[3] } or nil)
    if not r.ok then setMsg(r.msg, true); return end
    armAnim = { t = 0, held = { armHeld[1], armHeld[2], armHeld[3] } }
    armHeld = { false, false, false }
    setMsg(r.msg)
    saveGame()
end

function toggleHold(k)
    if not run.arm or modal then return end
    armHeld[k] = not armHeld[k]
end

function openArm() end

-- 走上楼梯（已经在楼梯口确认过）
local function stepOntoExit()
    local exit
    for i, c in ipairs(run.cells) do if c.kind == 'exit' then exit = i end end
    local path = run:findPath(exit)
    if not path then setMsg('走不过去', true); return end
    startWalk(path)
    walking.confirmedStairs = true
end

local pendingChoice = 1
function openStairs()
    local opts = run:nextOptions()
    local lines = { '下楼之后就回不来了。' }
    local due = run:rentDue()
    if due > 0 then lines[#lines + 1] = '楼梯口坐着收租的井神：下楼前要交 ' .. due .. ' 金币（你有 ' .. run.hero.gold .. '）。' end
    local back = { label = '再想想', fn = function() closeModal(); setMsg('留在本层。想好了再走到楼梯口。') end }
    local function down(k) closeModal(); pendingChoice = k; stepOntoExit() end
    local buttons = { back }
    if #opts == 2 then
        lines[#lines + 1] = '这里有两条往下的楼梯。'
        lines[#lines + 1] = '左边的楼梯：' .. whisperMod.whisper(opts[1])
        lines[#lines + 1] = '右边的楼梯：' .. whisperMod.whisper(opts[2])
        buttons[#buttons + 1] = { label = '走左边', fn = function() down(1) end }
        buttons[#buttons + 1] = { label = '走右边', fn = function() down(2) end }
    elseif #opts == 1 then
        lines[#lines + 1] = whisperMod.whisper(opts[1])
        buttons[#buttons + 1] = { label = '下楼', primary = true, fn = function() down(1) end }
    else
        lines[#lines + 1] = '这是最后一层的出口。'
        buttons[#buttons + 1] = { label = '出去', primary = true, fn = function() down(1) end }
    end
    openModal('楼梯口', lines, buttons)
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
    run:finishFloor(sell, pendingChoice)
    pendingChoice = 1
    armHeld = { false, false, false }
    floats, walking, heroAnim = {}, nil, nil
    saveGame()
    if run.status == 'finished' then openVictory(); return end
    setMsg(run:floor().hint or '')
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
    floats, walking, heroAnim, pendingChoice = {}, nil, nil, 1
    armHeld = { false, false, false }
    saveGame()
    if tutorial then
        openModal('坠井', {
            '你失足掉进了一口很深的井。',
            '怪物格子上的数字是打它要掉的血。奖励都在怪物身后，值不值得打，自己算。',
            '走过不能撤回。死了就从第 1 层重来。',
        }, { { label = '往下走', primary = true, fn = function() closeModal(); setMsg(run:floor().hint or '') end } })
    else
        setMsg(run:floor().hint or '')
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
function love.load()
    love.graphics.setDefaultFilter('nearest', 'nearest')
    miner.load()
    canvas = love.graphics.newCanvas(LW, LH)
    relayout()
    local m = love.filesystem.getInfo(META_FILE) and serialize.load(love.filesystem.read(META_FILE))
    if m then meta = m end
    local data = love.filesystem.getInfo(SAVE_FILE) and serialize.load(love.filesystem.read(SAVE_FILE))
    if data and data.run and data.run.picks then
        loadGame(data)
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
    if armAnim then
        armAnim.t = armAnim.t + dt
        if armAnim.t > SPIN_TIME + 0.4 then armAnim = nil end
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
    elseif c.kind == 'exit' then base = C.exit
    elseif floorMod.isFacility(c) then base = C.door end
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
    miner.draw(facing, hx + 16, hy + 29, run.status == 'dead')
    love.graphics.setCanvas()
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(canvas, OX, OY, 0, S, S)
end

-- ---------- 绘制：UI 层 ----------
local SHORT = { moss = '苔', eel = '鳗', frog = '蛙', beetle = '甲', bat = '蝠', wraith = '魂', crab = '蟹', guardian = '守', rat = '鼠', slug = '蝓', priest = '祭', gatekeeper = '门', eye = '眼' }

local FACILITY_GLYPH = {
    stall = { '摊', '补给', '补给摊', '火边的补给摊，花金币买生命、攻击或防御。' },
    wheel = { '盘', '转盘', '大转盘', '盘面八格全部公开：金币、生命、攻防、新图案，也有井蛭和擦掉图案。' },
    pawn = { '当', '当铺', '当铺', '卖骨钥、当掉或赎回武器图案、买图案、擦图案。不收攻防。' },
    altar = { '坛', '骨坛', '骨坛', '献 3 点攻击或 1 把骨钥，把杀过的怪的本事移到一把武器上。' },
}

-- 右侧的断臂转轮：3×3 格子，亮的是现在停的位置
-- 右侧的断臂转轮：三个轮子并排，每个露出上中下 3 格，中间一行是结果。按住一个轮子上下拨动可以看整圈，松手弹回。
local ARM = { x = PANEL_X + 6, y = 206, rw = 38, gap = 6, ch = 15 }
ARM_SPIN = { x = PANEL_X + 146, y = 206, w = 84, h = 18 }
ARM_BLOOD = { x = PANEL_X + 146, y = 228, w = 84, h = 18 }
local function reelRect(r) return ARM.x + (r - 1) * (ARM.rw + ARM.gap), ARM.y + 10 end
local function lockRect(r) local x, y = reelRect(r); return x, y + ARM.ch * 3 + 3, ARM.rw, 11 end
local function inRect(lx, ly, x, y, w, h) return lx >= x and lx <= x + w and ly >= y and ly <= y + h end
SPIN_TIME = 0.45

-- 动画里每个轮子还要多滚几格
local function animOffset(r)
    if not armAnim or (armAnim.held and armAnim.held[r]) then return 0 end
    local dur = SPIN_TIME + (r - 1) * 0.15
    local t = math.min(1, armAnim.t / dur)
    return math.floor((1 - t) * (1 - t) * (8 + r * 4) + 0.5)
end

function drawArmPanel()
    if not run.arm then return end
    text('断臂转轮', ARM.x, ARM.y - 4, 8, C.accent)
    local held = armHeld
    for r = 1, armMod.REELS do
        local x, y = reelRect(r)
        local off = animOffset(r) + ((armDrag and armDrag.reel == r) and armDrag.off or 0)
        local center = run.arm.stops[r] - off
        for row = -1, 1 do
            local k = (center + row - 1) % armMod.SIZE + 1
            local cy = y + (row + 1) * ARM.ch
            local mid = row == 0
            setColor(mid and (held[r] and { 0.32, 0.26, 0.10 } or { 0.20, 0.32, 0.28 }) or { 0.09, 0.12, 0.14 })
            love.graphics.rectangle('fill', OX + x * S, OY + cy * S, ARM.rw * S, (ARM.ch - 1) * S)
            local w = run.arm.reels[r][k]
            text(w and SHORTW[w] or '·', x, cy + 2, mid and 8 or 7, w == armMod.WILD and C.ok or (w and (mid and C.text or C.dim) or C.dim), 'center', ARM.rw)
        end
        local lx, ly, lw, lh = lockRect(r)
        setColor(held[r] and { 0.45, 0.35, 0.12 } or { 0.11, 0.16, 0.19 })
        love.graphics.rectangle('fill', OX + lx * S, OY + ly * S, lw * S, lh * S)
        text(held[r] and '已锁' or '锁', lx, ly + 2, 6, C.text, 'center', lw)
    end
    -- 中间一行的标线
    setColor(C.ok, 0.8)
    local x1, y1 = reelRect(1)
    love.graphics.rectangle('line', OX + (x1 - 2) * S, OY + (y1 + ARM.ch - 1) * S, (ARM.rw * 3 + ARM.gap * 2 + 4) * S, (ARM.ch + 1) * S)
    local anyHeld = held[1] or held[2] or held[3]
    local price = run:armPrice(anyHeld)
    setColor({ 0.12, 0.35, 0.3 })
    love.graphics.rectangle('fill', OX + ARM_SPIN.x * S, OY + ARM_SPIN.y * S, ARM_SPIN.w * S, ARM_SPIN.h * S)
    text((anyHeld and '重转 ' or '转动 ') .. price.gold .. ' 金（R）', ARM_SPIN.x, ARM_SPIN.y + 4, 7, C.text, 'center', ARM_SPIN.w)
    setColor({ 0.35, 0.12, 0.16 })
    love.graphics.rectangle('fill', OX + ARM_BLOOD.x * S, OY + ARM_BLOOD.y * S, ARM_BLOOD.w * S, ARM_BLOOD.h * S)
    text('用血转 ' .. price.blood, ARM_BLOOD.x, ARM_BLOOD.y + 4, 7, C.text, 'center', ARM_BLOOD.w)
    text('按住轮子上下拨动看整圈', ARM_SPIN.x, ARM_BLOOD.y + 22, 6, C.dim, 'left', ARM_SPIN.w)
    text(armHint(), ARM.x, ARM.y + 76, 6.5, C.dim, 'left', PANEL_W - 12)
end

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
    text(h.weapon and ('⚔ ' .. config.WEAPONS[h.weapon].name) or (run.arm and '空手' or ''), 510, 9, 7.5, h.weapon and C.atk or C.dim)
    if h.boons then
        local names = {}
        for k, b in ipairs(h.boons) do names[k] = config.BOON_NAMES[b] end
        text(table.concat(names, '·'), 510, 21, 6.5, C.accent)
    end
    if run.decree then
        text('诏令：' .. run.decree.def.text .. (run.decree.def.kind == 'killTrait' and ('（' .. run.decree.progress .. '/' .. run.decree.def.n .. '）') or '') .. '，第 ' .. run.decree['until'] .. ' 层前', 16, 26, 6.5, C.ok)
    end

    -- 格子上的字：怪物名和战损、门、钥匙、金币
    for i, c in ipairs(run.cells) do
        local x, y = tileXY(i)
        if c.kind == 'monster' then
            local p = preview(i)
            text(SHORT[c.id], x, y + 3, 10, { 1, 0.84, 0.86 }, 'center', TILE)
            if run:marked(i) then text('印', x + 22, y, 7, C.ok) end
            text(p.fatal and (p.text == '会死' and ('-' .. p.lose) or p.text) or ('-' .. p.lose), x, y + 19, 6.5, p.fatal and C.warn or C.ok, 'center', TILE)
        elseif c.kind == 'door' then
            text(c.door == 'bone' and '门' or '血门', x, y + 5, 9, { 0.95, 0.84, 0.6 }, 'center', TILE)
            text(c.door == 'bone' and '骨钥' or ('-' .. run:floor().bloodCost), x, y + 20, 6, C.dim, 'center', TILE)
        elseif c.kind == 'item' and (c.id == 'key' or c.id == 'gold') then
            text(c.id == 'key' and '钥' or '金', x, y + 8, 11, C.gold, 'center', TILE)
        elseif c.kind == 'exit' then
            text('出口', x, y + 21, 6, C.accent, 'center', TILE)
        elseif floorMod.isFacility(c) then
            local g = FACILITY_GLYPH[c.kind]
            text(g[1], x, y + 4, 11, C.gold, 'center', TILE)
            text(g[2], x, y + 20, 6, C.dim, 'center', TILE)
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
            local base = config.MONSTERS[c.id]
            if m.atk ~= base.atk then text('（群居：身边有同类，攻击从 ' .. base.atk .. ' 涨到 ' .. m.atk .. '）', px, ty, 7, C.warn, 'left', PANEL_W - 12); ty = ty + 12 end
            if m.def ~= base.def then text('（被骸骨祭司庇护，防御从 ' .. base.def .. ' 涨到 ' .. m.def .. '）', px, ty, 7, C.warn, 'left', PANEL_W - 12); ty = ty + 12 end
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
            if run:marked(i) then text('印记：打败后可以把' .. config.WEAPONS[config.MARK_WEAPON[c.id]].name .. '刻到转轮上', px, ty + 52, 7, C.ok, 'left', PANEL_W - 12) end
        elseif c.kind == 'item' then
            text(config.ITEM_NAMES[c.id], px, py, 11, C.text)
            local f = run:floor()
            local gem = f.gem + run.ch.gemBonus
            local eff = ({ smallPotion = '生命 +' .. f.smallPotion, bigPotion = '生命 +' .. f.bigPotion, redGem = '攻击 +' .. gem, blueGem = '防御 +' .. gem, key = '骨钥 +1', gold = '金币 +' .. f.gold })[c.id]
            text(eff, px, py + 18, 8, C.text)
        elseif c.kind == 'door' then
            text(c.door == 'bone' and '骨门' or '血门', px, py, 11, C.text)
            text(c.door == 'bone' and '消耗 1 把骨钥打开' or ('通过时扣 ' .. run:floor().bloodCost .. ' 生命'), px, py + 18, 8, C.text)
        elseif c.kind == 'exit' then
            text('出口', px, py, 11, C.text)
            text(run:eliteAlive() and '精英还活着，出口被封住了' or '走到这里结束本层', px, py + 18, 8, C.text)
        elseif floorMod.isFacility(c) then
            local g = FACILITY_GLYPH[c.kind]
            text(g[3], px, py, 11, C.text)
            text(g[4], px, py + 18, 7.5, C.text, 'left', PANEL_W - 12)
            text('点它走到旁边使用', px, py + 44, 7, C.dim, 'left', PANEL_W - 12)
        end
    else
        text(run:floor().name, px, py, 11, C.text)
        text('鼠标移到格子上看详情，点击行动；点空地直接走过去。方向键 / WASD 也能走。', px, py + 18, 7.5, C.dim, 'left', PANEL_W - 12)
    end
    drawArmPanel()
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
    if run.arm and run.status == 'playing' and not walking then
        if inRect(lx, ly, ARM_SPIN.x, ARM_SPIN.y, ARM_SPIN.w, ARM_SPIN.h) then spinArm('gold'); return end
        if inRect(lx, ly, ARM_BLOOD.x, ARM_BLOOD.y, ARM_BLOOD.w, ARM_BLOOD.h) then spinArm('blood'); return end
        for r = 1, armMod.REELS do
            local x, y = reelRect(r)
            if inRect(lx, ly, x, y, ARM.rw, ARM.ch * 3) then armDrag = { reel = r, y0 = ly, off = 0 }; return end
            if inRect(lx, ly, lockRect(r)) then toggleHold(r); return end
        end
    end
    local i = tileAt(lx, ly)
    if i then act(i) end
end

function love.mousemoved(mx, my)
    if armDrag then
        local ly = (my - OY) / S
        armDrag.off = math.floor((ly - armDrag.y0) / ARM.ch + 0.5)
    end
end

-- 松手：转轮弹回转到的那一格
function love.mousereleased() armDrag = nil end

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
    if key == 'r' and run.arm and run.status == 'playing' and not walking then spinArm('gold'); return end
    local d = DIRS[key]
    if d and not walking and run.status == 'playing' then
        local x = (run.pos - 1) % run.w + d[1]
        local y = math.floor((run.pos - 1) / run.w) + d[2]
        if x >= 0 and y >= 0 and x < run.w and y < run.h then
            local t = y * run.w + x + 1
            if run.cells[t].kind ~= 'wall' then act(t) end
        end
    end
end

-- 给自动测试用的入口
return {
    getRun = function() return run end,
    getModal = function() return modal end,
    busy = function() return walking ~= nil end,
    act = act,
    newGame = function(seed, tutorial)
        closeModal()
        meta.tutorialDone = not tutorial
        newGame(seed)
    end,
    spinArm = function(pay) spinArm(pay) end,
    continue = function() continueFlow() end,
    toggleHold = function(k) toggleHold(k) end,
    dragReel = function(r, off) armDrag = off and { reel = r, y0 = 0, off = off } or nil end,
    getMeta = function() return meta end,
    setHover = function(i) hovered = i end,
}
