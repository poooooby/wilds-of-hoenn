-- Checks EnginePatch's probe() against the REAL engine. Run from inside a
-- gen1recomp checkout, with luajit (matches Wilds of Kanto Revival's own
-- two harness tests):
--   cd ../gen1recomp   (or wherever this mod is linked in as mods/wilds_of_hoenn)
--   luajit mods/wilds_of_hoenn/tests/engine_patch_probe_test.lua
--
-- A failure here means an engine update moved one of the fields
-- lib/engine_patch.lua depends on -- fix the TARGETS/READONLY entry (and
-- the code that reads it) before anything else, since every other feature
-- in this mod is built on top of these exact touch points holding still.
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

-- Locate lib/engine_patch.lua whether this test runs from the mod's own
-- repo root or from inside a gen1recomp checkout with the mod linked under
-- mods/wilds_of_hoenn (same two-path probe Wilds' harness tests use).
local function loadEnginePatch()
  for _, rel in ipairs({ "lib/engine_patch.lua", "mods/wilds_of_hoenn/lib/engine_patch.lua" }) do
    local f = io.open(rel, "rb")
    if f then
      f:close()
      return assert(loadfile(rel))()
    end
  end
  error("could not find lib/engine_patch.lua from " .. tostring(io.popen and "cwd"))
end

local EnginePatch = loadEnginePatch()

local ok, missing = EnginePatch.probe()
check(ok, "EnginePatch.probe() passes against the real engine")
if not ok then
  for _, m in ipairs(missing) do
    io.stderr:write("  missing: " .. tostring(m) .. "\n")
  end
end

-- isRse() should at least run without erroring, whichever game is active
-- in this checkout (it may be false if the checkout's default version
-- isn't Ruby/Sapphire/Emerald -- that's not a failure by itself).
local okRse, _ = pcall(EnginePatch.isRse)
check(okRse, "EnginePatch.isRse() runs without error")

-- The reachable area is re-measured only when its fingerprint changes; that reads
-- the engine's object list. If an engine update hides it, spawning still works (a
-- plain timer takes over), but this catches the change.
local okFp, fp = pcall(EnginePatch.reachFingerprint)
check(okFp and type(fp) == "number",
  "reachFingerprint reads the engine's object list (Objects._order / _byId), got " .. tostring(fp))

-- "Ready to evolve!" must never show for a Pokemon holding an Everstone: the label
-- is only set when the REAL engine offers an evolution, and the engine's own
-- rule (pokemon.c GetEvolutionTargetSpecies) refuses one for an Everstone holder.
-- No ROM here, so the species' evolution row is stubbed; the gate is the real code.
do
  local okMods, Pokemon = pcall(require, "src.core.game3.pokemon")
  local okEvo, Evolution = pcall(require, "src.core.game3.evolution")
  if okMods and okEvo and Pokemon and Evolution then
    local real = Pokemon.evolutions
    Pokemon.evolutions = function() return { { method = Evolution.EVO_LEVEL, param = 16, target = 278 } } end
    local ITEM_EVERSTONE = 195
    local mon = { species = 277, level = 30, personality = 1 }
    check((Evolution.targetSpecies(mon, Evolution.EVO_MODE_NORMAL)) == 278, "engine: a Pokemon past its evolution level has a target")
    mon.item = ITEM_EVERSTONE
    check((Evolution.targetSpecies(mon, Evolution.EVO_MODE_NORMAL)) == 0, "engine: holding an Everstone, it has none")
    mon.item = nil
    mon.level = 10
    check((Evolution.targetSpecies(mon, Evolution.EVO_MODE_NORMAL)) == 0, "engine: below the level, none")
    Pokemon.evolutions = real
  end
end

