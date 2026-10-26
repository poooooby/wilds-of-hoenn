-- Run: lua tests/spawn_filters_unit_test.lua
-- lib/spawn_filters.lua: other mods' species swaps run on a visible Pokemon as it is rolled.
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

local warned = {}
local V = { mod = { log = { warn = function(_, fmt, ...) warned[#warned + 1] = string.format(fmt, ...) end } } }
local F = assert(loadfile("lib/spawn_filters.lua"))(V)

local enc = { species = 37, level = 20, personality = 5 }
check(F.apply("FR_ROUTE_7", "land", enc, false) == enc, "no filters: the very same encounter")

-- the version-exclusive swap of the header's example (Vulpix -> Growlithe)
local seen
eq(F.add("highlander", function(e, info) seen = info if e.species == 37 then e.species = 58 end return e end), true,
  "a filter is added")
local out = F.apply("FR_ROUTE_7", "land", { species = 37, level = 20 }, true)
eq(out.species, 58, "the filter's species is the one that spawns")
eq(seen.mapId, "FR_ROUTE_7", "...told the map")
eq(seen.terrain, "land", "...the terrain")
eq(seen.lured, true, "...and that Sweet Scent called it")
eq(F.apply("FR_ROUTE_7", "land", { species = 16, level = 3 }).species, 16, "other species pass through")

-- speciesId follows; a filter returning a new table is used
F.add("copy", function(e) return { species = e.species, level = e.level, speciesId = 999 } end)
out = F.apply("M", "land", { species = 37, level = 5, speciesId = 37 })
eq(out.species, 58, "a later filter sees the earlier one's result")
eq(out.speciesId, 58, "speciesId is set from species")

-- replacing a filter by id; removing one
F.add("copy", function() return nil end)
eq(#F.list, 2, "the same id replaces, not adds")
eq(F.remove("copy"), true, "removed")
eq(F.remove("copy"), false, "removing again: false")

-- a filter that breaks, or leaves no species, never breaks the spawn
F.add("broken", function() error("boom") end)
out = F.apply("M", "land", { species = 37, level = 5 })
eq(out.species, 58, "an erroring filter is skipped")
eq(#warned, 1, "...and logged")
F.apply("M", "land", { species = 37, level = 5 })
eq(#warned, 1, "...once")
F.remove("broken")
F.add("nospecies", function(e) e.species = "nope" return e end)
eq(F.apply("M", "land", { species = 16, level = 5 }).species, 16, "no usable species: the rolled one is kept")
F.remove("nospecies")

-- roamers never go through filters; a non-function is refused
local roamer = { species = 37, roamer = true }
check(F.apply("M", "land", roamer) == roamer and roamer.species == 37, "a roamer is never filtered")
eq(F.add("x", "not a function"), false, "a filter must be a function")

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("spawn_filters_unit_test: all passed")
