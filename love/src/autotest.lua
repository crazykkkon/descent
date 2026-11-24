-- 自动测试：设置环境变量 DESCENT_AUTOTEST=1 启动时按界面操作并截图（截图存到存档目录）：
-- 1. 新手教程局：走到第 5 层被井底之眼打死，看到断臂剧情；
-- 2. 断臂转轮局：用很强的主角走完 20 层，沿途刻图案、转断臂转轮、接诏令、楼梯二选一，
--    尽量走进大转盘、当铺、骨坛、营火各一次，最后看到通关结算。
-- 只用于开发检查，正常游戏不会加载（打包时也不打进去）。

local M = {}

function M.start()
    local game = require('main')
    local floorMod = require('core.floor')
    local config = require('core.config')
    local co
    local wait = 0
    local log = {}
    local function say(s) log[#log + 1] = s; print('[autotest] ' .. s) end
    local function sleep(t) wait = t; coroutine.yield() end
    local function shot(name) love.graphics.captureScreenshot(name .. '.png'); sleep(0.3) end
    local function modalTitle() local m = game.getModal(); return m and m.title end
    local function button(prefix)
        local m = game.getModal()
        if not m then return false end
        for _, b in ipairs(m.buttons) do
            if b.label:sub(1, #prefix) == prefix then b.fn(); return true end
        end
        return false
    end
    -- 鼠标移到某个格子上（和 main.lua 的地图位置一致：每格 26，左上角 34, 44）
    local function hoverCell(i)
        local run = game.getRun()
        local x = (i - 1) % run.w
        local y = math.floor((i - 1) / run.w)
        local w, h = love.graphics.getDimensions()
        local S = math.max(1, math.min(math.floor(w / 640), math.floor(h / 360)))
        local OX, OY = math.floor((w - 640 * S) / 2), math.floor((h - 360 * S) / 2)
        love.mouse.setPosition(OX + (34 + x * 26 + 13) * S, OY + (44 + y * 26 + 10) * S)
    end
    local function find(pred)
        for i, c in ipairs(game.getRun().cells) do if pred(c, i) then return i end end
    end
    -- 穿过怪物、道具、门的最短路线（不穿墙和设施）
    local function route(target)
        local run = game.getRun()
        local prev = { [run.pos] = -1 }
        local q, head = { run.pos }, 1
        while head <= #q do
            local cur = q[head]; head = head + 1
            if cur == target then break end
            for _, n in ipairs(floorMod.neighbors(cur, run.w, run.h)) do
                local c = run.cells[n]
                if prev[n] == nil and c.kind ~= 'wall' and not floorMod.isFacility(c) and (c.kind ~= 'exit' or n == target) then
                    prev[n] = cur; q[#q + 1] = n
                end
            end
        end
        local path, p = {}, target
        while p and p ~= run.pos do table.insert(path, 1, p); p = prev[p] end
        return path
    end
    local function settle()
        for _ = 1, 200 do
            if not game.busy() then return end
            sleep(0.05)
        end
    end
    -- 处理路上弹出来的东西：刻图案（刻第一个，刻满了覆盖第 1 行）、诏令（接下）、消息
    local function handlePopups()
        for _ = 1, 10 do
            local t = modalTitle()
            if t == '刻图案' then
                local m = game.getModal()
                m.buttons[1].fn()
                -- 选轮子：轮流刻在 1、2、3 号轮子上；刻满了覆盖第 1 格
                engraveTurn = engraveTurn % 3 + 1
                button('刻在轮子 ' .. engraveTurn)
                if modalTitle() and modalTitle():find('^刻') then button('覆盖第 1 格') end
            elseif t and t:find('诏令') and game.getModal().buttons[2] and game.getModal().buttons[2].label == '接下' then button('接下')
            elseif t == '井神的诏令' then button('知道了')
            else return end
            sleep(0.05)
        end
    end
    -- 走上出口前的确认弹窗
    local function isExit(t) return t ~= nil and (t == '出口' or t:find('的出口$') ~= nil) end
    local function go(target)
        for _, cell in ipairs(route(target)) do
            local run = game.getRun()
            if run.status ~= 'playing' then return end
            game.act(cell)
            settle()
            handlePopups()
            local t = modalTitle()
            if isExit(t) or t == '你倒下了' or t == '……' then return end
        end
    end
    local function near(i)
        local run = game.getRun()
        for _, n in ipairs(floorMod.neighbors(i, run.w, run.h)) do
            local k = run.cells[n].kind
            if k ~= 'wall' and k ~= 'exit' and not floorMod.isFacility(run.cells[n]) then go(n); return end
        end
    end
    local function strong()
        local h = game.getRun().hero
        h.hp, h.atk, h.def, h.keys = math.max(h.hp, 99999), math.max(h.atk, 300), math.max(h.def, 300), 9
        h.gold = math.max(h.gold, 3000)
    end
    engraveTurn = 0
    local shots = {}
    local function once(name) if not shots[name] then shots[name] = true; shot(name) end end

    co = coroutine.create(function()
        love.filesystem.remove('save.lua')
        love.filesystem.remove('meta.lua')
        -- 0. 开局界面和设置
        sleep(0.5)
        say('开局界面：' .. tostring(game.getScene()))
        shot('00-title')
        game.openSettings(); sleep(0.2)
        say('设置：' .. tostring(modalTitle()))
        shot('00b-settings')
        game.closeModal()
        -- 1. 新手教程
        game.newGame(1, true)
        sleep(0.3)
        say('教程开场：' .. tostring(modalTitle()))
        shot('01-tutorial')
        button('往下走')
        for f = 1, 5 do
            local run = game.getRun()
            sleep(0.1)
            shot('01c-coach-' .. f)
            if f == 1 then
                -- 第 1 层：先往右走几步打第一只井苔，看教学提示换没换
                game.pressKey('right', true); sleep(1.2); game.pressKey('right', false); settle()
                local mon = find(function(c) return c.kind == 'monster' end)
                go(mon); settle(); sleep(0.2)
                shot('01d-coach-after-kill')
            end
            if f < 5 then
                strong()
                local h = run.hero
                h.atk, h.def = 25, 22 -- 不能太强，第 5 层要打不过
            end
            local boss = find(function(c) return c.kind == 'monster' and c.id == 'eye' end)
            if boss then
                go(boss)
                -- 走近井底之眼会进剧情，然后直接开打（不会弹"硬打会死"）
                say('第 5 层走近井底之眼：' .. tostring(modalTitle()))
                shot('01e-boss-scene')
                button('迎上去')
                settle(); sleep(0.4)
                say('第 5 层硬打井底之眼：' .. tostring(modalTitle()))
                break
            end
            local elite = find(function(c) return c.kind == 'monster' and config.MONSTERS[c.id].elite end)
            if elite then go(elite) end
            go(find(function(c) return c.kind == 'exit' end))
            if f == 1 then shot('01b-exit-confirm') end
            button('往下走'); settle(); sleep(0.1)
            button('下楼'); sleep(0.1)
        end
        shot('02-arm-story')
        say('断臂剧情：' .. tostring(modalTitle()) .. '，教程完成 ' .. tostring(game.getMeta().tutorialDone))
        button('再下井')
        sleep(0.3)

        -- 2. 断臂转轮局
        local visited = {}
        for f = 1, 20 do
            local run = game.getRun()
            strong()
            handlePopups()
            if f == 1 then
                -- 长按方向键：一直走到空地和道具走完为止，前面是怪物、门、出口时停下
                for _, dir in ipairs({ { 'right', 1, 0 }, { 'down', 0, 1 } }) do
                    local x0, y0 = (run.pos - 1) % run.w, math.floor((run.pos - 1) / run.w)
                    local n = 0
                    while true do
                        local x, y = x0 + dir[2] * (n + 1), y0 + dir[3] * (n + 1)
                        if x >= run.w or y >= run.h then break end
                        local k = run.cells[y * run.w + x + 1].kind
                        if k ~= 'floor' and k ~= 'item' then break end
                        n = n + 1
                    end
                    if n >= 2 then
                        local start = run.pos
                        game.pressKey(dir[1], true); sleep(0.4 + n * 0.2); game.pressKey(dir[1], false); settle()
                        local moved = math.abs((run.pos - start) / (dir[2] + dir[3] * run.w))
                        say(string.format('长按%s：应走 %d 格，走了 %d 格', dir[1], n, moved))
                        break
                    end
                end
                once('03-floor1')
                game.openPause(); sleep(0.1); say('暂停：' .. tostring(modalTitle())); once('03c-pause'); game.closeModal()
                local mon = find(function(c) return c.kind == 'monster' end)
                if mon then hoverCell(mon); sleep(0.3); once('03b-hover'); love.mouse.setPosition(1, 1) end
            end
            if f == 12 then once('10-deep-floor') end
            if f == 3 then
                -- 测试用：塞一个赖子进来，看界面
                run.engraveQueue[#run.engraveQueue + 1] = { from = 'wheel', choices = { 'wild' } }
                game.continue()
                sleep(0.1)
                once('06a-engrave-wild')
                handlePopups()
                say('刻赖子后：' .. tostring(run.arm.reels[engraveTurn][1]) .. ' / 手上 ' .. tostring(run.hero.weapon))
                sleep(0.2)
                once('06b-wild-reel')
            end
            -- 印记怪：先打它，拿第一把武器
            local mark = find(function(c, i) return run:marked(i) end)
            if mark then
                go(mark); sleep(0.2)
                once('04-engrave')
                handlePopups()
                say(string.format('第 %d 层印记怪：手上 %s', f, tostring(run.hero.weapon)))
            end
            -- 设施
            local fac = find(function(c) return floorMod.isFacility(c) end)
            if fac then
                local kind = run.cells[fac].kind
                near(fac)
                game.act(fac); settle(); sleep(0.2)
                say(string.format('第 %d 层设施 %s：%s', f, kind, tostring(modalTitle())))
                once('05-' .. kind)
                if kind == 'wheel' then button('金币'); sleep(0.1); handlePopups(); if modalTitle() == '大转盘' then button('离开') end
                elseif kind == 'pawn' then
                    if button('买') then button('刻在轮子 3'); if modalTitle() and modalTitle():find('^买') then button('覆盖第 1 格') end else button('卖骨钥') end
                    handlePopups(); if modalTitle() == '当铺' then button('离开') end
                elseif kind == 'altar' then
                    local m = game.getModal()
                    if m and #m.buttons > 1 then m.buttons[1].fn(); local m2 = game.getModal(); if m2 and #m2.buttons > 1 then m2.buttons[1].fn(); button('献 1 把骨钥') end end
                    if modalTitle() == '骨坛' then button('离开') end
                else button('攻击'); if modalTitle() == '补给摊' then button('离开') end end
                visited[kind] = true
                handlePopups()
            end
            -- 断臂转轮：有图案就转两次（第二次锁住第 1 个轮子）
            local armCells = 0
            for r = 1, 3 do for k = 1, 5 do if run.arm.reels[r][k] then armCells = armCells + 1 end end end
            if armCells > 0 then
                game.spinArm('gold'); sleep(0.62)
                if not shots['06c-spinning'] then once('06c-spinning') end
                sleep(0.3)
                game.toggleHold(1)
                game.dragReel(2, 2)
                if armCells >= 3 then once('06-arm') end
                game.dragReel(2, nil)
                game.spinArm('gold'); sleep(0.2)
                say(string.format('第 %d 层转了两次（锁住轮子 1）：手上 %s', f, tostring(run.hero.weapon)))
            end
            local elite = find(function(c) return c.kind == 'monster' and config.MONSTERS[c.id].elite end)
            if elite then
                go(elite); sleep(0.2)
                if modalTitle() == '刻图案' then once('07-elite-engrave') end
                handlePopups()
                say(string.format('第 %d 层精英倒下，手上 %s', f, tostring(run.hero.weapon)))
            end
            -- 两个出口：优先走通向还没去过的设施层的那个
            local opts = run:nextOptions()
            local pick = 0
            if #opts == 2 then
                for k = 1, 2 do
                    local kind = opts[k].kind
                    if kind ~= 'normal' and kind ~= 'elite' and not visited[kind] then pick = k - 1; break end
                end
                if not shots['08-exit-hover'] then
                    game.setHover(game.exitTo(1)); sleep(0.1); once('08-exit-hover'); game.setHover(nil)
                end
            end
            local exitCell = game.exitTo(pick)
            go(exitCell)
            if not isExit(modalTitle()) then say('第 ' .. f .. ' 层没走到出口：' .. tostring(modalTitle())); break end
            if #opts == 2 then once('08b-exit-confirm') end
            say(string.format('第 %d 层走出口 %d（%s）', f, pick, tostring(modalTitle())))
            button('往下走')
            settle(); sleep(0.2)
            if modalTitle() ~= run:floor().name .. ' 完成' then say('第 ' .. f .. ' 层没出结算：' .. tostring(modalTitle())); break end
            button('下楼')
            if modalTitle() == '井租' then say('第 ' .. f .. ' 层交井租：' .. tostring(button('交'))) end
            sleep(0.2)
            run = game.getRun()
            if run.status == 'finished' then say('通关'); break end
            say(string.format('第 %d 层完成 → %s（%s）', f, run:floor().name, tostring(run:floor().kind)))
        end
        local v = {}
        for k in pairs(visited) do v[#v + 1] = k end
        table.sort(v)
        say('去过的设施：' .. table.concat(v, '、'))
        say('结束弹窗：' .. tostring(modalTitle()))
        shot('09-victory')
        love.filesystem.write('autotest.log', table.concat(log, '\n'))
        love.event.quit(0)
    end)

    local update = love.update
    love.update = function(dt)
        update(dt)
        wait = wait - dt
        if wait <= 0 and coroutine.status(co) ~= 'dead' then
            local ok, err = coroutine.resume(co)
            if not ok then print('[autotest] 出错：' .. tostring(err)); love.event.quit(1) end
        end
    end
end

return M