-- Flying Pokemon in the sky (lib/sky_flyers.lua, lib/perch_spots.lua): the engine pieces
-- EnginePatch's sky helpers read. They fail soft (no answer = no birds / no perches), so
-- this is what catches a rename.
do
  local okM, Map = pcall(require, "src.core.game3.map")
  check(okM and type(Map.worldMidAt) == "function", "engine: Map.worldMidAt (perches: a cell's metatile)")
  check(okM and type(Map.currentDef) == "function", "engine: Map.currentDef (sky: map type, cave flag, signs)")
  check(okM and (Map.neighborList == nil or type(Map.neighborList) == "table"), "engine: Map.neighborList (town birds)")
  check(okM and type(Map.loadNeighborsDepth1) == "function", "engine: Map.loadNeighborsDepth1 fills neighborList")
  local okT, NT = pcall(require, "src.core.game3.tileset_native")
  check(okT and type(NT.get) == "function" and type(NT.slotFor) == "function",
    "engine: NativeTileset.get / slotFor (perches: does a metatile draw over actors)")
  local okW, FW = pcall(require, "src.core.game3.field_weather")
  check(okW and type(FW.getWeather) == "function", "engine: FieldWeather.getWeather (fewer birds in rain)")
  local okP, P = pcall(require, "src.core.game3.pokemon")
  check(okP and type(P.types) == "function", "engine: Pokemon.types (which species fly)")
  local okD, D = pcall(require, "src.core.game3.dataset")
  check(okD and type(D.isOutdoorMapType) == "function" and D.isOutdoorMapType(3) and not D.isOutdoorMapType(8),
    "engine: map types 3 = route (outdoor), 8 = indoor, as EnginePatch.skyAllowed reads them")
  -- tileset_native.lua's over-layer blob layout, which EnginePatch.coversActors reads
  local src = io.open("src/core/game3/tileset_native.lua", "rb")
  local text = src and src:read("*a") or ""
  if src then src:close() end
  check(text:find("local base = 13 + midCount * 2", 1, true) ~= nil and text:find("blob:byte(7) + blob:byte(8) * 256", 1, true) ~= nil,
    "engine: the over-layer blob still has a 12-byte header + 2 bytes per metatile + 256 per slot")
  local EP = loadEnginePatch()
  check(type(EP.isFlying) == "function" and type(EP.coversActors) == "function", "mod: the sky helpers exist")
  local okX, Dex = pcall(require, "src.core.game3.pokedex_data")
  check(okX and type(Dex.init) == "function", "engine: PokedexData.init (bird rule: Pokedex height)")
  local hG = EP.heightDm(130) -- internal id 130 = Gyarados (same number as its national one)
  if hG then
    check(hG == 65, "engine data: Gyarados is 6.5 m in the Pokedex (" .. tostring(hG) .. ")")
  else
    print("note: no Pokedex entries in this checkout -- the height rule is not checked")
  end
  -- Taillow (national 276) is Normal / Flying in the engine's own data
  local okI, internal = pcall(P.speciesFromNational, 276)
  if okI and internal then
    check(EP.isFlying(internal), "engine data: Taillow is a Flying type")
  end
end

