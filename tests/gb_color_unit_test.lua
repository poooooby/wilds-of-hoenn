-- Run: lua tests/gb_color_unit_test.lua
-- lib/gb_color.lua: which colour path a Gen 1 / Gen 2 draw takes, and the three shades
-- the luminance path writes (they must land between the palette-zone pass's thresholds).
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

local shaderSet = {}
love = { graphics = {
  newShader = function() return { lum = true } end,
  getShader = function() return "prev" end,
  setShader = function(s) shaderSet[#shaderSet + 1] = s end,
} }

local GbColor = assert(loadfile("lib/gb_color.lua"))({})

-- the palette-zone pass (PaletteFX shader()): r > 0.83 -> c0, > 0.5 -> c1, > 0.17 -> c2, else c3
local function zone(r)
  if r > 0.83 then return 0 elseif r > 0.5 then return 1 elseif r > 0.17 then return 2 end
  return 3
end
eq(zone(GbColor.shadeOf(1, 1, 1)), 1, "white art is the light shade (never the white key)")
eq(zone(GbColor.shadeOf(0.9, 0.5, 0.2)), 1, "an orange body is light")
eq(zone(GbColor.shadeOf(0.4, 0.3, 0.2)), 2, "a brown is the middle shade")
eq(zone(GbColor.shadeOf(0.05, 0.05, 0.1)), 3, "an outline is the dark shade")

local honors = false
local PaletteFX = { honorsTrueColor = function() return honors end }
PaletteFX.markTrueColor = function(...) PaletteFX.marked = { ... } end
eq(GbColor.mode(1, PaletteFX), "luma", "Gen 1 in a palette mode: luminance")
honors = true
eq(GbColor.mode(1, PaletteFX), "mark", "Gen 1 in a true-colour mode: drawn as is, its rect marked")
eq(GbColor.mode(2, PaletteFX), "raw", "Gen 2: drawn as is")
eq(GbColor.mode(1, nil), "raw", "no PaletteFX: drawn as is")

local ran = 0
GbColor.draw("mark", PaletteFX, function() ran = ran + 1 end, 1, 2, 3, 4)
check(ran == 1 and PaletteFX.marked and PaletteFX.marked[1] == 1 and PaletteFX.marked[4] == 4, "mark: drawn, rect reported")
GbColor.draw("luma", PaletteFX, function() ran = ran + 1 end)
check(ran == 2 and shaderSet[1] and shaderSet[1].lum and shaderSet[2] == "prev", "luma: drawn through the shader, the previous one put back")
local ok = pcall(GbColor.draw, "luma", PaletteFX, function() error("boom") end)
check(not ok and shaderSet[#shaderSet] == "prev", "an error inside still puts the shader back")

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("gb_color_unit_test: all passed")
