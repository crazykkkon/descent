-- 规则在拉杆时已结算，显示旧武器直到最后一个未锁住的轮子停稳。
local view = require('view.arm_view')
local before = { weapon = 'harpoon', stops = { 5, 2, 2 } }
local stops = { 5, 1, 2 }
local function replay(faces, kind, after)
    local locks = { true, false, true }
    view.startSpin(locks, faces, before, stops, 'settled')
    assert(view.displayHero(after) == before and view.displayHeld({}) == locks)
    assert(view.rolling(1) == 0 and view.rolling(3) == 0)
    assert((stops[2] - view.rolling(2) - before.stops[2]) % 5 == 0)
    assert(view.update(0.70) == nil and view.displayHero(after) == before)
    assert(view.update(0.08) == 'settled' and view.displayHero(after) == after)
    local actual, _, weapon = view.flashInfo()
    assert(actual == kind and (kind ~= 'win' or weapon == after.weapon))
    assert(view.update(0.4) == nil and not view.busy())
end
replay({ 'wild', 'boneKnife', 'boneKnife' }, 'win', { weapon = 'boneKnife' })
replay({ false, false, false }, 'lose', {})
replay({ 'wild', 'wild', 'wild' }, 'keep', before)
replay({ 'boneKnife', false, 'boneKnife' }, 'keep', before)
view.reset()
assert(view.flashInfo() == nil and not view.busy())
print('转轮显示检查通过（锁轴、图案起止位置、赖子、中线生效时机、空手与保留）')
