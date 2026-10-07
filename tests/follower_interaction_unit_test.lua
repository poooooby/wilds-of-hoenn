-- Run: lua tests/follower_interaction_unit_test.lua
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

-- ------- fake engine: just the surface FollowerInteraction touches
local E = {
  startable = true, follower = { cellX = 1 }, lead = nil,
  messageOpen = false, lastPage = false, choiceUp = false, choice = nil,
  closedStay = 0,
}
E.canStartInteraction = function() return E.startable end
E.followerInFacingCell = function() return E.follower end
E.leadPartyMon = function() return E.lead end
E.displayName = function(mon) return mon.nickname or "TREECKO" end
E.isMessageOpen = function() return E.messageOpen end
E.messageOnLastPage = function() return E.lastPage end
E.closeStayMessage = function() E.closedStay = E.closedStay + 1 E.messageOpen = false return true end
E.showChoice = function(options, default, cb, layout)
  E.choice = { options = options, default = default, cb = cb, layout = layout }
  E.choiceUp = true
  return true
end
E.choiceActive = function() return E.choiceUp end
E.friendshipOf = function(mon) return mon.friendship or 0 end
E.setFriendship = function(mon, v) v = math.max(0, math.min(255, v)) mon.friendship = v return v end
E.petFriendship = function(mon)
  local before = mon.friendship or 0
  mon.friendship = math.min(255, before + 3)
  return mon.friendship - before
end

