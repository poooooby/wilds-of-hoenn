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
E.clearStatus = function(mon)
  local had = mon.status ~= nil
  mon.status, mon.sleep = nil, 0
  return had
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
-- the interaction under test (the last one built), so pick() can tick it
local lastFi
do
  local realNew = FollowerInteraction.new
  FollowerInteraction.new = function(...)
    lastFi = realNew(...)
    return lastFi
  end
end
-- Pick an action by its old flat index, walking the primary menu and sub menus
-- the way a player does: 0 Pet, 1 Play, 2 Talk (Interact), 3 Recall,
-- 4 Follow, 6 Forage, 5 Fight (Role), 7 Cancel, 127 = B on the primary menu.
local function choose(index)
  E.choiceUp = false
  E.choice.cb(index)
end
local function pick(index)
  if index <= 2 then
    choose(0) lastFi:tick({}) -- Interact
    choose(index)
  elseif index == 3 then choose(2)
  elseif index >= 4 and index <= 6 then
    choose(1) lastFi:tick({}) -- Role
    choose(({ [4] = 0, [6] = 1, [5] = 2 })[index])
  elseif index == 7 then choose(3)
  else choose(index) end
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
local RIGHT, LEFT = "\226\150\182", "\226\151\128"
local function plain(options)
  local out = {}
  for i, o in ipairs(options) do out[i] = (o:gsub("[ ]+", " ")) end
  return table.concat(out, "/")
