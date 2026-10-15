-- Wilds of Hoenn (id: wilds_of_hoenn): visible wild Pokemon for Ruby,
-- Sapphire and Emerald.
--
-- Architecture
--   lib/engine_patch.lua    - the ONLY module touching src/core/game3 (see
--                             its header for why: RSE has no mod seam yet
--                             for a visible overworld actor)
--   lib/config.lua          - option defaults/getters, options.lua loader
--   lib/sprite_source.lua   - national-dex -> walker sheet path (Wilds art)
--   lib/actor_renderer.lua  - true-color 16x96 walker sheet draw
--   lib/encounter_source.lua- per-map eligible cells + wild table presence
--   lib/shiny.lua           - Gen 3 shiny check + Boosted re-roll
--   lib/behavior.lua        - Idle/Roam movement
--   lib/spawn_manager.lua   - entity lifecycle (the mod's core state)
--   lib/battle_trigger.lua  - player-bump -> wild battle, same mon
--   lib/follower_adapter.lua- party follower sprite (public hook, no patch)
--   lib/portrait_ui.lua     - PMDCollab portrait drawn above dialogue messages
--   lib/follower_interaction.lua - face the follower + A: Pet/Play/Talk menu
--   lib/interaction_limiter.lua  - cooldowns, window budget, abuse lock-out for it
--   options.lua             - Mod Manager option schema
--
-- Every generation: Ruby / Sapphire / Emerald (layout "rse") and FireRed /
-- LeafGreen (layout "frlg") share every game3 module patched here; Red / Blue /
-- Yellow ("gen1") and Gold / Silver / Crystal ("gen2") run on other engines, which
-- lib/engine_gb.lua answers for behind the same EnginePatch API (engine_patch.lua
-- hands it out on such a boot). There the core runs -- visible spawns, battles, the
-- follower, both sprite styles -- and the Gen 3-only systems (the sky, Water Life,
-- Local Scenes, Wild Reacts, the companion roles and menus) are not built.
--
-- Fail-safe: if EnginePatch.probe() finds any engine touch point has moved
-- (a gen1recomp update), this mod logs exactly what and installs nothing
-- -- vanilla play is always the fallback, never a crash.

return function(mod)
  local V = { mod = mod, path = mod.path }

  local function chunkFor(rel)
    local source = mod:read(rel)
    if not source then
      error(("wilds_of_hoenn: %s is missing"):format(rel), 0)
    end
    local loadcode = loadstring or load
    local chunk, err = loadcode(source, "@" .. mod.path .. "/" .. rel)
    if not chunk then
      error(("wilds_of_hoenn: %s did not compile: %s"):format(rel, tostring(err)), 0)
    end
    return chunk
  end

  local modules = {}
  function V.require(name)
    local hit = modules[name]
    if hit ~= nil then return hit end
    local value = chunkFor("lib/" .. name .. ".lua")(V)
    modules[name] = value
    return value
  end

  local Config = V.require("config")
  local HdField = V.require("hd_field")
  local EnginePatch = V.require("engine_patch")
  local SpriteAtlas = V.require("sprite_atlas")
  local SpawnManager = V.require("spawn_manager")
  local BattleTrigger = V.require("battle_trigger")
  local FollowerAdapter = V.require("follower_adapter")
  local PortraitUI = V.require("portrait_ui")
  local FollowerInteraction = V.require("follower_interaction")
  local Companion = V.require("companion")
  local LevelReady = V.require("level_ready")
  local Forager = V.require("forager")
  local ForageSource = V.require("forage_source")
  local OverworldBattle = V.require("overworld_battle")
  local PartyRoles = V.require("party_roles")
  local Reflection = V.require("reflection")
  local ModernSpawns = V.require("modern_spawns_bridge")
  local Shiny = V.require("shiny")
  local SkyFlyers = V.require("sky_flyers")
  local WaterLife = V.require("water_life")
  local LocalScenes = V.require("local_scenes")

  -- a Gen 1 / Gen 2 boot (lib/engine_gb.lua): no Gen 3-only options, no Gen 3-only systems
  local gb = EnginePatch.isGb == true
  Config.gbBoot = gb
  Config.defineOptions(mod)

  -- The engine's follower npc is built with the SPRITE_PIKACHU record (PikachuFollower /
  -- gen2/Follower.lua), which Red and Blue do not have (Yellow and Gold do): register a
  -- placeholder -- the player's own sheet -- while the registry is open (load phase).
  -- FollowerAdapter puts our renderer on the npc the first tick it is out.
  if gb and mod.content and mod.content.sprites then
    pcall(function()
      local sprites = mod.content.sprites
      local okGet, have = pcall(sprites.get, sprites, "SPRITE_PIKACHU")
      if okGet and have then return end
      local okRed, red = pcall(sprites.get, sprites, "SPRITE_RED")
      sprites:register("SPRITE_PIKACHU", {
        id = "SPRITE_PIKACHU",
        image = okRed and type(red) == "table" and red.image or "assets/generated/sprites/red.png",
        frames = 6, walker = true,
      })
    end)
  end
  HdField.setSpeciesSizes(Config.get(mod, "species_sizes"))

  -- Pure asset I/O, no engine dependency: safe to try regardless of game
  -- version. A repo checkout or --no-atlas build has no assets/atlas/
  -- index, so this is a normal, silent false everywhere except a release
  -- ZIP built with the atlas (scripts/build-mod.py's default mode).
  local atlasOk, atlasReason = SpriteAtlas.install(mod)
  mod.log:info("[wilds_of_hoenn] sprite atlas: %s", atlasOk and "installed" or tostring(atlasReason))

  mod.exports = mod.exports or {}
  mod.exports.version = "1.8.0-beta.1"
  mod.exports.engineReady = false
  -- Public extension points for consumers; defaults stay unchanged.
  mod.exports.spriteAtlas = SpriteAtlas
  mod.exports.enginePatch = EnginePatch
  mod.exports.hdField = HdField

  local layout = EnginePatch.layoutName()
  if not layout then
    mod.log:info("[wilds_of_hoenn] not a game this mod knows -- installing nothing")
    return
  end
  mod.exports.layout = layout

  local ok, missing = EnginePatch.probe()
  if not ok then
    mod.log:warn("[wilds_of_hoenn] engine probe failed, visible spawns disabled:")
    for _, m in ipairs(missing) do
      mod.log:warn("[wilds_of_hoenn]   missing: %s", m)
    end
    return
  end

  local spawnManager = SpawnManager.new(mod)
  -- the Gen 3-only ambient systems: on a Gen 1 / Gen 2 boot an inert stand-in
  local inert = setmetatable({}, { __index = function() return function() end end })
  -- flying Pokemon in the sky; wild Flying types arrive and leave through it
  local skyFlyers = gb and inert or SkyFlyers.new(mod, {
    occupied = function(x, y) return spawnManager:blocksCell(x, y) end,
  })
  spawnManager.sky = not gb and skyFlyers or nil
  -- fish leaping, whales surfacing (ambient)
  local waterLife = gb and inert or WaterLife.new(mod, {
    occupied = function(x, y) return spawnManager:blocksCell(x, y) end,
  })
  spawnManager.water = not gb and waterLife or nil -- wild fish swim in / out under the sea
  -- little moments in a few places (Lavender's ghosts, Petalburg Woods' bugs, Fortree's Tropius)
  local localScenes = gb and inert or LocalScenes.new(mod)
  local battleTrigger = BattleTrigger.new(mod, spawnManager, mod.log)
  -- a wild Pokemon chasing the player catches up (lib/wild_reactions.lua): the battle
  spawnManager.onContact = function(e) battleTrigger:onChaserContact(e) end
  local companion = Companion.new(mod)
  local partyRoles = PartyRoles.new(companion)
  local followerAdapter = FollowerAdapter.new(mod, companion)
  -- what a levelled-up companion is waiting for ("New move ready!" / "Ready to evolve!")
  local levelReady = LevelReady.new(mod, {
    movesLearnedAt = EnginePatch.movesLearnedAt, knowsMove = EnginePatch.knowsMove,
    evolutionTarget = EnginePatch.evolutionTarget,
  })
  followerAdapter.levelReady = levelReady
  local portraitUI = PortraitUI.new(mod)
  local followerInteraction = FollowerInteraction.new(mod, portraitUI, {
    isAway = function() return followerAdapter:isRecalled() end, -- shrunk into the player
    adapter = followerAdapter, -- acts the menu choices out (lib/follower_actions.lua)
    companion = companion,
    levelReady = levelReady,
  })

  mod.exports.spawnManager = spawnManager
  mod.exports.skyFlyers = skyFlyers
  mod.exports.waterLife = waterLife
  mod.exports.localScenes = localScenes
  mod.exports.battleTrigger = battleTrigger
  mod.exports.followerAdapter = followerAdapter
  mod.exports.portraitUI = portraitUI
  mod.exports.followerInteraction = followerInteraction
  mod.exports.companion = companion
  mod.exports.levelReady = levelReady

  -- Forage role: wanders on open cells near the player and bags what it finds
  local forageSource = ForageSource.new(mod)
  local forager = Forager.new({
    cellFree = EnginePatch.cellFree,
    occupied = function(x, y) return spawnManager:blocksCell(x, y) end,
    -- the find is rolled before it sets out (so a trip never comes back empty)
    -- and only bagged once it has dug it up
    rollItem = function(friendship) return forageSource:roll(friendship) end,
    commitItem = function(rolled) return forageSource:commit(rolled) end,
    elevation = EnginePatch.playerElevation,
    playCry = EnginePatch.playCry, -- the cry that tells the player it is foraging
    playFound = EnginePatch.playSuccess,
  })
  followerAdapter.behaviors.forage = forager
  mod.exports.forageSource = forageSource -- what it can find (tests and tools)
  mod.exports.forager = forager

  -- Battle role: charges wild overworld Pokemon near the player, real moves / PP
  local battler = OverworldBattle.new({
    combat = {
      battlerOf = EnginePatch.battlerOf, moveRow = EnginePatch.moveRow,
      moveDamage = EnginePatch.moveDamage, moveNumber = EnginePatch.moveNumber,
      expGain = EnginePatch.expGain, expApply = EnginePatch.expApply,
      buildWild = EnginePatch.buildWildFighter, rng = math.random,
    },
    targets = function() return spawnManager:fightTargets() end,
    alive = function(e) return spawnManager:get(e.id) == e end,
    cellFree = EnginePatch.cellFree,
    swimFree = EnginePatch.waterFree,
    occupied = function(x, y) return spawnManager:blocksCell(x, y) end,
    defeat = function(id) spawnManager:despawn(id) end,
    chainRecord = ModernSpawns.chainRecord,
    playCry = EnginePatch.playCry,
    levelUp = function(mon, from, to) levelReady:record(mon, from, to) end,
    expFrozen = function(mon) return levelReady:pending(mon) ~= nil end,
    rng = math.random,
  })
  followerAdapter.behaviors.battle = battler
  mod.exports.battler = battler

  local installed = EnginePatch.install({
    collectActors = function(actors, camX, camY)
      spawnManager:collectActors(actors, camX, camY)
      skyFlyers:collectActors(actors, camX, camY)
      waterLife:collectActors(actors, camX, camY)
      localScenes:collectActors(actors, camX, camY)
      followerAdapter:collectActors(actors)
    end,
    -- See lib/battle_trigger.lua's header: exceptLocalId == nil is the
    -- signature of the player's OWN collision check (collision.lua:1003
    -- entityBlocks -> Objects.blocks(tx, ty, nil, elevation)); every NPC
    -- movement and trainer-sight caller passes its own localId instead.
    -- BUT a roaming wild Pokemon's own candidate-step check also reaches
    -- here with exceptLocalId == nil (it goes through the exact same
    -- entityBlocks path via EnginePatch.canEnter -> real Collision.canEnter
    -- -- see lib/engine_patch.lua's canEnter comment) -- without the
    -- isProbingCanEnter() guard, a wild Pokemon merely considering a step
    -- onto the player's tile (needs no player movement at all) would start
    -- a battle on its own. Still answers "occupied" (returns true) either
    -- way, so the wild Pokemon correctly treats the player's tile as blocked.
    blocks = function(tx, ty, exceptLocalId, _elevation)
      local entity = spawnManager:entityAt(tx, ty)
      if not entity then return false end
      -- The player's OWN check: let them step onto the wild Pokemon. The
      -- battle starts once that step lands (battleTrigger:checkContact in
      -- followerTick), never from the adjacent tile. Our own roaming
      -- probe also arrives with exceptLocalId == nil but is still blocked.
      if exceptLocalId == nil and not EnginePatch.isProbingCanEnter() then
        return false
      end
      -- a cutscene / trainer approach moving its characters (exceptLocalId = theirs):
      -- a wild Pokemon in the way must never hold the script up
      if exceptLocalId ~= nil and EnginePatch.fieldBusy() then return false end
      return true
    end,
    messageDraw = function()
      portraitUI:draw()
    end,
    -- water reflections of the wild Pokemon and the follower (lib/reflection.lua),
    -- drawn just before the engine's own reflections of the player and NPCs
    drawBehind = function(camX, camY)
      local list = {}
      spawnManager:reflections(list, camX, camY)
      followerAdapter:reflections(list)
      if #list > 0 then Reflection.drawAll(list, camX, camY) end
    end,
    -- Runs BEFORE the engine's A-button handler: facing your follower and
    -- pressing A opens its Pet / Play / Talk menu instead (true = handled).
    interact = function(game)
      return followerInteraction:tryStart(game)
    end,
    -- the ROLE row in the party menu (lib/party_roles.lua)
    partyMenuUpdate = function(menu)
      partyRoles:onMenuUpdate(menu)
    end,
    -- A / B in the party menu's ROLE submenu (lib/party_roles.lua); true = consumed
    partyMenuInput = function(menu, input)
      return partyRoles:onInput(menu, input)
    end,
    fromMenu = function(label, ctx)
      return partyRoles:fromMenu(label, ctx)
    end,
    -- Sweet Scent used in the field: with the visible spawns on, it calls wild Pokemon
    -- over (SpawnManager:sweetScent) instead of the engine's instant battle; nothing
    -- nearby -> the engine's own "nothing here" text. false -> the engine's Sweet Scent.
    sweetScent = function(payload)
      local came = spawnManager:sweetScent()
      if came == nil then return false end
      if came == 0 then EnginePatch.sweetScentFail(payload) end
      return true
    end,
    followerTick = function(game)
      spawnManager:tick(game)
      skyFlyers:tick()
      waterLife:tick()
      localScenes:tick()
      if not gb then followerInteraction:tick(game) end
      battleTrigger:tick()
      battleTrigger:checkContact()
      followerAdapter:tick()
    end,
  }, mod.log)

  if not installed then
    mod.log:warn("[wilds_of_hoenn] EnginePatch.install reported failure after a passing probe")
    return
  end

  mod.exports.engineReady = true

  if gb then
    -- a voxel world mod (TERRARIUM, Potato Voxel, Dramaless, Stadium2) draws the world from
    -- engine sprites: our Pokemon go in as sheets baked from their own art
    -- (lib/voxel_sheets.lua), on cards of their own size (lib/compat/: Wilds of Kanto
    -- Revival's adapters, one per provider, over one shared SpriteBillboards wrap)
    local VoxelSheets = V.require("voxel_sheets")
    local ActorRenderer = V.require("actor_renderer")
    local SpriteSource = V.require("sprite_source")
    local okAssets, Assets = pcall(require, "src.render.Assets")
    EnginePatch.voxelSheets = VoxelSheets.new({
      assets = okAssets and Assets or nil,
      poses = { STAND = ActorRenderer.POSE_STAND, WALK_A = ActorRenderer.POSE_WALK_A },
      makeRenderer = function(key, shiny, style)
        return V.require("renderer_factory").new(mod, key, shiny, style, SpriteSource.PRESENTATION_LAND)
      end,
    })
    local VOXEL_ADAPTERS = {
      "compat/terrarium_variable_geometry", "compat/potato_voxel_variable_geometry",
      "compat/dramaless_variable_geometry", "compat/stadium2_variable_geometry",
    }
    -- each adapter installs only when its provider is loaded (absent -> nothing)
    local function voxelAdapters()
      for _, name in ipairs(VOXEL_ADAPTERS) do
        pcall(function() V.require(name).install(mod) end)
      end
    end
    mod.events:on("mods.loaded", voxelAdapters)
    mod.events:on("game.ready", voxelAdapters)

    -- Gen 1 / Gen 2 collision is a public hook: a wild Pokemon blocks NPCs, never the
    -- player stepping onto it (lib/engine_gb.lua collisionVerdict)
    mod.hooks:wrap("movement.collision", function(next, allowed, ctx)
      local base = next(allowed, ctx)
      local ok, out = pcall(EnginePatch.collisionVerdict, base, ctx, function(x, y)
        return spawnManager:entityAt(x, y)
      end)
      if ok then return out end
      return base
    end)
    -- the field's battle state (Gen 3 reads it off the engine)
    mod.events:on("battle.started", function() EnginePatch.noteBattle(true) end)
    mod.events:on("battle.ended", function() EnginePatch.noteBattle(false) end)
  end

  mod.events:on("map.entered", function(ev)
    local ok2, err = pcall(function()
      -- Gen 1 / Gen 2: the world that loaded this map, before the spawns read it
      if EnginePatch.noteMap then EnginePatch.noteMap(mod.world and mod.world.game, ev and ev.map) end
      skyFlyers:onMapEntered(ev and ev.mapId)
      waterLife:onMapEntered(ev and ev.mapId)
      localScenes:onMapEntered(ev and ev.mapId)
      spawnManager:onMapEntered(ev and ev.mapId, mod.world and mod.world.game)
      followerAdapter:mapChanged()
    end)
    if not ok2 then
      mod.log:warn("[wilds_of_hoenn] map.entered error: %s", tostring(err))
    end
  end)

  -- The interaction limiter's saved state is per playthrough: re-read it
  -- whenever a different save/checkpoint becomes current.
  for _, eventName in ipairs({ "save.loaded", "save.created", "checkpoint.restored" }) do
    mod.events:on(eventName, function()
      pcall(function() followerInteraction:onSaveChanged() end)
      pcall(function() companion:reset() end)
      pcall(function() levelReady:reset() end)
      pcall(function() forageSource:reset() end)
      pcall(function() followerAdapter:resetBehaviors() end)
      pcall(function() followerAdapter:resetDisplay() end)
    end)
  end

  -- A finished step is the contact signal (see lib/battle_trigger.lua): walking
  -- through a wild Pokemon with the direction held must still battle it.
  mod.events:on("world.stepped", function(ev)
    pcall(function()
      battleTrigger:onPlayerStepped(ev and ev.x, ev and ev.y)
    end)
  end)

  -- a battle with a wild Pokemon Sweet Scent called over: its evasion starts lowered
  -- (Config.SWEET_SCENT.evasion, -1 = 75%), as the in-battle move would leave it
  mod.events:on("battle.started", function(_ev)
    pcall(function()
      if battleTrigger.pendingLured then
        battleTrigger.pendingLured = false
        EnginePatch.setFoeStage("evasion", Config.SWEET_SCENT.evasion)
      end
    end)
  end)

  mod.events:on("map.exited", function(_ev)
    pcall(function() spawnManager:onMapExited() end)
    pcall(function() skyFlyers:onMapExited() end)
    pcall(function() waterLife:onMapExited() end)
    pcall(function() localScenes:onMapExited() end)
  end)

  -- Lavender Town's "Do you believe in ghosts?": her reply to a "No" (its text key) may
  -- bring a Gengar up behind the player (lib/local_scenes.lua), gone once she has finished.
  if not gb then
    mod.hooks:wrap("script.command", function(next, _ctx, op, row)
      if op == "loadword" and type(row) == "table" and type(row.value) == "string" then
        pcall(function() localScenes:onScriptText(row.value) end)
      end
      return next()
    end)
    mod.events:on("script.ended", function(_ev)
      pcall(function() localScenes:onScriptEnded() end)
    end)
  end

  -- Classic Encounters: suppresses the vanilla step-based land/water roll
  -- while OFF. Fishing (rollFishing) and Rock Smash (rollRocks) never run
  -- through onStep/encounter.roll, so they stay vanilla regardless.
  mod.hooks:wrap("encounter.roll", function(next, tableForMap, ctx)
    if not Config.classicEncEnabled(mod) then return nil end
    return next()
  end)

  -- Shiny chains on classic step encounters: Modern Spawns (priority -100) has
  -- already counted the chain and maybe swapped in the chained species; this
  -- runs after it and makes the encounter shiny / gives it perfect stats (a Gen 3
  -- shiny is this mod's job, lib/shiny.lua). Nothing without Modern Spawns.
  if not gb then mod.hooks:wrap("encounter.species", function(next, _enc, _ctx)
    local out = next()
    if type(out) ~= "table" then return out end
    local species = tonumber(out.speciesId) or tonumber(out.species)
    local bonus = species and ModernSpawns.chainBonus(species)
    if not bonus then return out end
    -- FireRed / LeafGreen roll no personality: draw it now so it can be made shiny
    if out.personality == nil then out.personality = EnginePatch.randomPersonality() end
    local probe = { species = species, personality = out.personality, ivs = out.ivs }
    Shiny.rollForEncounter(probe, bonus)
    out.personality, out.ivs = probe.personality, probe.ivs
    return out
  end) end

  -- Party follower: the engine's public seam, no patching needed.
  mod.hooks:wrap("world.follower.spawn", function(_next, _game, _world)
    return followerAdapter:shouldSpawn()
  end)

  mod.events:on("mod.options_changed", function(ev)
    if not (ev and ev.mod == mod.id) then return end
    if ev.key == "enabled" then
      local current = mod.world and mod.world:current()
      local mapId = current and current.mapId
      if ev.value == true and mapId then
        spawnManager:onMapEntered(mapId, mod.world and mod.world.game)
      elseif ev.value ~= true then
        spawnManager:onMapExited()
      end
    elseif ev.key == "spawn_amount" then
      -- raised: refill tops up on the next tick; lowered: the extras go now
      pcall(function() spawnManager:trimToAmount() end)
    elseif ev.key == "flyers" then
      local current = mod.world and mod.world:current()
      pcall(function() skyFlyers:onOptionChanged(current and current.mapId) end)
    elseif ev.key == "water_life" then
      local current = mod.world and mod.world:current()
      pcall(function() waterLife:onOptionChanged(current and current.mapId) end)
    elseif ev.key == "local_scenes" then
      local current = mod.world and mod.world:current()
      pcall(function() localScenes:onOptionChanged(current and current.mapId) end)
    elseif ev.key == "wild_reacts" then
      if ev.value == false then pcall(function() spawnManager:calmReactions() end) end
    elseif ev.key == "species_sizes" then
      HdField.setSpeciesSizes(ev.value)
    elseif ev.key == "sprite_style" then
      -- Re-point every already-spawned entity's renderer immediately,
      -- rather than waiting for the next map transition.
      spawnManager:refreshSpriteStyle()
      skyFlyers:clear() -- the ambient birds come back in the new style
      waterLife:clear()
      localScenes:clear()
    end
  end)

  return
end