-- ------- fake portrait UI: records what is said, mimics the real contract
local P = { says = {}, cleared = 0 }
function P:say(text, opts)
  local entry = { text = text, opts = opts }
  P.says[#P.says + 1] = entry
  E.messageOpen = true
  return true
end
function P:clear() P.cleared = P.cleared + 1 end
local function lastSay() return P.says[#P.says] end
-- the player closes a non-stay message: the engine calls its `done`
local function closeMessage()
  E.messageOpen = false
  local done = lastSay().opts.done
  if done then done() end
end

local modules = {}
local mod = { id = "wilds_of_hoenn", options = { get = function(_, k) if k == "follower" then return true end end } }
local V = { path = ".", mod = mod }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  if name == "engine_patch" then modules[name] = E return E end
  local value = assert(loadfile("lib/" .. name .. ".lua"))(V)
  modules[name] = value
  return value
end
local Config = V.require("config")
local FollowerInteraction = V.require("follower_interaction")

local clock = 10000
local rng = function() return 0 end
local function newInteraction()
  P.says, P.cleared = {}, 0
  E.messageOpen, E.lastPage, E.choiceUp, E.choice = false, false, false, nil
  E.closedStay = 0
  return FollowerInteraction.new(mod, P, { clock = function() return clock end, rng = rng })
end
local function mon(t)
  local m = { nickname = "BLAZE", hp = 100, maxHp = 100, friendship = 100 }
  for k, v in pairs(t or {}) do m[k] = v end
  return m
end

-- walk a started interaction up to the open menu
local function openMenu(fi)
  fi:tick({})
  E.lastPage = true
  fi:tick({})
end
-- pick a row in the open menu (what Choice.confirm would do)
local function pick(index)
  E.choiceUp = false
  E.choice.cb(index)
end

-- ------- starting
local fi = newInteraction()
E.lead = mon()
check(fi:tryStart({}), "facing the follower and pressing A starts an interaction")
check(fi:isActive(), "...which is now active")
local say = lastSay()
check(say.opts.stay == true, "the report is a stay message (a menu goes under it)")
check(say.opts.mon == E.lead, "...shown with the lead Pokemon's own portrait")
check(say.text:find("BLAZE", 1, true), "...and its words name the Pokemon")

-- not started when the engine says no / nothing is there
local fi2 = newInteraction()
E.startable = false
check(not fi2:tryStart({}), "not while something else owns the screen")
E.startable = true
E.follower = nil
check(not fi2:tryStart({}), "not when the follower is not in the facing cell")
E.follower = { cellX = 1 }
E.lead = nil
check(not fi2:tryStart({}), "not without a party Pokemon")
E.lead = mon()
mod.options.get = function(_, k) if k == "follower" then return false end end
check(not fi2:tryStart({}), "not when the Follower option is off")
mod.options.get = function(_, k) if k == "follower" then return true end end

-- ------- a follower shrunk into the player (surfing, PMD recall) cannot be talked to
do
  local away = true
  local fiAway = FollowerInteraction.new(mod, P, { clock = function() return clock end, rng = rng, isAway = function() return away end })
  E.lead = mon()
  check(not fiAway:tryStart({}), "no interaction while the follower is recalled into the player")
  away = false
  check(fiAway:tryStart({}), "...and it works again once it is back out")
  fiAway:abort()
  E.messageOpen = false
end

-- ------- the report waits for its text, then the menu opens
fi = newInteraction()
E.lead = mon()
fi:tryStart({})
fi:tick({})
check(E.choice == nil, "no menu while the text is still typing")
E.lastPage = true
fi:tick({})
check(E.choice ~= nil, "the menu opens once the last page has been typed")
eq(table.concat(E.choice.options, "/"), "Pet/Play/Talk/Cancel", "Pet / Play / Talk / Cancel")
eq(E.choice.default, 0, "the cursor starts on Pet")
eq(E.choice.layout.top, 3, "the menu sits clear of the dialogue box")

-- ------- Pet: friendship up, happy reply with a happy face, then it ends
E.lead.friendship = 100
pick(0)
eq(E.lead.friendship, 103, "Pet raises friendship through the engine's massage event (+3)")
say = lastSay()
check(say.opts.stay == nil and say.opts.mon == E.lead, "the result is a normal message the player closes")
eq(say.opts.emotion, "Joyous", "a healthy Pokemon looks joyous after a Pet")
check(say.text:find("pet", 1, true), "and the reply is about petting")
closeMessage()
check(not fi:isActive(), "closing the reply ends the interaction")

-- ------- Play / Talk: flat gains, their own faces
fi = newInteraction()
E.lead = mon({ friendship = 100 })
fi:tryStart({}) openMenu(fi) pick(1)
eq(E.lead.friendship, 102, "Play gives +2")
eq(lastSay().opts.emotion, "Inspired", "Play: Inspired face")
closeMessage()
clock = clock + 100
fi:tryStart({}) openMenu(fi) pick(2)
eq(E.lead.friendship, 103, "Talk gives +1")
eq(lastSay().opts.emotion, "Happy", "Talk: Happy face")
closeMessage()

-- ------- a hurting Pokemon keeps its own face and gets softer text
fi = newInteraction()
clock = clock + 5000
E.lead = mon({ status = "PSN", friendship = 100 })
fi:tryStart({}) openMenu(fi) pick(0)
eq(lastSay().opts.emotion, "Pain", "a poisoned Pokemon still looks pained after a Pet")
check(lastSay().text:find("gently", 1, true), "and gets the gentle reply")
eq(E.lead.friendship, 103, "but the Pet still counts")
closeMessage()

-- ------- Cancel and B
fi = newInteraction()
clock = clock + 5000
E.lead = mon()
fi:tryStart({}) openMenu(fi) pick(3)
check(not fi:isActive(), "Cancel ends the interaction")
eq(E.closedStay, 1, "...closing the message")
eq(P.cleared, 1, "...and clearing the portrait")
fi = newInteraction()
fi:tryStart({}) openMenu(fi) pick(127)
check(not fi:isActive() and E.closedStay == 1, "B (127) cancels too")

-- ------- maxed friendship: nothing to gain, nothing spent
fi = newInteraction()
clock = clock + 5000
E.lead = mon({ friendship = 255 })
fi:tryStart({}) openMenu(fi) pick(0)
eq(E.lead.friendship, 255, "friendship stays at the cap")
check(lastSay().text:find("happy as can be", 1, true) or lastSay().text:find("fonder", 1, true), "the Pokemon says it is maxed")
closeMessage()
for i = 1, 8 do fi:tryStart({}) openMenu(fi) pick(0) closeMessage() end
check(not fi.limiter:status().locked, "a maxed Pokemon never spends the abuse budget")

-- ------- the limiter: cooldown, then a lock-out for button mashing
fi = newInteraction()
clock = clock + 100000
E.lead = mon({ friendship = 50 })
fi:tryStart({}) openMenu(fi) pick(0)
local after1 = E.lead.friendship
closeMessage()
clock = clock + 1
fi:tryStart({}) openMenu(fi) pick(0)
eq(E.lead.friendship, after1, "an immediate second Pet gives nothing")
check(lastSay().text:find("mood", 1, true) or lastSay().text:find("moment", 1, true), "the Pokemon says it isn't in the mood")
closeMessage()
local gotLocked
for i = 1, 6 do
  clock = clock + 1
  if fi:tryStart({}) and E.choice and fi.state == "report" then
    openMenu(fi)
    pick(0)
    gotLocked = lastSay().text
    closeMessage()
  else
    break
  end
end
if fi.state == "result" then closeMessage() end -- the loop's last press
check(fi.limiter:status().locked, "mashing the menu locks it")
check(gotLocked ~= nil, "the cut-off was announced")
local freezeFriendship = E.lead.friendship
-- locked: A on the follower gives no menu, just a turned back
P.says = {}
check(fi:tryStart({}), "the press is still consumed while locked")
check(not fi.state or fi.state == "result", "but it goes straight to a result, no report/menu")
check(lastSay().text:find("space", 1, true) or lastSay().text:find("alone", 1, true) or lastSay().text:find("ignores", 1, true),
  "the Pokemon asks for space")
eq(lastSay().opts.emotion, "Angry", "with an angry face")
eq(E.lead.friendship, freezeFriendship, "and nothing is granted")
closeMessage()
clock = clock + 400
check(not fi.limiter:status().locked, "the lock wears off")

-- ------- safety: things going wrong mid-flow never leave us stuck
fi = newInteraction()
clock = clock + 100000
E.lead = mon()
fi:tryStart({})
E.messageOpen = false -- something else closed our message
fi:tick({})
check(not fi:isActive(), "report: a vanished message aborts cleanly")
fi = newInteraction()
fi:tryStart({}) openMenu(fi)
E.choiceUp = false -- the menu was torn down without calling back
fi:tick({})
check(not fi:isActive() and P.cleared >= 1, "menu: a vanished menu aborts and clears the portrait")
fi = newInteraction()
E.lead = mon()
fi:tryStart({}) openMenu(fi)
E.lead = mon() -- the party changed (a different table)
pick(0)
check(not fi:isActive(), "a changed lead Pokemon aborts instead of rewarding the wrong one")
fi = newInteraction()
E.lead = mon()
fi:tryStart({}) openMenu(fi) pick(0)
E.messageOpen = false
fi:tick({})
check(not fi:isActive(), "result: a message closed without its callback still resets")

-- onSaveChanged: abort + forget cached limiter state
fi = newInteraction()
E.lead = mon()
fi:tryStart({})
fi:onSaveChanged()
check(not fi:isActive(), "loading a save aborts an interaction in progress")

-- ------- scenes: the follower acts the choice out before the result shows
do
  local locks, unlocks, poses = {}, {}, {}
  E.lockField = function(tag) locks[#locks + 1] = tag return true end
  E.unlockField = function(tag) unlocks[#unlocks + 1] = tag return true end
  E.playerPose = function(n) poses[#poses + 1] = n return true end
  -- like the real Hud.busy(): an open message owns the screen
  E.screenBusy = function() return E.messageOpen end
  local adapter = { started = {}, active = false, cancelled = 0 }
  function adapter:startAction(kind)
    self.started[#self.started + 1] = kind
    self.active = true
    return { kind = kind }
  end
  function adapter:actionActive() return self.active end
  function adapter:cancelAction() self.active = false self.cancelled = self.cancelled + 1 end

  local function sceneInteraction()
    P.says, P.cleared = {}, 0
    E.messageOpen, E.lastPage, E.choiceUp, E.choice = false, false, false, nil
    clock = clock + 100000
    locks, unlocks, poses = {}, {}, {}
    adapter.started, adapter.active, adapter.cancelled = {}, false, 0
    return FollowerInteraction.new(mod, P, { clock = function() return clock end, rng = rng, adapter = adapter })
  end

  for row, action in ipairs({ "pet", "play", "talk" }) do
    local fiS = sceneInteraction()
    E.lead = mon({ friendship = 50 })
    fiS:tryStart({}) openMenu(fiS)
    local before = #P.says
    pick(row - 1)
    eq(adapter.started[1], action, action .. ": the follower starts its scene")
    eq(fiS.state, "anim", action .. ": the interaction waits in the scene state")
    eq(#P.says, before, action .. ": no result message yet")
    eq(#locks, 1, action .. ": the field is locked for the scene")
    eq(#poses, action == "play" and 1 or 0, action .. ": only Play strikes the throwing pose")
    check(not E.messageOpen, action .. ": the report message is taken down so the screen is free")
    fiS:tick({})
    eq(fiS.state, "anim", action .. ": still waiting while the scene runs (not cancelled by the old message)")
    check(#unlocks == 0, action .. ": ...and the lock is held")
    adapter.active = false -- the scene ends
    fiS:tick({})
    eq(fiS.state, "result", action .. ": the result shows after the scene")
    eq(#unlocks, 1, action .. ": the field lock is released")
    check(#P.says == before + 1 and lastSay().opts.emotion ~= nil, action .. ": with its portrait face")
    closeMessage()
    check(not fiS:isActive(), action .. ": and the interaction ends")
  end

  -- a refusal (cooldown) gets no scene
  do
    local fiS = sceneInteraction()
    E.lead = mon({ friendship = 50 })
    fiS:tryStart({}) openMenu(fiS) pick(0)
    adapter.active = false fiS:tick({}) closeMessage()
    adapter.started = {}
    clock = clock + 1
    fiS:tryStart({}) openMenu(fiS) pick(0)
    eq(#adapter.started, 0, "a refused action plays no scene")
    eq(fiS.state, "result", "...it goes straight to its reply")
    closeMessage()
  end

  -- a maxed-out Pokemon still plays the scene (and still spends nothing)
  do
    local fiS = sceneInteraction()
    E.lead = mon({ friendship = 255 })
    fiS:tryStart({}) openMenu(fiS) pick(1)
    eq(adapter.started[1], "play", "a maxed Pokemon still plays")
    eq(fiS.state, "anim", "...in the scene state")
    fiS:abort()
  end

  -- aborting mid-scene releases the lock and cancels the scene
  do
    local fiS = sceneInteraction()
    E.lead = mon({ friendship = 50 })
    fiS:tryStart({}) openMenu(fiS) pick(2)
    fiS:abort()
    eq(#unlocks, 1, "abort releases the field lock")
    check(adapter.cancelled >= 1, "...and cancels the scene")
    check(not fiS:isActive(), "...and ends the interaction")
  end

  -- something taking the screen mid-scene drops it cleanly
  do
    local fiS = sceneInteraction()
    E.lead = mon({ friendship = 50 })
    fiS:tryStart({}) openMenu(fiS) pick(0)
    E.screenBusy = function() return true end
    fiS:tick({})
    check(not fiS:isActive(), "a battle or menu mid-scene aborts it")
    eq(#unlocks, 1, "...releasing the lock")
    E.screenBusy = function() return false end
  end

  -- loading a save mid-scene
  do
    local fiS = sceneInteraction()
    E.lead = mon({ friendship = 50 })
    fiS:tryStart({}) openMenu(fiS) pick(0)
    fiS:onSaveChanged()
    eq(#unlocks, 1, "loading a save mid-scene releases the lock")
  end

  -- no follower to animate: straight to the result, never locked
  do
    local fiS = sceneInteraction()
    function adapter:startAction() return nil end
    E.lead = mon({ friendship = 50 })
    fiS:tryStart({}) openMenu(fiS) pick(0)
    eq(fiS.state, "result", "no scene possible: the result shows at once")
    eq(#locks, 0, "...and nothing was locked")
    closeMessage()
  end
end

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("follower_interaction_unit_test: all passed")
