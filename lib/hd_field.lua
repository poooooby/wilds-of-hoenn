-- Hands the overworld sprite sheets (wild Pokemon and the follower, both styles) to
-- gen3-hd-sprites when it is installed: the field then draws them at the window's
-- resolution instead of on the game's pixel grid, so they can be any size without
-- lumpy pixels and walkers move smoothly between pixels.
--
-- A sheet's size is  Overworld Size (the player's percentage, every sheet)
--                  x Species Sizes  (while that option is on), per style:
--                      HGSS / PokeMMO  lib/HGSS_scale.lua (Wilds of Kanto Revival's table)
--                      PMDCollab       lib/PMD_scale.lua (1.0 for every species until tuned)
-- Both are plain dex -> size tables, edited by hand; a form key ("479-heat") sizes one form.
--
-- Without that mod, or with its Field HD option off, this does nothing and the sheets
-- are drawn exactly as before. Each sheet has its own spec table (one species, one
-- size), kept so a changed option re-sizes the sheets already loaded.
local V = ...

local HdField = {}

local function load(name)
  if V and V.require then
    local ok, value = pcall(V.require, name)
    if ok and type(value) == "table" then return value end
  end
  return nil
end
local SizeTables = { hgss = load("HGSS_scale"), pmd = load("PMD_scale") }
local SpriteSource = load("sprite_source")

HdField.size = 1             -- "Overworld Size", as a multiplier
HdField.speciesSizes = true  -- "Species Sizes"
local MIN_SCALE, MAX_SCALE = 0.2, 2

local specs = setmetatable({}, { __mode = "k" }) -- image -> { scale, factor, path, ... }

local function library(mod)
  if not (mod and type(mod.find) == "function") then return nil end
  local ok, found = pcall(mod.find, mod, "gen3-hd-sprites")
  local ex = ok and found and found.exports
  if type(ex) ~= "table" or type(ex.tag) ~= "function" then return nil end
  return ex
end

--- What a sprite sheet path is: style ("hgss" | "pmd"), art key ("479" or "479-heat"),
--- base dex number and, for PMD, the animation. nil for anything else (a portrait, an
--- unknown path). A swimming Pokemon's foam overlay (assets/pmd/foam<anim>/) reads as
--- its animation, so it is sized and pivoted exactly like the sprite it sits on.
function HdField.parse(path)
  if type(path) ~= "string" then return nil end
  local key = path:match("/true_size18/%w+/(%d+[%w_%-]-)%-%a+%.png$")
  if key then return { style = "hgss", key = key, dex = tonumber(key:match("^(%d+)")) } end
  local anim, pkey = path:match("^assets/pmd/(%a+)/(%d+[%w_%-]-)%-%a+%.png$")
  if anim and anim ~= "portraits" then
    local foam = anim:match("^foam(%a+)$")
    return { style = "pmd", key = pkey, dex = tonumber(pkey:match("^(%d+)")), anim = foam or anim,
             foam = foam ~= nil or nil }
  end
  return nil
end

local function lookup(tbl, info)
  if type(tbl) ~= "table" then return nil end
  local v = tbl[info.key]
  if v == nil then v = tbl[tonumber(info.key)] end
  if v == nil and info.dex then v = tbl[info.dex] end
  if type(v) == "number" and v > 0 then return v end
  return nil
end

--- The species factor of a sheet path: its style's table (HGSS_scale / PMD_scale), else
--- 1. A form is sized like its base species unless it has a form key of its own.
function HdField.speciesFactor(path)
  if not HdField.speciesSizes then return 1 end
  local info = HdField.parse(path)
  if not info then return 1 end
  return lookup(SizeTables[info.style], info) or 1
end

local function scaleOf(spec)
  return math.max(MIN_SCALE, math.min(MAX_SCALE, HdField.size * spec.factor))
end

-- a PMD sheet stands on its baked ground point, not on the bottom centre of its cell
local function pmdPivot(mod, info)
  if not (SpriteSource and info and info.style == "pmd") then return nil end
  local ok, pmd = pcall(SpriteSource.pmdInfo, mod, tonumber(info.key) or info.key)
  local entry = ok and type(pmd) == "table" and pmd[info.anim] or nil
  if type(entry) == "table" and tonumber(entry.ax) and tonumber(entry.ay) then
    return { tonumber(entry.ax), tonumber(entry.ay) }
  end
  return nil
end

--- Tag one sheet image (from ActorRenderer.loadImage) loaded from `path`. Safe to
--- call with no library. Only sprite sheets are tagged: a portrait or any other image
--- loaded the same way is left alone.
function HdField.tag(mod, image, path)
  if image == nil then return false end
  if type(path) == "string" and not HdField.parse(path) then return false end
  local ex = library(mod)
  if not ex then return false end
  local info = HdField.parse(path)
  local spec = { filter = "nearest", path = path, factor = HdField.speciesFactor(path) }
  local pivot = pmdPivot(mod, info)
  if pivot then
    spec.lowPivot = pivot
  else
    spec.anchor = "feet" -- a size change keeps a Pokemon standing on its spot
  end
  spec.scale = scaleOf(spec)
  specs[image] = spec
  local ok = pcall(ex.tag, image, spec)
  return ok
end

--- Make draws of `image` through `quad` scale about (x, y) in the quad instead of the
--- sheet's ground point -- a swimming PMD sprite stands on its waterline, not its feet.
--- `scale` (optional) replaces the sheet's size for that quad: 1 for a slice that is
--- already drawn at its final size (a reflection). Needs a gen3-hd-sprites that reads
--- `quadPivots` (HdField.slicesSupported); an older one ignores it. No-op for an
--- untagged image.
function HdField.quadPivot(image, quad, x, y, scale)
  local spec = image and specs[image]
  if not (spec and quad) then return false end
  spec.quadPivots = spec.quadPivots or setmetatable({}, { __mode = "k" })
  local p = spec.quadPivots[quad]
  if not (p and p[1] == x and p[2] == y and p[3] == scale) then spec.quadPivots[quad] = { x, y, scale } end
  return true
end

--- Can `image` be drawn in slices through gen3-hd-sprites (the library is installed,
--- reads per-quad pivots and scales, and the image is tagged)? Otherwise a slice must be
--- drawn the plain way (HdField.untagged), or the library would size it twice.
function HdField.slicesSupported(mod, image)
  if not (image and specs[image]) then return false end
  local ex = library(mod)
  return ex ~= nil and type(ex.features) == "table" and ex.features.quadPivots == true
end

--- Run `fn` with `image` drawn the plain way: gen3-hd-sprites would otherwise catch
--- every draw of a tagged sheet and redraw it at window resolution about its own pivot,
--- which is wrong for a sliced, mirrored reflection (lib/reflection.lua). The tag is put
--- back right after, even when `fn` fails.
function HdField.untagged(mod, image, fn)
  local spec = image and specs[image]
  local ex = spec and library(mod)
  if not (ex and type(ex.untag) == "function") then return fn() end
  pcall(ex.untag, image)
  local ok, err = pcall(fn)
  pcall(ex.tag, image, spec)
  if not ok then error(err, 0) end
end

local function rescale()
  for _, spec in pairs(specs) do
    spec.factor = HdField.speciesFactor(spec.path)
    spec.scale = scaleOf(spec)
  end
end

--- The "Overworld Size" option: a percentage ("100", "90", ...) -> the shared multiplier.
function HdField.setSize(value)
  local pct = tonumber(value)
  if not pct or pct <= 0 then pct = 100 end
  HdField.size = math.max(0.25, math.min(2, pct / 100))
  rescale()
  return HdField.size
end

--- The "Species Sizes" option (on / off) -- applies to sheets already loaded too.
function HdField.setSpeciesSizes(on)
  HdField.speciesSizes = on ~= false
  rescale()
  return HdField.speciesSizes
end

--- Is the library there and drawing the field at full resolution right now?
function HdField.active(mod)
  local ex = library(mod)
  if not ex then return false end
  if type(ex.isActive) == "function" then
    local ok, on = pcall(ex.isActive)
    if not (ok and on) then return false end
  end
  if type(ex.enabled) == "function" then
    local ok, on = pcall(ex.enabled, "field")
    if ok and on == false then return false end
  end
  return true
end

--- How big the sheet at `path` is actually drawn (1 without the library): what a
--- caller spacing sprites out by their width has to use instead of the sheet's.
function HdField.scaleOfPath(mod, path)
  if not HdField.active(mod) then return 1 end
  return math.max(MIN_SCALE, math.min(MAX_SCALE, HdField.size * HdField.speciesFactor(path)))
end

return HdField
