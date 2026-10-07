-- National-dex overworld sheet lookup, borrowed from Wilds of Kanto
-- Revival's assets (see tools/copy_wilds_assets.py -- a read-only copy, not
-- a shared runtime dependency) plus a new 18-frame bake of our own
-- (tools/generate_true_size_18frame.py) from Wilds' raw source grids.
--
-- Two independent dimensions: `style` (which art family: HGSS / PokeMMO here,
-- PMDCollab through its own index below) and
-- `presentation` (land vs water kind, from where the Pokemon is standing).
--
--   style = "pokemmo" (HGSS / PokeMMO, "True Size" -- native per-species
--   frame size). 18 frames (stand x3, walk-A/walk-B x3 directions,
--   run-base/run-A/run-B x3 directions -- see lib/actor_renderer.lua and
--   tools/generate_true_size_18frame.py for the exact layout and how the
--   run frames reuse walk art, since there is no dedicated running
--   source). Presentation selects which baked pack:
--     assets/wilds_generated/true_size18/hgss/%03d-{normal,shiny}.png       (land)
--     assets/wilds_generated/true_size18/swimming/%03d-{normal,shiny}.png   (water)
--     assets/wilds_generated/true_size18/levitates/%03d-{normal,shiny}.png  (water)
--   For water presentation, "swimming" is tried first and "levitates"
--   second -- confirmed against Wilds of Kanto Revival's own
--   water_sprite_registry.lua that this exact try-order IS the real
--   behaviour: its per-species preferredWaterKind override field exists
--   in the code but is unset on every single entry in the real mapping
--   data (checked directly), so "try swimming, fall back to levitates" is
--   not a simplification, it's what actually happens. If neither water
--   pack covers a dex (narrower coverage than land), falls through to
--   land art rather than drawing nothing.
--
-- Either way, a species with no genuine shiny source art falls back to
-- its own normal sheet -- never a guessed palette recolor.
--
-- MAX_DEX is 1025 (Wilds' own full National Dex coverage), not Gen 3's
-- native 386 -- a dex-expansion mod for Gen 3 (gen1recomp's
-- `national_dex_gen3`) can put species beyond 386 in a real RSE save, and
-- nationalFor()/speciesForNational() make no 386 assumption either, so
-- there is no reason to cap art lookup lower than the species the engine
-- could actually hand us. See tools/copy_wilds_assets.py.
--
-- Sprite identity is always the national dex number, never engine-internal
-- species id or display name -- see lib/engine_patch.lua's
-- nationalFor/speciesForNational.
--
-- Everything ships in the release ZIP as a baked atlas
-- (tools/generate_sprite_atlases.py, lib/sprite_atlas.lua), not as
-- thousands of individual files -- SpriteSource only ever resolves a
-- RELATIVE path; lib/actor_renderer.lua decides whether that path comes
-- from a real file or an atlas shard.

local V = ...

-- Which relative paths exist also depends on the sprite atlas: a release ZIP
-- ships the HGSS sheets only as atlas shards, never as loose files.
-- (V is nil in the standalone tests that load this file bare.)
local SpriteAtlas = V and V.require("sprite_atlas") or nil

local SpriteSource = {}

local TRUE_SIZE18_REL = "assets/wilds_generated/true_size18"
local MAX_DEX = 1025

SpriteSource.STYLE_POKEMMO = "pokemmo"
SpriteSource.STYLE_PMD = "pmd"
-- A species with no PMDCollab art (about 50 of them) draws in this style.
SpriteSource.PMD_FALLBACK_STYLE = SpriteSource.STYLE_POKEMMO
SpriteSource.DEFAULT_STYLE = SpriteSource.STYLE_POKEMMO

SpriteSource.PRESENTATION_LAND = "land"
SpriteSource.PRESENTATION_SWIMMING = "swimming"
SpriteSource.PRESENTATION_LEVITATES = "levitates"
SpriteSource.DEFAULT_PRESENTATION = SpriteSource.PRESENTATION_LAND

-- A caller that only knows "this entity is standing in water" (not which
-- water kind) should pass this -- see the module header for why "swimming
-- first, levitates second" is the real behaviour and not a simplification.
SpriteSource.DEFAULT_WATER_PRESENTATION = SpriteSource.PRESENTATION_SWIMMING

local function fileExists(mod, rel)
  -- baked into the atlas (a release ZIP has no loose per-species sheets)
  if SpriteAtlas and SpriteAtlas.installed() and SpriteAtlas.has(rel) then return true end
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

-- presentation -> true_size18 folder name. Land art's baked folder is
-- "hgss" (tools/generate_true_size_18frame.py's KINDS, inherited from the
-- style name before `presentation` existed as its own dimension) -- NOT
-- "land" -- swimming/levitates match their presentation name exactly.
local TRUE_SIZE18_FOLDER = {
  [SpriteSource.PRESENTATION_LAND] = "hgss",
  [SpriteSource.PRESENTATION_SWIMMING] = "swimming",
  [SpriteSource.PRESENTATION_LEVITATES] = "levitates",
}

local function trueSize18Path(mod, dex, presentation, variant)
  local folder = TRUE_SIZE18_FOLDER[presentation]
  if not folder then return nil end
  local p = string.format("%s/%s/%03d-%s.png", TRUE_SIZE18_REL, folder, dex, variant)
  if fileExists(mod, p) then return p end
  return nil
end

local function pokemmoPath(mod, dex, presentation, variant)
  if presentation == SpriteSource.PRESENTATION_SWIMMING or presentation == SpriteSource.PRESENTATION_LEVITATES then
    local p = trueSize18Path(mod, dex, presentation, variant)
    if p then return p end
    -- That specific water kind has no art for this dex -- try the other
    -- water kind before giving up to land (narrower coverage than land
    -- is expected; see module header).
    local other = (presentation == SpriteSource.PRESENTATION_SWIMMING)
      and SpriteSource.PRESENTATION_LEVITATES or SpriteSource.PRESENTATION_SWIMMING
    p = trueSize18Path(mod, dex, other, variant)
    if p then return p end
    return trueSize18Path(mod, dex, SpriteSource.PRESENTATION_LAND, variant)
  end
  return trueSize18Path(mod, dex, SpriteSource.PRESENTATION_LAND, variant)
end

--- rel path for a dex's normal sheet in the given presentation ("land" |
--- "swimming" | "levitates"). `style` is accepted for the callers that
--- always pass it but there is only one baked family now (HGSS / PokeMMO,
--- 18 frames); an unknown or stale style (a saved "followers" option from
--- before that style was removed) draws it too. Returns nil if nothing at
--- all covers this dex.
function SpriteSource.normalPath(mod, dex, _style, presentation)
  if type(dex) ~= "number" or dex < 1 or dex > MAX_DEX then return nil end
  return pokemmoPath(mod, dex, presentation or SpriteSource.DEFAULT_PRESENTATION, "normal")
