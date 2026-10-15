-- Run: lua tests/voxel_sprite_billboards_adapter_unit_test.lua
-- lib/compat/ (Wilds of Kanto Revival's voxel adapters): every provider's adapter wraps its
-- SpriteBillboards so a def with its own geometry (our voxel sheets) gets a card of that
-- size -- with the feet `cut` TERRARIUM passes -- while a classic 16x16 def keeps the
-- provider's own card.
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

local fakeAssets = {
  image = function() return { getDimensions = function() return 64, 384 end } end,
  register = function() end,
}
local realRequire = require
require = function(p) if p == "src.render.Assets" then return fakeAssets end return realRequire(p) end

local ours = { image = "wilds_of_hoenn/voxel/x.png", frames = 6, frameWidth = 64, frameHeight = 64, anchorX = 32, anchorY = 64 }

for _, case in ipairs({
  { file = "compat/terrarium_variable_geometry", id = "TERRARIUM" },
  { file = "compat/potato_voxel_variable_geometry", id = "potato_voxel" },
  { file = "compat/dramaless_variable_geometry", id = "DRAMALESS_SHAPE" },
  { file = "compat/stadium2_variable_geometry", id = "STADIUM2_OVERWORLD_MODELS" },
}) do
  local made = 0
  local SB = {}
  SB.mesh = function(def) return "orig:" .. tostring(def.image) end
  SB.shadowQuad = SB.mesh
  SB.invalidate = function() end
  local Voxel3D = {
    pushQuad = function(ind) ind[#ind + 1] = 1 end,
    newMesh = function(verts) made = made + 1 return { verts = verts } end,
  }
  local provider = { exports = { lib = { require = function(n)
    if n == "SpriteBillboards" then return SB end
    if n == "Voxel3D" then return Voxel3D end
  end } } }
  local mod = { find = function(_, id) return id == case.id and provider or nil end, log = { info = function() end } }
  modules[case.file] = nil
  modules["compat/voxel_sprite_billboards_adapter"] = nil
  local Adapter = V.require(case.file)
  eq(Adapter.PROVIDER_ID, case.id, case.id .. ": the adapter is for that provider")
  check(Adapter.install(mod), case.id .. ": installs over its SpriteBillboards")
  local m = SB.mesh(ours, 3)
  check(type(m) == "table" and m.verts, case.id .. ": our sheet gets a card of its own")
  local v = m.verts
  eq(v[2][1] - v[1][1], 64, case.id .. ": 64 px wide")
  eq(v[1][1], 8 - 32, case.id .. ": its anchor on the pivot (x 8)")
  eq(v[3][2], 64, case.id .. ": 64 px tall, feet on the ground")
  check(SB.mesh(ours, 3) == m and made == 1, case.id .. ": cached")
  eq(SB.mesh({ image = "red.png" }, 0), "orig:red.png", case.id .. ": a classic 16x16 def keeps the provider's card")
  check(SB.shadowQuad(ours, 3) == m, case.id .. ": the sun / silhouette pass gets the same card")
  local c = SB.mesh(ours, 3, 6)
  check(c ~= m, case.id .. ": a cut is its own card")
  eq(c.verts[1][2], 0, case.id .. ": cut: the cut edge is the card's origin")
  eq(c.verts[3][2], 58, case.id .. ": ...the body above it")
  check(math.abs(c.verts[1][5] - (3 * 64 + 64 - 6) / 384) < 1e-9, case.id .. ": ...its bottom samples 6 rows above the feet")
  check(SB.mesh(ours, 3, 999).verts[3][2] == 64 - 48, case.id .. ": a cut stops at three quarters of the body")
  local sized = { image = ours.image, frames = 6, frameWidth = 64, frameHeight = 64, anchorX = 32, anchorY = 64,
    displayWidth = 64 * 0.85, displayHeight = 64 * 0.85 }
  local sm = SB.mesh(sized, 3)
  eq(sm.verts[2][1] - sm.verts[1][1], 54, case.id .. ": Species Sizes: the card is the display size (rounded)")
  eq(sm.verts[1][1], 8 - 27, case.id .. ": ...its anchor scaled with it, still on the pivot")
  Adapter.reset()
  eq(SB.mesh({ image = "a" }), "orig:a", case.id .. ": reset puts the provider's own back")
end

-- no provider loaded: nothing to do
modules["compat/terrarium_variable_geometry"] = nil
modules["compat/voxel_sprite_billboards_adapter"] = nil
local Absent = V.require("compat/terrarium_variable_geometry")
check(not Absent.install({ find = function() return nil end, log = { info = function() end } }), "no provider: nothing installed")

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("voxel_sprite_billboards_adapter_unit_test: all passed")
