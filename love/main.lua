-- 《坠井者》LÖVE 白盒：20 层主线（关卡数据由原型导出到 src/data/mainline.lua）。
-- 流程：楼梯口（情报、契约、井租）→ 出口结算 → 下一层；精英倒下三选一武器；井中轮、补给摊；第 20 层通关结算。
-- 画面分两层：像素层画在 640×360 的逻辑画布上，按整数倍放大（最近邻，不糊）；
-- 中文和数字画在单独的 UI 层，按屏幕分辨率直接绘制，保证清晰。

love.filesystem.setRequirePath('src/?.lua;src/?/init.lua;' .. love.filesystem.getRequirePath())

local config = require('core.config')
local combat = require('core.combat')
local Run = require('core.run')
local rules = require('core.rules')
local contractMod = require('core.contract')
local serialize = require('core.serialize')
local intelMod = require('core.intel')
local slotMod = require('core.slot')
local levels = require('core.levels')
local twinPath = require('view.twin_path')
local mainline = require('data.mainline')
local floorMod = require('core.floor')

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
local LAST_FILE = 'last-choices.lua' -- 上一局的选图（新开一局时尽量换图）
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
local choices              -- 本局每层的选图
local slotHeld = { false, false, false }

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
    love.filesystem.write(SAVE_FILE, serialize.dump({ run = run:save(), choices = choices }))
end

local function floorsFor(c) return levels.buildFloors(mainline.pools, c) end

