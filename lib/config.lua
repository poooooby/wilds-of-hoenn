-- Tunables and option helpers for wilds_of_hoenn.
local V = ...

local Config = {}

Config.DEFAULTS = {
  enabled = true,
  sprite_style = "followers",
  classic_enc = true,
  wild_silhouettes = "off",
  shiny_rate = "vanilla",
  follower = true,
}

Config.STATE = {
  AVAILABLE = "available",
  ENCOUNTER_STARTING = "encounter_starting",
  DESPAWNED = "despawned",
}

-- Density: fixed in v1 (no "Spawn Amount" option -- see
-- docs/ARCHITECTURE.md's "what v1 deliberately leaves out").
Config.MIN_VISIBLE = 1
Config.MAX_VISIBLE = 8
Config.TILES_PER_ADDITIONAL = 20

--- Reads and compiles options.lua fresh (not cached -- this only runs once
--- at boot) and hands the schema table to the Mod Manager. Same pattern as
--- Wilds of Kanto Revival's lib/config.lua: the manifest's
--- "options_schema" field is a hint for external tooling, not something
--- the engine auto-registers for a mod -- the mod must call
--- mod.options:define itself.
function Config.defineOptions(mod)
  local source = mod:read("options.lua")
  if not source then
    error("wilds_of_hoenn: options.lua is missing", 0)
  end
  local loadcode = loadstring or load
  local chunk, err = loadcode(source, "@" .. mod.path .. "/options.lua")
  if not chunk then
    error(("wilds_of_hoenn: options.lua did not compile: %s"):format(tostring(err)), 0)
  end
  mod.options:define(chunk())
end

local function optGet(mod, key)
  if mod and mod.options and type(mod.options.get) == "function" then
    local v = mod.options:get(key)
    if v ~= nil then return v end
  end
  return Config.DEFAULTS[key]
end

function Config.get(mod, key)
  return optGet(mod, key)
end

function Config.enabled(mod)
  return optGet(mod, "enabled") == true
end

local VALID_SPRITE_STYLE = { followers = true, pokemmo = true }
function Config.spriteStyle(mod)
  local v = optGet(mod, "sprite_style")
  if VALID_SPRITE_STYLE[v] then return v end
  return Config.DEFAULTS.sprite_style
end

function Config.classicEncEnabled(mod)
  return optGet(mod, "classic_enc") == true
end

local VALID_SILHOUETTE = { off = true, undiscovered = true, all = true }
function Config.silhouetteMode(mod)
  local v = optGet(mod, "wild_silhouettes")
  if VALID_SILHOUETTE[v] then return v end
  return Config.DEFAULTS.wild_silhouettes
end

local VALID_SHINY_RATE = { vanilla = true, boosted = true, off = true }
function Config.shinyRate(mod)
  local v = optGet(mod, "shiny_rate")
  if VALID_SHINY_RATE[v] then return v end
  return Config.DEFAULTS.shiny_rate
end

function Config.followerEnabled(mod)
  return optGet(mod, "follower") == true
end

return Config
