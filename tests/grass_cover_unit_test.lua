-- Run: lua tests/grass_cover_unit_test.lua
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
local function eq(a, b, msg)
  check(a == b, string.format("%s (got %s expected %s)", msg, tostring(a), tostring(b)))
end

local fakeEngine = {}
local modules = {}
local V = { path = "." }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  if name == "engine_patch" then
    modules[name] = fakeEngine
    return fakeEngine
  end
  local chunk = assert(loadfile("lib/" .. name .. ".lua"))
  local value = chunk(V)
  modules[name] = value
  return value
end

local fakeSheet = { image = "fake_image", quadsFront = { [4] = "fake_quad" } }
fakeEngine.isGrass = function(_cx, _cy) return true end
V.require("grass_cover").reset() -- (new grass: forget the old tiles)
fakeEngine.grassSheet = function() return fakeSheet end
V.require("grass_cover").reset() -- (new grass: forget the old tiles)

local GrassCover = V.require("grass_cover")

-- ------- a grass cell with feet in the right band appends an overlay actor
local actors = {}
GrassCover.append(actors, 2, 3, 3 * 16, 3, 7) -- py exactly at the cell's own row -> feet mid-band
eq(#actors, 1, "a grass cell with feet in band appends exactly one overlay")
eq(actors[1].kind, "field_effect_wild_grass", "overlay actor has the expected kind")
eq(actors[1].i, 90007, "overlay actor's draw-order id incorporates idBase")
eq(actors[1].elevation, 3, "overlay actor carries the given elevation")

-- ------- not grass -> no overlay
fakeEngine.isGrass = function(_cx, _cy) return false end
V.require("grass_cover").reset() -- (new grass: forget the old tiles)
local actorsNoGrass = {}
GrassCover.append(actorsNoGrass, 2, 3, 3 * 16, 3, 1)
eq(#actorsNoGrass, 0, "a non-grass cell appends nothing")
fakeEngine.isGrass = function(_cx, _cy) return true end
V.require("grass_cover").reset() -- (new grass: forget the old tiles)

-- ------- feet outside the vertical band (mid-step, between cells) -> no overlay
local actorsOutOfBand = {}
GrassCover.append(actorsOutOfBand, 2, 3, 3 * 16 - 10, 3, 1) -- feet well above the band
eq(#actorsOutOfBand, 0, "feet outside the tuft's draw band append nothing")

-- ------- no sheet loaded yet (no map, or missing ROM extract) -> no overlay
fakeEngine.grassSheet = function() return nil end
V.require("grass_cover").reset() -- (new grass: forget the old tiles)
local actorsNoSheet = {}
GrassCover.append(actorsNoSheet, 2, 3, 3 * 16, 3, 1)
eq(#actorsNoSheet, 0, "no loaded sheet appends nothing, never throws")
fakeEngine.grassSheet = function() return fakeSheet end
V.require("grass_cover").reset() -- (new grass: forget the old tiles)

-- ------- a sheet missing the static frame specifically -> no overlay
fakeEngine.grassSheet = function() return { image = "fake_image", quadsFront = {} } end
V.require("grass_cover").reset() -- (new grass: forget the old tiles)
local actorsNoFrame = {}
GrassCover.append(actorsNoFrame, 2, 3, 3 * 16, 3, 1)
eq(#actorsNoFrame, 0, "a sheet missing the static frame 4 appends nothing")
fakeEngine.grassSheet = function() return fakeSheet end
V.require("grass_cover").reset() -- (new grass: forget the old tiles)

-- ------- garbage coordinates never throw
local actorsGarbage = {}
GrassCover.append(actorsGarbage, nil, nil, nil, 3, 1)
eq(#actorsGarbage, 0, "nil coordinates append nothing, never throw")

-- ------- per frame: the same actor table, refilled; the engine asked once per tile
do
  GrassCover.reset()
  local asks = 0
  fakeEngine.isGrass = function() asks = asks + 1 return true end
  local f1, f2 = {}, {}
  GrassCover.append(f1, 2, 3, 3 * 16, 3, 9)
  GrassCover.append(f2, 2, 3, 3 * 16 + 1, 4, 9)
  check(f1[1] == f2[1], "the next frame reuses the same actor table")
  eq(f2[1].sortY, 3 * 16 + 1 + 0.5, "...refilled with this frame's position")
  eq(f2[1].elevation, 4, "...and elevation")
  eq(asks, 1, "the tile's grass is asked once, not every frame")
  local other = {}
  GrassCover.append(other, 2, 3, 3 * 16, 3, 10)
  check(other[1] ~= f1[1], "another owner gets its own actor")
  GrassCover.reset()
  GrassCover.append({}, 2, 3, 3 * 16, 3, 9)
  eq(asks, 2, "a new map asks again")
end

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("grass_cover_unit_test: all passed")
