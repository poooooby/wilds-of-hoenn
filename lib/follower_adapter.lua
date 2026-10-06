-- Party follower sprite: the engine's own single-follower seam already
-- supports this with no patching. main.lua wires FOLLOWERS up via the
-- public `world.follower.spawn` hook (mod.hooks:wrap); this module only
-- answers "should one be visible right now" and keeps its sprite in sync
-- with the current party lead, reusing the same walker art as wild spawns.
local V = ...
local Config = V.require("config")
local EnginePatch = V.require("engine_patch")
local ActorRenderer = V.require("actor_renderer")

local FollowerAdapter = {}
FollowerAdapter.__index = FollowerAdapter

function FollowerAdapter.new(mod)
  return setmetatable({ mod = mod, leadSpecies = nil, renderer = nil }, FollowerAdapter)
end

--- The callback passed to mod.hooks:wrap("world.follower.spawn", ...).
function FollowerAdapter:shouldSpawn()
  return Config.followerEnabled(self.mod)
end

--- Called every field tick, after the engine's own Follower.update has run
--- (engine_patch's `followerTick` hook) -- keeps npc.sprite pointed at a
--- renderer for the CURRENT party lead, rebuilding it only when the lead
--- species actually changes (a swap in the party menu, not every tick).
function FollowerAdapter:tick()
  local npc = EnginePatch.followerCurrent()
  if not npc then
    self.leadSpecies = nil
    return
  end
  local species = EnginePatch.leadPartySpecies()
  if species == self.leadSpecies and npc.sprite == self.renderer then return end
  self.leadSpecies = species
  local dex = species and EnginePatch.nationalFor(species) or nil
  if not dex then
    self.renderer = nil
    npc.sprite = nil
    return
  end
  self.renderer = ActorRenderer.new(self.mod, dex, false)
  npc.sprite = self.renderer
end

return FollowerAdapter
