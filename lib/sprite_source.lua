-- National-dex overworld sheet lookup, borrowed from Wilds of Kanto
-- Revival's assets (see tools/copy_wilds_assets.py -- a read-only copy, not
-- a shared runtime dependency).
--
-- Two styles, matching Wilds' own Sprite Style option:
--
--   "followers" (Poke Followers / GSC, Classic 16x16 frames):
--     assets/enhanced_overworld/poke_followers/follower_%03d_normal.png  (dex 1-251, primary)
--     assets/enhanced_overworld/poke_followers/follower_%03d_shiny.png
--     assets/enhanced_overworld/Pokewilds/follower_%03d_normal.png       (dex 252-386, extension)
--     assets/enhanced_overworld/Pokewilds/follower_%03d_shiny.png
--     poke_followers is tried first; Pokewilds only fills a dex missing
--     there, so dex 1-251 is untouched by the extension pack.
--
--   "pokemmo" (HGSS / PokeMMO, "True Size" -- native per-species frame
--   size, e.g. Bulbasaur's frames are 24x24, Pikachu's are 18x18):
--     assets/wilds_generated/true_size/hgss/%03d-normal.png
--     assets/wilds_generated/true_size/hgss/%03d-shiny.png
--
-- Either way, a species with no genuine shiny source art falls back to
-- its own normal sheet -- never a guessed palette recolor.
--
-- Sprite identity is always the national dex number, never engine-internal
-- species id or display name -- see lib/engine_patch.lua's
-- nationalFor/speciesForNational.

local V = ...

local SpriteSource = {}

local PRIMARY_REL = "assets/enhanced_overworld/poke_followers"
local EXTENSION_REL = "assets/enhanced_overworld/Pokewilds"
local HGSS_REL = "assets/wilds_generated/true_size/hgss"
local MAX_DEX = 386

SpriteSource.STYLE_FOLLOWERS = "followers"
SpriteSource.STYLE_POKEMMO = "pokemmo"
SpriteSource.DEFAULT_STYLE = SpriteSource.STYLE_FOLLOWERS

local function fileExists(mod, rel)
  if mod and mod.assets and type(mod.assets.exists) == "function" then
    local ok, exists = pcall(mod.assets.exists, mod, rel)
    if ok then return exists == true end
  end
  -- Standalone unit tests: a fake mod.read/io.open probe. Real contract:
  -- mod:read returns file bytes or nil (see lib/config.lua's own use of
  -- it for options.lua), never a plain boolean.
  if mod and type(mod.read) == "function" then
    local ok, data = pcall(mod.read, mod, rel)
    return ok and data ~= nil
  end
  local f = io.open(rel, "rb")
  if f then f:close() return true end
  return false
end

local function followersNormalPath(mod, dex)
  local primary = string.format("%s/follower_%03d_normal.png", PRIMARY_REL, dex)
  if fileExists(mod, primary) then return primary end
  local ext = string.format("%s/follower_%03d_normal.png", EXTENSION_REL, dex)
  if fileExists(mod, ext) then return ext end
  return nil
end

local function followersShinyPath(mod, dex)
  local primary = string.format("%s/follower_%03d_shiny.png", PRIMARY_REL, dex)
  if fileExists(mod, primary) then return primary end
  local ext = string.format("%s/follower_%03d_shiny.png", EXTENSION_REL, dex)
  if fileExists(mod, ext) then return ext end
  return nil
end

local function pokemmoNormalPath(mod, dex)
  local p = string.format("%s/%03d-normal.png", HGSS_REL, dex)
  if fileExists(mod, p) then return p end
  return nil
end

local function pokemmoShinyPath(mod, dex)
  local p = string.format("%s/%03d-shiny.png", HGSS_REL, dex)
  if fileExists(mod, p) then return p end
  return nil
end

--- rel path for a dex's normal sheet in the given style ("followers" |
--- "pokemmo", defaults to "followers"). Returns nil if that style has no
--- art for this dex at all.
function SpriteSource.normalPath(mod, dex, style)
  if type(dex) ~= "number" or dex < 1 or dex > MAX_DEX then return nil end
  if style == SpriteSource.STYLE_POKEMMO then
    return pokemmoNormalPath(mod, dex)
  end
  return followersNormalPath(mod, dex)
end

--- rel path for a dex's shiny sheet, same style/fallback rules as
--- normalPath. Returns nil if no genuine shiny art exists for this
--- dex+style (caller should fall back to normalPath, not synthesize a
--- recolor).
function SpriteSource.shinyPath(mod, dex, style)
  if type(dex) ~= "number" or dex < 1 or dex > MAX_DEX then return nil end
  if style == SpriteSource.STYLE_POKEMMO then
    return pokemmoShinyPath(mod, dex)
  end
  return followersShinyPath(mod, dex)
end

--- The path this mod actually draws for (dex, shiny, style): shiny art
--- when it exists and shiny was asked for, the normal sheet otherwise.
--- Never nil for a dex 1..386 with the asset copy present.
function SpriteSource.pathFor(mod, dex, shiny, style)
  if shiny then
    local p = SpriteSource.shinyPath(mod, dex, style)
    if p then return p end
  end
  return SpriteSource.normalPath(mod, dex, style)
end

SpriteSource.MAX_DEX = MAX_DEX

return SpriteSource