end
eq(plain(E.choice.options), "Interact "..RIGHT.."/Role "..RIGHT.."/Recall/Cancel", "primary menu: Interact / Role / Recall / Cancel, arrows on the two that open more")
eq(#E.choice.options[1], #E.choice.options[2], "the arrows line up in one column (same padded length)")
eq(E.choice.default, 0, "the cursor starts on the first row")
eq(E.choice.layout.top, 3, "the menu sits clear of the dialogue box")

-- ------- Pet: friendship up, happy reply with a happy face, then it ends
E.lead.friendship = 100
pick(0)
eq(E.lead.friendship, 102, "Pet gives +2")
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
eq(E.lead.friendship, 103, "Play gives +3")
eq(lastSay().opts.emotion, "Inspired", "Play: Inspired face")
closeMessage()
clock = clock + 100
fi:tryStart({}) openMenu(fi) pick(2)
eq(E.lead.friendship, 104, "Talk gives +1")
eq(lastSay().opts.emotion, "Happy", "Talk: the face matches how fond it is (40-59% = Happy)")
check(lastSay().text:find("starting", 1, true), "Talk: it reports 'starting to like you'")
closeMessage()

-- ------- a hurting Pokemon keeps its own face and gets softer text (no cure this time)
do
  local savedRng = rng
  rng = function() return 0.9 end -- over the 25% cure chance
  fi = newInteraction()
  clock = clock + 5000
  E.lead = mon({ status = "PSN", friendship = 100 })
  fi:tryStart({}) openMenu(fi) pick(0)
  eq(lastSay().opts.emotion, "Pain", "a poisoned Pokemon still looks pained after a Pet")
  check(lastSay().text:find("gently", 1, true), "and gets the gentle reply")
  eq(E.lead.friendship, 102, "but the Pet still counts (+2)")
  eq(E.lead.status, "PSN", "...and a roll over 25% leaves the poison alone")
  closeMessage()
  rng = savedRng
end

-- ------- Pet: a 25% chance to cure a status condition
do
  local savedRng = rng
  rng = function() return 0.1 end -- under 25%
  fi = newInteraction()
  clock = clock + 5000
  E.lead = mon({ status = "PSN", friendship = 100 })
  fi:tryStart({}) openMenu(fi) pick(0)
  check(E.lead.status == nil, "a roll under 25% cures the status")
  check(lastSay().text:find("feels better now", 1, true), "...and says '<name> feels better now!' instead of the usual reply")
  check(not lastSay().text:find("pet", 1, true), "...not the pet line")
  eq(E.lead.friendship, 102, "...and the Pet's +2 still counts")
  eq(lastSay().opts.emotion, "Joyous", "a healed, healthy Pokemon looks joyous")
  closeMessage()
  -- a healed Pokemon that is still badly hurt keeps its own face
  fi = newInteraction()
  clock = clock + 5000
  E.lead = mon({ status = "BRN", hp = 20, maxHp = 100, friendship = 100 })
  fi:tryStart({}) openMenu(fi) pick(0)
  check(E.lead.status == nil and lastSay().text:find("feels better now", 1, true), "a burn is cured too")
  eq(lastSay().opts.emotion, "Pain", "...but low HP still shows in its face")
  closeMessage()
  -- no status, nothing to cure: the normal reply
  fi = newInteraction()
  clock = clock + 5000
  E.lead = mon({ friendship = 100 })
  fi:tryStart({}) openMenu(fi) pick(0)
  check(lastSay().text:find("pet", 1, true) or lastSay().text:find("stroke", 1, true), "a healthy Pokemon gets the normal pet reply")
  closeMessage()
  rng = savedRng
end

-- ------- Play: a hurt or sick Pokemon refuses and says why (nothing is spent)
do
  local cases = {
    { { hp = 20, maxHp = 100 }, "is hurt", "low HP" },
    { { status = "PSN" }, "is sick", "poison" },
    { { status = "TOX" }, "is sick", "bad poison" },
    { { status = "PAR" }, "is paralyzed", "paralysis" },
    { { status = "FRZ" }, "is too cold", "freeze" },
    { { status = "BRN" }, "is burning", "burn" },
    { { status = "SLP" }, "is asleep", "sleep" },
  }
  for _, c in ipairs(cases) do
    fi = newInteraction()
    clock = clock + 5000
    E.lead = mon(c[1])
    E.lead.friendship = 100
    fi:tryStart({}) openMenu(fi) pick(1)
    check(lastSay().text:find(c[2], 1, true) and lastSay().text:find("can't play", 1, true),
      "Play refused: '" .. c[2] .. " ... can't play' (" .. c[3] .. ")")
    eq(E.lead.friendship, 100, "...no friendship gained (" .. c[3] .. ")")
    check(not fi.limiter:status().locked and fi.state == "result", "...and no scene, straight to the reply (" .. c[3] .. ")")
    closeMessage()
  end
  -- 25% HP exactly is fine; just under is not
  fi = newInteraction()
  clock = clock + 5000
  E.lead = mon({ hp = 25, maxHp = 100, friendship = 100 })
  fi:tryStart({}) openMenu(fi) pick(1)
  eq(E.lead.friendship, 103, "a Pokemon at exactly 25% HP will play")
  closeMessage()
  fi = newInteraction()
  clock = clock + 5000
  E.lead = mon({ hp = 24, maxHp = 100, friendship = 100 })
  fi:tryStart({}) openMenu(fi) pick(1)
  eq(E.lead.friendship, 100, "...but one just under 25% will not")
  closeMessage()
  -- Pet and Talk are still fine for a sick Pokemon
  fi = newInteraction()
  clock = clock + 5000
  E.lead = mon({ status = "PAR", friendship = 100 })
  fi:tryStart({}) openMenu(fi) pick(2)
  eq(E.lead.friendship, 101, "a sick Pokemon can still be talked to (+1)")
  closeMessage()
end

-- ------- Talk: how fond it is, as a share of the maximum, with a matching face
do
  local bands = {
    { 10, "wary", "Worried" }, { 60, "curious", "Surprised" }, { 110, "starting", "Happy" },
    { 160, "trusts", "Determined" }, { 210, "really likes", "Joyous" }, { 250, "loves", "Inspired" },
  }
  for _, b in ipairs(bands) do
    fi = newInteraction()
    clock = clock + 5000
    E.lead = mon({ friendship = b[1] })
    fi:tryStart({}) openMenu(fi) pick(2)
    check(lastSay().text:find(b[2], 1, true), "Talk at friendship " .. b[1] .. " says '" .. b[2] .. "'")
    eq(lastSay().opts.emotion, b[3], "...with the " .. b[3] .. " portrait")
    closeMessage()
  end
  -- a Pokemon at the maximum loves you (instead of the 'as happy as can be' line)
  fi = newInteraction()
  clock = clock + 5000
  E.lead = mon({ friendship = 255 })
  fi:tryStart({}) openMenu(fi) pick(2)
  check(lastSay().text:find("loves you", 1, true), "Talk at the maximum: it loves you")
  eq(lastSay().opts.emotion, "Inspired", "...Inspired")
  eq(E.lead.friendship, 255, "...with nothing more to gain")
  closeMessage()
  -- hurting does not change what it says about you
  fi = newInteraction()
  clock = clock + 5000
  E.lead = mon({ status = "PSN", friendship = 160 })
  fi:tryStart({}) openMenu(fi) pick(2)
  check(lastSay().text:find("trusts", 1, true), "a poisoned Pokemon still tells you how it feels")
  eq(lastSay().opts.emotion, "Determined", "...with that feeling's face")
  closeMessage()
end

-- ------- Recall and the three jobs: they change the companion and say so
do
  local set = {}
  local comp
  comp = {
    saved = nil,
    savedRole = function(_, _) return comp.saved end,
    set = function(_, m, role) set[#set + 1] = role comp.saved = role return true end,
    resolve = function(_, _) return E.lead, comp.saved or "follow" end,
  }
  E.partyMons = function() return { E.lead } end
  local function jobInteraction()
    return FollowerInteraction.new(mod, P, { clock = function() return clock end, rng = rng, companion = comp })
  end
  clock = clock + 5000
  E.lead = mon()
  fi = jobInteraction()
  fi:tryStart({}) openMenu(fi) pick(3)
  eq(set[#set], "recall", "Recall sets the recall role")
  check(lastSay().text:find("returned to you"), "...and says it came back")
  closeMessage()
  fi = jobInteraction()
  fi:tryStart({}) openMenu(fi) pick(5)
  eq(set[#set], "battle", "Fight sets the battle role")
  check(lastSay().text:find("battle wild"), "...and says what it will do")
  closeMessage()
  fi = jobInteraction()
  fi:tryStart({}) openMenu(fi) pick(6)
  eq(set[#set], "forage", "Forage sets the forage role")
  closeMessage()
  fi = jobInteraction()
  fi:tryStart({}) openMenu(fi) pick(4)
  eq(set[#set], "follow", "Follow sets the follow role")
  local n = #set
  closeMessage()
  fi = jobInteraction()
  fi:tryStart({}) openMenu(fi) pick(4)
  eq(#set, n, "choosing the job it already has changes nothing")
  check(lastSay().text:find("already"), "...and says so")
  closeMessage()
end

-- ------- sub menus: Interact and Role open under the primary menu, Back returns
do
  local fiS = newInteraction()
  clock = clock + 5000
  E.lead = mon()
  fiS:tryStart({}) openMenu(fiS)
  choose(0) fiS:tick({})
  eq(table.concat(E.choice.options, "/"), "Pet/Play/Talk/"..LEFT.." Back", "Interact opens Pet / Play / Talk / left arrow Back")
  choose(3) fiS:tick({})
  eq(plain(E.choice.options), "Interact "..RIGHT.."/Role "..RIGHT.."/Recall/Cancel", "Back returns to the primary menu")
  choose(1) fiS:tick({})
  eq(table.concat(E.choice.options, "/"), "Follow/Forage/Fight/"..LEFT.." Back", "Role opens Follow / Forage / Fight / left arrow Back")
  choose(127) fiS:tick({})
  eq(plain(E.choice.options), "Interact "..RIGHT.."/Role "..RIGHT.."/Recall/Cancel", "B in a sub menu goes back too")
  check(fiS:isActive(), "...and the interaction is still going")
  choose(3)
  check(not fiS:isActive(), "Cancel on the primary menu ends it")
end

-- ------- with the engine font: the arrows end at the same pixel, at the window's edge
do
  local widths = { [RIGHT] = 8 }
  E.measureText = function(text)
    local w = 0
    for _, byte in ipairs({ (text:gsub(RIGHT, string.char(1))):byte(1, -1) }) do
      w = w + (byte == 1 and 8 or 6)
    end
    return w
  end
  local labels = FollowerInteraction.labels("main")
  local function clearto(label)
    local at = label:find(string.char(0xFC, 0x13), 1, true)
    return at and label:byte(at + 2)
  end
  check(clearto(labels[1]) ~= nil, "measured: the arrow is placed by pixel (CLEARTO)")
  eq(clearto(labels[1]), clearto(labels[2]), "both arrow rows put the arrow at the same pixel")
  eq(clearto(labels[1]), 8 * 6 + 24, "...a short gap after the widest label")
  eq(labels[1]:sub(-3), string.char(0xFC, 0x11, 0), "the byte count is padded so the window holds the arrow")
  local tiles = math.min(18, math.max(6, math.floor(#labels[1] * 0.7) + 2))
  check(tiles * 8 - 14 >= clearto(labels[1]) + 8, "...and the window is wide enough for it")
  check(not labels[3]:find(string.char(0xFC), 1, true), "rows without a sub menu are plain")
  E.measureText = nil
end

-- ------- Cancel and B
fi = newInteraction()
clock = clock + 5000
E.lead = mon()
fi:tryStart({}) openMenu(fi) pick(7)
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
