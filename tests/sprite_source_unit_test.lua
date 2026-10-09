-- Run: lua tests/sprite_source_unit_test.lua
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

local SpriteSource = assert(loadfile("lib/sprite_source.lua"))(nil)

-- Dex 1 (Bulbasaur): real file, primary folder, both variants present.
-- mod:read's real contract is "file contents or nil" (see lib/config.lua's
-- own use of it for options.lua) -- never a plain boolean.
local mod = {
  read = function(_, rel)
    local f = io.open(rel, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
  end,
}

local p1 = SpriteSource.normalPath(mod, 1)
check(p1 ~= nil and p1:find("true_size18/hgss", 1, true) ~= nil,
  "dex 1 normal resolves to the HGSS / PokeMMO sheet")

-- ------- a release ZIP ships the sheets only as atlas shards (no loose files):
-- they must still resolve, or the HGSS / PokeMMO style draws nothing at all
do
  local modules = {}
  local V2 = { path = "." }
  function V2.require(name)
    if modules[name] ~= nil then return modules[name] end
    local value = assert(loadfile("lib/" .. name .. ".lua"))(V2)
    modules[name] = value
    return value
  end
  local Atlas = V2.require("sprite_atlas")
  local SS = V2.require("sprite_source")
  local dir = "assets/wilds_generated/true_size18/hgss"
  local swim = "assets/wilds_generated/true_size18/swimming"
  local files = {
    ["assets/atlas/index.json"] = '{"version":1,"families":{'
      .. '"hgss18":{"index":"assets/atlas/hgss18.json","dirs":["' .. dir .. '"]},'
      .. '"swimming18":{"index":"assets/atlas/swimming18.json","dirs":["' .. swim .. '"]}}}',
    ["assets/atlas/hgss18.json"] = '{"shards":["hgss18_0.png"],"dirs":{"' .. dir
      .. '":{"252-normal.png":{"shard":0,"x":0,"y":0,"w":24,"h":432}}}}',
    ["assets/atlas/swimming18.json"] = '{"shards":["swimming18_0.png"],"dirs":{"' .. swim
      .. '":{"121-normal.png":{"shard":0,"x":0,"y":0,"w":32,"h":576}}}}',
  }
  local zipMod = { read = function(_, rel) return files[rel] end } -- no loose sheet anywhere
  check(SS.normalPath(zipMod, 252) == nil, "before the atlas is installed, a shard-only sheet does not resolve")
  check(Atlas.install(zipMod), "the atlas installs from its index")
  eq(SS.normalPath(zipMod, 252), dir .. "/252-normal.png", "an atlas-only land sheet resolves")
  eq(SS.pathFor(zipMod, 252, false, "pokemmo", "land"), dir .. "/252-normal.png", "pathFor too")
  eq(SS.normalPath(zipMod, 121, "pokemmo", "swimming"), swim .. "/121-normal.png", "an atlas-only swimming sheet resolves")
  check(SS.normalPath(zipMod, 253) == nil, "a dex the atlas does not cover still resolves to nothing")
  Atlas._reset()
end

-- Kanto's Poke Followers / GSC style and its Pokewilds extension are not part
-- of this mod: nothing resolves into them and the style constant is gone.
eq(SpriteSource.STYLE_FOLLOWERS, nil, "there is no Poke Followers / GSC style any more")
check(p1:find("poke_followers", 1, true) == nil and p1:find("Pokewilds", 1, true) == nil,
  "default art never comes from the Poke Followers / Pokewilds trees")

-- isFloater: the levitates pack is a species REFERENCE only (Zubat 41 is in
-- it, Bulbasaur 1 is not); out-of-range dex never floats.
SpriteSource._resetFloaterCache()
check(SpriteSource.isFloater(mod, 41), "Zubat (41) is a floater")
check(not SpriteSource.isFloater(mod, 6), "Charizard (6) is excluded despite being in the levitates pack")
check(not SpriteSource.isFloater(mod, 1), "Bulbasaur (1) is not a floater")
check(not SpriteSource.isFloater(mod, 0) and not SpriteSource.isFloater(mod, 99999) and not SpriteSource.isFloater(mod, nil),
  "out-of-range dex is never a floater")
local reads = 0
local countingMod = { read = function(_, rel) reads = reads + 1 return mod.read(nil, rel) end }
SpriteSource._resetFloaterCache()
SpriteSource.isFloater(countingMod, 41)
local after1 = reads
SpriteSource.isFloater(countingMod, 41)
eq(reads, after1, "isFloater is memoized per dex")
SpriteSource._resetFloaterCache()

-- water packs carry a baked transparent bottom margin the renderer compensates for
eq(SpriteSource.bottomPadFor("assets/wilds_generated/true_size18/swimming/130-normal.png"), 2, "swimming sheets have a bottom pad")
eq(SpriteSource.bottomPadFor("assets/wilds_generated/true_size18/levitates/006-normal.png"), 2, "levitates sheets have a bottom pad")
eq(SpriteSource.bottomPadFor("assets/wilds_generated/true_size18/hgss/006-normal.png"), 0, "land sheets have none")
eq(SpriteSource.bottomPadFor(nil), 0, "nil path is safe")

-- Dex 252 (Treecko): Hoenn's own starter, HGSS / PokeMMO art.
local p252 = SpriteSource.normalPath(mod, 252)
check(p252 ~= nil and p252:find("true_size18/hgss", 1, true) ~= nil,
  "dex 252 normal resolves to the HGSS / PokeMMO sheet")

-- Dex 700 (Sylveon): beyond Gen 3's native 386, but well within Wilds'
-- own art coverage -- a National Dex expansion mod could legitimately
-- hand this mod that species, so the cap must not have stopped at 386.
local p700Default = SpriteSource.normalPath(mod, 700)
check(p700Default ~= nil and p700Default:find("true_size18/hgss", 1, true) ~= nil,
  "dex 700 (beyond Gen 3's native 386) still resolves by default")
local p700Hgss = SpriteSource.normalPath(mod, 700, SpriteSource.STYLE_POKEMMO)
check(p700Hgss ~= nil and p700Hgss:find("true_size18/hgss", 1, true) ~= nil,
  "dex 700 also resolves under pokemmo")

-- Out-of-range dex numbers resolve to nothing, not a garbage path.
eq(SpriteSource.normalPath(mod, 0), nil, "dex 0 resolves to nothing")
eq(SpriteSource.normalPath(mod, 1026), nil, "dex 1026 (beyond Wilds' own coverage) resolves to nothing")
eq(SpriteSource.normalPath(mod, 999999), nil, "absurd dex resolves to nothing")

-- pathFor: shiny requested and present -> shiny path.
local pShiny = SpriteSource.pathFor(mod, 1, true)
check(pShiny ~= nil and pShiny:find("shiny", 1, true) ~= nil, "pathFor(shiny=true) serves the shiny file")

-- pathFor: shiny requested but genuinely absent for this dex -> falls back
-- to the normal sheet, never a synthesized recolor. Use a fake mod whose
-- `read` reports the shiny file missing but the normal file present.
local fallbackMod = {
  read = function(_, rel)
    if rel:find("shiny", 1, true) then return nil end
    return "present"
  end,
}
local pFallback = SpriteSource.pathFor(fallbackMod, 1, true)
check(pFallback ~= nil and pFallback:find("normal", 1, true) ~= nil,
  "pathFor falls back to normal when no genuine shiny art exists")

-- pathFor: not shiny -> always the normal path regardless of shiny art.
local pNormal = SpriteSource.pathFor(mod, 1, false)
check(pNormal ~= nil and pNormal:find("normal", 1, true) ~= nil, "pathFor(shiny=false) serves normal")

-- ------- HGSS / PokeMMO style ("pokemmo"): a completely different tree,
-- selected explicitly.
local pHgssNormal = SpriteSource.normalPath(mod, 1, SpriteSource.STYLE_POKEMMO)
check(pHgssNormal ~= nil and pHgssNormal:find("true_size18/hgss", 1, true) ~= nil,
  "pokemmo style resolves under true_size18/hgss")
check(pHgssNormal ~= nil and pHgssNormal:find("poke_followers", 1, true) == nil,
  "pokemmo style never falls through to the removed followers tree")

local pHgssShiny = SpriteSource.pathFor(mod, 1, true, SpriteSource.STYLE_POKEMMO)
check(pHgssShiny ~= nil and pHgssShiny:find("true_size18/hgss", 1, true) ~= nil
  and pHgssShiny:find("shiny", 1, true) ~= nil,
  "pokemmo style serves its own shiny file")

-- ------- presentation dimension: land is the default, and swimming /
-- levitates select a different tree entirely. Dex 1 (Bulbasaur) has real
-- baked art in all three true_size18 packs.
local pLand = SpriteSource.normalPath(mod, 1, SpriteSource.STYLE_POKEMMO, SpriteSource.PRESENTATION_LAND)
check(pLand ~= nil and pLand:find("true_size18/hgss", 1, true) ~= nil,
  "land presentation resolves under true_size18/hgss")

local pSwim = SpriteSource.normalPath(mod, 1, SpriteSource.STYLE_POKEMMO, SpriteSource.PRESENTATION_SWIMMING)
check(pSwim ~= nil and pSwim:find("true_size18/swimming", 1, true) ~= nil,
  "swimming presentation resolves under true_size18/swimming")

-- Dex 6 (Charizard): real levitates art, unlike dex 1 which has no
-- levitates pack entry (narrower water coverage than land, by design).
local pLevitate = SpriteSource.normalPath(mod, 6, SpriteSource.STYLE_POKEMMO, SpriteSource.PRESENTATION_LEVITATES)
check(pLevitate ~= nil and pLevitate:find("true_size18/levitates", 1, true) ~= nil,
  "levitates presentation resolves under true_size18/levitates")

-- A nil presentation defaults to land, matching SpriteSource.DEFAULT_PRESENTATION.
local pNoPresentation = SpriteSource.normalPath(mod, 1, SpriteSource.STYLE_POKEMMO)
eq(pNoPresentation, pLand, "no presentation argument behaves exactly like PRESENTATION_LAND")

-- A stale style name (a saved "followers" option from before that style was
-- removed) is not an error: it draws the same HGSS / PokeMMO art, presentation
-- and all.
local pStale = SpriteSource.normalPath(mod, 1, "followers", SpriteSource.PRESENTATION_SWIMMING)
eq(pStale, pSwim, "a stale 'followers' style resolves exactly like HGSS / PokeMMO")

-- A dex with no water-kind art at all falls through to land (narrower
-- water coverage than land is expected).
local pWaterFallback = SpriteSource.normalPath(mod, 1026, SpriteSource.STYLE_POKEMMO, SpriteSource.PRESENTATION_SWIMMING)
eq(pWaterFallback, nil, "a dex beyond Wilds' own coverage resolves to nothing even for water presentation")

-- A nil/unrecognized style defaults to HGSS / PokeMMO, matching
-- SpriteSource.DEFAULT_STYLE -- never a silent empty path.
local pDefaultStyle = SpriteSource.normalPath(mod, 1, nil)
eq(pDefaultStyle, p1, "no style argument behaves exactly like STYLE_POKEMMO")
eq(SpriteSource.DEFAULT_STYLE, SpriteSource.STYLE_POKEMMO, "the renderer's default art style is HGSS / PokeMMO")

-- ------- art keys: a form is "%03d-<form>"; with no art of its own it draws its base
do
  eq(SpriteSource.keyName(413), "413", "a dex number pads to three digits")
  eq(SpriteSource.keyName(7), "007", "...")
  eq(SpriteSource.keyName("413-sandy"), "413-sandy", "a form key is used as is")
  eq(SpriteSource.baseOf("479-heat"), 479, "a form key's base dex")
  eq(SpriteSource.baseOf(25), 25, "a dex number is its own base")
  check(SpriteSource.isForm("479-heat") and not SpriteSource.isForm(479), "isForm tells a key from a number")
  local base = SpriteSource.pathFor(mod, 1, false, nil, nil)
  eq(SpriteSource.pathFor(mod, "001-nosuchform", false, nil, nil), base, "a form with no art falls back to its base sheet")
  eq(SpriteSource.pathFor(mod, "999-x", false, nil, nil), SpriteSource.pathFor(mod, 999, false, nil, nil), "...whichever the base is")
  local info = { walk = { shiny = true } }
  eq(SpriteSource.pmdPath(info, "walk", "479-heat", true), "assets/pmd/walk/479-heat-shiny.png", "PMD form sheets are %03d-<form>")
  eq(SpriteSource.pmdPath(info, "walk", 479, false), "assets/pmd/walk/479-normal.png", "...and base sheets are unchanged")
  eq(SpriteSource.isFloater(mod, "006-nosuch"), SpriteSource.isFloater(mod, 6), "a form floats if its base does")
end

-- ------- portraits of forms: its own sheet when baked, else the base species'
do
  local pm = { read = function(_, rel)
    if rel == "assets/pmd/portraits.json" then
      return '{"version":1,"size":40,"dex":{"25":{"emotions":["Normal"]},"479-heat":{"emotions":["Normal"]}}}'
    end
  end }
  local V3 = { path = "." }
  local mods = {}
  function V3.require(n)
    if mods[n] then return mods[n] end
    if n == "sprite_atlas" then return { installed = function() return false end, has = function() return false end } end
    mods[n] = assert(loadfile("lib/" .. n .. ".lua"))(V3)
    return mods[n]
  end
  local SS = V3.require("sprite_source")
  eq(SS.portraitKey(pm, "479-heat"), "479-heat", "a form with its own portrait uses it")
  eq(SS.portraitKey(pm, "711-small"), 711, "a form without one shows its base species")
  eq(SS.portraitKey(pm, 25), 25, "a base species is unchanged")
  local info = SS.portraitInfo(pm, "479-heat")
  local path = SS.portraitCell(info, "479-heat", false, "Happy")
  eq(path, "assets/pmd/portraits/479-heat-normal.png", "the form's sheet path")
end

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("sprite_source_unit_test: all passed")
