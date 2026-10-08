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
-- Gen 3 only: runs on Ruby / Sapphire / Emerald (layout "rse") and FireRed /
-- LeafGreen (layout "frlg") -- they share every game3 module patched here --
-- and installs nothing on any other game (EnginePatch.layoutName() == nil).
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
  local EnginePatch = V.require("engine_patch")
  local SpriteAtlas = V.require("sprite_atlas")
  local SpawnManager = V.require("spawn_manager")
  local BattleTrigger = V.require("battle_trigger")
  local FollowerAdapter = V.require("follower_adapter")
  local PortraitUI = V.require("portrait_ui")
  local FollowerInteraction = V.require("follower_interaction")
  local Companion = V.require("companion")
  local Forager = V.require("forager")
  local ForageSource = V.require("forage_source")
  local OverworldBattle = V.require("overworld_battle")
  local PartyRoles = V.require("party_roles")

  Config.defineOptions(mod)

  -- Pure asset I/O, no engine dependency: safe to try regardless of game
  -- version. A repo checkout or --no-atlas build has no assets/atlas/
  -- index, so this is a normal, silent false everywhere except a release
  -- ZIP built with the atlas (scripts/build-mod.py's default mode).
  local atlasOk, atlasReason = SpriteAtlas.install(mod)
  mod.log:info("[wilds_of_hoenn] sprite atlas: %s", atlasOk and "installed" or tostring(atlasReason))

  mod.exports = mod.exports or {}
  mod.exports.version = "1.4.0"
  mod.exports.engineReady = false

  local layout = EnginePatch.layoutName()
  if not layout then
    mod.log:info("[wilds_of_hoenn] not a Gen 3 boot (Ruby/Sapphire/Emerald/FireRed/LeafGreen) -- installing nothing")
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
  local battleTrigger = BattleTrigger.new(mod, spawnManager, mod.log)
  local companion = Companion.new(mod)
  local partyRoles = PartyRoles.new(companion)
  local followerAdapter = FollowerAdapter.new(mod, companion)
  local portraitUI = PortraitUI.new(mod)
  local followerInteraction = FollowerInteraction.new(mod, portraitUI, {
    isAway = function() return followerAdapter:isRecalled() end, -- shrunk into the player
    adapter = followerAdapter, -- acts the menu choices out (lib/follower_actions.lua)
    companion = companion,
  })

  mod.exports.spawnManager = spawnManager
  mod.exports.battleTrigger = battleTrigger
  mod.exports.followerAdapter = followerAdapter
  mod.exports.portraitUI = portraitUI
  mod.exports.followerInteraction = followerInteraction
  mod.exports.companion = companion

  -- Forage role: wanders on open cells near the player and bags what it finds
  local forageSource = ForageSource.new(mod)
  local forager = Forager.new({
    cellFree = EnginePatch.cellFree,
    occupied = function(x, y) return spawnManager:blocksCell(x, y) end,
    pickItem = function() return forageSource:pick() end,
    playCry = EnginePatch.playCry, -- the cry that tells the player it is foraging
    playFound = EnginePatch.playSuccess,
  })
  followerAdapter.behaviors.forage = forager
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
    occupied = function(x, y) return spawnManager:blocksCell(x, y) end,
    defeat = function(id) spawnManager:despawn(id) end,
    playCry = EnginePatch.playCry,
    rng = math.random,
  })
  followerAdapter.behaviors.battle = battler
  mod.exports.battler = battler

  local installed = EnginePatch.install({
    collectActors = function(actors)
      spawnManager:collectActors(actors)
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
      return true
    end,
    messageDraw = function()
      portraitUI:draw()
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
    followerTick = function(game)
      spawnManager:tick(game)
      followerInteraction:tick(game)
      battleTrigger:checkContact()
      followerAdapter:tick()
    end,
  }, mod.log)

  if not installed then
    mod.log:warn("[wilds_of_hoenn] EnginePatch.install reported failure after a passing probe")
    return
  end

  mod.exports.engineReady = true

  mod.events:on("map.entered", function(ev)
    local ok2, err = pcall(function()
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

  mod.events:on("map.exited", function(_ev)
    pcall(function() spawnManager:onMapExited() end)
  end)

  -- Classic Encounters: suppresses the vanilla step-based land/water roll
  -- while OFF. Fishing (rollFishing) and Rock Smash (rollRocks) never run
  -- through onStep/encounter.roll, so they stay vanilla regardless.
  mod.hooks:wrap("encounter.roll", function(next, tableForMap, ctx)
    if not Config.classicEncEnabled(mod) then return nil end
    return next()
  end)

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
    elseif ev.key == "sprite_style" then
      -- Re-point every already-spawned entity's renderer immediately,
      -- rather than waiting for the next map transition.
      spawnManager:refreshSpriteStyle()
    end
  end)

  return
end
