-- Run: lua tests/renderer_factory_unit_test.lua
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
  local value = assert(loadfile("lib/" .. name .. ".lua"))(V)
  modules[name] = value
  return value
end

local INDEX = [[{"version":1,"dex":{"252":{
  "walk":{"cw":30,"ch":26,"cols":4,"durations":[6,10,6,10],"ax":15.5,"ay":19.5,"shiny":true},
  "idle":{"cw":29,"ch":31,"cols":3,"durations":[40,4,2],"ax":15.5,"ay":25.5,"shiny":false}}}}]]
local mod = { read = function(_, rel) if rel == "assets/pmd/index.json" then return INDEX end end }
V.mod = mod

local SpriteSource = V.require("sprite_source")
local Factory = V.require("renderer_factory")

-- the index drives availability
check(SpriteSource.pmdInfo(mod, 252) ~= nil, "a species in the index has PMD info")
check(SpriteSource.pmdInfo(mod, 1) == nil, "a species not in the index has none")
eq(SpriteSource.pmdPath(SpriteSource.pmdInfo(mod, 252), "walk", 252, true),
  "assets/pmd/walk/252-shiny.png", "shiny walk sheet path")
eq(SpriteSource.pmdPath(SpriteSource.pmdInfo(mod, 252), "idle", 252, true),
  "assets/pmd/idle/252-normal.png", "no baked shiny idle -> the normal sheet")
eq(SpriteSource.pmdPath(SpriteSource.pmdInfo(mod, 252), "walk", 252, false),
  "assets/pmd/walk/252-normal.png", "normal walk sheet path")

-- PMD style + art -> PmdRenderer
local r = Factory.new(mod, 252, false, "pmd")
check(r.isPmd == true, "pmd style with art builds a PmdRenderer")

-- PMD style, species without art -> falls back to the HGSS renderer
local fb = Factory.new(mod, 1, false, "pmd")
check(not fb.isPmd, "pmd style without art does not build a PmdRenderer")
eq(fb.style, "pokemmo", "and falls back to the HGSS / PokeMMO style")
eq(fb.frameCount, 18, "with that style's 18-frame layout")

-- the other styles never touch PMD
local f = Factory.new(mod, 252, false, "pokemmo")
check(not f.isPmd, "pokemmo style is an ActorRenderer")
eq(f.frameCount, 18, "with the 18-frame layout")
local stale = Factory.new(mod, 252, false, "followers")
check(not stale.isPmd and stale.frameCount == 18, "a stale 'followers' style is an 18-frame ActorRenderer, never a 6-frame one")

-- no index at all (a checkout that never baked PMD) -> always the fallback
local bare = { read = function() return nil end }
SpriteSource._resetPmdCache()
check(not Factory.new(bare, 252, false, "pmd").isPmd, "no index.json -> fallback renderer")
local garbage = { read = function() return "not json" end }
check(not Factory.new(garbage, 252, false, "pmd").isPmd, "malformed index.json -> fallback renderer")

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("renderer_factory_unit_test: all passed")
