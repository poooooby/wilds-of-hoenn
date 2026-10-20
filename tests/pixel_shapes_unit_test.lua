-- Run: lua tests/pixel_shapes_unit_test.lua
-- lib/pixel_shapes.lua: the shared registry of little code-drawn pixel shapes.
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

local PixelShapes = assert(loadfile("lib/pixel_shapes.lua"))({})

PixelShapes.define("dot", { { 1, 0 }, { 0, 2 } }, { { 1, 0, 0 }, { 0, 0, 1 } })
local w, h = PixelShapes.size("dot")
check(w == 2 and h == 2, "a defined shape has its size")
eq(select(1, PixelShapes.size("nothing")), 0, "an unknown shape is 0 wide")
PixelShapes.defineAll({ bar = { rows = { { 1, 1, 1 } }, colours = { { 1, 1, 1 } } } })
eq(select(1, PixelShapes.size("bar")), 3, "defineAll registers a table of shapes")

-- no image support: drawn pixel by pixel, the tint multiplying the colours, scaled
local rects, colours = {}, {}
local g = {
  setColor = function(r, gg, b, a) colours[#colours + 1] = { r, gg, b, a } end,
  rectangle = function(_, x, y, ww, hh) rects[#rects + 1] = { x, y, ww, hh } end,
}
PixelShapes.draw(g, "dot", 10, 20, 0.5, { 0.5, 1, 1 }, 2)
eq(#rects, 2, "two coloured pixels drawn (clear ones skipped)")
check(rects[1][1] == 10 and rects[1][2] == 20 and rects[1][3] == 2, "...scaled 2x from the top-left")
check(rects[2][1] == 12 and rects[2][2] == 22, "...the second pixel in place")
check(colours[1][1] == 0.5 and colours[1][4] == 0.5, "...tinted and faded")
rects = {}
PixelShapes.draw(g, "dot", 0, 0, 0)
eq(#rects, 0, "an invisible draw draws nothing")
PixelShapes.draw(g, "nothing", 0, 0, 1)
eq(#rects, 0, "an unknown shape draws nothing")

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("pixel_shapes_unit_test: all passed")
