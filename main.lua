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
--   options.lua             - Mod Manager option schema
--
-- Gen 1/2-only: this mod installs nothing outside Ruby/Sapphire/Emerald
-- (GameVersion.layout() == "rse"). FireRed/LeafGreen keep their own
-- compat layer and are untouched.
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
  local SpawnManager = V.require("spawn_manager")
  local BattleTrigger = V.require("battle_trigger")
  local FollowerAdapter = V.require("follower_adapter")

  Config.defineOptions(mod)

  mod.exports = mod.exports or {}
  mod.exports.version = "0.1.0"
  mod.exports.engineReady = false

  if not EnginePatch.isRse() then
    mod.log:info("[wilds_of_hoenn] not a Ruby/Sapphire/Emerald boot -- installing nothing")
    return
  end

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
  local followerAdapter = FollowerAdapter.new(mod)

  mod.exports.spawnManager = spawnManager
  mod.exports.battleTrigger = battleTrigger
  mod.exports.followerAdapter = followerAdapter

  local installed = EnginePatch.install({
    collectActors = function(actors)
      spawnManager:collectActors(actors)
    end,
    -- See lib/battle_trigger.lua's header: exceptLocalId == nil is the
    -- signature of the player's OWN collision check (collision.lua:1003
    -- entityBlocks -> Objects.blocks(tx, ty, nil, elevation)); every NPC
    -- movement and trainer-sight caller passes its own localId instead.
    blocks = function(tx, ty, exceptLocalId, _elevation)
      local entity = spawnManager:entityAt(tx, ty)
      if not entity then return false end
      if exceptLocalId == nil and not battleTrigger:isPending() then
        battleTrigger:onPlayerBumped(entity)
      end
      return true
    end,
    followerTick = function(game)
      spawnManager:tick(game)
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
    end)
    if not ok2 then
      mod.log:warn("[wilds_of_hoenn] map.entered error: %s", tostring(err))
    end
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
