-- Run: lua tests/forage_source_unit_test.lua
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

local E = { catalogCalls = 0, bag = {}, bagFull = false }
E.itemCatalog = function(_mod)
  E.catalogCalls = E.catalogCalls + 1
  return {
    { id = 13, name = "Potion", pocket = "ITEMS", price = 300, use = "heal" },
    { id = 346, name = "HM08", pocket = "TM_CASE", price = 0, isHm = true },
  }
end
E.bagAdd = function(id, qty)
  if E.bagFull then return false end
  E.bag[#E.bag + 1] = { id, qty }
  return true
end

local modules = {}
local V = { path = "." }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  if name == "engine_patch" then modules[name] = E return E end
  local value = assert(loadfile("lib/" .. name .. ".lua"))(V)
  modules[name] = value
  return value
end
local ForageSource = V.require("forage_source")

local src = ForageSource.new({}, { rng = function() return 0 end })
eq(E.catalogCalls, 0, "nothing is read from the engine until it is needed")
eq(src:pick(), "Potion", "a find is returned by name")
eq(#E.bag, 1, "...and put in the bag")
eq(E.bag[1][1], 13, "...by id")
src:pick()
eq(E.catalogCalls, 1, "the pool is built once")
E.bagFull = true
eq(src:pick(), nil, "a full bag finds nothing (and loses nothing)")
E.bagFull = false
src:reset()
src:pick()
eq(E.catalogCalls, 2, "reset rebuilds the pool from the engine")
check(not src:getPool().entries[2], "the HM never made it into the pool")

E.itemCatalog = function() return {} end
src:reset()
eq(src:pick(), nil, "an empty catalog finds nothing")

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("forage_source_unit_test: all passed")
