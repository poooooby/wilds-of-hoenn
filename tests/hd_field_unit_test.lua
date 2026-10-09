-- Run: lua tests/hd_field_unit_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
local failures = 0
local function check(cond, msg)
  if not cond then failures = failures + 1; io.stderr:write("FAIL: " .. tostring(msg) .. "\n") else print("ok  " .. tostring(msg)) end
end
local HdField = assert(loadfile("lib/hd_field.lua"))({ require = function() end })

-- no library: nothing is tagged, nothing breaks
local plainMod = { find = function() return nil end }
check(HdField.tag(plainMod, {}) == false, "without gen3-hd-sprites a sheet is left alone")
check(HdField.tag(nil, {}) == false, "...and without a mod table")

-- with the library: every sheet gets the one shared spec
local tagged = {}
local lib = { exports = { tag = function(img, spec) tagged[#tagged + 1] = { img = img, spec = spec } end } }
local mod = { find = function(_, id) return id == "gen3-hd-sprites" and lib or nil end }
local a, b = {}, {}
check(HdField.tag(mod, a) and HdField.tag(mod, b), "sheets are tagged when the library is there")
check(tagged[1].spec == tagged[2].spec, "...with one shared spec")
check(tagged[1].spec.anchor == "feet", "...anchored at the feet")

-- the option changes the shared spec, so loaded sheets follow
check(HdField.setSize("75") == 0.75 and tagged[1].spec.scale == 0.75, "Overworld Size 75% -> scale 0.75 on loaded sheets")
check(HdField.setSize("100") == 1, "100% -> 1")
check(HdField.setSize(nil) == 1 and HdField.setSize("junk") == 1, "a bad value is 100%")
check(HdField.setSize("10") == 0.25, "clamped to at least 25%")

if failures > 0 then io.stderr:write(failures .. " failure(s)\n") os.exit(1) end
print("hd_field_unit_test: all passed")
