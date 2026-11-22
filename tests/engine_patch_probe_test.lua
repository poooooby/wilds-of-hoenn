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

-- The mod's own wild double (EnginePatch.startWildDouble, lib/wild_double.lua): every piece it
-- wraps or reads is there, and the two places the engine forces a wild battle single are where
-- the wraps expect them (Battle.start builds State.new through the module table).
do
  check(EnginePatch.wildDoubleSupported(), "engine: every piece the mod's own wild double needs")
  local init = io.open("src/core/game3/battle/init.lua"):read("a")
  check(init:find("local double = (opts.double == true) and not opts.wild", 1, true) ~= nil,
    "engine: Battle.start still forces a wild battle single (the State.new wrap turns it double)")
  check(init:find("local st = State.new({", 1, true) ~= nil, "engine: Battle.start calls State.new through its table")
  check(init:find("IntroSeq.begin(st, introOpts)", 1, true) ~= nil, "engine: the intro begins through IntroSeq.begin")
  local ui = io.open("src/core/game3/battle/ui.lua"):read("a")
  check(ui:find("BagMenu.show(bag, {", 1, true) ~= nil and ui:find("onBattleUse = function", 1, true) ~= nil,
    "engine: the battle opens the bag through BagMenu.show with onBattleUse")
  local eng = io.open("src/core/game3/battle/engine.lua"):read("a")
  check(eng:find('ModRuntime.wantsHook("battle.run")', 1, true) ~= nil, "engine: the battle.run hook (running from the double)")
  check(not EnginePatch.wildDoubleActive(), "no double running at rest")
end

-- the mod's own herd battle (EnginePatch.startWildHerd): every piece it wraps or reads, and the
-- singles draw still draws the foe right after its z 0..99 particles (the others go there)
do
  check(EnginePatch.wildHerdSupported(), "engine: every piece the mod's own herd battle needs")
  local ui = io.open("src/core/game3/battle/ui.lua"):read("a")
  local at = ui:find("Anim.drawParticles(0, 99)", 1, true)
  local foe = at and ui:find("draw_mon_sprite(st.enemy, ENEMY_MON, false)", at, true)
  check(foe ~= nil and foe - at < 80,
    "engine: the singles draw puts the foe right after Anim.drawParticles(0, 99) (the herd stands behind it)")
  local intro = io.open("src/core/game3/battle/intro_seq.lua"):read("a")
  check(intro:find('add("msg", { text = intro_msg(st) })', 1, true) ~= nil,
    "engine: the wild intro's line is a msg step with IntroSeq.introText's text")
  -- the leader caught: the others flee (engine_patch whCaught reads these)
  local CS = require("src.core.game3.battle.catch_seq")
  local cs = io.open("src/core/game3/battle/catch_seq.lua"):read("a")
  check(type(CS.catchResult) == "function" and cs:find("CatchSeq._st = st", 1, true) ~= nil
    and cs:find("CatchSeq._caught = caught", 1, true) ~= nil and cs:find("CatchSeq._catchResult = res", 1, true) ~= nil,
    "engine: CatchSeq notes the battle, the catch and its stored result (the herd flees on a catch)")
  local State = require("src.core.game3.battle.state")
  local anim = io.open("src/core/game3/battle/anim.lua"):read("a")
  check(type(State.isFainted) == "function" and State.isFainted({ mon = { hp = 0 } }) and not State.isFainted({ mon = { hp = 5 } })
    and anim:find("p.oy = fromOy + step * 8", 1, true) ~= nil and anim:find("p.visible = false", 1, true) ~= nil,
    "engine: a knocked-out foe reads as fainted and its faint sinks (p.oy) then hides it (the herd flees on a KO)")
  -- the group's boost (WildHerd.addBoostSteps): a "general" intro step plays a named battle
  -- animation, STATS_CHANGE is one, and a battler's stat stages carry the keys WildHerd.boosts names
  local AnimM = require("src.core.game3.battle.anim")
  local Sec = require("src.core.game3.battle.effects.secondary")
  local Ctx = require("src.core.game3.battle.anim_ctx")
  check(intro:find('if kind == "wait" then', 1, true) ~= nil and intro:find("if Anim.busy() or IntroSeq._waitingFade", 1, true) ~= nil
    and type(AnimM.launchGeneral) == "function" and type(Ctx.build) == "function"
    and type(Sec.statAnimArg) == "function" and type(Sec.STAT_ANIM) == "table" and Sec.STAT_ANIM.MULTIPLE_PLUS1 ~= nil
    and io.open("src/core/game3/battle/anim_seq.lua"):read("a"):find("STATS_CHANGE", 1, true) ~= nil,
    "engine: an intro wait holds while an animation runs, and STATS_CHANGE takes the stats' argument (the group's boost)")
  local okB, b = pcall(State.newBattler, { species = 1, level = 5 }, "enemy", {})
  local stg = okB and type(b) == "table" and b.stages
  if not stg then
    local stSrc = io.open("src/core/game3/battle/state.lua"):read("a")
    check(stSrc:find("attack = 0, defense = 0, spAtk = 0, spDef = 0, speed = 0", 1, true) ~= nil,
      "engine: a battler's stat stages are attack / defense / spAtk / spDef / speed (the group's boost)")
  else
    check(stg.attack == 0 and stg.defense == 0 and stg.spAtk == 0 and stg.spDef == 0 and stg.speed == 0,
      "engine: a battler's stat stages are attack / defense / spAtk / spDef / speed (the group's boost)")
  end
  check(not EnginePatch.wildHerdActive(), "no herd battle running at rest")
