-- Run: lua tests/tail_flame_unit_test.lua
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
local function near(a, b) return math.abs(a - b) < 1e-9 end

local modules = {}
local V = { path = "." }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  modules[name] = assert(loadfile("lib/" .. name .. ".lua"))(V)
  return modules[name]
end
local TailFlame = V.require("tail_flame")
local Config = V.require("config")

-- a sheet from a char map: '.' empty, '#' outline, 'o' body orange, 'Y' flame yellow,
-- 'y' belly dark yellow, 'r' flame red
local COLORS = {
  ["#"] = { 0, 0, 0, 255 }, o = { 255, 135, 95, 255 }, Y = { 255, 247, 0, 255 },
  y = { 223, 183, 0, 255 }, r = { 215, 63, 0, 255 }, ["."] = { 0, 0, 0, 0 },
}
local function sheet(cells, cw, ch)
  -- cells[row][col] = list of ch strings of cw chars
  local rows, cols = #cells, #cells[1]
  local w = cols * cw
  local out = {}
  for row = 1, rows do
    for y = 1, ch do
      for col = 1, cols do
        local line = cells[row][col][y]
        for x = 1, cw do
          local c = COLORS[line:sub(x, x)]
          out[#out + 1] = string.char(c[1], c[2], c[3], c[4])
        end
      end
    end
  end
  return table.concat(out), w
end

-- ------- detect: the flame, not the belly
do
  local tail = {
    ".r......",
    "rYr.###.",
    "rYY#ooo#",
    ".o.#oyY#",
    ".o.#yYy#",
    "...####.",
  }
  local hidden = {
    "........",
    "....###.",
    "...#ooo#",
    "...#oyY#",
    "...#yYy#",
    "...####.",
  }
  local bytes, w = sheet({ { tail, hidden } }, 8, 6)
  local pts = TailFlame.detect(bytes, w, 8, 6, 2, 1)
  local p = pts[0][0]
  check(p and near(p[1], 4 / 3 + 0.5) and near(p[2], 1.5), "the flame's yellow is the emitter (its top, centred across)")
  check(pts[0][1] == false, "a frame with only belly yellow has no flame")
end

-- ------- detect: two yellow bits up to 2 px apart are one flame; the biggest wins
do
  local cell = {
    "Y.Y.....",
    "........",
    "......Y.",
    "........",
  }
  local bytes, w = sheet({ { cell } }, 8, 4)
  local p = TailFlame.detect(bytes, w, 8, 4, 1, 1)[0][0]
  check(p and near(p[1], 1.5) and near(p[2], 0.5), "pixels 2 apart join; the larger cluster is the flame")
end

-- ------- settingsFor: only the Charmander line
check(TailFlame.settingsFor(4) and TailFlame.settingsFor(5) and TailFlame.settingsFor(6), "Charmander, Charmeleon and Charizard have a flame")
check(TailFlame.settingsFor("006") ~= nil, "...by art key too")
check(TailFlame.settingsFor(25) == nil and TailFlame.settingsFor(nil) == nil, "nothing else does")

-- ------- colorAt: white-hot to dark red
do
  local colors = Config.TAIL_FLAME.colors
  local r, g, b = TailFlame.colorAt(colors, 0)
  check(r == colors[1][1] and g == colors[1][2] and b == colors[1][3], "a new particle is the first colour")
  r, g, b = TailFlame.colorAt(colors, 1)
  local last = colors[#colors]
  check(r == last[1] and g == last[2] and b == last[3], "a dying one the last")
  local _, g1 = TailFlame.colorAt(colors, 0.2)
  local _, g2 = TailFlame.colorAt(colors, 0.7)
  check(g1 > g2, "...going redder as it ages")
end

-- ------- offsetAt: rises, faster later
do
  local cfg = { accel = 0.01, sway = 0, drift = 0 }
  local p = { life = 20, vx = 0, vy = -0.5, phase = 0, k = 1 }
  local _, y1, f1 = TailFlame.offsetAt(p, 4, cfg)
  local _, y2, f2 = TailFlame.offsetAt(p, 8, cfg)
  check(y1 < 0 and y2 < y1, "a particle rises")
  check(near(f1, 0.2) and near(f2, 0.4), "...through its life")
  check(-(y2 - y1) > -y1, "...speeding up")
  local q = { life = 20, vx = 0, vy = -0.5, phase = 0, k = 2 }
  local _, yk = TailFlame.offsetAt(q, 8, cfg)
  check(yk < y2, "a bigger sprite's flame climbs further (accel grows with it)")
end

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("tail_flame_unit_test: all passed")
