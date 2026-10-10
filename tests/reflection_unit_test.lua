-- Run: lua tests/reflection_unit_test.lua
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
local function near(a, b) return type(a) == "number" and math.abs(a - b) < 1e-9 end

-- a fake engine: reflective tiles are listed, kind and wobble are settable
local reflective, kind, wobble, covers = {}, 2, nil, {}
local fakeEngine = {
  reflectionKind = function() return kind end,
  reflectiveAt = function(tx, ty) return reflective[tx .. "," .. ty] == true end,
  reflectionWobble = function() return wobble end,
  coverReflections = function(l, t, w, h) covers[#covers + 1] = { l, t, w, h } return true end,
}
local modules = { engine_patch = fakeEngine }
local V = { path = ".", mod = {} }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  local value = assert(loadfile("lib/" .. name .. ".lua"))(V)
  modules[name] = value
  return value
end

-- a fake love.graphics that records draws
local draws = {}
local function fakeQuad()
  local q = {}
  function q:setViewport(x, y, w, h) self.vp = { x, y, w, h } end
  return q
end
love = { graphics = {
  newQuad = function() return fakeQuad() end,
  setColor = function() end,
  draw = function(img, q, x, y, r, sx, sy)
    draws[#draws + 1] = { img = img, q = q, vp = { (table.unpack or unpack)(q.vp) }, x = x, y = y, sx = sx, sy = sy }
  end,
} }

local Reflection = V.require("reflection")
local Config = V.require("config")
local image = { getDimensions = function() return 64, 128 end }

-- a 20 px wide frame, 24 rows above its feet, drawn at scale 1 with its left edge at
-- world x 2 and its feet at world y 30 (a sprite on the tile at (0, 16))
local geo = { image = image, qx = 20, qy = 40, qw = 20, rows = 24, left = 2, mirror = 30, sx = 1, sy = 1 }

-- ------- the box: starts OVERLAP px up the feet, as tall as the frame above them
do
  local l, t, w, h, sx = Reflection.box(geo, nil)
  eq(l, 2, "it lines up with the sprite")
  eq(t, 30 - Config.REFLECTION_OVERLAP, "its top is the overlap above the feet")
  eq(w, 20, "same width")
  eq(h, 24, "as tall as the frame above its feet")
  eq(sx, 1, "drawn at the sprite's scale")
  l, t, w, h, sx = Reflection.box(geo, 256 / 1.25)
  check(near(w, 25) and near(l, 2 - 2.5), "the wobble widens it about its centre")
  l, t, w, h = Reflection.box({ image = image, qx = 0, qy = 0, qw = 20, rows = 24, left = 0, mirror = 30, sx = -2, sy = 2 }, nil)
  check(w == 40 and h == 48, "a flipped, doubled sprite: twice the size")
end

-- ------- the source: the mirror flips it, the first row below the feet is the last above
do
  local _, top = Reflection.box(geo, nil)
  local x, y, w, h = Reflection.source(geo, 2, top, 1, 2, 22, top, top + 1, false)
  eq(y, 40 + 23, "the reflection's first row is the frame's last row above the feet")
  eq(h, 1, "one row")
  check(x == 20 and w == 20, "full width")
  x, y, w, h = Reflection.source(geo, 2, top, 1, 2, 12, top, top + 24, false)
  check(x == 20 and w == 10 and y == 40 and h == 24, "the left half of the box is the left half of the frame")
  x = Reflection.source(geo, 2, top, 1, 2, 12, top, top + 24, true)
  eq(x, 30, "...and the RIGHT half when the sprite is flipped")
end

-- ------- drawing: only on reflective tiles, and covered afterwards
do
  draws, covers = {}, {}
  kind = 0
  eq(Reflection.drawAll({ { geo = geo, cell = { cx = 0, cy = 1 } } }, 0, 0), 0, "no water below: no reflection")
  eq(#draws, 0, "...nothing drawn")
  kind = 2
  eq(Reflection.drawAll({ { geo = geo, cell = { cx = 0, cy = 1 } } }, 0, 0), 0, "water below but no reflective tile in the box: nothing")
  reflective["0,2"] = true -- world y 32..47: the reflection's rows 4..19 below its top
  draws, covers = {}, {}
  eq(Reflection.drawAll({ { geo = geo, cell = { cx = 0, cy = 1 } } }, 0, 0), 1, "a reflective tile under it: one reflection")
  eq(#draws, 1, "...drawn once, clipped to that tile")
  local d = draws[1]
  check(d.sy == -1 and d.sx == 1, "mirrored upside down at the sprite's scale")
  eq(d.y, 48, "its clip ends at the tile's bottom edge (drawn up from there)")
  eq(d.vp[4], 16, "the 16 rows that fall in that tile")
  eq(d.vp[2], 40 + 24 - (48 - 28), "...starting at the frame row that far above its feet")
  eq(#covers, 1, "the map's upper layer goes back over it")
  -- with the camera moved, the screen position moves and the source does not
  draws = {}
  Reflection.drawAll({ { geo = geo, cell = { cx = 0, cy = 1 } } }, 5, 7)
  check(draws[1].x == d.x - 5 and draws[1].y == d.y - 7 and draws[1].vp[2] == d.vp[2], "the camera only moves where it lands")
  -- a fading sprite's reflection fades; a gone one has none
  local faded = {}
  for k, v in pairs(geo) do faded[k] = v end
  faded.alpha = 0
  draws = {}
  eq(Reflection.drawAll({ { geo = faded, cell = { cx = 0, cy = 1 } } }, 0, 0), 0, "an invisible sprite casts none")
  check(pcall(Reflection.drawAll, { { geo = nil, cell = { cx = 0, cy = 0 } } }, 0, 0), "a missing frame is skipped, never an error")
end

-- ------- gen3-hd-sprites must not catch these draws (they are slices, not the sprite)
do
  local HdField = V.require("hd_field")
  local untagged, retagged = 0, 0
  local lastSpec
  local lib = { tag = function(_, spec) retagged = retagged + 1 lastSpec = spec end,
                untag = function() untagged = untagged + 1 end }
  local mod = { find = function() return { exports = lib } end }
  local img = { getDimensions = function() return 64, 128 end, setFilter = function() end }
  HdField.tag(mod, img, "assets/pmd/walk/025-normal.png")
  local before = retagged
  local g = {}
  for k, v in pairs(geo) do g[k] = v end
  g.image, g.mod = img, mod
  Reflection.drawAll({ { geo = g, cell = { cx = 0, cy = 1 } } }, 0, 0)
  check(untagged == 1 and retagged == before + 1, "an older library: the sheet is untagged while its reflection is drawn, then tagged again")

  -- a library that takes per-quad scales draws the slices itself, each at scale 1
  lib.features = { quadPivots = true }
  untagged = 0
  reflective["0,3"] = true -- two tiles: two slices
  draws = {}
  Reflection.drawAll({ { geo = g, cell = { cx = 0, cy = 1 } } }, 0, 0)
  eq(untagged, 0, "with HD slice support the sheet stays tagged")
  eq(#draws, 2, "one slice per reflective tile")
  check(draws[1] and draws[2] and draws[1].q ~= draws[2].q, "...each through its own quad (the library reads them at composite time)")
  check(HdField.slicesSupported(mod, img), "slices are supported for a tagged sheet")
  local qp = lastSpec and lastSpec.quadPivots and draws[1] and lastSpec.quadPivots[draws[1].q]
  check(qp and qp[3] == 1, "...and each is registered at scale 1, so the library does not size it twice")
  reflective["0,3"] = nil
end

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("reflection_unit_test: all passed")
