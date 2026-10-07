-- Run: lua tests/portrait_ui_unit_test.lua
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

local INDEX = [[{"version":1,"size":40,"dex":{
  "252":{"emotions":["Normal","Happy","Joyous"],"shiny":true},
  "6":{"emotions":["Normal","Sad"],"shiny":false}}}]]
local mod = { read = function(_, rel) if rel == "assets/pmd/portraits.json" then return INDEX end end }

local fakeEngine = { messageOpen = false, shown = {} }
fakeEngine.isMessageOpen = function() return fakeEngine.messageOpen end
fakeEngine.dialogueWindow = function() return { left = 2, top = 15, width = 26, height = 4 } end
fakeEngine.showMessage = function(text, opts)
  fakeEngine.shown[#fakeEngine.shown + 1] = { text = text, opts = opts }
  fakeEngine.messageOpen = true
  return true
end

local modules = {}
local V = { path = ".", mod = mod }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  if name == "engine_patch" then modules[name] = fakeEngine return fakeEngine end
  local value = assert(loadfile("lib/" .. name .. ".lua"))(V)
  modules[name] = value
  return value
end
local SpriteSource = V.require("sprite_source")
local PortraitUI = V.require("portrait_ui")

-- ------- the index drives which emotions/cells exist
local info = SpriteSource.portraitInfo(mod, 252)
check(info ~= nil and info.size == 40 and info.shiny == true, "portraitInfo reads the species entry")
check(SpriteSource.portraitInfo(mod, 1) == nil, "a species with no portraits has no info")
local path, col = SpriteSource.portraitCell(info, 252, false, "Joyous")
eq(path, "assets/pmd/portraits/252-normal.png", "normal sheet path")
eq(col, 2, "Joyous is the third column")
path, col = SpriteSource.portraitCell(info, 252, true, "Happy")
eq(path, "assets/pmd/portraits/252-shiny.png", "shiny sheet for a shiny mon")
eq(col, 1, "Happy is the second column")
path, col = SpriteSource.portraitCell(info, 252, false, "Pain")
eq(col, 0, "an emotion the species lacks falls back to Normal")
local info6 = SpriteSource.portraitInfo(mod, 6)
path = SpriteSource.portraitCell(info6, 6, true, "Sad")
eq(path, "assets/pmd/portraits/006-normal.png", "no shiny sheet baked -> the normal one")
check(SpriteSource.portraitCell(nil, 1, false, "Normal") == nil, "no info -> no cell")

-- ------- placement: above the left of the dialogue frame, in canvas px
local x, y = PortraitUI.placement({ left = 2, top = 15 }, 40)
eq(x, 16, "aligned with the text window's left edge (tile 2)")
eq(y, 112 - 40 - 2, "sits just above the frame (which starts a tile above the text window)")
local dx, dy = PortraitUI.placement(nil, 40)
check(dx == 16 and dy == 70, "defaults match the standard dialogue window")

-- ------- say(): shows the message, the portrait lives and dies with it
local ui = PortraitUI.new(mod)
check(not ui:isActive(), "starts with no portrait")
local closed = 0
check(ui:say("Hello!", { dex = 252, emotion = "Happy", done = function() closed = closed + 1 end }), "say shows a message")
check(ui:isActive() and ui.emotion == "Happy" and ui.dex == 252, "say sets the portrait")
eq(fakeEngine.shown[1].text, "Hello!", "the text reaches Message.show")
fakeEngine.shown[1].opts.done()
check(not ui:isActive(), "the portrait clears when the message closes")
eq(closed, 1, "and the caller's done callback still runs")

-- stay: the box (and portrait) remain up for a menu underneath
ui:say("Pick one", { dex = 6, stay = true })
fakeEngine.shown[2].opts.done()
check(ui:isActive(), "a stay message keeps the portrait up when its text finishes")
ui:setEmotion("Sad")
eq(ui.emotion, "Sad", "setEmotion changes the face between messages")
ui:clear()

-- draw clears itself when no message is open, and never throws without love
ui:show(252, false, "Normal")
fakeEngine.messageOpen = false
check(pcall(function() ui:draw() end), "draw without love/art never throws")
check(not ui:isActive(), "draw clears a portrait whose message is gone")
fakeEngine.messageOpen = true
ui:show(252, false, "Normal")
check(pcall(function() ui:draw() end), "draw with a message open but no renderer never throws")
check(ui:isActive(), "and keeps the portrait while the message is open")

-- say fails cleanly when the engine refuses the message
fakeEngine.showMessage = function() return false end
check(not ui:say("x", { dex = 252 }), "say reports a failed show")
check(not ui:isActive(), "and leaves no portrait behind")

-- ------- the face follows the mon's real state
fakeEngine.showMessage = function(text, opts)
  fakeEngine.shown[#fakeEngine.shown + 1] = { text = text, opts = opts }
  fakeEngine.messageOpen = true
  return true
end
fakeEngine.nationalFor = function(species) if species == 277 then return 252 end return nil end
fakeEngine.isShiny = function(personality) return personality == 99 end
local treecko = { species = 277, hp = 100, maxHp = 100, friendship = 255, personality = 1 }
check(ui:showMon(treecko), "showMon accepts a party mon")
eq(ui.dex, 252, "the portrait uses the NATIONAL dex number, not the engine species id")
eq(ui.emotion, "Inspired", "a healthy max-friendship mon is Inspired")
eq(ui.shiny, false, "not shiny")
treecko.status = "PSN"
ui:refreshMon(treecko)
eq(ui.emotion, "Pain", "refreshMon follows a status change")
treecko.status, treecko.hp = nil, 5
ui:refreshMon(treecko)
eq(ui.emotion, "Crying", "...and low HP")
treecko.hp, treecko.friendship = 100, 20
ui:refreshMon(treecko)
eq(ui.emotion, "Angry", "...and friendship")
treecko.personality = 99
ui:showMon(treecko, "Determined")
eq(ui.emotion, "Determined", "an explicit emotion overrides the derived one")
eq(ui.shiny, true, "the mon's shininess selects the shiny sheet")
check(not ui:showMon({ species = 4242 }), "a mon with no national dex number has no portrait")
ui:clear()
ui:refreshMon(treecko)
check(not ui:isActive(), "refreshMon never opens a portrait by itself")

ui:say("Hi", { mon = { species = 277, hp = 100, maxHp = 100, friendship = 150, personality = 1 } })
eq(ui.emotion, "Happy", "say{mon=} derives the emotion from the mon's state")
ui:say("Hi", { mon = { species = 277, hp = 100, maxHp = 100, friendship = 150, personality = 1 }, emotion = "Surprised" })
eq(ui.emotion, "Surprised", "say{mon=, emotion=} lets the caller override it")
ui:clear()

-- ------- a species lacking an emotion falls back along the chain
local sparse = { emotions = { "Normal", "Sad", "Crying" }, shiny = false, size = 40 }
local _, c1 = SpriteSource.portraitCell(sparse, 1, false, "Teary-Eyed")
eq(c1, 2, "Teary-Eyed -> Crying when that is what the species has")
local _, c2 = SpriteSource.portraitCell(sparse, 1, false, "Worried")
eq(c2, 1, "Worried -> Sad")
local _, c3 = SpriteSource.portraitCell(sparse, 1, false, "Inspired")
eq(c3, 0, "Inspired -> Joyous -> Happy -> Normal")
local _, c4 = SpriteSource.portraitCell({ emotions = { "Normal" }, shiny = false, size = 40 }, 1, false, "Stunned")
eq(c4, 0, "a Normal-only species always shows Normal")
local _, c5 = SpriteSource.portraitCell(sparse, 1, false, "Pain")
eq(c5, 1, "Pain -> Worried -> Sad")

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("portrait_ui_unit_test: all passed")
