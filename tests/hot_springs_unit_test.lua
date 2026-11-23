-- Run: lua tests/hot_springs_unit_test.lua
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

-- a fake LOVE: quads remember their viewport
_G.love = {
  graphics = {
    newQuad = function(x, y, w, h) return { vx = x, vy = y, vw = w, vh = h,
      getViewport = function(self) return self.vx, self.vy, self.vw, self.vh end } end,
  },
}

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

-- the spa: columns 2..5 of rows 3..4
local springs = function(cx, cy) return cx >= 2 and cx <= 5 and cy >= 3 and cy <= 4 end
local asked = 0
fakeEngine.isHotSprings = function(cx, cy) asked = asked + 1 return springs(cx, cy) end
local fullQuad = love.graphics.newQuad(0, 0, 16, 16)
local sheet = { image = { getDimensions = function() return 16, 16 end } }
fakeEngine.hotSpringsSheet = function() return sheet, fullQuad end

local HS = V.require("hot_springs")

-- ------- the engine's rule: both its cell and the one it steps to
check(HS.inSprings(3, 3, 3, 3), "standing in the spa: in")
check(HS.inSprings(3, 3, 4, 3), "stepping on inside the spa: in")
check(not HS.inSprings(3, 3, 6, 3), "stepping out of it: not (as the engine does)")
check(not HS.inSprings(6, 3, 5, 3), "stepping in from the bank: not yet")
check(not HS.inSprings(nil, 3), "no cell: not")

-- ------- tiles are asked once per map
asked = 0
HS.inSprings(3, 3, 3, 3)
eq(asked, 0, "a tile's answer is kept")
HS.reset()
HS.inSprings(3, 3, 3, 3)
eq(asked, 1, "...until the next map")

-- ------- pieces: the whole art (+ a margin), at least 16 px, cut to the spring's tiles
local all = function() return true end
local list, n = HS.pieces(56, 10, 3, all)
eq(n, 1, "a small one on a tile: one piece")
eq(list[1][3], 16, "...16 px wide, like the player's")
eq(list[1][1], 48, "...centred on its feet")
list, n = HS.pieces(64, 10, 3, all)
eq(n, 2, "between two tiles: a piece of each")
eq(list[1][3] + list[2][3], 16, "...16 px in all")
list, n = HS.pieces(64, 40, 3, all) -- 40 + 2 x 2 = 44 px: 42..86
local total = 0
for k = 1, n do total = total + list[k][3] end
eq(total, 44, "a 40 px wide one: the band spans it, with a margin")
eq(list[1][1], 42, "...from its left edge")
eq(list[1][2], 10, "...each piece cut from its own tile's columns (42 is column 10 of tile 2)")
for k = 2, n do eq(list[k][1], list[k - 1][1] + list[k - 1][3], "...side by side (" .. k .. ")") end
local again = HS.pieces(56, 10, 3, all, list)
eq(#again, 1, "a reused list is trimmed")
list, n = HS.pieces(64, 400, 3, all)
total = 0
for k = 1, n do total = total + list[k][3] end
eq(total, HS.MAX_WIDTH, "never wider than MAX_WIDTH")
-- the spring's edge: water stops at the last spring tile, exactly
list, n = HS.pieces(5 * 16 + 16, 40, 3, springs)
eq(list[n][1] + list[n][3], 6 * 16, "at the spring's edge the band stops where the spring does")
for k = 1, n do check(springs(math.floor(list[k][1] / 16), 3), "...every piece over the spring (" .. k .. ")") end

-- ------- append: drawn at the feet, after the sprite, only over the spa
HS.reset()
local actors = {}
HS.append(actors, 3 * 16 + 8, 4 * 16, 12, 3, 3, 3, 3, 48, 3, 0)
eq(#actors, 1, "in the spa: the water band")
eq(actors[1].x, 48, "...over its feet")
eq(actors[1].y, 48, "...the band's tile ends on its feet")
eq(actors[1].sortY, 48.5, "...drawn right after the sprite")
eq(actors[1].quad, fullQuad, "...the engine's own sheet")
eq(actors[1].i, 91601, "...a stable draw-order id")
actors = {}
HS.append(actors, 3 * 16 + 8, 4 * 16, 16, 7, 3, 7, 3, 48, 3, 0)
eq(#actors, 0, "on dry ground: nothing")
-- at the spa's edge: no water over the bank
actors = {}
HS.append(actors, 5 * 16 + 16, 4 * 16, 40, 5, 3, 5, 3, 48, 3, 0)
check(#actors >= 1, "at the edge: water over the spring part")
for _, a in ipairs(actors) do
  check(a.x + a.quad.vw <= 6 * 16, "...none past the spring's last tile")
end
-- no sheet yet: nothing (and no error)
fakeEngine.hotSpringsSheet = function() return nil end
actors = {}
HS.append(actors, 56, 64, 16, 3, 3, 3, 3, 48, 3, 0)
eq(#actors, 0, "no sheet: nothing")

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("all hot_springs tests passed")
