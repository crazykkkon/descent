-- 楼层：用文字地图配置，解析成格子数组。和 TypeScript 原型 src/core/floor.ts 一致。
--
-- 注意：Lua 版格子下标从 1 开始（第 y 行第 x 列 = y * w + x + 1，x、y 从 0 开始）；
-- TypeScript 原型从 0 开始。对账时 +1 / -1 转换。
--
-- 地图字符：
--   #  墙        .  空地      @  入口（主角起点）   >  出口
--   D  骨门      B  血门
--   k  骨钥      h  小血瓶    H  大血瓶   r  赤晶   b  青晶   $  金币袋
--   m  井苔      e  盲鳗      f  骨蛙     c  锈甲虫  v  回声蝠  g  溺魂  x  裂岩蟹  G  石鳞守卫
--   w  井鼠      u  盐蚀蛞蝓  p  骸骨祭司  K  守门人（精英）
--   E  井底之眼（Boss 占位）   M  补给摊   S  大转盘   N  当铺   A  骨坛（设施都站在旁边用）

local M = {}

local LEGEND = {
    ['#'] = { kind = 'wall' },
    ['.'] = { kind = 'floor' },
    ['@'] = { kind = 'floor' },
    ['>'] = { kind = 'exit' },
    D = { kind = 'door', door = 'bone' },
    B = { kind = 'door', door = 'blood' },
    k = { kind = 'item', id = 'key' },
    h = { kind = 'item', id = 'smallPotion' },
    H = { kind = 'item', id = 'bigPotion' },
    r = { kind = 'item', id = 'redGem' },
    b = { kind = 'item', id = 'blueGem' },
    ['$'] = { kind = 'item', id = 'gold' },
    m = { kind = 'monster', id = 'moss' },
    e = { kind = 'monster', id = 'eel' },
    f = { kind = 'monster', id = 'frog' },
    c = { kind = 'monster', id = 'beetle' },
    v = { kind = 'monster', id = 'bat' },
    g = { kind = 'monster', id = 'wraith' },
    x = { kind = 'monster', id = 'crab' },
    G = { kind = 'monster', id = 'guardian' },
    w = { kind = 'monster', id = 'rat' },
    u = { kind = 'monster', id = 'slug' },
    p = { kind = 'monster', id = 'priest' },
    K = { kind = 'monster', id = 'gatekeeper' },
    E = { kind = 'monster', id = 'eye' },
    M = { kind = 'stall' },
    S = { kind = 'wheel' },
    N = { kind = 'pawn' },
    A = { kind = 'altar' },
}

local function copyCell(c)
    local t = {}
    for k, v in pairs(c) do t[k] = v end
    return t
end
M.copyCell = copyCell

-- 返回 { w, h, cells, start }
function M.parse(def)
    local h = #def.map
    local w = #def.map[1]
    local cells = {}
    local start, exits = nil, 0
    for y = 1, h do
        local row = def.map[y]
        assert(#row == w, def.name .. ': 第 ' .. y .. ' 行长度不对')
        for x = 1, w do
            local ch = row:sub(x, x)
            local cell = LEGEND[ch]
            assert(cell, def.name .. ': 未知字符 ' .. ch)
            if ch == '@' then start = (y - 1) * w + x end
            if cell.kind == 'exit' then exits = exits + 1 end
            cells[#cells + 1] = copyCell(cell)
        end
    end
    assert(start, def.name .. ': 没有入口 @')
    assert(exits == 1, def.name .. ': 出口必须正好 1 个')
    return { w = w, h = h, cells = cells, start = start }
end

-- 相邻格子（上、下、左、右，顺序和原型一致）
function M.neighbors(i, w, h)
    local x = (i - 1) % w
    local y = (i - 1 - x) / w
    local out = {}
    if y > 0 then out[#out + 1] = i - w end
    if y < h - 1 then out[#out + 1] = i + w end
    if x > 0 then out[#out + 1] = i - 1 end
    if x < w - 1 then out[#out + 1] = i + 1 end
    return out
end

-- 第 i 格相邻格子上的怪物 id；alive(j) 可以排除已经打掉的
function M.adjacentMonsters(cells, w, h, i, alive)
    local out = {}
    for _, n in ipairs(M.neighbors(i, w, h)) do
        local c = cells[n]
        if c.kind == 'monster' and (not alive or alive(n)) then out[#out + 1] = c.id end
    end
    return out
end

-- 设施格子：站在旁边用，不能走上去
local FACILITY = { stall = true, wheel = true, pawn = true, altar = true }
function M.isFacility(c) return FACILITY[c.kind] == true end

return M
