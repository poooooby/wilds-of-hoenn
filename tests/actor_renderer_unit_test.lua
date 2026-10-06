-- Run: lua tests/actor_renderer_unit_test.lua
-- Covers the parts of ActorRenderer that don't need love.graphics: frame
-- index selection and sheet path resolution. draw() itself needs a real
-- love context and is exercised only in game (see MANUAL_TEST.md).
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

local ActorRenderer = V.require("actor_renderer")

-- ------- frame index: stand frames (0/1/2), walk frames (3/4/5), right
-- mirrors left's indices exactly.
eq(ActorRenderer.frameIndexFor("down", 0), 0, "stand down = 0")
eq(ActorRenderer.frameIndexFor("up", 0), 1, "stand up = 1")
eq(ActorRenderer.frameIndexFor("left", 0), 2, "stand left = 2")
eq(ActorRenderer.frameIndexFor("right", 0), 2, "stand right mirrors left = 2")
eq(ActorRenderer.frameIndexFor("down", 1), 3, "walk down = 3")
eq(ActorRenderer.frameIndexFor("up", 1), 4, "walk up = 4")
eq(ActorRenderer.frameIndexFor("left", 1), 5, "walk left = 5")
eq(ActorRenderer.frameIndexFor("right", 1), 5, "walk right mirrors left = 5")
eq(ActorRenderer.frameIndexFor("right", true), 5, "walkPhase accepts boolean true")
eq(ActorRenderer.frameIndexFor(nil, 0), 0, "unknown facing falls back to down")

-- ------- construction + imagePath delegates to SpriteSource
local mod = {
  read = function(_, rel)
    local f = io.open(rel, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
  end,
}
local r = ActorRenderer.new(mod, 1, false)
eq(r.dex, 1, "stores dex")
eq(r.shiny, false, "stores shiny")
eq(r.silhouette, false, "silhouette defaults off")
local path = r:imagePath()
check(path ~= nil and path:find("follower_001_normal", 1, true) ~= nil,
  "imagePath resolves the real dex 1 normal sheet")

local rShiny = ActorRenderer.new(mod, 1, true)
local pathShiny = rShiny:imagePath()
check(pathShiny ~= nil and pathShiny:find("follower_001_shiny", 1, true) ~= nil,
  "imagePath resolves the real dex 1 shiny sheet")

-- ------- HGSS / PokeMMO ("pokemmo") style resolves a completely
-- different, real, on-disk sheet when passed through
local SpriteSource = V.require("sprite_source")
local rPokemmo = ActorRenderer.new(mod, 1, false, SpriteSource.STYLE_POKEMMO)
eq(rPokemmo.style, SpriteSource.STYLE_POKEMMO, "stores the requested style")
local pokemmoPath = rPokemmo:imagePath()
check(pokemmoPath ~= nil and pokemmoPath:find("true_size/hgss", 1, true) ~= nil,
  "imagePath honours the pokemmo style")

local rDefaultStyle = ActorRenderer.new(mod, 1, false)
eq(rDefaultStyle.style, SpriteSource.STYLE_FOLLOWERS, "style defaults to followers when omitted")

-- ------- anchorOffset: Gen 3's own native OW sprite anchor -- centered
-- horizontally in a 16px cell, feet flush with the cell's bottom edge.
-- A plain 16x16 Followers/GSC frame is a no-op (fills the cell exactly).
local ax16, ay16 = ActorRenderer.anchorOffset(16, 16)
eq(ax16, 0, "a 16x16 frame has no horizontal anchor offset")
eq(ay16, 0, "a 16x16 frame has no vertical anchor offset")

-- A bigger HGSS-style frame (e.g. Snorlax-ish) is centered horizontally
-- and extends UPWARD from the cell's bottom (negative y offset), never
-- squashed or drawn hanging below its feet.
local ax32, ay32 = ActorRenderer.anchorOffset(32, 32)
eq(ax32, -8, "a 32-wide frame is centered 8px left of the cell")
eq(ay32, -16, "a 32-tall frame extends 16px above the cell, feet at the bottom")

-- A non-square frame (real HGSS sheets aren't always square, e.g. dex 252
-- is 25 wide x 28 tall per frame) anchors each axis independently.
local axRect, ayRect = ActorRenderer.anchorOffset(24, 18)
eq(axRect, -4, "non-square frame: horizontal anchor still centers")
eq(ayRect, -2, "non-square frame: vertical anchor still flushes feet to the bottom")

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("actor_renderer_unit_test: all passed")
