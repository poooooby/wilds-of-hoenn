-- Run: lua tests/signature_fx_unit_test.lua
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
local function near(a, b, eps) return math.abs(a - b) < (eps or 1e-9) end

local modules = {}
local V = { path = "." }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  modules[name] = assert(loadfile("lib/" .. name .. ".lua"))(V)
  return modules[name]
end
local Sig = V.require("signature_fx")
local Species = V.require("signature_species")
local Config = V.require("config")

-- a sheet from a char map: '.' empty, '#' outline, 'o' body orange, 'Y' flame yellow,
-- 'y' belly dark yellow, 'r' flame red, 'w' white
local COLORS = {
  ["#"] = { 0, 0, 0, 255 }, o = { 255, 135, 95, 255 }, Y = { 255, 247, 0, 255 },
  y = { 223, 183, 0, 255 }, r = { 215, 63, 0, 255 }, w = { 255, 255, 255, 255 }, ["."] = { 0, 0, 0, 0 },
}
local function sheet(cells, cw, ch)
  local rows, cols = #cells, #cells[1]
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
  return table.concat(out), cols * cw
end

-- ------- hsv / matches
do
  local h, s, v = Sig.hsv(255, 0, 0)
  check(near(h, 0) and near(s, 1) and near(v, 1), "hsv: red")
  h = Sig.hsv(0, 0, 255)
  check(near(h, 240), "hsv: blue is 240")
  check(Sig.matches({ hmin = 340, hmax = 20, smin = 0.5 }, 255, 20, 30), "a hue range wrapping through red matches red")
  check(not Sig.matches({ hmin = 340, hmax = 20, smin = 0.5 }, 30, 255, 30), "...not green")
  check(Sig.matches({ { rmin = 250 }, { bmin = 250 } }, 0, 0, 255), "a list of predicates matches any")
  check(Sig.matches("body", 1, 2, 3), "body matches anything opaque")
end

-- ------- detect: Charmander's flame, not its belly (the old tail flame finder)
local charPmd = Species[4].fx[1].pmd
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
  local pts = Sig.detect(bytes, w, 8, 6, 2, 1, { charPmd })
  local p = pts[1][0][0]
  check(p and near(p[1], 1.5) and near(p[2], 1.5), "the flame's top is the emitter (centred across its top row)")
  check(pts[1][0][1] == false, "a frame with only belly yellow has no flame")
end

