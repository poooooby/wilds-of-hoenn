-- Sprite atlas: serve the per-species sprite sheets from a few shard
-- PNGs, under their ORIGINAL relative paths, so the release ZIP does not
-- carry 1000+ individual files.
--
-- tools/generate_sprite_atlases.py packs each sprite FAMILY (a set of
-- directories of `<dex>-<variant>.png` or `follower_<dex>_<variant>.png`
-- sheets) into a few single-column shard PNGs plus a JSON index
-- (assets/atlas/index.json, one <family>.json per family), and
-- scripts/build-mod.py bakes that by default instead of shipping the
-- per-file sheets.
--
-- Unlike Wilds of Kanto Revival's lib/sprite_atlas.lua, this module does
-- NOT wrap the shared engine `src.render.Assets` module -- this mod is
-- the only consumer of these sprite paths (lib/actor_renderer.lua draws
-- its own quads; it never goes through SpriteRenderer or OwSprites), so
-- there is no shared choke point worth patching. `resolveImage(mod, rel)`
-- is just one more fallback ActorRenderer's own loadImage() tries after
-- the real per-file path, cheaper than Wilds needed and with no
-- `engine_internals` reach of its own (nothing here touches
-- src/core/game3 -- this module is pure asset I/O).
--
-- With no atlas present (a repo checkout, or any build before one is
-- generated), install() returns false and every image load falls
-- straight through to the real per-file sheets -- this mod behaves
-- exactly as it did before the atlas existed.
local V = ...
local JsonDecode = V.require("json_decode")

local SpriteAtlas = {}

SpriteAtlas.ROOT_INDEX = "assets/atlas/index.json"

local state

-- Optional memory bounds, set with SpriteAtlas.configure(). nil = unlimited,
-- which is the default (every decoded shard and every sliced sheet is kept).
local maxShards, maxImages

local function newState()
  return {
    mod = nil,
    dirToFamily = {}, -- sprite directory -> family name
    familyMeta = {}, -- family name -> { index = rel }
    families = {}, -- family name -> loaded index (or false when unusable)
    shardData = {}, -- "family#n" -> { data = love ImageData, tick = n }
    shardCount = 0,
    images = {}, -- sprite rel -> { img = love Image, tick = n }
    imageCount = 0,
    tick = 0, -- use counter: entries with the lowest tick are evicted first
    decodes = 0,
    evictedShards = 0,
    evictedImages = 0,
  }
end

local function releaseData(data)
  if data and type(data.release) == "function" then pcall(data.release, data) end
end

-- drop least-recently-used entries until `count` fits `cap`; returns the new count
local function evictOldest(map, count, cap, onEvict)
  while count > cap do
    local oldKey, oldTick
    for k, v in pairs(map) do
      if oldTick == nil or v.tick < oldTick then oldKey, oldTick = k, v.tick end
    end
    if oldKey == nil then break end
    onEvict(map[oldKey])
    map[oldKey] = nil
    count = count - 1
  end
  return count
end

local function trim()
  if not state then return end
  if maxShards then
    local n = evictOldest(state.shardData, state.shardCount, maxShards,
      function(entry) releaseData(entry.data) end)
    state.evictedShards = state.evictedShards + (state.shardCount - n)
    state.shardCount = n
  end
  if maxImages then
    local n = evictOldest(state.images, state.imageCount, maxImages, function() end)
    state.evictedImages = state.evictedImages + (state.imageCount - n)
    state.imageCount = n
  end
end

local function capOf(n)
  n = tonumber(n)
  if n and n >= 1 then return math.floor(n) end
  return nil
end

local function readMod(mod, rel)
  if not (mod and type(mod.read) == "function") then return nil end
  local ok, data = pcall(mod.read, mod, rel)
  if ok and type(data) == "string" and data ~= "" then return data end
  return nil
end

local function decodeJson(raw)
  local ok, value = pcall(JsonDecode.decode, raw)
  if ok and type(value) == "table" then return value end
  return nil
end

local function loadFamily(name)
  local fam = state.families[name]
  if fam ~= nil then return fam or nil end
  local meta = state.familyMeta[name]
  local raw = meta and readMod(state.mod, meta.index)
  local idx = raw and decodeJson(raw) or nil
  if not (idx and type(idx.shards) == "table" and type(idx.dirs) == "table") then
    state.families[name] = false
    return nil
  end
  idx.name = name
  state.families[name] = idx
  return idx
end

--- The index entry { shard, x, y, w, h } (shard 0-based) for a relative
--- path, and its family, or nil when the atlas doesn't cover that path.
local function lookup(rel)
  if not (state and type(rel) == "string") then return nil end
  local dir, fname = rel:match("^(.*)/([^/]+)$")
  if not dir then return nil end
  local famName = state.dirToFamily[dir]
  if not famName then return nil end
  local fam = loadFamily(famName)
  if not fam then return nil end
  local entry = fam.dirs[dir] and fam.dirs[dir][fname]
  if type(entry) ~= "table" then return nil end
  return fam, entry
end

--- true when `rel` is covered by the atlas index (doesn't guarantee the
--- shard itself decodes cleanly -- image()/imageData() are the real test).
function SpriteAtlas.has(rel)
  return lookup(rel) ~= nil
end