-- Water reflections and ripples for wild Pokemon and the follower (lib/reflection.lua,
-- EnginePatch.reflectionKind/reflectiveAt/reflectionWobble/coverReflections/
-- ripplesAt/startRipple, and the optional drawBehind wrap): every engine piece they
-- call is still there. They fail soft, so a rename would silently remove the effects;
-- this is what catches it.
do
  local okFx, FieldEffects = pcall(require, "src.core.game3.field_effects")
  check(okFx and type(FieldEffects.drawBehind) == "function", "engine: FieldEffects.drawBehind (reflection hook)")
  check(okFx and type(FieldEffects.startRipple) == "function", "engine: FieldEffects.startRipple")
  check(okFx and type(FieldEffects.rse) == "function", "engine: FieldEffects.rse")
  check(okFx and type(FieldEffects.frlgReflectionType) == "function", "engine: FieldEffects.frlgReflectionType (FRLG)")
  check(okFx and type(FieldEffects.isFrlgReflective) == "function", "engine: FieldEffects.isFrlgReflective (FRLG)")
  local okR, R = pcall(require, "src.core.game3.field_effects_rse")
  check(okR and type(R.reflectionType) == "function", "engine: FxRse.reflectionType (RSE)")
  check(okR and type(R.reflectionScale) == "function", "engine: FxRse.reflectionScale (RSE water wobble)")
  check(okR and type(R.coverWorldRect) == "function", "engine: FxRse.coverWorldRect (RSE)")
  check(okR and type(R.B) == "table" and type(R.B.reflective) == "function" and type(R.B.ripples) == "function",
    "engine: FxRse.B.reflective / ripples (RSE)")
  local okC, Collision = pcall(require, "src.core.game3.collision")
  check(okC and type(Collision.worldBehavior or Collision.behavior) == "function", "engine: Collision.worldBehavior")
  if okR then
    local pa = R.reflectionScale()
    check(type(pa) == "number" and pa > 240 and pa < 272, "engine: the wobble is a width factor near 256 (" .. tostring(pa) .. ")")
  end

  -- the drawBehind wrap: ours runs first, then the engine's; uninstall puts it back
  if okFx then
    local realDraw = FieldEffects.drawBehind
    local order = {}
    FieldEffects.drawBehind = function() order[#order + 1] = "engine" end
    local wrapped = FieldEffects.drawBehind
    local EP = EnginePatch
    EP.uninstall()
    local okI = EP.install({ drawBehind = function() order[#order + 1] = "ours" end }, function() end)
    if okI then
      FieldEffects.drawBehind(0, 0)
      check(order[1] == "ours" and order[2] == "engine", "drawBehind: our reflections first, then the engine's")
      EP.uninstall()
      check(FieldEffects.drawBehind == wrapped, "uninstall restores drawBehind")
    end
    FieldEffects.drawBehind = realDraw
  end
end

-- No wild battle while a cutscene / trainer approach owns the field, and long grass gets
-- its own cover (EnginePatch.fieldBusy / grassCover): the engine pieces they read.
do
  local okF, Field = pcall(require, "src.core.game3.field")
  check(okF and type(Field) == "table" and type(Field.lock) == "function", "engine: Field.lock / Field.locked")
  local okW, Warp = pcall(require, "src.core.game3.warp")
  check(okW and type(Warp.isBusy) == "function", "engine: Warp.isBusy")
  local okS, Space = pcall(require, "src.core.game3.scripting.space")
  check(okS and type(Space) == "table", "engine: scripting.space (Space.vm:isRunning)")
  local okFx, FieldEffects = pcall(require, "src.core.game3.field_effects")
  check(okFx and type(FieldEffects.manifestObject) == "function" and type(FieldEffects.loadSheet) == "function",
    "engine: FieldEffects.manifestObject / loadSheet (long grass cover)")
  local okC, Collision = pcall(require, "src.core.game3.collision")
  check(okC and type(Collision.behavior) == "function", "engine: Collision.behavior")
  local okR, R = pcall(require, "src.core.game3.field_effects_rse")
  check(okR and type(R.B) == "table" and type(R.B.longGrass) == "function", "engine: FxRse.B.longGrass")
  check(type(EnginePatch.fieldBusy()) == "boolean", "EnginePatch.fieldBusy runs on the real engine")
end

-- The WILDS OF HOENN entry on the OPTIONS page: Rows.group (wrapped, optional) and the
-- Mod Manager's own option setter (EnginePatch.setModOption)
do
  local okR, Rows = pcall(require, "src.ui.game3.option_rows")
  check(okR and type(Rows.group) == "function", "engine: option_rows Rows.group (the OPTIONS page)")
  local okM, ManagerState = pcall(require, "src.mods.ManagerState")
  check(okM and type(ManagerState.setOption) == "function", "engine: ManagerState.setOption")
  -- the setter on a stand-in game: stored in both tables, announced, written
  local emitted, wrote = nil, false
  local game = { save = { options = {} }, mods = { modOptions = {}, events = { emit = function(_, name, ev) emitted = { name, ev } end } },
    writeOptions = function() wrote = true end }
  check(EnginePatch.setModOption(game, "wilds_of_hoenn", "spawn_amount", "high") == true, "setModOption runs the real setter")
  check(game.save.options.modOptions.wilds_of_hoenn.spawn_amount == "high", "...stored in the save's options")
  check(game.mods.modOptions.wilds_of_hoenn.spawn_amount == "high", "...and the loader's")
  check(wrote, "...the options file written")
  check(emitted and emitted[1] == "mod.options_changed" and emitted[2].key == "spawn_amount", "...and announced")
end

-- Fly / Teleport put the partner in its ball: the engine's own anim kinds and flags
do
  local src = io.open("src/core/game3/field_effects.lua", "r")
  local text = src and src:read("*a") or ""
  if src then src:close() end
  for _, kind in ipairs({ "fly_out", "fly_in", "teleport_out", "teleport_in" }) do
    check(text:find('kind = "' .. kind .. '"', 1, true) ~= nil, "engine: field_effects anim kind " .. kind)
  end
  check(text:find("P.flyRide = true", 1, true) ~= nil, "engine: Player.flyRide while riding the bird")
  local fsrc = io.open("src/core/game3/field.lua", "r")
  local ftext = fsrc and fsrc:read("*a") or ""
  if fsrc then fsrc:close() end
  check(ftext:find("Field._flyLanding = true", 1, true) ~= nil, "engine: Field._flyLanding while landing")
  local okFx, FieldEffects = pcall(require, "src.core.game3.field_effects")
  check(okFx and type(FieldEffects._anims) == "table", "engine: FieldEffects._anims")
  check(EnginePatch.playerTraveling() == false, "EnginePatch.playerTraveling: false at rest")
  if okFx and type(FieldEffects._anims) == "table" then
    local fake = { kind = "fly_in" }
    table.insert(FieldEffects._anims, fake)
    check(EnginePatch.playerTraveling() == true, "EnginePatch.playerTraveling: true during a fly_in anim")
    for i = #FieldEffects._anims, 1, -1 do
      if FieldEffects._anims[i] == fake then table.remove(FieldEffects._anims, i) end
    end
  end
end

-- Sweet Scent calls visible Pokemon over (the optional Field.finishSweetScent wrap,
-- EnginePatch.sweetScentFail, the evasion -1 on the battle's stage table)
do
  local okF, Field = pcall(require, "src.core.game3.field")
  check(okF and type(Field.finishSweetScent) == "function", "engine: Field.finishSweetScent (Sweet Scent seam)")
  local okT, RomText = pcall(require, "src.core.game3.rom_text")
  check(okT and type(RomText.box) == "function", "engine: RomText.box (Sweet Scent fail text)")
  local okS, State = pcall(require, "src.core.game3.battle.state")
  local src = io.open("src/core/game3/battle/state.lua", "rb")
  local text = src and src:read("*a") or ""
  if src then src:close() end
  check(okS and text:find("evasion = 0", 1, true) ~= nil, "engine: a battler's stages table has `evasion`")
end

-- Arriving / leaving wild Pokemon (lib/spawn_fx.lua): the grass rustle and the ripple
do
  local okFx, FieldEffects = pcall(require, "src.core.game3.field_effects")
  check(okFx and type(FieldEffects.loadSheet) == "function" and type(FieldEffects.startRipple) == "function",
    "engine: FieldEffects.loadSheet / startRipple (spawn rustle and ripple)")
  local okG = pcall(EnginePatch.grassRustle, 3, 3)
  check(okG, "EnginePatch.grassRustle runs on the real engine (no sheet without a ROM: nil)")
end

-- the Battler's knockout sounds (lib/finisher_fx.lua): every SE_* name must exist in each
-- game's own sound table, or that finisher would play silently
do
  local base
  for _, rel in ipairs({ "lib/", "mods/wilds_of_hoenn/lib/" }) do
    local f = io.open(rel .. "finisher_fx.lua", "rb")
    if f then f:close() base = rel break end
  end
  local V = {}
  local cache = { engine_patch = EnginePatch }
  V.require = function(name)
    if cache[name] == nil then cache[name] = assert(loadfile(base .. name .. ".lua"))(V) end
    return cache[name]
  end
  local FinisherFx = V.require("finisher_fx")
  local SE = require("src.core.game3.se_ids")
  for _, game in ipairs({ "firered", "emerald", "ruby" }) do
    local okT, t = pcall(SE.forVersion, game)
    local missingSe = {}
    for kind, r in pairs(FinisherFx.RECIPES) do
      if not (okT and type(t) == "table" and t[r.se]) then missingSe[#missingSe + 1] = kind .. "=" .. tostring(r.se) end
    end
    -- the ordinary hits' sounds (FinisherFx.hitSound), the real battle's own
    for _, eff in ipairs({ 2, 1, 0.5 }) do
      local se = FinisherFx.hitSound(eff)
      if not (okT and type(t) == "table" and t[se]) then missingSe[#missingSe + 1] = "hit=" .. tostring(se) end
    end
    check(#missingSe == 0, game .. ": every finisher's sound is in the game's own table ("
      .. (#missingSe == 0 and "all 18 + 3 hit sounds" or table.concat(missingSe, ", ")) .. ")")
  end
end

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("engine_patch_probe_test: all passed")
