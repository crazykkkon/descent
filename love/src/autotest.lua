-- 自动测试：设置环境变量 DESCENT_AUTOTEST=1 启动时，用一个很强的主角按界面操作走完 20 层，
-- 经过楼梯口、契约、井租、出口结算、武器三选一、补给摊、井中轮和通关结算，沿途截图（存到存档目录）。
-- 只用于开发检查，正常游戏不会加载（打包时也不打进去）。

local M = {}

function M.start()
    local game = require('main')
    local floorMod = require('core.floor')
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
    local function hoverCell(i)
        local run = game.getRun()
        local x = (i - 1) % run.w
        local y = math.floor((i - 1) / run.w)
        local w, h = love.graphics.getDimensions()
        local S = math.max(1, math.min(math.floor(w / 640), math.floor(h / 360)))
        local OX, OY = math.floor((w - 640 * S) / 2), math.floor((h - 360 * S) / 2)
        love.mouse.setPosition(OX + (16 + x * 32 + 16) * S, OY + (44 + y * 32 + 16) * S)
    end
    local function find(pred)
        for i, c in ipairs(game.getRun().cells) do if pred(c) then return i end end
    end
    -- 穿过怪物、道具、门的最短路线（不穿墙、井中轮、补给摊）
    local function route(target)
        local run = game.getRun()
        local prev = { [run.pos] = -1 }
        local q, head = { run.pos }, 1
        while head <= #q do
            local cur = q[head]; head = head + 1
            if cur == target then break end
            for _, n in ipairs(floorMod.neighbors(cur, run.w, run.h)) do
                local k = run.cells[n].kind
                if prev[n] == nil and k ~= 'wall' and k ~= 'slot' and k ~= 'stall' and (k ~= 'exit' or n == target) then
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
    -- 一步一步走过去；路上的弹窗按"最省事"处理
    local function go(target)
        for _, cell in ipairs(route(target)) do
            local run = game.getRun()
            if run.status ~= 'playing' then return end
            if run.cells[cell].kind == 'floor' or run.pos ~= cell then
                game.act(cell)
                settle()
            end
            if modalTitle() == '喝下这瓶血瓶？' then button('喝'); settle() end
            if modalTitle() == '精英倒下了' then return end
            if modalTitle() == '楼梯口' then return end
        end
    end
    local function strong()
        local h = game.getRun().hero
        h.hp, h.atk, h.def, h.keys = math.max(h.hp, 99999), math.max(h.atk, 300), math.max(h.def, 300), 9
        h.gold = math.max(h.gold, 3000)
    end

    co = coroutine.create(function()
        love.filesystem.remove('save.lua')
        love.filesystem.remove('last-choices.lua')
        game.newGame(1)
        sleep(0.5)
        shot('01-floor1')
        for f = 1, 20 do
            local run = game.getRun()
            strong()
            if f == 5 then
                local rat = find(function(c) return c.kind == 'monster' and c.id == 'rat' end)
                hoverCell(rat); sleep(0.3); shot('05-swarm'); love.mouse.setPosition(1, 1)
            end
            local function near(i)
                local run = game.getRun()
                for _, n in ipairs(floorMod.neighbors(i, run.w, run.h)) do
                    if run.cells[n].kind ~= 'wall' and run.cells[n].kind ~= 'exit' then go(n); return end
                end
            end
            local stall = find(function(c) return c.kind == 'stall' end)
            if stall then
                near(stall)
                game.act(stall); settle(); sleep(0.2)
                say(string.format('第 %d 层补给摊：%s', f, tostring(modalTitle())))
                if f == 3 then shot('03-stall') end
                local before = game.getRun().hero.atk
                button('攻击'); say('买攻击：' .. before .. ' → ' .. game.getRun().hero.atk)
                button('离开')
            end
            local slot = find(function(c) return c.kind == 'slot' end)
            if slot then
                near(slot)
                game.act(slot); settle(); sleep(0.2)
                button('金币'); button('锁 1'); sleep(0.1)
                shot('11-slot')
                button('金币'); button('收下')
                if modalTitle() == '精英倒下了' then button(game.getModal().buttons[1].label) end
                say(string.format('第 %d 层井中轮转了两次，现在 %s', f, tostring(game.getRun().hero.weapon)))
            end
            local elite = find(function(c) return c.kind == 'monster' and require('core.config').MONSTERS[c.id].elite end)
            if elite then
                go(elite); sleep(0.2)
                say(string.format('第 %d 层精英：%s', f, tostring(modalTitle())))
                if modalTitle() == '精英倒下了' then
                    if f == 4 then shot('04-weapons') end
                    button(game.getModal().buttons[1].label)
                    say('拿到武器 ' .. tostring(game.getRun().hero.weapon))
                end
            end
            go(find(function(c) return c.kind == 'exit' end))
            if modalTitle() ~= '楼梯口' then say('第 ' .. f .. ' 层没走到楼梯口：' .. tostring(modalTitle())); break end
            if f == 1 or f == 12 then shot(string.format('%02d-stairs', f)) end
            local _ = button('签约') or button('下楼')
            settle(); sleep(0.2)
            if modalTitle() ~= run:floor().name .. ' 完成' then say('第 ' .. f .. ' 层没出结算：' .. tostring(modalTitle())); break end
            button('下楼')
            if modalTitle() == '井租' then
                say('第 ' .. f .. ' 层交井租：' .. tostring(button('交')))
            end
            sleep(0.2)
            run = game.getRun()
            say(string.format('第 %d 层完成 → 现在%s，状态 %s', f, run.status == 'finished' and '通关' or run:floor().name, run.status))
            if run.status == 'finished' then break end
        end
        say('结束弹窗：' .. tostring(modalTitle()))
        shot('20-victory')
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