local openStairs, openSummary, openDeath, openVictory, openWeapons, openSlot, openStall, newGame

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
    elseif run.pendingWeapons then openWeapons() end
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
    -- 走上楼梯之前：楼梯口（情报、契约、井租），可以"再想想"
    if c.kind == 'exit' and not walking.confirmedStairs and not run:eliteAlive() then
        walking = nil
        openStairs()
        return
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
    -- 井中轮、补给摊：走到旁边再打开
    if c.kind == 'slot' or c.kind == 'stall' then
        local function open() if c.kind == 'slot' then openSlot(i) else openStall(i) end end
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
local function intelLines()
    local nf = run.floors[run.floorIndex + 1]
    if not nf then return {} end
    if nf.intel then return { '【下一层情报】' .. nf.intel } end
    local it = intelMod.stairIntel(nf, run.hero, run.ch, { floor = run:floor(), cells = run.cells })
    if not it then return { '【下一层情报】井底很安静。' } end
    local out = { '【下一层情报】' .. it.headline }
    for _, l in ipairs(it.lines) do out[#out + 1] = '　' .. l end
    return out
end

-- 走上楼梯（已经在楼梯口确认过）
local function stepOntoExit()
    local exit
    for i, c in ipairs(run.cells) do if c.kind == 'exit' then exit = i end end
    local path = run:findPath(exit)
    if not path then setMsg('走不过去', true); return end
    startWalk(path)
    walking.confirmedStairs = true
end

function openStairs()
    local c = run:offeredContract()
    local lines = { '下楼之后就回不来了。下楼前，你听到井底传来的回声：' }
    for _, l in ipairs(intelLines()) do lines[#lines + 1] = l end
    local due = run:rentDue()
    if due > 0 then lines[#lines + 1] = '楼梯口坐着收租的井神：下楼前要交 ' .. due .. ' 金币（你有 ' .. run.hero.gold .. '）。' end
    local back = { label = '再想想', fn = function() closeModal(); setMsg('留在本层。想好了再走到楼梯口。') end }
    local function down(sign) closeModal(); pendingSign = sign; stepOntoExit() end
    local buttons = { back }
    if c then
        local t = contractMod.text(c)
        local dep = contractMod.depositFor(c, run.hero)
        lines[#lines + 1] = ''
        lines[#lines + 1] = '楼梯边垂下一枚铁钩，钩上挂着一纸契约：'
        lines[#lines + 1] = '押　' .. dep .. ' 生命（现在就扣，签后剩 ' .. (run.hero.hp - dep) .. '）'
        lines[#lines + 1] = '得　' .. t.get
        lines[#lines + 1] = '约　' .. t.cond
        lines[#lines + 1] = '还　' .. t.reward
        buttons[#buttons + 1] = { label = '不签，下楼', fn = function() down(false) end }
        if run.hero.hp > dep then
            buttons[#buttons + 1] = { label = '签约（押 ' .. dep .. ' 血）', primary = true, fn = function() down(true) end }
        end
    else
        buttons[#buttons + 1] = { label = '下楼', primary = true, fn = function() down(false) end }
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
    run:finishFloor(sell, pendingSign)
    pendingSign = false
    slotHeld = { false, false, false }
    floats, walking, heroAnim = {}, nil, nil
    saveGame()
    if run.status == 'finished' then openVictory()
    else setMsg(run:floor().hint or '') end
end

function openSummary()
    local s = run:exitSummary()
    local start = run:floorStartHero()
    local lines = {}
    if s.contract then
        lines[#lines + 1] = s.contract.kept and ('契约守住了：+' .. s.contract.def.refund .. ' 生命，+' .. s.contract.def.gold .. ' 金币')
            or ('契约已毁：押下的 ' .. s.contract.def.deposit .. ' 生命归井')
    end
    local d = run.hero.hp - start.hp
    lines[#lines + 1] = '本层生命变化（不含退还）：' .. (d >= 0 and '+' or '') .. d
    local gains = {}
    for _, g in ipairs({ { '攻击', run.hero.atk - start.atk }, { '防御', run.hero.def - start.def }, { '金币', run.hero.gold - start.gold } }) do
        if g[2] ~= 0 then gains[#gains + 1] = g[1] .. ' ' .. (g[2] > 0 and '+' or '') .. g[2] end
    end
    lines[#lines + 1] = '本层换到：' .. (#gains > 0 and table.concat(gains, '，') or '没有')
    if s.leftoverPotions > 0 then lines[#lines + 1] = '地图上剩下的血瓶 ×' .. s.leftoverPotions .. '：+' .. s.potionGold .. ' 金币' end
    local buttons = { { label = '下楼', primary = true, fn = function() nextFloor(false) end } }
    if s.keys > 0 then
        table.insert(buttons, 1, { label = '卖掉 ' .. s.keys .. ' 把骨钥（+' .. s.keyGold .. '）', fn = function() nextFloor(true) end })
    end
    openModal(run:floor().name .. ' 完成', lines, buttons)
end

function openWeapons()
    local list = run.pendingWeapons
    if not list then return end
    local lines = { '它倒下的地方压着三件东西，你只能拿走一件：' }
    for _, w in ipairs(list) do lines[#lines + 1] = config.WEAPONS[w].name .. '：' .. config.WEAPONS[w].desc end
    local cur = run.hero.weapon
    lines[#lines + 1] = cur and ('你现在拿着' .. config.WEAPONS[cur].name .. '，换掉会当场卖 ' .. config.WEAPONS[cur].sell .. ' 金币。') or '你还没有武器。'
    local buttons = {}
    for _, w in ipairs(list) do
        buttons[#buttons + 1] = { label = config.WEAPONS[w].name, fn = function() closeModal(); setMsg(run:chooseWeapon(w)); saveGame() end }
    end
    openModal('精英倒下了', lines, buttons)
end

local SYM = { blade = '刀', hammer = '锤', harpoon = '叉', potion = '瓶', coin = '金', leech = '蛭' }

function openSlot(i)
    local c = run.cells[i]
    local def = slotMod.SLOTS[c.id]
    local st = run:slotState(i)
    local lines = { def.desc }
    for k, reel in ipairs(def.reels) do
        local t = {}
        for _, x in ipairs(reel) do t[#t + 1] = SYM[x] end
        lines[#lines + 1] = '转轮 ' .. k .. '：' .. table.concat(t, ' ')
    end
    local odds = slotMod.machineOdds(def)
    lines[#lines + 1] = string.format('三连武器 %.1f%%，至少一只井蛭 %.1f%%（每只当场咬 15 血）', odds.weapon * 100, odds.anyLeech * 100)
    local anyHeld = st.pending ~= nil and (slotHeld[1] or slotHeld[2] or slotHeld[3])
    if st.pending then
        local t = {}
        for k, x in ipairs(st.pending) do t[#t + 1] = (slotHeld[k] and '[' .. SYM[x] .. ']' or SYM[x]) end
        lines[#lines + 1] = '机器上停着：' .. table.concat(t, ' ') .. '　→ ' .. table.concat(slotMod.payout(st.pending).lines, '；')
        if anyHeld then lines[#lines + 1] = slotMod.holdHint(def, st.pending, slotHeld) end
    end
    local price = run:slotPrice(i, anyHeld)
    lines[#lines + 1] = (anyHeld and '锁轴重转（放弃当前结果）' or (st.pending and '再转一次（先收下当前结果）' or '转一次')) .. '：' .. price.gold .. ' 金币，或血注 ' .. price.blood .. ' 生命'
    local function spin(pay)
        local held = anyHeld and { slotHeld[1], slotHeld[2], slotHeld[3] } or nil
        local r = run:slotSpin(i, pay, held)
        if not r.ok then setMsg(r.msg, true); return end
        slotHeld = { false, false, false }
        setMsg(r.msg ~= '' and r.msg or '转出来了。', (r.bite or 0) > 0)
        saveGame()
        if run.status == 'dead' then closeModal(); openDeath() else openSlot(i) end
    end
    local buttons = {
        { label = '金币 ' .. price.gold, primary = true, fn = function() spin('gold') end },
        { label = '血注 ' .. price.blood, danger = true, fn = function() spin('blood') end },
    }
    if st.pending then
        for k = 1, 3 do
            buttons[#buttons + 1] = { label = (slotHeld[k] and '解锁 ' or '锁 ') .. k, fn = function() slotHeld[k] = not slotHeld[k]; openSlot(i) end }
        end
        buttons[#buttons + 1] = { label = '收下', fn = function()
            local got = run:slotCollect(i)
            slotHeld = { false, false, false }
            closeModal(); setMsg(table.concat(got, '；')); saveGame()
            if run.pendingWeapons then openWeapons() end
        end }
    else
        buttons[#buttons + 1] = { label = '离开', fn = function() closeModal() end }
    end
    openModal('井中轮·' .. def.name, lines, buttons)
end

function openStall(i)
    local offers = run:floor().stall or {}
    local lines = { '摊主不说话，只指了指木板上的价签。每样只卖一次。', '你有 ' .. run.hero.gold .. ' 金币。' }
    local buttons = {}
    for k, o in ipairs(offers) do
        local sold = run:stallSold(k)
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

function openVictory()
    love.filesystem.remove(SAVE_FILE)
    local h = run.hero
    openModal('你走到了井底', {
        '二十层，一层不落。',
        '剩余生命 ' .. h.hp .. '，攻 ' .. h.atk .. ' / 防 ' .. h.def .. '，金币 ' .. h.gold .. (h.weapon and ('，武器 ' .. config.WEAPONS[h.weapon].name) or '') .. '。',
        '总步数 ' .. run.totalSteps .. '。',
        '（第 15 层落石和第 20 层 Boss 站位战还是占位，正式版会换掉。）',
    }, { { label = '再来一局', primary = true, fn = function() closeModal(); newGame() end } })
end

function openDeath()
    love.filesystem.remove(SAVE_FILE)
    openModal('你倒下了', { '你倒在了' .. run:floor().name .. '。', '这一局结束了。重新开始要从第 1 层走起，地图会换。' }, {
        { label = '从第 1 层重新开始', primary = true, fn = function() closeModal(); newGame() end },
    })
end

function newGame(seed)
    seed = seed or tonumber(os.getenv('DESCENT_SEED') or '') or os.time()
    local last = love.filesystem.getInfo(LAST_FILE) and serialize.load(love.filesystem.read(LAST_FILE))
    choices = levels.pickChoices(seed, mainline.pools, last and last.choices)
    love.filesystem.write(LAST_FILE, serialize.dump({ choices = choices }))
    run = Run.new(floorsFor(choices), 'digger', seed)
    floats, walking, heroAnim, pendingSign = {}, nil, nil, false
    slotHeld = { false, false, false }
    setMsg(run:floor().hint or '')
    saveGame()
end

-- ---------- LÖVE 回调 ----------
function love.load()
    love.graphics.setDefaultFilter('nearest', 'nearest')
    twinPath.load()
    canvas = love.graphics.newCanvas(LW, LH)
    relayout()
    local data = love.filesystem.getInfo(SAVE_FILE) and serialize.load(love.filesystem.read(SAVE_FILE))
    if data and data.run and data.choices then
        choices = data.choices
        run = Run.load(floorsFor(choices), data.run)
        setMsg('继续上一局。')
        if run.status == 'floorDone' then openSummary() elseif run.pendingWeapons then openWeapons() end
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
local function isTwinPath()
    return run.floorIndex == 2 and run:floor().layout == '双道'
end

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
    elseif c.kind == 'slot' or c.kind == 'stall' then base = C.door end
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
    local painted = isTwinPath()
    setColor(C.line)
    love.graphics.rectangle('line', MAP_X - 2.5, MAP_Y - 2.5, run.w * TILE + 5, run.h * TILE + 5 + (painted and 24 or 0))
    if not painted then
        for i = 1, #run.cells do drawTile(i) end
    end
    -- 悬停框
    if not painted and hovered and run.cells[hovered].kind ~= 'wall' and not modal then
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
    if not painted then
        setColor(run.status == 'dead' and { 0.4, 0.4, 0.4 } or C.hero)
        love.graphics.circle('fill', hx + 16, hy + 16, 11)
    end
    love.graphics.setCanvas()
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(canvas, OX, OY, 0, S, S)
    if painted then
        twinPath.drawScene(run, MAP_X, MAP_Y, hx, hy, not modal and hovered, S, OX, OY)
    end
end

-- ---------- 绘制：UI 层 ----------
local SHORT = { moss = '苔', eel = '鳗', frog = '蛙', beetle = '甲', bat = '蝠', wraith = '魂', crab = '蟹', guardian = '守', rat = '鼠', slug = '蝓', priest = '祭', gatekeeper = '门', eye = '眼' }

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
    if h.weapon then text('⚔ ' .. config.WEAPONS[h.weapon].name, 510, 22, 7, C.atk) end
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
            if not isTwinPath() or not twinPath.hasSprite(c.id) then
                text(SHORT[c.id], x, y + 3, 10, { 1, 0.84, 0.86 }, 'center', TILE)
            end
            text(p.fatal and (p.text == '会死' and ('-' .. p.lose) or p.text) or ('-' .. p.lose), x, y + 19, 6.5, p.fatal and C.warn or C.ok, 'center', TILE)
        elseif c.kind == 'door' then
            text(c.door == 'bone' and '门' or '血门', x, y + 5, 9, { 0.95, 0.84, 0.6 }, 'center', TILE)
            text(c.door == 'bone' and '骨钥' or ('-' .. run:floor().bloodCost), x, y + 20, 6, C.dim, 'center', TILE)
        elseif c.kind == 'item' and (c.id == 'key' or c.id == 'gold') then
            text(c.id == 'key' and '钥' or '金', x, y + 8, 11, C.gold, 'center', TILE)
        elseif c.kind == 'exit' then
            text('出口', x, y + 21, 6, C.accent, 'center', TILE)
        elseif c.kind == 'slot' then
            text('轮', x, y + 4, 11, C.gold, 'center', TILE)
            text(slotMod.SLOTS[c.id].name, x, y + 20, 6, C.dim, 'center', TILE)
        elseif c.kind == 'stall' then
            text('摊', x, y + 4, 11, C.accent, 'center', TILE)
            text('补给', x, y + 20, 6, C.dim, 'center', TILE)
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
        if isTwinPath() and twinPath.hasSprite(c.id) then
            twinPath.drawPortrait(c.id, OX + (px + PANEL_W / 2) * S, OY + (py + 206) * S, S)
        end
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
            text(run:eliteAlive() and '精英还活着，出口被封住了' or '走到这里结束本层', px, py + 18, 8, C.text)
        elseif c.kind == 'slot' then
            local d = slotMod.SLOTS[c.id]
            text('井中轮·' .. d.name, px, py, 11, C.text)
            text(d.desc, px, py + 18, 7.5, C.text, 'left', PANEL_W - 12)
            text('点它走到旁边，花金币或生命转一次', px, py + 44, 7, C.dim, 'left', PANEL_W - 12)
        elseif c.kind == 'stall' then
            text('补给摊', px, py, 11, C.text)
            local ty = py + 18
            for k, o in ipairs(run:floor().stall or {}) do
                text(Run.stallText(o) .. '：' .. o.price .. ' 金' .. (run:stallSold(k) and '（已买）' or ''), px, ty, 8, C.text)
                ty = ty + 13
            end
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
    newGame = function(seed) closeModal(); newGame(seed) end,
    setHover = function(i) hovered = i end,
}
