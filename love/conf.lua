function love.conf(t)
    t.identity = 'descent-wellhead-print-preview'              -- 存档目录名
    t.version = '11.5'
    t.window.title = '坠井者 · 断臂转轮试玩'
    t.window.width = 1280
    t.window.height = 720
    t.window.minwidth = 640
    t.window.minheight = 360
    t.window.resizable = true
    t.window.vsync = 1
    t.modules.joystick = false
    t.modules.physics = false
end
