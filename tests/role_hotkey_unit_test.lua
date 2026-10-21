-- Run: lua tests/role_hotkey_unit_test.lua
-- lib/role_hotkey.lua: one button / key flips the partner between Battle and Follow in the
-- overworld, swallowing the press only when it acts.
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

local RoleHotkey = assert(loadfile("lib/role_hotkey.lua"))({})

eq(RoleHotkey.nextRole("battle"), "follow", "Battle -> Follow")
eq(RoleHotkey.nextRole("follow"), "battle", "Follow -> Battle")
eq(RoleHotkey.nextRole("forage"), "battle", "Forage -> Battle")
eq(RoleHotkey.nextRole("recall"), "battle", "recalled -> Battle")

local mon = { personality = 7 }
local state = { pad = "r", key = "e", free = true, role = "follow", mon = mon }
local notes, sounds = {}, 0
local hk = RoleHotkey.new({
  padChoice = function() return state.pad end,
  keyChoice = function() return state.key end,
  free = function() return state.free end,
  current = function() return state.mon, state.role end,
  set = function(m, role) if m ~= mon then return false end state.role = role return true end,
  nameOf = function() return "MUDKIP" end,
  notify = function(text) notes[#notes + 1] = text end,
  sound = function() sounds = sounds + 1 end,
})

-- the keyboard
eq(hk:onKey({ phase = "pressed", key = "e" }), true, "E pressed in the free overworld: ours (swallowed)")
eq(state.role, "battle", "...the partner battles now")
eq(notes[1], "Go!\nMUDKIP!", "...the player calls it out by name, like sending it into battle")
eq(sounds, 1, "...with the select sound")
eq(hk:onKey({ phase = "pressed", key = "e" }), true, "held (a key repeat): still ours")
eq(state.role, "battle", "...but it flips only once")
eq(hk:onKey({ phase = "released", key = "e" }), true, "its release is ours too")
eq(hk:onKey({ phase = "pressed", key = "e" }), true, "pressed again")
eq(state.role, "follow", "...back to Follow")
eq(notes[2], "That's enough,\nMUDKIP!", "...and calls it back like a recall")
hk:onKey({ phase = "released", key = "e" })
eq(hk:onKey({ phase = "pressed", key = "q" }), false, "another key goes through")
eq(state.role, "follow", "...and changes nothing")
state.free = false
eq(hk:onKey({ phase = "pressed", key = "e" }), false, "a menu / message / battle up: E goes through to the game")
eq(state.role, "follow", "...the partner untouched")
eq(hk:onKey({ phase = "released", key = "e" }), false, "...and so does its release")
state.free = true
state.key = "off"
eq(hk:onKey({ phase = "pressed", key = "e" }), false, "keyboard option OFF: nothing is ours")
state.key = "r"
eq(hk:onKey({ phase = "pressed", key = "r" }), true, "the R key option")
hk:onKey({ phase = "released", key = "r" })
eq(state.role, "battle", "...flips it")

-- the controller
eq(hk:onPad({ phase = "pressed", button = "rightshoulder" }), true, "R shoulder pressed: ours")
eq(state.role, "follow", "...flipped back")
hk:onPad({ phase = "released", button = "rightshoulder" })
eq(hk:onPad({ phase = "pressed", button = "leftshoulder" }), false, "L goes through while the option is R")
state.pad = "l"
eq(hk:onPad({ phase = "pressed", button = "leftshoulder" }), true, "the L option takes L")
hk:onPad({ phase = "released", button = "leftshoulder" })
eq(hk:onPad({ phase = "axis", axis = "leftx", value = 0.5 }), false, "stick movement goes through")
state.pad = "off"
eq(hk:onPad({ phase = "pressed", button = "leftshoulder" }), false, "controller option OFF: nothing is ours")

-- no partner (an empty / all-egg party) or a refused set: the press goes through
state.pad, state.mon = "r", nil
eq(hk:onPad({ phase = "pressed", button = "rightshoulder" }), false, "no partner: goes through")
state.mon = mon
hk.deps.set = function() return false end
eq(hk:onPad({ phase = "pressed", button = "rightshoulder" }), false, "a refused change: goes through")
eq(hk:onKey(nil), false, "a nil event never errors")

-- the call-outs: each list in turn, never the same line twice running
eq(RoleHotkey.lineFor("battle", 2, "Rex"), "Get 'em,\nRex!", "the second send-out line, broken before the name")
eq(RoleHotkey.lineFor("follow", 2, "Rex"), "Come back,\nRex!", "the second recall line")
eq(RoleHotkey.lineFor("battle", #RoleHotkey.SEND + 1, "Rex"), RoleHotkey.lineFor("battle", 1, "Rex"), "the list wraps round")
eq(RoleHotkey.lineFor("follow", 3, "A%B"), "A%B, good!\nCome back!", "a name with a % in it is kept as it is")
for _, list in ipairs({ RoleHotkey.SEND, RoleHotkey.RECALL }) do
  for _, line in ipairs(list) do
    local _, breaks = line:gsub("|", "")
    eq(breaks, 1, "one break in: " .. line)
  end
end
check(#RoleHotkey.SEND >= 8 and #RoleHotkey.RECALL >= 8, "plenty of lines for flavour")
for i = 2, #RoleHotkey.SEND do
  check(RoleHotkey.SEND[i] ~= RoleHotkey.SEND[i - 1], "send-out line " .. i .. " differs from the one before")
end

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("role_hotkey_unit_test: all passed")
