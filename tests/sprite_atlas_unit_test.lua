-- Run: lua tests/sprite_atlas_unit_test.lua
-- Covers install()/has()/lookup against a fake index -- no love context,
-- so image()'s actual shard-decode/slice is exercised in game only (see
-- docs/MANUAL_TEST.md). tools/validate_sprite_atlases.py is the one that
-- proves a REAL generated atlas round-trips pixel-exact.
package.path = "./?.lua;./?/init.lua;" .. package.path

local failures = 0
local function check(cond, msg)
  if not cond then
    failures = failures + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  else
    print("ok  " .. tostring(msg))
  end
end
local function eq(a, b, msg)
  check(a == b, string.format("%s (got %s expected %s)", msg, tostring(a), tostring(b)))
end

local modules = {}
local V = { path = "." }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  local chunk = assert(loadfile("lib/" .. name .. ".lua"))
  local value = chunk(V)
  modules[name] = value
  return value
end

local SpriteAtlas = V.require("sprite_atlas")

local files = {}
local function setFile(rel, data) files[rel] = data end
local mod = {
  read = function(_, rel)
    local data = files[rel]
    if data == nil then return nil end
    return data
  end,
}

-- ------- no index at all: a normal, silent "not installed"
local ok1, why1 = SpriteAtlas.install(mod)
check(ok1 == false, "install() false with no index file")
check(type(why1) == "string", "install() gives a reason")
check(not SpriteAtlas.installed(), "installed() false with no index")

-- ------- malformed index (bad JSON)
setFile(SpriteAtlas.ROOT_INDEX, "{not valid json")
local ok2 = SpriteAtlas.install(mod)
check(ok2 == false, "install() false on malformed JSON")

-- ------- wrong version / shape
local function encode(t)
  -- Minimal, test-only JSON encoder (lib/json_decode.lua only decodes) --
  -- just enough for the small, known-shape tables this test builds.
  if type(t) == "table" then
    local isArray = (#t > 0) or next(t) == nil
    local parts = {}
    if isArray then
      for _, v in ipairs(t) do parts[#parts + 1] = encode(v) end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    for k, v in pairs(t) do
      parts[#parts + 1] = string.format("%q", k) .. ":" .. encode(v)
    end
    return "{" .. table.concat(parts, ",") .. "}"
  elseif type(t) == "string" then
    return string.format("%q", t)
  else
    return tostring(t)
  end
end

setFile(SpriteAtlas.ROOT_INDEX, encode({ version = 2, families = {} }))
local ok3, why3 = SpriteAtlas.install(mod)
check(ok3 == false, "install() false on an unsupported version")
check(why3:find("version", 1, true) ~= nil, "reason mentions the version mismatch")

setFile(SpriteAtlas.ROOT_INDEX, encode({ version = 1, families = {} }))
local ok4 = SpriteAtlas.install(mod)
check(ok4 == false, "install() false on an empty families table")

-- ------- a real-shaped minimal index: one family, one shard, two sprites
setFile(SpriteAtlas.ROOT_INDEX, encode({
  version = 1,
  families = {
    hgss18 = {
      index = "assets/atlas/hgss18.json",
      dirs = { "assets/wilds_generated/true_size18/hgss" },
    },
  },
}))
files["assets/atlas/hgss18.json"] = encode({
  version = 1, family = "hgss18",
  shards = { { file = "assets/atlas/hgss18_0.png", w = 16, h = 32 } },
  dirs = {
    ["assets/wilds_generated/true_size18/hgss"] = {
      ["001-normal.png"] = { 0, 0, 0, 16, 16 },
      ["001-shiny.png"] = { 0, 0, 16, 16, 16 },
    },
  },
})

local ok5, why5 = SpriteAtlas.install(mod)
check(ok5 == true, "install() succeeds on a real-shaped index (" .. tostring(why5) .. ")")
check(SpriteAtlas.installed(), "installed() true after a successful install")

check(SpriteAtlas.has("assets/wilds_generated/true_size18/hgss/001-normal.png"),
  "has() true for an indexed sprite")
check(SpriteAtlas.has("assets/wilds_generated/true_size18/hgss/001-shiny.png"),
  "has() true for the shiny variant too")
check(not SpriteAtlas.has("assets/wilds_generated/true_size18/hgss/999-normal.png"),
  "has() false for a sprite not in the index")
check(not SpriteAtlas.has("assets/wilds_generated/true_size18/swimming/700-normal.png"),
  "has() false for a directory this family doesn't claim")
check(not SpriteAtlas.has("not/even/a/path/style/string"), "has() false for garbage input")

-- ------- image(): no love context in the standalone suite, so this must
-- return nil cleanly rather than erroring (see the pcall-boundary comment
-- in lib/sprite_atlas.lua -- indexing a nil `love` global outside a pcall
-- raises, so every love.* touch is guarded first).
local okCall, img = pcall(SpriteAtlas.image, mod,
  "assets/wilds_generated/true_size18/hgss/001-normal.png")
check(okCall, "image() does not throw with no love context (" .. tostring(img) .. ")")
eq(img, nil, "image() returns nil with no love context")

-- image() for a mod that isn't the one install() was called with never
-- leaks another mod's atlas state.
local otherMod = { read = function() return nil end }
eq(SpriteAtlas.image(otherMod, "assets/wilds_generated/true_size18/hgss/001-normal.png"),
  nil, "image() returns nil for an unrelated mod")

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("sprite_atlas_unit_test: all passed")
