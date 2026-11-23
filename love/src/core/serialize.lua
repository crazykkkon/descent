-- 把存档表写成 Lua 源码字符串，再读回来（只支持数字、字符串、布尔和嵌套表）。

local M = {}

local function ser(v, out)
    local t = type(v)
    if t == 'number' or t == 'boolean' then out[#out + 1] = tostring(v)
    elseif t == 'string' then out[#out + 1] = string.format('%q', v)
    elseif t == 'table' then
        out[#out + 1] = '{'
        for k, x in pairs(v) do
            if type(k) == 'string' then out[#out + 1] = '[' .. string.format('%q', k) .. ']='
            else out[#out + 1] = '[' .. tostring(k) .. ']=' end
            ser(x, out)
            out[#out + 1] = ','
        end
        out[#out + 1] = '}'
    else
        out[#out + 1] = 'nil'
    end
end

function M.dump(v)
    local out = {}
    ser(v, out)
    return 'return ' .. table.concat(out)
end

function M.load(s)
    local fn = (loadstring or load)(s)
    if not fn then return nil end
    if setfenv then setfenv(fn, {}) end -- 存档里只有数据，不给它访问任何全局变量
    local ok, v = pcall(fn)
    return ok and v or nil
end

return M