-- ------- detect: area / edge / region / cluster limits
do
  local cell = {
    "........",
    ".www....",
    ".www..r.",
    ".www....",
    "........",
    "rr......",
  }
  local bytes, w = sheet({ { cell } }, 8, 6)
  local white = { smax = 0.1, vmin = 0.9 }
  local out = Sig.detect(bytes, w, 8, 6, 1, 1, {
    { match = white, at = "area", samples = 100 },
    { match = white, at = "edge", samples = 100 },
    { match = { rmin = 200, gmax = 80 }, at = "area", maxPx = 1 },
    { match = { rmin = 200, gmax = 80 }, region = { 0, 0, 1, 0.5 }, at = "area" },
    { match = { rmin = 200, gmax = 80 }, at = "area", clusters = 1, samples = 100 },
  })
  check(#out[1][0][0] == 18, "area: every matched pixel (9)")
  check(#out[2][0][0] == 16, "edge: all but the middle one (8)")
  local small = out[3][0][0]
  check(small and #small == 2 and near(small[1], 6.5) and near(small[2], 2.5), "maxPx drops the bigger cluster")
  local top = out[4][0][0]
  check(top and #top == 2 and near(top[2], 2.5), "a region keeps to its part of the art's box")
  local big = out[5][0][0]
  check(big and #big == 4 and near(big[2], 5.5), "clusters = 1 keeps the largest")
end

-- ------- detect: box points, mirrored for the other side
do
  local cell = {
    "##########",
    "##########",
    "##########",
    "##########",
  }
  local bytes, w = sheet({ { cell }, { cell } }, 10, 4)
  local finder = { box = { left = { { 0.2, 0.5 } }, down = { { 0.5, 0.25 } } } }
  local rows = { [0] = "left", [1] = "right" }
  local out = Sig.detect(bytes, w, 10, 4, 1, 2, { finder }, function(r) return rows[r] end)
  check(near(out[1][0][0][1], 2) and near(out[1][0][0][2], 2), "box: a point on the art's box")
  check(near(out[1][1][0][1], 8), "box: right mirrors left")
  local none = Sig.detect(bytes, w, 10, 4, 1, 1, { finder }, function() return "up" end)
  check(none[1][0][0] == false, "box: a facing with no points emits nothing")
  check(Sig.facingOfRow("hgss", 7) == "left" and Sig.facingOfRow("hgss", 1) == "up", "HGSS frames know their facing")
  check(Sig.facingOfRow("pmd", 1) == "right" and Sig.facingOfRow("pmd", 0, "up") == "up", "PMD rows too (one-row anims by their own)")
end

-- ------- specFor: forms
check(Sig.specFor(25) ~= nil and Sig.specFor("025") ~= nil, "Pikachu has one, by dex or art key")
check(Sig.specFor(1) == nil and Sig.specFor(nil) == nil, "Bulbasaur has none")
check(Sig.specFor("026-alola") ~= nil and Sig.specFor("026-alola") ~= Sig.specFor(26), "Alolan Raichu has its own")
check(Sig.specFor("078-galar") == nil, "Galarian Rapidash does not burn")
check(Sig.specFor("386-attack") == Sig.specFor(386), "a legendary's glow fits every form")

-- ------- every entry is well formed
do
  local kinds = Config.SIGNATURE_FX.kinds
  local bad = {}
  local n = 0
  for key, spec in pairs(Species) do
    n = n + 1
    if not (spec.fx or spec.glow) then bad[#bad + 1] = tostring(key) .. ": nothing" end
    for i, em in ipairs(spec.fx or {}) do
      if not kinds[em.kind] then bad[#bad + 1] = tostring(key) .. ": kind " .. tostring(em.kind) end
      for _, f in ipairs({ em.find, em.pmd, em.hgss }) do
        if f and not (f.box or f.match) then bad[#bad + 1] = tostring(key) .. ": finder " .. i end
      end
      if not (em.find or (em.pmd and em.hgss)) then bad[#bad + 1] = tostring(key) .. ": a style without a finder" end
    end
    if spec.glow and not (spec.glow.rainbow or (spec.glow.colors and #spec.glow.colors > 0)) then
      bad[#bad + 1] = tostring(key) .. ": glow colours"
    end
  end
  check(#bad == 0, "every species entry is well formed (" .. n .. " entries) " .. table.concat(bad, ", "))
  local want = { 4, 5, 6, 25, 26, "026-alola", 172, 77, 78, 81, 82, 92, "105-alola", 109, 110, "110-galar", 126, 146,
    "146-galar", 150, 151, 155, 156, 157, "157-hisui", 170, 171, 250, 249, 245, 244, 243, 324, 333, 334, 380, 381, 382,
    383, 384, 385, 386, 390, 391, 392, 462, 467, 486, 487, 490, 491, 492, 493, 494, 500, 555, 607, 609, 641, 645, 643,
    644, 646, 638, 639, 640, 647, 648, 649, 655, 716, 717, 718, 719, 720, 721, 727, 800, 802, 809, 851, 888, 889, 890,
    905, 910, 911, 935, 936, 937, 1007, 1008, 1014, 1015, 1016, 1017, 1024, 1025 }
  local missing = {}
  for _, k in ipairs(want) do if not Species[k] then missing[#missing + 1] = tostring(k) end end
  check(#missing == 0 and n == #want, "the whole list is there (" .. #want .. ") " .. table.concat(missing, ", "))
end

-- ------- colorAt / offsetAt / glowColor
do
  local colors = { { 1, 1, 0 }, { 1, 0, 0 } }
  local r, g, b = Sig.colorAt(colors, 0)
  check(r == 1 and g == 1 and b == 0, "a new particle is the first colour")
  r, g = Sig.colorAt(colors, 0.5)
  check(near(g, 0.5), "...blending through")
  r, g = Sig.colorAt(colors, 1)
  check(g == 0, "...to the last")
  local p = { life = 20, vx = 0, vy = -0.5, phase = 0, k = 1 }
  local s = { accel = 0.01, sway = 0 }
  local _, y1, f1 = Sig.offsetAt(p, 4, s)
  local _, y2 = Sig.offsetAt(p, 8, s)
  check(y1 < 0 and y2 < y1 and near(f1, 0.2), "a particle rises through its life")
  local gl = { colors = { { 1, 0, 0 }, { 0, 0, 1 } }, cycle = 100, alpha = { 0.2, 0.6 }, pulse = 50 }
  local r0, _, b0, a0 = Sig.glowColor(gl, 0)
  local r1, _, b1, a1 = Sig.glowColor(gl, 50)
  check(near(r0, 1) and near(b0, 0) and near(a0, 0.2), "a glow starts on its first colour, dim")
  check(near(r1, 0, 1e-6) and near(b1, 1) and near(a1, 0.2), "...and blends into the next")
  local _, _, _, am = Sig.glowColor(gl, 25)
  check(near(am, 0.6), "...pulsing up between")
  local rr, rg, rb = Sig.glowColor({ rainbow = true, cycle = 60 }, 20)
  check(rr and rg and rb and rg > rr, "a rainbow glow turns through the hues")
end

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("signature_fx_unit_test: all passed")
