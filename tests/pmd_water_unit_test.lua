-- Run: lua tests/pmd_water_unit_test.lua
-- The shipped true-flyer list (lib/pmd_water.lua, hand-edited): who the PMDCollab
-- style draws whole over water instead of swimming.
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

local modules = {}
local V = { path = ".", mod = {} }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  local value = assert(loadfile("lib/" .. name .. ".lua"))(V)
  modules[name] = value
  return value
end

local data = V.require("pmd_water")
check(type(data) == "table" and type(data.fly) == "table", "lib/pmd_water.lua returns { fly = {...} }")
for k, v in pairs(data.fly) do
  local ok = (type(k) == "number" and k >= 1 and k <= 1025 and k % 1 == 0)
    or (type(k) == "string" and k:find("^%d%d%d+%-.") ~= nil)
  if not ok then check(false, "bad key " .. tostring(k)) end
  if type(v) ~= "boolean" then check(false, "entry " .. tostring(k) .. " is not true/false") end
end

local SpriteSource = V.require("sprite_source")
for _, dex in ipairs({ 41, 42, 92, 93, 169, 384 }) do
  check(SpriteSource.pmdFlies(dex), "dex " .. dex .. " is drawn whole over water (a true flyer / floater)")
end
for _, dex in ipairs({ 6, 18, 149, 373, 7, 130, 131 }) do
  check(not SpriteSource.pmdFlies(dex), "dex " .. dex .. " swims (it walks, or is a water Pokemon)")
end

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("pmd_water_unit_test: all passed")
