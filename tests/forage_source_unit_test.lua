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

local E = { catalogCalls = 0, bag = {}, bagFull = false, fullAfter = nil }
E.itemCatalog = function(_mod)
  E.catalogCalls = E.catalogCalls + 1
  return {
    { id = 13, name = "Potion", pocket = "ITEMS", price = 300, use = "heal" },
    { id = 346, name = "HM08", pocket = "TM_CASE", price = 0, isHm = true },
    { id = "DUSK_STONE", name = "Dusk Stone", pocket = "ITEMS", price = 2100, use = "evo", extra = true },
  }
end
E.bagCanAdd = function(id) return not E.bagFull and id ~= nil end
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
local rolled = src:roll(0)
check(rolled and rolled.name == "Potion" and rolled.tier == 1, "a roll returns the find and its tier")
eq(#E.bag, 0, "...but rolling bags nothing")
local got = src:commit(rolled)
check(got and got.name == "Potion", "commit bags it and says what it was")
eq(#E.bag, 1, "...one item in the bag")
eq(E.bag[1][1], 13, "...by id")
src:roll(0)
eq(E.catalogCalls, 1, "the pool is built once")

-- friendship decides the tier: at 0 the rare Dusk Stone can never come up
local rare = 0
local r = ForageSource.new({}, { rng = (function() local x = 0 return function() x = (x * 7 + 3) % 101 return x / 101 end end)() })
for _ = 1, 300 do
  local x = r:roll(0)
  if x.tier == 3 then rare = rare + 1 end
end
eq(rare, 0, "a friendship-0 Pokemon never rolls the rare find")
local rareHi = 0
for _ = 1, 300 do
  local x = r:roll(255)
  if x.tier == 3 then rareHi = rareHi + 1 end
end
check(rareHi > 0, "a friendship-255 Pokemon does (" .. rareHi .. " of 300)")

-- a full bag: nothing to set out for, nothing lost
E.bagFull = true
eq(src:roll(255), nil, "a full bag rolls nothing (so no trip starts)")
-- the bag fills while the Pokemon is out: one fresh roll, then nothing
E.bagFull = false
local pending = src:roll(0)
E.bagFull = true
eq(src:commit(pending), nil, "the bag filled during the trip: nothing is bagged")
E.bagFull = false
local before = #E.bag
local realAdd = E.bagAdd
local first = true
E.bagAdd = function(id, qty)
  if first then first = false return false end -- this item no longer fits ...
  return realAdd(id, qty)                      -- ... but another one does
end
check(src:commit(src:roll(0)) ~= nil, "if the rolled item no longer fits, one that does is bagged")
eq(#E.bag, before + 1, "...exactly one")
E.bagAdd = realAdd
eq(src:commit(nil), nil, "committing nothing does nothing")

local callsBefore = E.catalogCalls
src:reset()
src:roll(0)
eq(E.catalogCalls, callsBefore + 1, "reset rebuilds the pool from the engine")
check(not src:getPool().tiers[2].entries[1], "the HM never made it into the pool")

E.itemCatalog = function() return {} end
src:reset()
eq(src:roll(255), nil, "an empty catalog finds nothing")

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("forage_source_unit_test: all passed")