end

-- Fly Mount (lib/fly_mount.lua; the optional Field.flyTo / FieldEffects.drawFront wraps
-- and EnginePatch.flyAnims / playerRide / flyMoveId): the engine pieces, and the two wraps
-- doing what they must -- the chosen Pokemon noted first; the bird hidden only for the
-- engine's draw call, its own `invisible` back after.
do
  local okFx, FieldEffects = pcall(require, "src.core.game3.field_effects")
  local okF, Field = pcall(require, "src.core.game3.field")
  local okM, FieldMoves = pcall(require, "src.core.game3.field_moves")
  check(okFx and type(FieldEffects.drawFront) == "function", "engine: FieldEffects.drawFront (draws the Fly bird)")
  check(okFx and type(FieldEffects.startFlyOut) == "function" and type(FieldEffects.startFlyIn) == "function",
    "engine: FieldEffects.startFlyOut / startFlyIn")
  check(okFx and type(FieldEffects._anims) == "table", "engine: FieldEffects._anims (the live Fly animations)")
  check(okF and type(Field.flyTo) == "function", "engine: Field.flyTo (gets the Pokemon chosen for Fly)")
  check(okM and type(FieldMoves.MOVES) == "table" and FieldMoves.MOVES.FLY == 19 and EnginePatch.flyMoveId() == 19,
    "engine: FieldMoves.MOVES.FLY = 19")
  local okP, Player = pcall(require, "src.core.game3.player")
  check(okP and Player.spriteXOffset ~= nil and Player.spriteYOffset ~= nil, "engine: Player.spriteXOffset / spriteYOffset")
  if okP then
    local fvSrc = io.open("src/core/game3/field_view.lua"):read("a")
    check(fvSrc:find("PlayerMod.oamPriority", 1, true) and fvSrc:find("PlayerMod.fixedPriority", 1, true)
      and fvSrc:find("PlayerMod.subpriority", 1, true), "engine: field_view reads Player.oamPriority / fixedPriority / subpriority")
    local before = { Player.oamPriority, Player.fixedPriority, Player.subpriority }
    EnginePatch.liftPlayer(true)
    check(Player.oamPriority == 1 and Player.fixedPriority == true and Player.subpriority == 1, "liftPlayer: the rider over everything")
    EnginePatch.liftPlayer(false)
    check(Player.oamPriority == before[1] and Player.fixedPriority == before[2] and Player.subpriority == before[3],
      "liftPlayer(false): put back as it was")
  end
  if okFx and okF then
    local realDraw, realFly = FieldEffects.drawFront, Field.flyTo
    local seen, flown = {}, {}
    FieldEffects.drawFront = function() local a = FieldEffects._anims[#FieldEffects._anims]; seen[#seen + 1] = a.bird.invisible end
    Field.flyTo = function(_, mon) flown[#flown + 1] = "engine:" .. tostring(mon and mon.species) end
    local wrapDraw, wrapFly = FieldEffects.drawFront, Field.flyTo
    local EP = EnginePatch
    EP.uninstall()
    local active = true
    local okI = EP.install({
      flyStarted = function(mon) flown[#flown + 1] = "ours:" .. tostring(mon and mon.species) end,
      flyMountActive = function() return active end,
    }, function() end)
    if okI then
      local bird = { x = 120, y = 72 }
      local anim = { kind = "fly_out", bird = bird }
      table.insert(FieldEffects._anims, anim)
      FieldEffects.drawFront(0, 0)
      check(seen[1] == true and bird.invisible == nil, "drawFront: the bird hidden for the engine's call only")
      local list = {}
      check(EP.flyAnims(list) >= 1 and list[#list] == anim, "flyAnims finds the live Fly animation")
      active = false
      FieldEffects.drawFront(0, 0)
      check(seen[2] == nil, "drawFront: Fly Mount off, the bird drawn as always")
      for i = #FieldEffects._anims, 1, -1 do if FieldEffects._anims[i] == anim then table.remove(FieldEffects._anims, i) end end
      Field.flyTo(1, { species = 18 })
      check(flown[1] == "ours:18" and flown[2] == "engine:18", "flyTo: the chosen Pokemon noted, then the engine's Fly")
      EP.uninstall()
      check(FieldEffects.drawFront == wrapDraw and Field.flyTo == wrapFly, "uninstall restores drawFront / flyTo")
    end
    FieldEffects.drawFront, Field.flyTo = realDraw, realFly
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

-- The VIVID WORLDS entry on the OPTIONS page: Rows.group (wrapped, optional) and the
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

-- Translations (lib/lang/*.lua): every character is one the game's own font can draw
-- (FrlgFont.glyphId: 0 = no glyph, except the space itself). ã / õ are drawn as a / o.
do
  local okF, FrlgFont = pcall(require, "src.ui.game3.frlg_font")
  check(okF and type(FrlgFont.glyphId) == "function", "engine: FrlgFont.glyphId")
  local base = io.open("lib/i18n.lua", "rb") and "lib/" or "mods/wilds_of_hoenn/lib/"
  if okF then
    local skip = { [" "] = true, ["\n"] = true, ["ã"] = true, ["õ"] = true, ["Ã"] = true, ["Õ"] = true }
    for _, code in ipairs({ "ja", "pt", "es", "de" }) do
      local t = assert(loadfile(base .. "lang/" .. code .. ".lua"))()
      local bad = {}
      local function scan(s)
        s = s:gsub("{name}", ""):gsub("|", "") -- placeholders, never drawn
        for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
          if not skip[ch] and FrlgFont.glyphId(ch) == 0 then bad[ch] = true end
        end
      end
      for _, v in pairs(t) do
        if type(v) == "string" then scan(v) else for _, line in ipairs(v) do scan(line) end end
      end
      local list = {}
      for ch in pairs(bad) do list[#list + 1] = ch end
      check(#list == 0, code .. ": every character is in the game's font" .. (#list > 0 and (" (missing: " .. table.concat(list, " ") .. ")") or ""))
    end
  end
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

-- the hour for Wild Ecology's sleepers (EnginePatch.localHour): the game's clock module
do
  local okR, Rtc = pcall(require, "src.core.game3.rtc")
  check(okR and type(Rtc.enabled) == "function" and type(Rtc.calcLocalTime) == "function",
    "rtc.lua has enabled / calcLocalTime (the hour of day for sleepers)")
  local h = EnginePatch.localHour()
  check(h == nil or (h >= 0 and h <= 23), "EnginePatch.localHour answers an hour 0-23 (" .. tostring(h) .. ")")
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
    -- the partner's Poke Ball popping in a swap scene (lib/ball_drop.lua)
    local ballSe = V.require("config").BALL.se
    if not (okT and type(t) == "table" and t[ballSe]) then missingSe[#missingSe + 1] = "ball=" .. tostring(ballSe) end
    check(#missingSe == 0, game .. ": every finisher's sound is in the game's own table ("
      .. (#missingSe == 0 and "all 18 + 3 hit sounds + the ball pop" or table.concat(missingSe, ", ")) .. ")")
  end
end

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("engine_patch_probe_test: all passed")
