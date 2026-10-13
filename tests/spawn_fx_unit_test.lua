-- Run: lua tests/spawn_fx_unit_test.lua
-- How a wild Pokemon arrives / leaves (lib/spawn_fx.lua): rise or fade, eased, the
-- rustle frames in order, and the reverse for leaving.
package.path = "./?.lua;./?/init.lua;" .. package.path

local failures = 0
local function check(cond, msg)
  if not cond then
    failures = failures + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  else
    print("ok  " .. tostring(msg))
  end
end

local modules = {}
local V = { path = "." }
function V.require(name)
  if modules[name] == nil then modules[name] = assert(loadfile("lib/" .. name .. ".lua"))(V) end
  return modules[name]
end
local SpawnFx = V.require("spawn_fx")

-- appear in grass: sink 1 (under the grass) -> 0 (standing), eased
local fx = SpawnFx.new("appear", "grass", 20)
check(SpawnFx.visual(fx).sink == 1 and SpawnFx.visual(fx).alpha == nil, "appear starts fully sunk, no fade")
local prev = 1
local monotonic = true
for _ = 1, 20 do
  local done = SpawnFx.step(fx)
  local s = SpawnFx.visual(fx).sink
  if s > prev + 1e-9 then monotonic = false end
  prev = s
  if done then break end
end
check(monotonic and prev == 0, "it rises steadily to standing")
fx = SpawnFx.new("appear", "grass", 20)
fx.t = 2
local early = 1 - SpawnFx.visual(fx).sink
fx.t = 10
local mid = 1 - SpawnFx.visual(fx).sink
check(early < 0.1 and math.abs(mid - 0.5) < 1e-9, "eased: slow start, halfway at the midpoint")

-- leave: the reverse
local lv = SpawnFx.new("leave", "water", 10)
check(SpawnFx.visual(lv).sink == 0, "leave starts standing")
for _ = 1, 10 do SpawnFx.step(lv) end
check(SpawnFx.visual(lv).sink == 1, "and ends fully under the water line")

-- fade: alpha only
local fd = SpawnFx.new("appear", "fade", 8)
check(SpawnFx.visual(fd).alpha == 0 and SpawnFx.visual(fd).sink == nil, "fade starts invisible, no sink")
for _ = 1, 8 do SpawnFx.step(fd) end
check(SpawnFx.visual(fd).alpha == 1, "and ends fully shown")
local fo = SpawnFx.new("leave", "fade", 8)
for _ = 1, 8 do SpawnFx.step(fo) end
check(SpawnFx.visual(fo).alpha == 0, "fading out ends invisible")
check(SpawnFx.step(SpawnFx.new("appear", "grass", 1)) == true, "step reports the end")

-- the rustle: the engine's frames in order, then nothing (the static cover takes over)
local frames = { { 1, 10 }, { 2, 10 }, { 3, 10 }, { 4, 10 } }
check(SpawnFx.rustleFrame(frames, 0) == 1 and SpawnFx.rustleFrame(frames, 9) == 1, "frame 1 for its 10 ticks")
check(SpawnFx.rustleFrame(frames, 10) == 2 and SpawnFx.rustleFrame(frames, 35) == 4, "then 2 .. 4")
check(SpawnFx.rustleFrame(frames, 40) == nil, "then it has played out")
check(SpawnFx.rustleFrame(nil, 0) == nil, "no frames: no rustle")
local sheet = { quadsFront = { [1] = "q1", [2] = "q2" }, image = {} }
local a = SpawnFx.rustleActor(sheet, frames, 0, 32, 48, 48, 3, 7)
check(a and a.kind == "ow_spawn_rustle" and a.y == 48 + 8 and a.sortY > 48, "the rustle sits on the tile's lower half, in front")
check(SpawnFx.rustleActor(sheet, frames, 40, 32, 48, 48, 3, 7) == nil, "no actor once it has played")
check(pcall(a.draw, a, 0, 0), "drawing without love never errors")

-- water: three rings, one after another, growing outward and fading
check(#SpawnFx.rings(0) == 1, "the first ring starts at once")
check(#SpawnFx.rings(SpawnFx.RING_GAP) == 2 and #SpawnFx.rings(2 * SpawnFx.RING_GAP) == 3, "then a second and a third")
local r1, r2 = SpawnFx.rings(4)[1], SpawnFx.rings(20)[1]
check(r2.rx > r1.rx and r2.ry > r1.ry, "a ring grows outward")
check(r2.rx <= SpawnFx.RING_R1 and r1.rx >= SpawnFx.RING_R0, "within its start and end size")
check(r1.ry < r1.rx, "flattened, lying on the water")
check(SpawnFx.rings(SpawnFx.RING_LIFE - 1)[1].alpha < SpawnFx.rings(10)[1].alpha, "and fades as it spreads")
local three = SpawnFx.rings(2 * SpawnFx.RING_GAP + 1)
check(three[1].rx > three[2].rx and three[2].rx > three[3].rx, "the oldest ring is the widest")
check(#SpawnFx.rings(SpawnFx.ringsTicks()) == 0 and SpawnFx.ringsActor(SpawnFx.ringsTicks(), 0, 0, 0) == nil,
  "all gone after ringsTicks")
local px = SpawnFx.ringPixels(10, 4)
local onRing, dup, seen = true, false, {}
for _, p in ipairs(px) do
  local d = (p[1] / 10) ^ 2 + (p[2] / 4) ^ 2
  if d < 0.5 or d > 1.6 then onRing = false end
  local k = p[1] .. "," .. p[2]
  if seen[k] then dup = true end
  seen[k] = true
end
check(#px > 20 and onRing and not dup, "a ring is a 1 px outline of whole pixels, no doubles")
local ra = SpawnFx.ringsActor(5, 32, 48, 48, 3, 2)
check(ra and ra.kind == "ow_spawn_rings" and ra.sortY < 48, "drawn on the water, under the Pokemon")
check(pcall(ra.draw, ra, 0, 0), "drawing without love never errors")

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("spawn_fx_unit_test: all passed")
