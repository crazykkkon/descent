-- 楼梯口的一句话：和原型 src/core/whisper.ts 一致。按下一层的真实内容挑，但不说破。
local config = require('core.config')
local floorMod = require('core.floor')
local M = {}

local KIND = {
    wheel = '下面传来木轮转动的吱呀声。',
    pawn = '下面有人在拨算盘。',
    altar = '下面飘上来一股骨灰味。',
    camp = '下面有火光，暖暖的。',
}

function M.whisper(f)
    if KIND[f.kind] then return KIND[f.kind] end
    local n, elite = 0, false
    for _, c in ipairs(floorMod.parse(f).cells) do
        if c.kind == 'monster' then
            n = n + 1
            if config.MONSTERS[c.id].elite then elite = true end
        end
    end
    if elite then return '下面有很沉的呼吸声。' end
    if n >= 8 then return '下面动静很大，像有一群东西在爬。' end
    if n <= 3 then return '下面很安静。' end
    return '下面有爪子挠石头的声音。'
end

return M
