-- 楼梯口的一句话：和原型 src/core/whisper.ts 一致。只透露"下面有多凶"的大概，不说类型、不给数字。
local config = require('core.config')
local floorMod = require('core.floor')
local M = {}

M.WHISPERS = {
    loud = { '下面有什么东西在动。', '下面传来一阵闷响。', '风从下面往上吹，带着一股腥味。' },
    quiet = { '下面很安静。', '下面黑得看不见底。', '下面滴答滴答地漏着水。' },
    mid = { '下面有爪子挠石头的声音。', '下面隐约有回声。', '下面有点潮。' },
}

-- 按地图字符算一个稳定的编号（地图只有 ASCII 字符，和原型的 charCodeAt 一样）
local function mapCode(map)
    local n = 0
    for _, row in ipairs(map) do
        for i = 1, #row do n = (n + row:byte(i) * i) % 9973 end
    end
    return n
end

-- 下面有多凶：'loud' | 'quiet' | 'mid'（楼梯口的画面效果用，不说破类型）
function M.level(f)
    local n, elite = 0, false
    for _, c in ipairs(floorMod.parse(f).cells) do
        if c.kind == 'monster' then
            n = n + 1
            if config.MONSTERS[c.id].elite then elite = true end
        end
    end
    return (elite or n >= 8) and 'loud' or (n <= 3 and 'quiet' or 'mid')
end

function M.whisper(f)
    local n, elite = 0, false
    for _, c in ipairs(floorMod.parse(f).cells) do
        if c.kind == 'monster' then
            n = n + 1
            if config.MONSTERS[c.id].elite then elite = true end
        end
    end
    local level = (elite or n >= 8) and 'loud' or (n <= 3 and 'quiet' or 'mid')
    local list = M.WHISPERS[level]
    return list[mapCode(f.map) % #list + 1]
end

return M
