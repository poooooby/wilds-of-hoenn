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

-- the Game Boy player is one 16 px tile, the Gen 3 one 22 px: on Gen 1 / 2 a card is
-- scaled by 16 / 22 so it keeps the same size next to the player; never on Gen 3
local Config = V.require("config")
eq(Config.gbSizeRatio(), 1, "not a Game Boy boot: no player-size ratio")
Config.gbBoot = true
check(math.abs(Config.gbSizeRatio() - 16 / 22) < 1e-9, "a Game Boy boot: 16 / 22")
local gbPika = sheets:spriteFor({ dex = 25, shiny = false, style = "pokemmo" }, false)
check(math.abs(gbPika.def.displayWidth - 48 * HGSS[25] * 16 / 22) < 1e-9,
  "Game Boy: the Pikachu card is its Species Size x 16 / 22")
HdField.setSpeciesSizes(false)
local gbPlain = sheets:spriteFor({ dex = 25, shiny = false, style = "pokemmo" }, false)
check(gbPlain.def.displayWidth == nil, "...Species Sizes off: still the sheet's own size")
HdField.setSpeciesSizes(true)
Config.gbBoot = false
local again = sheets:spriteFor({ dex = 25, shiny = false, style = "pokemmo" }, false)
check(math.abs(again.def.displayWidth - 48 * HGSS[25]) < 1e-9, "back off a Game Boy boot: the plain Species Size")

-- strides: a renderer on its B step gets its own sheet (the walk rows hold stride B), so
-- a sideways walk is stand, A, stand, B instead of a bob between stand and A
local ra = { dex = 7, shiny = false, style = "pokemmo", voxelStride = "a" }
local sa = sheets:spriteFor(ra, false)
check(sheets:spriteFor({ dex = 7, shiny = false, style = "pokemmo" }, false) == sa, "no stride set: the A sheet")
ra.voxelStride = "b"
local sb = sheets:spriteFor(ra, false)
check(sb ~= sa and sb.def.image ~= sa.def.image, "stride B: its own sheet")
check(composed[sb.def.image] ~= nil, "...a composed asset too")
eq(sb.def.frameWidth, sa.def.frameWidth, "...the same cell")
check(sheets:spriteFor(ra, false) == sb, "...one per art")
-- the PMD Walk frame each stride bakes
eq(VS.pmdStrideClock({ 8, 10, 8, 10 }, false), 8, "PMD four-frame Walk: A = its second frame")
eq(VS.pmdStrideClock({ 8, 10, 8, 10 }, true), 26, "...B = its fourth")
eq(VS.pmdStrideClock({ 6, 6, 6, 6, 6, 6 }, false), 6, "another length: A = the first frame change")
eq(VS.pmdStrideClock({ 6, 6, 6, 6, 6, 6 }, true), 18, "...B = half way round the loop")
eq(VS.pmdStrideClock(nil, true), 0, "no Walk timings: frame 0")

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("voxel_sheets_unit_test: all passed")
