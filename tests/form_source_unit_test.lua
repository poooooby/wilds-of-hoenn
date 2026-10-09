-- Run: lua tests/form_source_unit_test.lua
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

-- a fake engine: slot 300 = WORMADAM (413), 1100 = WORMADAM_SANDY (reports 413 too)
local NATIONAL = { [300] = 413, [1100] = 413, [1105] = 479, [1110] = 741, [5] = 5 }
local Engine = { nationalFor = function(slot) return NATIONAL[slot] end }
local V = { path = "." }
function V.require(name)
  if name == "engine_patch" then return Engine end
  return assert(loadfile("lib/" .. name .. ".lua"))(V)
end
local FormSource = V.require("form_source")

local IDS = { [300] = "WORMADAM", [1100] = "WORMADAM_SANDY", [1105] = "ROTOM_HEAT", [1110] = "ORICORIO_POM_POM" }
local function fakeMod(apiVersion)
  local api = {
    apiVersion = apiVersion,
    idOfSlot = function(slot) return IDS[slot] end,
    listForms = function()
      return {
        { id = "WORMADAM_SANDY", slot = 1100, baseSpecies = "WORMADAM", form = "SANDY", baseDex = 413, dex = 413 },
        { id = "ROTOM_HEAT", slot = 1105, baseSpecies = "ROTOM", form = "HEAT", baseDex = 479, dex = 479 },
        { id = "ORICORIO_POM_POM", slot = 1110, baseSpecies = "ORICORIO", form = "POM_POM", baseDex = 741, dex = 741 },
      }
    end,
  }
  return { find = function(_, id) if id == "national_dex_gen3" then return { exports = api } end end }
end

eq(FormSource.keyOf(413, "SANDY"), "413-sandy", "a key is %03d-<form>, lower-cased")
eq(FormSource.keyOf(7, "X"), "007-x", "...zero-padded")

local mod = fakeMod(2)
eq(FormSource.artKeyFor(mod, 300), 413, "a base species is its plain dex number")
eq(FormSource.artKeyFor(mod, 1100), "413-sandy", "a form shares the dex number but not the key")
eq(FormSource.artKeyFor(mod, 1105), "479-heat", "Rotom-Heat")
eq(FormSource.artKeyFor(mod, 1110), "741-pom_pom", "a form name keeps its underscores")
eq(FormSource.artKeyFor(mod, 5), 5, "a slot the mod does not know is its dex number")
eq(FormSource.artKeyFor(mod, 9999), nil, "a slot with no dex number has no key")

FormSource._reset()
eq(FormSource.artKeyFor(fakeMod(1), 1100), 413, "an older mod (no forms API) gives the base dex")
FormSource._reset()
eq(FormSource.artKeyFor({}, 1100), 413, "no national_dex_gen3 gives the base dex")
FormSource._reset()
local broken = fakeMod(2)
broken.find = function() error("boom") end
eq(FormSource.artKeyFor(broken, 1100), 413, "a failing lookup falls back quietly")

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("form_source_unit_test: all passed")
