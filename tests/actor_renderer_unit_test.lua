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

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("actor_renderer_unit_test: all passed")
