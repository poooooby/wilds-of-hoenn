-- Run: lua tests/hd_field_unit_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
local failures = 0
local function check(cond, msg)
  if not cond then failures = failures + 1; io.stderr:write("FAIL: " .. tostring(msg) .. "\n") else print("ok  " .. tostring(msg)) end
end
local function near(a, b) return math.abs(a - b) < 1e-9 end

local modules = {}
local V = { path = "." }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  modules[name] = assert(loadfile("lib/" .. name .. ".lua"))(V)
  return modules[name]
end
local HdField = V.require("hd_field")
local PMD_TABLE = V.require("PMD_scale")
local pinned = { [143] = PMD_TABLE[143], [150] = PMD_TABLE[150] }
PMD_TABLE[143], PMD_TABLE[150] = 1.0, 1.0 -- the real file is hand-tuned; these tests need a known start
local SpeciesScale = V.require("HGSS_scale")

local HGSS = "assets/wilds_generated/true_size18/hgss/%s-normal.png"
local PMD = "assets/pmd/walk/%s-normal.png"

-- no library: nothing is tagged, nothing breaks
local plainMod = { find = function() return nil end }
check(HdField.tag(plainMod, {}, HGSS:format("006")) == false, "without gen3-hd-sprites a sheet is left alone")
check(HdField.tag(nil, {}) == false, "...and without a mod table")
check(HdField.scaleOfPath(plainMod, HGSS:format("006")) == 1, "...and everything is drawn at 1")
check(HdField.active(plainMod) == false, "...the library is not active")

