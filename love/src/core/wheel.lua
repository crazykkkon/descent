-- 大转盘：和原型 src/core/wheel.ts 一致。盘面 8 格全部公开，每格 1/8。
local rng = require('core.rng')
local M = {}

M.SECTORS = {
    { prize = 'gold', amount = 30, text = '金币 +30' },
    { prize = 'hp', amount = 60, text = '生命 +60' },
    { prize = 'atk', amount = 2, text = '攻击 +2' },
    { prize = 'engrave', amount = 1, text = '新图案' },
    { prize = 'gold', amount = 30, text = '金币 +30' },
    { prize = 'def', amount = 2, text = '防御 +2' },
    { prize = 'leech', amount = 40, text = '井蛭 −40 生命' },
    { prize = 'erase', amount = 1, text = '擦掉一个图案' },
}
M.BASE_PRICE = 30

function M.price(spins) return rng.risingPrice(M.BASE_PRICE, spins) end

-- 第 n 次停在哪一格（从 1 开始）
function M.stop(seed, key, n) return math.floor(rng.draw(seed, key, n) * #M.SECTORS) + 1 end

return M
