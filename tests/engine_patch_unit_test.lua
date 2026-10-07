-- Run: lua tests/engine_patch_unit_test.lua
-- Exercises EnginePatch's probe/install/uninstall against FAKE
-- src.core.game3.* modules stuffed into package.loaded -- this never
-- touches a real gen1recomp checkout. tests/engine_patch_probe_test.lua
-- (luajit, inside a gen1recomp checkout) is the one that checks the real
-- engine still has the shape this file assumes.
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

-- ------- fake engine modules, one per EnginePatch target/readonly entry
local fake = {}
fake["src.core.game3.field_effects"] = {
  collectActors = function(_actors) end,
  loadSheet = function(_name, _fw, _fh, _frames) return { image = "fake_image", quadsFront = { [4] = "fake_quad" } } end,
}
local objectAtCell = {}
fake["src.core.game3.objects"] = {
  blocks = function(_tx, _ty, _except, _elev) return false end,
  at = function(tx, ty) return objectAtCell[tx .. "," .. ty] end,
}
local moveMon = {}
local badgeOwned = { SURF = true, CUT = true, ROCK_SMASH = true, STRENGTH = true }
fake["src.core.game3.field_moves"] = {
  GFX_IDS = { CUT_TREE = 95, ROCK_SMASH_ROCK = 96, PUSHABLE_BOULDER = 97 },
  hasBadge = function(_ctx, key) return badgeOwned[key] == true end,
  partyMoveUser = function(_party, key) return moveMon[key] end,
}
local followerNpc = nil
fake["src.world.game3.Follower"] = {
  update = function(_game) end,
  current = function() return nil end,
  at = function(_, x, y) if followerNpc and followerNpc.cellX == x and followerNpc.cellY == y then return followerNpc end end,
}
local fieldState = { running = true, locked = false }
local originalInteract = function(_game) return "original" end
fieldState.interact = originalInteract
fake["src.core.game3.field"] = fieldState
local hudBusy = false
fake["src.ui.game3.hud"] = { busy = function() return hudBusy end }
local choiceState = { active = false }
choiceState.multi = function(options, default, cb, layout)
  choiceState.active = true
  choiceState.last = { options = options, default = default, cb = cb, layout = layout }
end
fake["src.ui.game3.choice"] = choiceState
fake["src.core.game3.battle_bridge"] = {
  startWild = function(_mod, _game, _enc, _opts) return true end,
}
fake["src.core.game3.encounters"] = {
  rollSweetScent = function(_mapId, _terrain) return nil end,
  terrainAt = function(_x, _y) return nil end,
  ensureLoaded = function() return true end,
  tableFor = function(_mapId) return nil end,
  rules = function() return {} end,
  _h = { wild_level_allowed_by_repel = function(_level) return true end },
}
fake["src.core.game3.collision"] = {
  isWater = function() return false end,
  isGrass = function() return false end,
  canEnter = function() return true end,
  inBounds = function() return true end,
  ledgeLanding = function() return nil end,
  nextElevation = function() return 3 end,
  isWalkable = function() return true end,
  _widthCells = 10, _heightCells = 10,
}
fake["src.core.game3.pokemon"] = {
  FRIENDSHIP_EVENT_MASSAGE = 6,
  displayName = function(mon) return mon.nickname or "TREECKO" end,
  friendshipOf = function(mon) return mon.friendship or 0 end,
  setFriendship = function(mon, v) v = math.max(0, math.min(255, v)) mon.friendship = v return v end,
  adjustFriendship = function(mon, event) if event == 6 then mon.friendship = (mon.friendship or 0) + 3 return true end return false end,
  national = function(id) return id end,
  speciesFromNational = function(nat) return nat end,
  speciesMeta = function() return {} end,
  isShiny = function(_mon) return false end,
  gender = function() return 0 end,
}
fake["src.core.game3.runtime"] = {
  getSession = function() return { trainerId = 1234, secretId = 5678, party = {} } end,
}
fake["src.core.game3.dex"] = { isCaught = function() return false end }
local safariOn = false
fake["src.core.game3.safari"] = { isActive = function() return safariOn end }
local rngNext = 987654321
fake["src.core.game3.rng"] = { Random32 = function() return rngNext end }
local messageIsOpen = false
fake["src.ui.game3.message"] = {
  draw = function() end,
  isOpen = function() return messageIsOpen end,
  show = function(_text, opts) fake["src.ui.game3.message"]._shown = opts return true end,
  isWaiting = function() return fake["src.ui.game3.message"]._waiting == true end,
  closeStay = function() fake["src.ui.game3.message"]._closed = true return true end,
}
fake["src.ui.game3.chrome"] = { dialogueWindow = function() return 2, 15, 26, 4 end }
fake["src.core.GameVersion"] = {
  layout = function() return "rse" end,
  get = function() return "emerald" end,
}
-- player.lua:62 -- a live boolean DATA FIELD, not a function. The one
-- `kind = "data"` probe target; see EnginePatch.probe()'s handling of it.
fake["src.core.game3.player"] = { running = false, moving = false, cellX = 5, cellY = 5, facing = "down" }