-- with the library
local tagged = {}
local fieldOn = true
local lib = { exports = {
  tag = function(img, spec) tagged[#tagged + 1] = { img = img, spec = spec } end,
  isActive = function() return true end,
  enabled = function(pass) return pass ~= "field" or fieldOn end,
} }
local mod = { find = function(_, id) return id == "gen3-hd-sprites" and lib or nil end }
HdField.setSize("100")
HdField.setSpeciesSizes(true)

local charmander, charizard, snorlaxPmd, rotom = {}, {}, {}, {}
check(HdField.tag(mod, charmander, HGSS:format("004")) and HdField.tag(mod, charizard, HGSS:format("006")),
  "sheets are tagged when the library is there")
check(tagged[1].spec ~= tagged[2].spec, "...each with its own spec (one species, one size)")
check(tagged[1].spec.anchor == "feet", "...anchored at the feet")
check(near(tagged[1].spec.scale, SpeciesScale[4]), "an HGSS sheet is sized by its species (Charmander " .. SpeciesScale[4] .. ")")
check(near(tagged[2].spec.scale, SpeciesScale[6]), "...Charizard " .. SpeciesScale[6])
check(tagged[1].spec.scale ~= tagged[2].spec.scale, "...so two species are different sizes")

HdField.tag(mod, snorlaxPmd, PMD:format("143"))
check(tagged[3].spec.scale == 1, "a PMDCollab sheet keeps its own size")

HdField.tag(mod, rotom, "assets/wilds_generated/true_size18/hgss/479-heat-normal.png")
check(near(tagged[4].spec.scale, SpeciesScale[479]), "a form is sized like its base species")
local swim = {}
HdField.tag(mod, swim, "assets/wilds_generated/true_size18/swimming/130-shiny.png")
check(near(tagged[5].spec.scale, SpeciesScale[130]), "water sheets are sized by species too")

-- Overworld Size multiplies on top, and loaded sheets follow
check(HdField.setSize("50") == 0.5, "Overworld Size 50% -> 0.5")
check(near(tagged[2].spec.scale, SpeciesScale[6] * 0.5), "...times the species size on a loaded sheet")
check(near(tagged[3].spec.scale, 0.5), "...and alone on a PMDCollab sheet")
check(HdField.setSize("100") == 1, "100% -> 1")
check(HdField.setSize(nil) == 1 and HdField.setSize("junk") == 1, "a bad value is 100%")
check(HdField.setSize("10") == 0.25, "clamped to at least 25%")
HdField.setSize("100")

-- Species Sizes off: every sheet is back to the global size only
HdField.setSpeciesSizes(false)
check(tagged[1].spec.scale == 1 and tagged[2].spec.scale == 1, "Species Sizes off -> sheets already loaded go back to 1")
local late = {}
HdField.tag(mod, late, HGSS:format("143"))
check(tagged[#tagged].spec.scale == 1, "...and sheets loaded afterwards too")
HdField.setSpeciesSizes(true)
check(near(tagged[1].spec.scale, SpeciesScale[4]), "...back on again")

-- what spacing a follower by its width must use
check(near(HdField.scaleOfPath(mod, HGSS:format("006")), SpeciesScale[6]), "the drawn size of a sheet while the library draws the field")
fieldOn = false
check(HdField.scaleOfPath(mod, HGSS:format("006")) == 1, "...is 1 when the library's Field HD is off")
fieldOn = true

-- ------- the two tables are the tuning files: editing one changes that style only
do
  local HG, PM = V.require("HGSS_scale"), V.require("PMD_scale")
  HdField.setSize("100") HdField.setSpeciesSizes(true)
  local sheet, formSheet, pmdSheet = {}, {}, {}
  HdField.tag(mod, sheet, HGSS:format("006"))
  HdField.tag(mod, formSheet, "assets/wilds_generated/true_size18/hgss/479-heat-normal.png")
  HdField.tag(mod, pmdSheet, PMD:format("150"))
  local function specOf(img) for i = #tagged, 1, -1 do if tagged[i].img == img then return tagged[i].spec end end end
  local was6, was479 = HG[6], HG[479]
  check(near(specOf(sheet).scale, was6), "before tuning: the table's size")
  HG[6] = 0.5
  HdField.setSpeciesSizes(true) -- re-reads the tables
  check(near(specOf(sheet).scale, 0.5), "editing HGSS_scale re-sizes the sheets already loaded")
  check(near(specOf(formSheet).scale, SpeciesScale[479]), "...other species are unaffected")
  HG["479-heat"] = 0.9
  HdField.setSpeciesSizes(true)
  check(near(specOf(formSheet).scale, 0.9), "a form key tunes one form on its own")
  HG[479] = 0.7
  HdField.setSpeciesSizes(true)
  check(near(specOf(formSheet).scale, 0.9), "...and wins over its base species' tuning")
  check(near(HdField.scaleOfPath(mod, HGSS:format("479")), 0.7), "...which still sizes the base species")
  check(specOf(pmdSheet).scale == 1, "PMD sheets start at 1 (PMD_scale)")
  PM[150] = 0.85
  HdField.setSpeciesSizes(true)
  check(near(specOf(pmdSheet).scale, 0.85), "editing PMD_scale sizes a PMDCollab sheet")
  check(near(HdField.scaleOfPath(mod, PMD:format("150")), 0.85), "...and the size spacing goes by")
  check(near(specOf(sheet).scale, 0.5), "...without touching the hgss one")
  HdField.setSize("50")
  check(near(specOf(pmdSheet).scale, 0.425), "Overworld Size multiplies with an edited size")
  HdField.setSpeciesSizes(false)
  check(specOf(pmdSheet).scale == 0.5 and specOf(sheet).scale == 0.5, "Species Sizes off ignores both tables")
  HG[6], HG["479-heat"], HG[479], PM[150] = was6, nil, was479, 1.0
  HdField.setSize("100") HdField.setSpeciesSizes(true)
end

-- ------- a PMD sheet scales about its ground point; HGSS about its feet
do
  local indexJson = '{"version":1,"directions":["down","right","up","left"],"gutter":2,"dex":{"150":{"walk":{"cw":40,"ch":44,"cols":4,"ax":19.5,"ay":35.5,"durations":[4,4,4,4],"shiny":true},"idle":{"cw":40,"ch":44,"cols":4,"ax":20.5,"ay":36.5,"durations":[4,4,4,4],"shiny":true}}}}'
  local pmod = { find = mod.find, read = function(_, rel) if rel == "assets/pmd/index.json" then return indexJson end end }
  local walk, idle, hgss, portrait = {}, {}, {}, {}
  HdField.tag(pmod, walk, PMD:format("150"))
  HdField.tag(pmod, idle, "assets/pmd/idle/150-shiny.png")
  HdField.tag(pmod, hgss, HGSS:format("150"))
  local function specOf(img) for i = #tagged, 1, -1 do if tagged[i].img == img then return tagged[i].spec end end end
  check(specOf(walk).lowPivot and specOf(walk).lowPivot[1] == 19.5 and specOf(walk).lowPivot[2] == 35.5, "a PMD walk sheet pivots on its baked ground point")
  check(specOf(idle).lowPivot and specOf(idle).lowPivot[2] == 36.5, "...each animation on its own")
  check(specOf(walk).anchor == nil, "...not on the bottom of its cell")
  check(specOf(hgss).anchor == "feet" and specOf(hgss).lowPivot == nil, "an HGSS sheet still scales about its feet")
  check(HdField.tag(pmod, portrait, "assets/pmd/portraits/150-normal.png") == false and specOf(portrait) == nil,
    "a portrait sheet is never tagged")
  check(HdField.tag(pmod, {}, "assets/atlas/whatever.png") == false, "...nor any other image")
  local info = HdField.parse("assets/wilds_generated/true_size18/levitates/718-10-shiny.png")
  check(info and info.style == "hgss" and info.key == "718-10" and info.dex == 718, "a numeric form name parses")
  info = HdField.parse("assets/pmd/attack/741-pom_pom-normal.png")
  check(info and info.style == "pmd" and info.key == "741-pom_pom" and info.anim == "attack", "a PMD form sheet parses")
end

-- the table itself
local n, lo, hi = 0, 9, 0
for dex = 1, 1025 do
  local s = SpeciesScale[dex]
  if type(s) ~= "number" then check(false, "species " .. dex .. " has a size") end
  if type(s) == "number" then n = n + 1 lo, hi = math.min(lo, s), math.max(hi, s) end
end
check(n == 1025, "all 1025 species have a size")
check(lo >= 0.4 and hi <= 1.2 + 1e-9, "sizes stay within 0.4x to 1.2x (" .. lo .. " to " .. hi .. ")")

PMD_TABLE[143], PMD_TABLE[150] = pinned[143], pinned[150]
if failures > 0 then io.stderr:write(failures .. " failure(s)\n") os.exit(1) end
print("hd_field_unit_test: all passed")
