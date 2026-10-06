-- National-dex overworld sheet lookup, borrowed from Wilds of Kanto
-- Revival's assets (see tools/copy_wilds_assets.py -- a read-only copy, not
-- a shared runtime dependency).
--
-- Layout, identical to Wilds:
--   assets/enhanced_overworld/poke_followers/follower_%03d_normal.png  (dex 1-251, primary)
--   assets/enhanced_overworld/poke_followers/follower_%03d_shiny.png
--   assets/enhanced_overworld/Pokewilds/follower_%03d_normal.png       (dex 252-386, extension)
--   assets/enhanced_overworld/Pokewilds/follower_%03d_shiny.png
-- poke_followers is tried first; Pokewilds only fills a dex missing there,
-- so dex 1-251 is untouched by the extension pack. A species with no
-- genuine shiny source art falls back to its own normal sheet -- never a
-- guessed recolor.
--
-- Sprite identity is always the national dex number, never engine-internal
-- species id or display name -- see lib/national_dex.lua for the convert.

local V = ...

local SpriteSource = {}

local PRIMARY_REL = "assets/enhanced_overworld/poke_followers"
local EXTENSION_REL = "assets/enhanced_overworld/Pokewilds"
local MAX_DEX = 386

local function fileExists(mod, rel)
  if mod and mod.assets and type(mod.assets.exists) == "function" then
    local ok, exists = pcall(mod.assets.exists, mod, rel)
    if ok then return exists == true end
  end
  -- Standalone unit tests: a fake mod.read/io.open probe.
  if mod and type(mod.read) == "function" then
    local ok, data = pcall(mod.read, mod, rel)
    return ok and data ~= nil
  end
  local f = io.open(rel, "rb")
  if f then f:close() return true end
  return false
end

--- rel path for a dex's normal sheet, trying poke_followers then Pokewilds.
--- Returns nil if neither folder has it (never happens for dex 1..386 with
--- the asset copy run, but a trimmed/partial install should fail soft).
function SpriteSource.normalPath(mod, dex)
  if type(dex) ~= "number" or dex < 1 or dex > MAX_DEX then return nil end
  local primary = string.format("%s/follower_%03d_normal.png", PRIMARY_REL, dex)
  if fileExists(mod, primary) then return primary end
  local ext = string.format("%s/follower_%03d_normal.png", EXTENSION_REL, dex)
  if fileExists(mod, ext) then return ext end
  return nil
end

--- rel path for a dex's shiny sheet, same fallback order as normalPath.
--- Returns nil if no genuine shiny art exists for this dex (caller should
--- fall back to normalPath, not synthesize a recolor).
function SpriteSource.shinyPath(mod, dex)
  if type(dex) ~= "number" or dex < 1 or dex > MAX_DEX then return nil end
  local primary = string.format("%s/follower_%03d_shiny.png", PRIMARY_REL, dex)
  if fileExists(mod, primary) then return primary end
  local ext = string.format("%s/follower_%03d_shiny.png", EXTENSION_REL, dex)
  if fileExists(mod, ext) then return ext end
  return nil
end

--- The path this mod actually draws for (dex, shiny): shiny art when it
--- exists and shiny was asked for, the normal sheet otherwise. Never nil
--- for a dex 1..386 with the asset copy present.
function SpriteSource.pathFor(mod, dex, shiny)
  if shiny then
    local p = SpriteSource.shinyPath(mod, dex)
    if p then return p end
  end
  return SpriteSource.normalPath(mod, dex)
end

SpriteSource.MAX_DEX = MAX_DEX

return SpriteSource