end

--- rel path for a dex's shiny sheet, same style/presentation/fallback
--- rules as normalPath. Returns nil if no genuine shiny source art exists
--- (caller should fall back to normalPath, not synthesize a recolor).
function SpriteSource.shinyPath(mod, dex, _style, presentation)
  if type(dex) ~= "number" or dex < 1 or dex > MAX_DEX then return nil end
  return pokemmoPath(mod, dex, presentation or SpriteSource.DEFAULT_PRESENTATION, "shiny")
end

--- The path this mod actually draws for (dex, shiny, style,
--- presentation): shiny art when it exists and shiny was asked for, the
--- normal sheet otherwise. Never nil for a dex 1..1025 with the asset
--- copy present (water falls through water -> water -> land, see
--- pokemmoPath).
function SpriteSource.pathFor(mod, dex, shiny, style, presentation)
  if shiny then
    local p = SpriteSource.shinyPath(mod, dex, style, presentation)
    if p then return p end
  end
  return SpriteSource.normalPath(mod, dex, style, presentation)
end

-- PMDCollab (STYLE_PMD): assets/pmd/index.json, baked by
-- tools/generate_pmd_sprites.py, says which species have art and describes
-- each Walk/Idle sheet (cell size, frame count, durations, ground anchor).
-- The sheets themselves are assets/pmd/<walk|idle>/%03d-<normal|shiny>.png.
-- Availability comes from the index alone (always shipped, loose), so it is
-- right in a release ZIP where the per-file sheets live in the atlas.
local PMD_INDEX_REL = "assets/pmd/index.json"
local pmdCache = {} -- [mod] = index table | false (no/bad index)

function SpriteSource.pmdIndex(mod)
  local hit = pmdCache[mod]
  if hit ~= nil then return hit or nil end
  local index = false
  if mod and type(mod.read) == "function" then
    local ok, raw = pcall(mod.read, mod, PMD_INDEX_REL)
    if ok and type(raw) == "string" then
      local okJ, decoded = pcall(function() return V.require("json_decode").decode(raw) end)
      if okJ and type(decoded) == "table" and decoded.version == 1 and type(decoded.dex) == "table" then
        index = decoded
      end
    end
  end
  pmdCache[mod] = index
  return index or nil
end

--- { walk = {...}, idle = {...} } for a national dex number, or nil when the
--- species has no PMDCollab art.
function SpriteSource.pmdInfo(mod, dex)
  local index = SpriteSource.pmdIndex(mod)
  local info = index and type(dex) == "number" and index.dex[tostring(dex)]
  if type(info) == "table" and type(info.walk) == "table" and type(info.idle) == "table" then
    return info
  end
  return nil
end

--- rel path of one PMD animation sheet ("walk" | "idle"); the shiny sheet
--- only when the index says one was baked for that animation.
function SpriteSource.pmdPath(info, anim, dex, shiny)
  local entry = info and info[anim]
  if type(entry) ~= "table" then return nil end
  local variant = (shiny and entry.shiny) and "shiny" or "normal"
  return string.format("assets/pmd/%s/%03d-%s.png", anim, dex, variant)
