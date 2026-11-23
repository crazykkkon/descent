-- 自动测试：设置环境变量 DESCENT_AUTOTEST=1 启动时，按脚本操作并截图（截图存到存档目录）。
-- 只用于开发检查，正常游戏不会加载。

local M = {}

function M.start()
    local game = require('main')
    local co
    local wait = 0
    local log = {}
    local function say(s) log[#log + 1] = s; print('[autotest] ' .. s) end
    local function sleep(t) wait = t; coroutine.yield() end
    local function shot(name) love.graphics.captureScreenshot(name .. '.png'); sleep(0.3) end
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
    local function walkTo(i)
        game.act(i)
        for _ = 1, 400 do
            sleep(0.05)
            if game.getModal() then return end
            local run = game.getRun()
            if run.pos == i or run.status ~= 'playing' then return end
        end
    end

    co = coroutine.create(function()
        sleep(0.5)
        shot('01-stairs')
        say('签约：' .. tostring(button('签约')))
        sleep(0.3)
        local run = game.getRun()
        say(string.format('进入第 2 层：生命 %d 攻 %d 契约生效 %s', run.hero.hp, run.hero.atk, tostring(run:contractActive())))
        shot('02-floor')
        hoverCell(3) -- 第一只盲鳗
        sleep(0.3)
        shot('03-hover')
        love.mouse.setPosition(1, 1)
        walkTo(3) -- 先打第一只盲鳗
        run = game.getRun()
        say(string.format('打完盲鳗：生命 %d 金 %d', run.hero.hp, run.hero.gold))
        walkTo(5) -- 第一瓶血瓶：弹出毁约确认
        say('弹窗：' .. tostring(game.getModal() and game.getModal().title))
        shot('04-break')
        say('喝（毁约）：' .. tostring(button('喝')))
        sleep(1.0)
        run = game.getRun()
        say(string.format('喝完：生命 %d 契约生效 %s', run.hero.hp, tostring(run:contractActive())))
        for _, t in ipairs({ 7, 9, 11 }) do walkTo(t); if game.getModal() then break end end -- 第二只盲鳗、第二瓶药、出口
        for _ = 1, 10 do
            if game.getModal() then break end
            sleep(0.2)
        end
        say('出口弹窗：' .. tostring(game.getModal() and game.getModal().title))
        shot('05-summary')
        button('继续')
        sleep(0.3)
        say('结束弹窗：' .. tostring(game.getModal() and game.getModal().title))
        shot('06-end')
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
