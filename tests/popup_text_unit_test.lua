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
E.drawText = function(text, x, y, opts) E.drawn[#E.drawn + 1] = { text, x, y, opts } return #text * 6 end
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

-- with a fake love: the bubble and the text, centred on the label's anchor
local rects, colours, savedLove = {}, {}, love
local function fakeLove()
  rects, colours = {}, {}
  love = { graphics = {
    setColor = function(r, g, b, al) colours[#colours + 1] = { r, g, b, al } end,
    rectangle = function(mode, x, y, w, h) rects[#rects + 1] = { mode, x, y, w, h, colours[#colours] } end,
  } }
end
local function cover()
  local px, minX, maxX, minY, maxY = {}, math.huge, -math.huge, math.huge, -math.huge
  for _, r in ipairs(rects) do
    for y = r[3], r[3] + r[5] - 1 do for x = r[2], r[2] + r[4] - 1 do
      px[x .. "," .. y] = r[6]
      minX, maxX = math.min(minX, x), math.max(maxX, x)
      minY, maxY = math.min(minY, y), math.max(maxY, y)
    end end
  end
  return px, minX, maxX, minY, maxY
end
fakeLove()
a.draw(a, 8, 4)
love = savedLove
eq(a.style, "bubble", "\"Found Potion!\" is a speech bubble")
eq(#E.drawn, 2, "the text, one word at a time (the small font's space draws a stray glyph)")
local px, minX, maxX, minY, maxY = cover()
check(maxX - minX + 1 > 13 * 6, "the bubble is wider than the text")
local white = px[(minX + 3) .. "," .. (minY + 3)]
check(white and white[1] == 1 and white[2] == 1, "white inside")
local line = px[(minX + 3) .. "," .. minY]
check(line and line[1] < 0.3, "a dark outline along its top")
check(not px[minX .. "," .. minY] and not px[(minX + 1) .. "," .. minY], "...its corners rounded")
local mid = minX + math.floor((maxX - minX + 1) / 2)
check(px[mid .. "," .. maxY] and not px[(mid - 1) .. "," .. maxY] and not px[(mid + 1) .. "," .. maxY],
  "a tail narrowing to one pixel at the bottom centre")
check(math.abs(mid - (72 - 8)) <= 1, "...right under the label's anchor")
check(maxY < 48 - 4 - 20 + 1, "...ending just above where the label stands")
check(E.drawn[1][4] == nil or E.drawn[1][4].colorName == nil, "the text in the font's dark colours")
local plate = { "fill", minX }

-- the styles
eq(PopupText.styleFor("Found Potion!"), "bubble", "styles: an item found -> bubble")
eq(PopupText.styleFor("+12 EXP"), "bubble", "...EXP -> bubble")
eq(PopupText.styleFor("Lv.14!"), "level", "...a level -> rainbow letters")
eq(PopupText.styleFor("New move ready!"), "bubble", "...a move ready -> bubble")
eq(PopupText.styleFor("Ready to evolve!"), "bubble", "...an evolution ready -> bubble")
eq(PopupText.styleFor("Hello"), "bubble", "...anything else -> bubble")

-- level-up: rainbow letters in a wave, a glow growing in and out
local l0, l1 = PopupText.rainbowLetters("Lv.14!", 0), PopupText.rainbowLetters("Lv.14!", 30)
eq(#l0, 6, "one rainbow letter per character")
check(l0[1].r ~= l0[4].r or l0[1].g ~= l0[4].g or l0[1].b ~= l0[4].b, "...coloured along the word")
check(l0[1].r ~= l1[1].r or l0[1].g ~= l1[1].g or l0[1].b ~= l1[1].b, "...the colours shifting over time")
local waveOk, moved = true, false
for t = 0, 120 do
  for i, l in ipairs(PopupText.rainbowLetters("Lv.14!", t)) do
    if math.abs(l.dy) > 2.001 then waveOk = false end
    if l.dy ~= l0[i].dy then moved = true end
  end
end
check(waveOk and moved, "...each letter rising and falling within 2 px")
check(l0[1].dy ~= l0[3].dy, "...in turn, not all together")
eq(#PopupText.rainbowLetters("Lv 14", 0), 4, "a space is a gap, not a letter")
check(PopupText.rainbowLetters("Lv 14", 0)[3].gap, "...marked on the letter after it")
local gMin, gMax = math.huge, -math.huge
for t = 0, 160 do
  local gl = PopupText.glow(t)
  gMin, gMax = math.min(gMin, gl.grow), math.max(gMax, gl.grow)
  if gl.alpha < 0.1 - 1e-9 or gl.alpha > 0.28 + 1e-9 then check(false, "glow alpha out of range") end
end
check(gMin < 1.1 and gMax > 2.9, "the glow grows in and out (1..3 px)")
local lv = PopupText.actor("Lv.14!", 64, 48, 3, 20, 2, 10)
fakeLove()
E.drawn = {}
lv.draw(lv, 8, 4)
love = savedLove
eq(#E.drawn, 6, "no canvas: each letter drawn on its own")
local first = E.drawn[1][4]
check(first and first.colors and first.colors.fg and first.colors.fg[1] ~= nil, "...in its own colour")
check(#rects > 0, "...over the glow")

-- a move / evolution ready label is a speech bubble too
local rd = PopupText.actor("New move ready!", 64, 48, 3, 20, 2, 25)
eq(rd.style, "bubble", "\"New move ready!\" is a speech bubble like the rest")

-- the Game Boy font only draws dark: the classic light plate there, for every label
E.fontLayout = function() return "gb" end
fakeLove()
E.drawn = {}
a.draw(a, 8, 4)
love = savedLove
eq(#rects, 2, "Game Boy: a dark outline and a white plate")
fakeLove()
E.drawn = {}
lv.draw(lv, 8, 4)
love = savedLove
eq(#rects, 2, "...a level-up too (no rainbow)")
E.fontLayout = nil
E.drawn = {}
fakeLove()
a.draw(a, 8, 4)
love = savedLove
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


-- ------- the label is baked into a small canvas once and drawn like a sprite
do
  PopupText._dropCache()
  E.measureText = function(t) return #t * 6 end
  E.drawn = {}
  local log, canvases = {}, 0
  local state = { canvas = "screen" }
  local savedLove = love
  local function rec(name) return function(...) log[#log + 1] = { name, state.canvas, ... } end end
  love = { graphics = {
    setColor = function() end,
    rectangle = rec("rectangle"),
    draw = rec("draw"),
    newCanvas = function(w, h, settings)
      canvases = canvases + 1
      return { w = w, h = h, settings = settings, setFilter = function(self, a, b) self.filter = a .. b end }
    end,
    setCanvas = function(c) state.canvas = c or "screen" end,
    push = function(kind) log[#log + 1] = { "push", kind } state.saved = state.canvas end,
    pop = function() log[#log + 1] = { "pop" } state.canvas = state.saved end,
    origin = function() end, setScissor = function() end, setShader = function() end,
    setBlendMode = function() end, clear = function() end,
  } }
  local origDraw = E.drawText
  E.drawText = function(text, x, y, opts) log[#log + 1] = { "text", state.canvas, text, x, y } return origDraw(text, x, y, opts) end
  local actor = PopupText.actor("+8 EXP", 0, 0, 3, 20, 0)
  actor.draw(actor, 0, 0)
  eq(canvases, 1, "the label is baked into ONE canvas")
  local texts, onCanvas, drawn = {}, true, nil
  for _, e in ipairs(log) do
    if e[1] == "text" then texts[#texts + 1] = e[3] onCanvas = onCanvas and type(e[2]) == "table" end
    if e[1] == "draw" then drawn = e end
  end
  eq(table.concat(texts, "|"), "+8|EXP", "the words are painted one at a time ...")
  check(onCanvas, "... onto that canvas, not the screen")
  check(log[1][1] == "push" and log[1][2] == "all", "the graphics state is saved first (push 'all')")
  eq(log[#log][1] == "draw" and log[#log][2], "screen", "the canvas is then drawn to the screen like a sprite")
  check(drawn ~= nil, "(the whole label is one draw call)")
  local canvas = nil
  for _, e in ipairs(log) do if e[1] == "draw" then canvas = e[3] end end
  eq(canvas.settings.dpiscale, 1, "the canvas is 1:1 with the game pixels (no DPI scaling)")
  eq(canvas.filter, "nearestnearest", "...and nearest-filtered")
  eq(canvas.w, 1 + 2 + (6 * 2 + 6 * 3 + 3) + 2 + 1, "it is the bubble's size: outline, padding, text")
  eq(canvas.h, 12 + 3, "...12 rows and the 3-row tail")
  log = {}
  actor.draw(actor, 0, 0)
  eq(canvases, 1, "a second frame reuses it (no new canvas)")
  local n = 0
  for _, e in ipairs(log) do if e[1] == "draw" then n = n + 1 end end
  eq(n, 1, "...and just draws it")

  -- a different label gets its own canvas
  local other = PopupText.actor("Found Potion!", 0, 0, 3, 20, 1)
  other.draw(other, 0, 0)
  eq(canvases, 2, "another label bakes another canvas")

  -- no canvas support: the plate and text are drawn straight to the screen
  PopupText._dropCache()
  love.graphics.newCanvas = nil
  log = {}
  actor.draw(actor, 0, 0)
  local rects, direct = 0, true
  for _, e in ipairs(log) do
    if e[1] == "rectangle" then rects = rects + 1 end
    if e[1] == "text" and e[2] ~= "screen" then direct = false end
  end
  check(rects > 10, "without canvases the bubble is drawn directly")
  check(direct, "...with the text straight on the screen")

  -- a canvas that cannot be created falls back too
  PopupText._dropCache()
  love.graphics.newCanvas = function() error("no gpu") end
  log = {}
  actor.draw(actor, 0, 0)
  local rects2 = 0
  for _, e in ipairs(log) do if e[1] == "rectangle" then rects2 = rects2 + 1 end end
  check(rects2 > 10, "a canvas that fails to build falls back to direct drawing")
  E.drawText = origDraw
  love = savedLove
  PopupText._dropCache()
end

-- ------- the text sits lower in its cell on Ruby / Sapphire / Emerald than on
-- FireRed / LeafGreen, so the pen is dropped by a different amount
do
  local function textY(layout)
    E.fontLayout = function() return layout end
    E.measureText = function(t) return #t * 6 end
    E.drawn = {}
    local plateY, saved3 = nil, love
    love = { graphics = { setColor = function() end,
      rectangle = function(_m, _x, y) plateY = y end } }
    local actor = PopupText.actor("+5 EXP", 0, 0, 3, 20, 0)
    actor.draw(actor, 0, 0)
    love = saved3
    return E.drawn[1][3] - plateY
  end
  local rsOffset = textY("rs")
  local frlgOffset = textY("frlg")
  eq(textY(nil), rsOffset, "an unknown layout keeps the Ruby / Sapphire / Emerald drop")
  check(frlgOffset > rsOffset, "FireRed / LeafGreen's text is drawn lower than RSE's pen offset (less drop), so it is not cut off")
  eq(frlgOffset - rsOffset, 4, "by the difference between the two drops")
  E.fontLayout = nil
end


-- ------- two-line bubbles (the Battler call-outs): broken at a space, never mid-word
eq(PopupText.twoLines("Get 'em, MARSHTOMP!"), "Get 'em,\nMARSHTOMP!", "broken at the space nearest the middle")
eq(PopupText.twoLines("Show 'em what you've got!"), "Show 'em what\nyou've got!", "...a longer one too")
eq(PopupText.twoLines("Go!"), "Go!", "one word: one line")
eq(PopupText.twoLines("A BCDEFGHIJKLMNOP"), "A\nBCDEFGHIJKLMNOP", "...only ever at a space, never inside a word")
eq(PopupText.twoLines("once\nalready"), "once\nalready", "already two lines: kept")
local ls = PopupText.lines("one\ntwo")
check(#ls == 2 and ls[1] == "one" and ls[2] == "two", "lines() splits at the line break")

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("popup_text_unit_test: all passed")