end

-- Portraits: assets/pmd/portraits.json lists, per species, which emotions its
-- sheet has (column order) and whether a shiny sheet exists; the sheets are
-- assets/pmd/portraits/%03d-<normal|shiny>.png, 40x40 cells side by side.
local PORTRAIT_INDEX_REL = "assets/pmd/portraits.json"
local portraitCache = {} -- [mod] = index | false

local function portraitIndex(mod)
  local hit = portraitCache[mod]
  if hit ~= nil then return hit or nil end
  local index = false
  if mod and type(mod.read) == "function" then
    local ok, raw = pcall(mod.read, mod, PORTRAIT_INDEX_REL)
    if ok and type(raw) == "string" then
      local okJ, decoded = pcall(function() return V.require("json_decode").decode(raw) end)
      if okJ and type(decoded) == "table" and decoded.version == 1 and type(decoded.dex) == "table" then
        index = decoded
      end
    end
  end
  portraitCache[mod] = index
  return index or nil
end

--- { emotions = {...}, shiny = bool, size = 40 } for a national dex number,
--- or nil when it has no portrait art.
function SpriteSource.portraitInfo(mod, dex)
  local index = portraitIndex(mod)
  local entry = index and type(dex) == "number" and index.dex[tostring(dex)]
  if type(entry) ~= "table" or type(entry.emotions) ~= "table" then return nil end
  return { emotions = entry.emotions, shiny = entry.shiny == true, size = tonumber(index.size) or 40 }
end

-- When a species has no art for an emotion, the nearest one it does have is
-- used, walking this chain and ending at Normal (so e.g. a species with no
-- Teary-Eyed shows Crying, then Sad).
local EMOTION_FALLBACK = {
  Inspired = "Joyous", Joyous = "Happy", Happy = "Normal",
  ["Teary-Eyed"] = "Crying", Crying = "Sad", Sad = "Normal",
  Shouting = "Angry", Angry = "Determined", Determined = "Normal",
  Stunned = "Dizzy", Dizzy = "Surprised", Surprised = "Normal",
  Sigh = "Sad", Worried = "Sad", Pain = "Worried",
}

--- (path, columnIndex) of one emotion's cell, 0-based column; an emotion the
--- species lacks falls back to "Normal". nil when there is no portrait art.
function SpriteSource.portraitCell(info, dex, shiny, emotion)
  if not info then return nil end
  local columns = {}
  for i, name in ipairs(info.emotions) do columns[name] = i - 1 end
  local column
  local want, hops = emotion, 0
  while want and hops < 8 do
    column = columns[want]
    if column then break end
    want, hops = EMOTION_FALLBACK[want], hops + 1
  end
  column = column or columns.Normal
  if column == nil then return nil end
  local variant = (shiny and info.shiny) and "shiny" or "normal"
  return string.format("assets/pmd/portraits/%03d-%s.png", dex, variant), column
end

function SpriteSource._resetPmdCache() pmdCache = {} portraitCache = {} end

--- Whether a species floats/flies, for the idle wing-flap
--- (ActorRenderer.idleFlapPose). Uses the baked "levitates" pack purely as a
--- species REFERENCE -- membership means "hovers/flies"; that art is never
--- drawn for this (it is the water pack, see pokemmoPath). Independent of
--- Sprite Style and presentation, and memoized per dex (asset presence never
--- changes at runtime).
local floaterCache = {}
-- In the levitates pack but deliberately NOT given the idle flap.
local NOT_FLOATERS = {
  [6] = true, -- Charizard
}
function SpriteSource.isFloater(mod, dex)
  if type(dex) ~= "number" or dex < 1 or dex > MAX_DEX then return false end
  if NOT_FLOATERS[dex] then return false end
  local hit = floaterCache[dex]
  if hit == nil then
    hit = trueSize18Path(mod, dex, SpriteSource.PRESENTATION_LEVITATES, "normal") ~= nil
    floaterCache[dex] = hit
  end
  return hit
end
function SpriteSource._resetFloaterCache() floaterCache = {} end

--- Transparent rows baked under the water packs' frames (swimming/levitates;
--- tools/generate_true_size_18frame.py's WATER_PAD). 0 for every other sheet.
--- ActorRenderer shifts such a frame down by this much so the creature's feet
--- stay flush with the tile instead of floating above it.
SpriteSource.WATER_BOTTOM_PAD = 2
function SpriteSource.bottomPadFor(path)
  if type(path) == "string" and (path:find("/true_size18/swimming/", 1, true)
      or path:find("/true_size18/levitates/", 1, true)) then
    return SpriteSource.WATER_BOTTOM_PAD
  end
  return 0
end

SpriteSource.MAX_DEX = MAX_DEX

return SpriteSource