-- `love` is nil under the standalone (plain-Lua) test suite, and indexing
-- a nil global raises OUTSIDE a pcall's protection (the pcall'd function
-- reference is evaluated as an argument before pcall itself runs) -- so
-- every love.* access below is guarded by an explicit presence check
-- first, same as lib/actor_renderer.lua's loadImage.
local function haveImageApi()
  return love and love.image and love.image.newImageData
end

local function shardImageData(fam, shardIndex)
  local key = fam.name .. "#" .. tostring(shardIndex)
  state.tick = state.tick + 1
  local cached = state.shardData[key]
  if cached then
    cached.tick = state.tick
    return cached.data
  end
  local meta = fam.shards[shardIndex + 1]
  if type(meta) ~= "table" or type(meta.file) ~= "string" then return nil end
  if not haveImageApi() then return nil end
  local full = state.mod.assets and state.mod.assets.path
    and state.mod.assets:path(meta.file) or meta.file
  local ok, data = pcall(love.image.newImageData, full)
  if not ok or not data then return nil end
  state.decodes = state.decodes + 1
  state.shardData[key] = { data = data, tick = state.tick }
  state.shardCount = state.shardCount + 1
  trim()
  return data
end

--- Cached love Image for an atlased relative path, sliced out of its
--- shard the first time it's asked for, or nil when `rel` isn't covered
--- or the shard fails to decode (the caller then falls back to its own
--- real-file load).
function SpriteAtlas.image(mod, rel)
  if not (state and state.mod == mod) then return nil end
  local cached = state.images[rel]
  if cached then
    state.tick = state.tick + 1
    cached.tick = state.tick
    return cached.img
  end
  local fam, entry = lookup(rel)
  if not fam then return nil end
  local data = shardImageData(fam, entry[1])
  if not data then return nil end
  if not (love and love.graphics and love.graphics.newImage) then return nil end
  local x, y, w, h = entry[2], entry[3], entry[4], entry[5]
  local okSlice, sliced = pcall(function()
    local id = love.image.newImageData(w, h)
    id:paste(data, 0, 0, x, y, w, h)
    return id
  end)
  if not okSlice or not sliced then return nil end
  local okImg, img = pcall(love.graphics.newImage, sliced)
  if not okImg or not img then return nil end
  if maxShards or maxImages then releaseData(sliced) end -- bounded: the Image owns its pixels now, drop the temporary copy
  state.tick = state.tick + 1
  state.images[rel] = { img = img, tick = state.tick }
  state.imageCount = state.imageCount + 1
  trim()
  return img
end

--- Optional memory bounds: `{ maxShards = n, maxImages = n }`, the most
--- decoded shards / sliced sheets kept at once (least recently used go
--- first; an evicted shard is release()d, an evicted sheet is re-sliced on
--- its next use). A missing, nil or 0 field means unlimited, which is the
--- default; configure() / configure({}) restores that. Applies at once.
--- A sheet already handed out stays valid; only the cache forgets it.
function SpriteAtlas.configure(opts)
  opts = type(opts) == "table" and opts or {}
  maxShards = capOf(opts.maxShards)
  maxImages = capOf(opts.maxImages)
  trim()
end

--- Cache counters: shards / images currently held, how many were evicted
--- and how many shard decodes happened since install().
function SpriteAtlas.stats()
  local s = state
  if not s then return { shards = 0, images = 0, evictedShards = 0, evictedImages = 0, decodes = 0 } end
  return { shards = s.shardCount, images = s.imageCount, evictedShards = s.evictedShards,
    evictedImages = s.evictedImages, decodes = s.decodes }
end

--- Drop every cached shard, sheet and parsed family index (shards are
--- release()d). The atlas stays installed; the next use reloads.
function SpriteAtlas.release()
  local s = state
  if not s then return end
  for _, entry in pairs(s.shardData) do releaseData(entry.data) end
  s.shardData, s.shardCount = {}, 0
  s.images, s.imageCount = {}, 0
  s.families = {}
end

function SpriteAtlas.installed()
  return state ~= nil and state.mod ~= nil
end

--- Loads assets/atlas/index.json via `mod:read`. Returns true, or false
--- plus a reason -- a false return is the NORMAL case for a repo
--- checkout or a --no-atlas build, not an error.
function SpriteAtlas.install(mod)
  local raw = readMod(mod, SpriteAtlas.ROOT_INDEX)
  if not raw then return false, "no atlas index" end
  local root = decodeJson(raw)
  if not root then return false, "malformed atlas index JSON" end
  if root.version ~= 1 then
    return false, "unsupported atlas index version " .. tostring(root.version)
  end
  if type(root.families) ~= "table" then
    return false, "atlas index has no families table"
  end
  local s = newState()
  s.mod = mod
  local any = false
  for name, meta in pairs(root.families) do
    if type(meta) == "table" and type(meta.index) == "string" and type(meta.dirs) == "table" then
      s.familyMeta[name] = { index = meta.index }
      for _, dir in ipairs(meta.dirs) do
        s.dirToFamily[dir] = name
        any = true
      end
    end
  end
  if not any then return false, "empty atlas index" end
  state = s
  return true
end

--- Test / tooling hook: forget everything.
function SpriteAtlas._reset()
  state = nil
end

return SpriteAtlas
