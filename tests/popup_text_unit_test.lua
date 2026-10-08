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
  eq(canvas.w, 4 + 6 * 2 + 6 * 3 + 3 + 2, "it is the plate plus its outline in size")
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
  eq(rects, 2, "without canvases the plate (outline + fill) is drawn directly")
  check(direct, "...with the text straight on the screen")

  -- a canvas that cannot be created falls back too
  PopupText._dropCache()
  love.graphics.newCanvas = function() error("no gpu") end
  log = {}
  actor.draw(actor, 0, 0)
  local rects2 = 0
  for _, e in ipairs(log) do if e[1] == "rectangle" then rects2 = rects2 + 1 end end
  eq(rects2, 2, "a canvas that fails to build falls back to direct drawing")
  E.drawText = origDraw
  love = savedLove
  PopupText._dropCache()
end

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("popup_text_unit_test: all passed")
