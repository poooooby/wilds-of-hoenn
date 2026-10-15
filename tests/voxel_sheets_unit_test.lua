-- Run: lua tests/voxel_sheets_unit_test.lua
-- lib/voxel_sheets.lua: the engine-shaped sprite a voxel world mod reads for our art, its
-- composed asset, its geometry, one per art / colour mode / silhouette.
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

local modules = {}
local V = { path = "." }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  local value = assert(loadfile("lib/" .. name .. ".lua"))(V)
  modules[name] = value
  return value
end

love = { image = { newImageData = function() return { clone = function(s) return s end } end } }
local composed = {}
local Assets = { compose = function(path, build) composed[path] = build end, image = function(p) return { path = p } end }
local VS = V.require("voxel_sheets")
eq(VS.cellFor(20), 48, "a small Pokemon: a 48 px cell")
eq(VS.cellFor(1000), VS.MAX_CELL, "a giant one is capped")
eq(VS.cellFor(0), 32, "never under 32")
local sheets = VS.new({
  assets = Assets, poses = { STAND = 1, WALK_A = 2 },
  makeRenderer = function(key, shiny, style) return { dex = key, shiny = shiny, style = style, headLift = function() return 20 end } end,
})
local r = { dex = 25, shiny = false, style = "pokemmo", silhouette = false }
local s = sheets:spriteFor(r, false)
check(s and s.def and s.def.frames == 6 and s.def.walker, "a 6-frame walker def (Gen 1's SpriteRenderer layout)")
eq(s.def.trueColor, true, "colour mode: true colour")
eq(s.def.frameWidth, 48, "...its real frame size (what the adapters size the card by)")
eq(s.def.anchorX, 24, "...centred")
eq(s.def.anchorY, 48, "...feet on the frame's bottom edge")
check(composed[s.def.image] ~= nil, "its sheet is a composed asset")
eq(s:resolveImage().path, s.def.image, "resolveImage loads that asset")
check(sheets:spriteFor(r, false) == s, "one sprite per art")
local l = sheets:spriteFor(r, true)
check(l ~= s and l.def.trueColor == false, "the luminance sheet is its own, not true colour")
r.silhouette = true
check(sheets:spriteFor(r, false) ~= s, "a silhouette is its own sheet")
eq(sheets:spriteFor({ shiny = false }, false), nil, "no art key, no sprite")

-- Species Sizes: the card's display size is the frame times the species' factor
local HGSS = V.require("HGSS_scale")
local HdField = V.require("hd_field")
local pika = sheets:spriteFor({ dex = 25, shiny = false, style = "pokemmo" }, false)
check(math.abs(pika.def.displayWidth - 48 * HGSS[25]) < 1e-9, "Species Sizes: a Pikachu card is its HGSS_scale size")
eq(pika.def.displayHeight, pika.def.displayWidth, "...scaled evenly")
eq(pika.def.frameWidth, 48, "...the sheet itself unscaled")
HdField.setSpeciesSizes(false)
local plain = sheets:spriteFor({ dex = 25, shiny = false, style = "pokemmo" }, false)
check(plain ~= pika and plain.def.displayWidth == nil, "Species Sizes off: the sheet's own size")
eq(plain.def.image, pika.def.image, "...the same baked sheet either way")
HdField.setSpeciesSizes(true)

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("voxel_sheets_unit_test: all passed")
