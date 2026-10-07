-- Run: lua tests/popup_text_unit_test.lua
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

local E = { drawn = {} }
E.measureText = function(text) return #text * 6 end
E.drawText = function(text, x, y) E.drawn[#E.drawn + 1] = { text, x, y } return #text * 6 end
local V = { path = "." }
function V.require(name)
  if name == "engine_patch" then return E end
  error("unexpected " .. name)
end
local PopupText = assert(loadfile("lib/popup_text.lua"))(V)

eq(PopupText.actor("", 0, 0), nil, "no text, no label")
eq(PopupText.actor(nil, 0, 0), nil, "...nor for nil")

local a = PopupText.actor("Found Potion!", 64, 48, 3, 20, 2)
eq(a.kind, "follower_popup", "it is a field actor of its own kind")
eq(a.x, 72, "centred over the tile")
eq(a.y, 48, "at the tile's top")
check(a.sortY > a.y, "it sorts in front of the sprites beside it")
eq(a.i, 90602, "with its own id")
check(pcall(a.draw, a, 0, 0), "drawing without love.graphics is harmless")

-- with a fake love: a plate and the text, centred on the label's anchor
local rects, savedLove = {}, love
love = { graphics = {
  setColor = function() end,
  rectangle = function(mode, x, y, w, h) rects[#rects + 1] = { mode, x, y, w, h } end,
} }
a.draw(a, 8, 4)
love = savedLove
eq(#rects, 2, "a dark outline and a white plate are drawn")
eq(#E.drawn, 2, "then the text, one word at a time (the small font's space draws a stray glyph)")
local plate = rects[2]
check(plate[4] > 13 * 6, "the plate is wider than the text")
eq(E.drawn[1][1], "Found", "the first word")
eq(E.drawn[2][1], "Potion!", "...then the second")
eq(E.drawn[2][2], E.drawn[1][2] + 5 * 6 + 3, "...after the first one's width and a plain gap")
eq(table.concat(PopupText.words("+5 EXP"), "|"), "+5|EXP", "words splits at spaces")
eq(#PopupText.words("   "), 0, "...and ignores blanks")
check(E.drawn[1][2] > plate[2], "...inside the plate")

E.measureText = function() return 0 end
rects, E.drawn = {}, {}
love = { graphics = { setColor = function() end, rectangle = function() rects[#rects + 1] = true end } }
a.draw(a, 0, 0)
love = savedLove
eq(#rects, 0, "without the engine font nothing is drawn")


-- ------- the plate grows with the text: 1, 2 and 3 digit EXP
do
  local function plateWidth(text)
    E.measureText = function(t) return #t * 6 end
    E.drawn = {}
    local rects2, saved2 = {}, love
    love = { graphics = { setColor = function() end,
      rectangle = function(_m, _x, _y, w) rects2[#rects2 + 1] = w end } }
    local actor = PopupText.actor(text, 0, 0, 3, 20, 0)
    actor.draw(actor, 0, 0)
    love = saved2
    return rects2[2], #E.drawn
  end
  local w1, n1 = plateWidth("+5 EXP")
  local w2 = plateWidth("+50 EXP")
  local w3, n3 = plateWidth("+123 EXP")
  check(w2 > w1 and w3 > w2, "more digits make a wider plate (" .. w1 .. " < " .. w2 .. " < " .. w3 .. ")")
  eq(w3 - w1, 2 * 6, "...by exactly the extra digits' width")
  eq(n1, 2, "the words are still drawn separately (1 digit)")
  eq(n3, 2, "...and with 3 digits")
end


-- ------- the text is clipped to the plate (the small face's empty cell half holds grey pixels)
do
  E.measureText = function(t) return #t * 6 end
  E.drawn = {}
  local scissors, calls = {}, {}
  local savedLove = love
  love = { graphics = {
    setColor = function() end,
    rectangle = function() end,
    getScissor = function() return nil end,
    transformPoint = function(x, y) return x * 2, y * 2 end, -- the field is scaled
    setScissor = function(...) scissors[#scissors + 1] = { ... } end,
  } }
  local orig = E.drawText
  E.drawText = function(...) calls[#calls + 1] = #scissors return orig(...) end
  local actor = PopupText.actor("+8 EXP", 0, 0, 3, 20, 0)
  actor.draw(actor, 0, 0)
  E.drawText = orig
  love = savedLove
  eq(#scissors, 2, "the clip is set, then restored")
  check(scissors[1][3] > 0 and scissors[1][4] == 20, "the clip is the plate's rectangle, in the scaled coordinates (height 10 x 2)")
  eq(scissors[2][1], nil, "the previous (no) scissor is restored afterwards")
  eq(calls[1], 1, "the words are drawn while the clip is on")
end

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("popup_text_unit_test: all passed")