local realRequire = require
_G.require = function(name)
  if fake[name] ~= nil then return fake[name] end
  return realRequire(name)
end

local EnginePatch = assert(loadfile("lib/engine_patch.lua"))(nil)

-- ------- probe passes against the full fake set
local ok, missing = EnginePatch.probe()
check(ok, "probe passes against a complete fake engine")
eq(#missing, 0, "no missing targets reported")

-- ------- the layout: RSE and FRLG are both supported
check(EnginePatch.isRse(), "isRse true for the fake emerald/rse version")
eq(EnginePatch.layoutName(), "rse", "layoutName rse")
check(EnginePatch.isSupported(), "isSupported on rse")
do
  local gv = fake["src.core.GameVersion"]
  local was = gv.layout
  gv.layout = function() return "frlg" end
  eq(EnginePatch.layoutName(), "frlg", "layoutName frlg")
  check(EnginePatch.isSupported() and not EnginePatch.isRse(), "FireRed / LeafGreen are supported, and are not RSE")
  gv.layout = function() return "gen2" end
  check(EnginePatch.layoutName() == nil and not EnginePatch.isSupported(), "a non-Gen-3 layout is not supported")
  gv.layout = was
end

-- ------- FRLG rolls no personality: the engine's own random stream supplies it
eq(EnginePatch.randomPersonality(), 987654321, "randomPersonality draws from the engine's Random32")
rngNext = nil
check(EnginePatch.randomPersonality() == nil, "...and is nil when the engine returns nothing usable")
rngNext = 5

-- ------- Safari Zone detection
check(not EnginePatch.safariActive(), "safariActive false normally")
safariOn = true
check(EnginePatch.safariActive(), "safariActive true during a Safari Zone visit")
safariOn = false

-- ------- install/uninstall wraps and restores exactly the TARGETS
local originalBlocks = fake["src.core.game3.objects"].blocks
local calls = { collectActors = 0, blocks = 0, followerTick = 0, messageDraw = 0, interact = 0 }
local originalMessageDraw = fake["src.ui.game3.message"].draw
local installed = EnginePatch.install({
  collectActors = function(_actors) calls.collectActors = calls.collectActors + 1 end,
  blocks = function(_tx, _ty, _except, _elev) calls.blocks = calls.blocks + 1 return true end,
  followerTick = function(_game) calls.followerTick = calls.followerTick + 1 end,
  messageDraw = function() calls.messageDraw = calls.messageDraw + 1 end,
  interact = function() calls.interact = calls.interact + 1 return calls.takeInteract == true end,
}, { warn = function() end, info = function() end })
check(installed, "install succeeds against the fake engine")

fake["src.core.game3.field_effects"].collectActors({})
eq(calls.collectActors, 1, "collectActors hook ran after the wrap")

local blocked = fake["src.core.game3.objects"].blocks(1, 2, nil, 3)
check(blocked == true, "blocks wrap returns true when our hook says blocked")
eq(calls.blocks, 1, "blocks hook ran")

fake["src.world.game3.Follower"].update({})
eq(calls.followerTick, 1, "followerTick hook ran after the real update")

fake["src.ui.game3.message"].draw()
eq(calls.messageDraw, 1, "messageDraw hook ran after Message.draw")

-- Message wrappers: isMessageOpen / showMessage / dialogueWindow
eq(EnginePatch.isMessageOpen(), false, "isMessageOpen false while no message is up")
messageIsOpen = true
eq(EnginePatch.isMessageOpen(), true, "isMessageOpen true while a message is up")
messageIsOpen = false
check(EnginePatch.showMessage("hi", { stay = true }), "showMessage returns true on success")
eq(fake["src.ui.game3.message"]._shown.stay, true, "showMessage passes opts to Message.show")
local win = EnginePatch.dialogueWindow()
check(win and win.left == 2 and win.top == 15 and win.width == 26 and win.height == 4, "dialogueWindow reads Chrome.dialogueWindow")

-- Field.interact hook: runs first, true = handled and the original is skipped
eq(fake["src.core.game3.field"].interact({}), "original", "interact falls through when the hook declines")
eq(calls.interact, 1, "the interact hook ran before the original")
calls.takeInteract = true
eq(fake["src.core.game3.field"].interact({}), true, "interact returns true when the hook takes the press")
calls.takeInteract = nil

-- canStartInteraction mirrors Field.interact's own gating
check(EnginePatch.canStartInteraction(), "idle field: an interaction may start")
hudBusy = true
check(not EnginePatch.canStartInteraction(), "a busy HUD (message/menu/battle) blocks it")
hudBusy = false
fieldState.locked = true
check(not EnginePatch.canStartInteraction(), "a locked field blocks it")
fieldState.locked = false
fake["src.core.game3.player"].moving = true
check(not EnginePatch.canStartInteraction(), "a moving player blocks it")
fake["src.core.game3.player"].moving = false
fieldState.running = false
check(not EnginePatch.canStartInteraction(), "a field that is not running blocks it")
fieldState.running = true

-- the follower must be in the FACING cell, standing still
followerNpc = { cellX = 5, cellY = 6 }
check(EnginePatch.followerInFacingCell() == followerNpc, "facing down at the follower below finds it")
fake["src.core.game3.player"].facing = "up"
check(EnginePatch.followerInFacingCell() == nil, "facing the other way finds nothing")
fake["src.core.game3.player"].facing = "down"
followerNpc.hidden = true
check(EnginePatch.followerInFacingCell() == nil, "a hidden follower is not interactable")
followerNpc = nil

-- messageOnLastPage: waiting AND on the last page (page fields are private)
local msg = fake["src.ui.game3.message"]
msg._waiting = false
check(not EnginePatch.messageOnLastPage(), "still typing -> not on the last page yet")
msg._waiting, msg._pages, msg._page = true, { "a", "b" }, 1
check(not EnginePatch.messageOnLastPage(), "waiting on page 1 of 2 -> not the last page")
msg._page = 2
check(EnginePatch.messageOnLastPage(), "waiting on the last page -> yes")
msg._pages, msg._page = nil, nil
check(EnginePatch.messageOnLastPage(), "unreadable page fields: a waiting message counts as done")
msg._waiting = false
check(EnginePatch.closeStayMessage(), "closeStayMessage calls Message.closeStay")
eq(msg._closed, true, "...and it ran")

-- choice + message + friendship wrappers
check(EnginePatch.showChoice({ "A", "B" }, 0, function() end, { top = 3 }), "showChoice opens Choice.multi")
eq(choiceState.last.layout.top, 3, "and passes the layout through")
check(EnginePatch.choiceActive(), "choiceActive reads Choice.active")
choiceState.active = false
check(not EnginePatch.choiceActive(), "...and its absence")
local mon = { nickname = "BLAZE", friendship = 100 }
eq(EnginePatch.displayName(mon), "BLAZE", "displayName delegates to Pokemon.displayName")
eq(EnginePatch.friendshipOf(mon), 100, "friendshipOf delegates")
eq(EnginePatch.setFriendship(mon, 300), 255, "setFriendship clamps through the engine")
mon.friendship = 100
eq(EnginePatch.petFriendship(mon), 3, "petFriendship runs the engine's massage event and reports the gain")

-- A second install() call while already installed is a no-op, not a
-- double-wrap (idempotent on hot reload).
local installedAgain = EnginePatch.install({
  collectActors = function() calls.collectActors = calls.collectActors + 100 end,
}, { warn = function() end, info = function() end })
check(installedAgain, "install() returns true when already installed")
fake["src.core.game3.field_effects"].collectActors({})
eq(calls.collectActors, 2, "second install() did not double-wrap collectActors")

EnginePatch.uninstall()
eq(fake["src.core.game3.objects"].blocks, originalBlocks, "uninstall restores the original blocks function")
eq(fake["src.ui.game3.message"].draw, originalMessageDraw, "uninstall restores the original Message.draw")
eq(fake["src.core.game3.field"].interact, originalInteract, "uninstall restores the original Field.interact")

local blockedAfterUninstall = fake["src.core.game3.objects"].blocks(1, 2, nil, 3)
check(blockedAfterUninstall == false, "blocks is back to vanilla (always false) after uninstall")

-- ------- probe fails loudly when a target goes missing (simulates an
-- engine update that renamed/removed a field this mod depends on)
local savedBlocks = fake["src.core.game3.objects"].blocks
fake["src.core.game3.objects"].blocks = nil
local ok2, missing2 = EnginePatch.probe()
check(not ok2, "probe fails when objects.blocks is missing")
local sawBlocks = false
for _, m in ipairs(missing2) do
  if m:find("blocks", 1, true) then sawBlocks = true end
end
check(sawBlocks, "the failure list names the missing target")

local installedAfterBreak, missing3 = EnginePatch.install({}, { warn = function() end, info = function() end })
check(not installedAfterBreak, "install() refuses when probe() fails")
check(type(missing3) == "table" and #missing3 > 0, "install() hands back the missing list")

fake["src.core.game3.objects"].blocks = savedBlocks

-- ------- read-only accessors
eq(EnginePatch.nationalFor(252), 252, "nationalFor delegates to pokemon.national")
eq(EnginePatch.speciesForNational(252), 252, "speciesForNational delegates to pokemon.speciesFromNational")
local w, h = EnginePatch.mapBounds()
eq(w, 10, "mapBounds width from Collision._widthCells")
eq(h, 10, "mapBounds height from Collision._heightCells")

local ids = EnginePatch.trainerIds()
check(ids ~= nil and ids.otId == 1234 and ids.otSecretId == 5678, "trainerIds reads the live session")

-- ------- grassSheet delegates to the engine's own FieldEffects.loadSheet,
-- the same cache-backed loader/art the player's and registered NPCs'
-- grass-feet effect already uses (lib/grass_cover.lua's whole reason for
-- existing).
local sheet = EnginePatch.grassSheet()
check(sheet ~= nil and sheet.quadsFront ~= nil, "grassSheet reads the live FieldEffects.loadSheet result")
eq(sheet.quadsFront[4], "fake_quad", "grassSheet returns the real sheet, not a copy")

-- ------- playerIsRunning reads the live data field directly, and probe()
-- treats a `kind = "data"` entry as present-but-not-a-function rather than
-- rejecting it (the one exception -- see EnginePatch.probe()).
eq(EnginePatch.playerIsRunning(), false, "playerIsRunning reads Player.running (false)")
fake["src.core.game3.player"].running = true
eq(EnginePatch.playerIsRunning(), true, "playerIsRunning reads Player.running (true)")
fake["src.core.game3.player"].running = false

fake["src.core.game3.player"] = nil
local ok3, missing3b = EnginePatch.probe()
check(not ok3, "probe fails when the data-field module itself fails to load")
local sawPlayerRunning = false
for _, m in ipairs(missing3b) do
  if m:find("playerRunning", 1, true) then sawPlayerRunning = true end
end
check(sawPlayerRunning, "the failure list names the missing data-field target")
fake["src.core.game3.player"] = { running = false }

-- ------- regression: EnginePatch.canEnter() (our OWN roaming wild
-- Pokemon's candidate-step probe) must not look like a real player bump
-- to a `blocks` hook written the way main.lua's actually is -- a
-- standing-still player got thrown into battle because a roaming wild
-- Pokemon merely checking whether it could step onto the player's own
-- tile went through the exact same exceptLocalId == nil path a real bump
-- does (collision.lua's entityBlocks always passes nil, regardless of
-- caller). EnginePatch.isProbingCanEnter() is how a `blocks` hook written
-- like main.lua's own tells the two apart. Runs in its own install/
-- uninstall pair so it doesn't disturb the lifecycle test above.
check(not EnginePatch.isProbingCanEnter(), "isProbingCanEnter starts false")

local bumpCount = 0
local mainLuaStyleHook = function(_tx, _ty, exceptLocalId, _elev)
  if exceptLocalId == nil and not EnginePatch.isProbingCanEnter() then
    bumpCount = bumpCount + 1
  end
  return true
end
EnginePatch.install({ blocks = mainLuaStyleHook }, { warn = function() end, info = function() end })

-- collision.lua's own canEnter always resolves occupancy through
-- Objects.blocks(tx, ty, nil, elevation) -- reproduced here the same way,
-- since that's the exact call shape that caused the bug.
fake["src.core.game3.collision"].canEnter = function(_game, tx, ty, _opts)
  if fake["src.core.game3.objects"].blocks(tx, ty, nil, 3) then return false end
  return true
end

EnginePatch.canEnter(nil, 5, 5, {})
eq(bumpCount, 0, "a wild Pokemon's own canEnter probe never counts as a player bump")

mainLuaStyleHook(5, 5, nil, 3) -- a REAL player movement check, not through EnginePatch.canEnter
eq(bumpCount, 1, "a genuine player-originated blocks call (not via canEnter) still counts as a bump")

check(not EnginePatch.isProbingCanEnter(), "the probing flag is cleared again after canEnter returns")
EnginePatch.uninstall()

_G.require = realRequire

-- ------- reachability: canEnterWhy keeps the probe flag and the reason
_G.require = function(name)
  if fake[name] ~= nil then return fake[name] end
  return realRequire(name)
end
local col = fake["src.core.game3.collision"]
local realCanEnter, realIsWater, realIsWalkable, realLedge = col.canEnter, col.isWater, col.isWalkable, col.ledgeLanding
local flagSeenInside
local GRID = {} -- "x,y" -> "tile" | "water" | "entity" | nil (open floor)
local WATER = {}
col.canEnter = function(_game, tx, ty, opts)
  flagSeenInside = EnginePatch.isProbingCanEnter()
  local k = GRID[tx .. "," .. ty]
  if k == "water" and opts.surfing then return true end
  if k then return false, k end
  return true
end
col.isWater = function(x, y) return WATER[x .. "," .. y] == true or GRID[x .. "," .. y] == "water" end
col.isWalkable = function(x, y) return GRID[x .. "," .. y] ~= "tile" end

local ok, why = EnginePatch.canEnterWhy({}, 1, 1, {})
check(ok and flagSeenInside == true, "canEnterWhy sets the probing flag around Collision.canEnter")
eq(EnginePatch.isProbingCanEnter(), false, "...and clears it afterwards")
GRID["1,2"] = "tile"
ok, why = EnginePatch.canEnterWhy({}, 1, 2, {})
check(not ok and why == "tile", "the engine's reason comes through")

-- ------- hmUsable: badge AND a party Pokemon that knows the move, fail-open
package.loaded["src.core.game3.scripting.space"] = { store = {} }
moveMon.SURF = { name = "LAPRAS" }
check(EnginePatch.hmUsable("SURF"), "badge + a Surf user -> usable")
badgeOwned.SURF = false
check(not EnginePatch.hmUsable("SURF"), "no badge -> not usable")
badgeOwned.SURF = true
moveMon.SURF = nil
check(not EnginePatch.hmUsable("SURF"), "badge but nobody knows the move -> not usable")
package.loaded["src.core.game3.scripting.space"] = nil
check(EnginePatch.hmUsable("SURF"), "an unreadable flag store fails open (usable)")
package.loaded["src.core.game3.scripting.space"] = { store = {} }

-- ------- reachMover: the engine's rules per step
fake["src.core.game3.player"] = { running = false, moving = false, cellX = 5, cellY = 5, facing = "down", currentElevation = 3 }
local start = EnginePatch.reachStart()
check(start and start.x == 5 and start.y == 5 and type(start.state) == "table", "reachStart reads the player's cell and state")
fake["src.core.game3.player"].surfing = true
check(EnginePatch.reachStart().state.surfing == true, "...including whether they are surfing")
fake["src.core.game3.player"].surfing = nil

-- the player's surf state and pixel position (the PMD follower recall reads them)
local st0 = EnginePatch.playerSurfState()
check(st0.surfing == false and st0.dismounting == false, "playerSurfState: on land")
fake["src.core.game3.player"].surfing = true
check(EnginePatch.playerSurfState().surfing == true, "playerSurfState: surfing")
fake["src.core.game3.player"].surfing, fake["src.core.game3.player"].surfHopping = false, true
check(EnginePatch.playerSurfState().surfing == true, "playerSurfState: the hop onto the water counts as surfing")
fake["src.core.game3.player"].surfHopping, fake["src.core.game3.player"].dismounting = false, true
local stD = EnginePatch.playerSurfState()
check(stD.dismounting == true, "playerSurfState: reports the dismount")
fake["src.core.game3.player"].dismounting = nil
fake["src.core.game3.player"].px, fake["src.core.game3.player"].py = 83, 41
local ppx, ppy = EnginePatch.playerPixel()
check(ppx == 83 and ppy == 41, "playerPixel reads the player's world pixel position")
fake["src.core.game3.player"].px, fake["src.core.game3.player"].py = nil, nil
check(EnginePatch.playerPixel() == nil, "playerPixel is nil without a position")

moveMon.SURF = { name = "LAPRAS" }
moveMon.CUT = { name = "FARFETCHD" }
badgeOwned.CUT = true
local move = EnginePatch.reachMover({})
local nx, ny, st = move(5, 5, "right", { surfing = false, elev = 3 })
check(nx == 6 and ny == 5 and st.surfing == false, "open floor: the step lands one cell over, still walking")
GRID["7,5"] = "tile"
check(move(6, 5, "right", { surfing = false, elev = 3 }) == nil, "a wall blocks")
GRID["5,6"] = "water"
nx, ny, st = move(5, 5, "down", { surfing = false, elev = 3 })
check(nx == 5 and ny == 6 and st.surfing == true, "water from the shore is entered as surfing when Surf is usable")
moveMon.SURF = nil
check(move(5, 5, "down", { surfing = false, elev = 3 }) ~= nil, "(the mover decides Surf once, when built)")
local noSurfMove = EnginePatch.reachMover({})
check(noSurfMove(5, 5, "down", { surfing = false, elev = 3 }) == nil, "without Surf the water is a wall")
moveMon.SURF = { name = "LAPRAS" }
move = EnginePatch.reachMover({})
nx, ny, st = move(5, 6, "up", { surfing = true, elev = 3 })
check(nx == 5 and ny == 5 and st.surfing == false, "surfing onto the shore dismounts")

-- an object in the way: an NPC is not a wall, a Cut tree is until Cut is usable
GRID["4,5"] = "entity"
check(move(5, 5, "left", { surfing = false, elev = 3 }) ~= nil, "an NPC / item ball standing in the way does not cut the area off")
objectAtCell["4,5"] = { def = { graphicsId = 95 } } -- a Cut tree
check(move(5, 5, "left", { surfing = false, elev = 3 }) ~= nil, "a Cut tree is open when Cut is usable")
moveMon.CUT = nil
local noCut = EnginePatch.reachMover({})
check(noCut(5, 5, "left", { surfing = false, elev = 3 }) == nil, "...and a wall when it is not")
objectAtCell["4,5"] = { graphicsId = 96 } -- a smashable rock, graphicsId on the object itself
badgeOwned.ROCK_SMASH = false
check(EnginePatch.reachMover({})(5, 5, "left", { surfing = false, elev = 3 }) == nil, "a rock blocks without Rock Smash")
badgeOwned.ROCK_SMASH = true
objectAtCell["4,5"] = nil
badgeOwned.CUT = true
moveMon.CUT = { name = "FARFETCHD" }

-- an object standing on a tile that is itself a wall stays a wall
GRID["4,5"] = "entity"
col.isWalkable = function(x, y) return not (x == 4 and y == 5) end
check(EnginePatch.reachMover({})(5, 5, "left", { surfing = false, elev = 3 }) == nil, "an object on an impassable tile does not open it")
col.isWalkable = function(x, y) return GRID[x .. "," .. y] ~= "tile" end

-- ledges: the hop to the landing cell, walking only
col.ledgeLanding = function(_game, x, y, dir) if dir == "down" and x == 3 and y == 3 then return 3, 5 end end
nx, ny, st = EnginePatch.reachMover({})(3, 3, "down", { surfing = false, elev = 3 })
check(nx == 3 and ny == 5 and st.surfing == false, "a ledge hops to its landing cell")
check(EnginePatch.reachMover({})(3, 3, "down", { surfing = true, elev = 3 }) ~= nil, "(a surfer takes the plain step instead)")
col.canEnter, col.isWater, col.isWalkable, col.ledgeLanding = realCanEnter, realIsWater, realIsWalkable, realLedge
package.loaded["src.core.game3.scripting.space"] = nil
_G.require = realRequire

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("engine_patch_unit_test: all passed")
