-- Run: lua tests/forager_unit_test.lua
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

local modules = {}
local V = { path = "." }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  local value = assert(loadfile("lib/" .. name .. ".lua"))(V)
  modules[name] = value
  return value
end
local Forager = V.require("forager")
local Config = V.require("config")

-- a quick timer (every 50 walking ticks) so the trips can be watched end to end
local CFG = {
  minSpread = 3, maxSpread = 5, maxWalk = 12,
  intervalMin = 50, intervalMax = 50, skewLow = 0.5, skewHigh = 3, retryTicks = 20,
  allowedMapTypes = { [3] = true },
  perkMax = 45, perkMin = 30, forageSpeedMin = 2.2, forageSpeedMax = 3.0, runSpeed = 4,
  digTicks = 12, cryPause = 6, cryGap = 10, rarePause = 20, rarePause4 = 30,
  popupTicks = 40, popupTicksRare = 60, popupTicksTop = 80,
}

-- a long open road with a wall column at x = 40 (north of y = 30 only)
local blocked = {}
local function open(x, y)
  if x < 0 or x > 5000 or y < 0 or y > 80 then return false end
  if x == 40 and y < 30 then return false end
  if blocked[x .. "," .. y] then return false end
  return true
end

local function newForager(deps, cfg)
  local d = { cellFree = open, rng = function() return 0.5 end, cfg = cfg or CFG,
              rollItem = function() return { name = "Potion", tier = 1 } end,
              commitItem = function(r) return r end }
  for k, v in pairs(deps or {}) do d[k] = v end
  return Forager.new(d)
end

local MON = { species = 252 }
-- the player at cell (px, 30), the follower one cell behind; `moving` = walking
local function env(px, moving, t)
  local e = { still = not moving, fx = px - 1, fy = 30, fpx = (px - 1) * 16, fpy = 30 * 16,
              px = px, py = 30, mon = MON, friendship = 70 }
  for k, v in pairs(t or {}) do e[k] = v end
  return e
end

-- walk the player along the row for `ticks`, one cell per 16 ticks
local function walk(f, startPx, ticks, onTick, t)
  local px = startPx
  for i = 1, ticks do
    if i % 16 == 0 then px = px + 1 end
    local e = env(px, true, t)
    local s = f:step(e)
    if onTick then onTick(s, px, i, e) end
  end
  return px
end
-- walk until the first trip is back home (or `ticks` run out)
local function firstTrip(f, startPx, ticks, onTick, t)
  local px, left = startPx, false
  for i = 1, ticks do
    if i % 16 == 0 then px = px + 1 end
    local e = env(px, true, t)
    local s = f:step(e)
    if f.mode ~= "near" then left = true end
    if onTick then onTick(s, px, i, e) end
    if left and f.mode == "near" then return true end
  end
  return false
end
local function modesOf(f, startPx, ticks, t)
  local order, last = {}, nil
  walk(f, startPx, ticks, function() if f.mode ~= last then order[#order + 1] = f.mode last = f.mode end end, t)
  return table.concat(order, ">")
end

-- ------- a standing player: it stays beside them and nothing starts
do
  local f = newForager()
  for _ = 1, 400 do
    eq(f:step(env(20, false)), nil, "standing: nothing to draw") ; if f.mode ~= "near" then break end
  end
  eq(f.mode, "near", "standing still never starts a trip")
  eq(f.forageTimer, 0, "...and the timer does not count")
end

-- ------- a find, end to end: perk > out > dig > react > back, and always an item
do
  local log, cries, found = {}, 0, 0
  local f = newForager({
    playCry = function(species) cries = cries + 1 log[#log + 1] = "cry" eq(species, 252, "the cry is its own species") end,
    playFound = function() found = found + 1 log[#log + 1] = "found" end,
    commitItem = function(r) log[#log + 1] = "bag" return r end,
  })
  local sawPopup, popupText, sawBounceInPerk = false, nil, false
  local spotDist, spotChecked = nil, false
  local order = modesOf(f, 20, 600)
  check(order:find("near>perk>out>dig>react>back>near", 1, true) ~= nil, "a trip is near > perk > out > dig > react > back (" .. order .. ")")
  -- run another trip watching the details
  local f2 = newForager({ playCry = function() cries = cries + 1 end })
  walk(f2, 20, 600, function(s, px, _, e)
    if f2.mode == "perk" and s and s.bounce then sawBounceInPerk = true end
    if f2.spot and not spotChecked then
      spotChecked = true
      spotDist = math.max(math.abs(f2.spot.x - e.px), math.abs(f2.spot.y - e.py))
    end
    if s and s.popup then sawPopup, popupText = true, s.popup.text end
  end)
  eq(log[1], "bag", "the find is bagged when it has dug")
  eq(log[2], "found", "...then the sound")
  eq(log[3], "cry", "...then its cry")
  check(sawPopup and popupText == "Found Potion!", "a 'Found Potion!' label showed")
  check(sawBounceInPerk, "it perks up (an alert bounce) before it dashes off")
  check(spotDist and spotDist >= 3 and spotDist <= 5, "the spot is 3-5 cells from the player (" .. tostring(spotDist) .. ")")
end

-- ------- every trip finds something: the item is rolled before it sets out
do
  local rolled, committed = 0, 0
  local f = newForager({
    rollItem = function(friendship) rolled = rolled + 1 eq(friendship, 70, "the roll is told its friendship") return { name = "Potion", tier = 1 } end,
    commitItem = function(r) committed = committed + 1 return r end,
  })
  walk(f, 20, 2000)
  check(rolled >= 2, "it went out more than once (" .. rolled .. ")")
  check(committed >= rolled - 1, "every trip that set out bagged its find")
end

-- ------- nothing that fits the bag (or nothing to find): no trip, the timer waits
do
  local fits = false
  local tries = 0
  local f = newForager({ rollItem = function() tries = tries + 1 if fits then return { name = "Potion", tier = 1 } end return nil end })
  local order = modesOf(f, 20, 300)
  eq(order, "near", "a full bag never sends it out")
  check(f.forageTimer >= 50, "...the timer is kept (it is due)")
  check(tries >= 2 and tries <= 300 / 20 + 1, "...and it only looks again now and then (" .. tries .. " tries)")
  fits = true
  check(modesOf(f, 40, 200):find("perk", 1, true) ~= nil, "once something fits it sets out")
end

-- ------- nowhere to go: no trip, the roll is not even asked
do
  local rolls = 0
  local f = newForager({ cellFree = function() return false end, rollItem = function() rolls = rolls + 1 return { name = "Potion" } end })
  eq(modesOf(f, 20, 300), "near", "hemmed in: it just trots along")
  eq(rolls, 0, "...and nothing is rolled")
end

-- ------- no idle wandering, ever
do
  local f = newForager(nil, setmetatable({ intervalMin = 1e9, intervalMax = 1e9 }, { __index = CFG }))
  local drawn = 0
  walk(f, 20, 20000, function(s) if s then drawn = drawn + 1 end end)
  eq(f.mode, "near", "with no find due it never leaves the player's side")
  eq(drawn, 0, "...and never draws away from them")
end

-- ------- the timer only runs while walking, where foraging is allowed
do
  local f = newForager()
  for _ = 1, 100 do f:step(env(20, false)) end
  eq(f.forageTimer, 0, "standing does not count")
  walk(f, 20, 30, nil, { forageOk = false })
  eq(f.forageTimer, 0, "walking in a town / building / on water does not count")
  eq(modesOf(f, 20, 300, { forageOk = false }), "near", "...and never starts a trip there")
  walk(f, 20, 10)
  eq(f.forageTimer, 10, "walking on a route does")
end

-- ------- the tell: it stops where it is while the player walks on; fonder = shorter
do
  local function tell(friendship)
    local f = newForager()
    local ticks, positions, followerMoved, firstFpx = 0, {}, false, nil
    firstTrip(f, 20, 600, function(s, _, _, e)
      if f.mode == "perk" and s then
        ticks = ticks + 1
        positions[#positions + 1] = e.fpx + s.dx
        firstFpx = firstFpx or e.fpx
        if e.fpx ~= firstFpx then followerMoved = true end
      end
    end, { friendship = friendship })
    local still = true
    for i = 2, #positions do if positions[i] ~= positions[1] then still = false end end
    return ticks, still, followerMoved
  end
  local ticks0, still0, moved0 = tell(0)
  check(still0 and moved0, "during the tell it stays put on the ground while the player walks on")
  eq(ticks0, 45, "the tell lasts 45 ticks at friendship 0")
  local ticks255 = tell(255)
  eq(ticks255, 30, "...and 30 at friendship 255 (a fond Pokemon is more eager)")
end

-- ------- and dashes out faster the fonder it is
do
  local function outTicks(friendship)
    local f = newForager()
    local n, dist = 0, 0
    firstTrip(f, 20, 600, function() if f.mode == "out" then n = n + 1 end end, { friendship = friendship })
    return n
  end
  local slow, quick = outTicks(0), outTicks(255)
  check(quick < slow, "the dash is quicker at friendship 255 (" .. quick .. " vs " .. slow .. " ticks)")
end

-- ------- the glint: from the tell until it has dug, and nowhere else
do
  local f = newForager()
  local byMode = {}
  walk(f, 20, 600, function()
    local a = {}
    f:collectActors(a)
    byMode[f.mode] = byMode[f.mode] or {}
    byMode[f.mode][#a > 0 and "yes" or "no"] = true
    if #a > 0 then eq(a[1].kind, "ow_forage_sparkle", "the glint is the forage sparkle") end
  end)
  check(byMode.perk and byMode.perk.yes and not byMode.perk.no, "it glints during the tell")
  check(byMode.out and byMode.out.yes and not byMode.out.no, "...while it runs there")
  check(byMode.dig and byMode.dig.yes, "...and while it digs")
  check(byMode.near and not byMode.near.yes, "never while it is beside the player")
  check(byMode.back and not byMode.back.yes, "...or on the way back")
  local g = newForager()
  walk(g, 20, 60)
  local a = {}
  g:collectActors(a)
  check(g.mode == "perk" and #a == 1, "sanity: it glints during a tell")
  g:mapChanged()
  a = {}
  g:collectActors(a)
  eq(#a, 0, "a map change takes the glint away")
  walk(g, 20, 60)
  g:reset()
  a = {}
  g:collectActors(a)
  eq(#a, 0, "so does a reset")
end

-- ------- a rare find: two cries, a longer label and a longer, happier pause
do
  local function react(tier)
    local cries, cryAt, label, reactTicks, bounced = 0, {}, nil, 0, false
    local f = newForager({
      rollItem = function() return { name = "Dusk Stone", tier = tier } end,
      playCry = function() cries = cries + 1 cryAt[#cryAt + 1] = f and f.t end,
    })
    firstTrip(f, 20, 700, function(s)
      if f.mode == "react" then
        reactTicks = reactTicks + 1
        if s and s.bounce then bounced = true end
      end
      if s and s.popup and not label then label = s.popup.text end
    end)
    return { cries = cries, reactTicks = reactTicks, popupFor = f.popupFor, bounced = bounced, label = label }
  end
  local common, rare, top = react(1), react(3), react(4)
  eq(common.cries, 1, "a common find cries once")
  eq(rare.cries, 2, "a rare find cries twice")
  eq(top.cries, 2, "...a very rare one too")
  eq(common.popupFor, CFG.popupTicks, "a common label lasts popupTicks")
  eq(rare.popupFor, CFG.popupTicksRare, "a rare one longer")
  eq(top.popupFor, CFG.popupTicksTop, "a very rare one longer still")
  check(rare.bounced and not common.bounced, "a rare find gets a happy bounce, a common one does not")
  check(top.reactTicks > rare.reactTicks and rare.reactTicks > common.reactTicks, "the pause grows with rarity")
  eq(rare.label, "Found Dusk Stone!", "the label names the find")
end

-- ------- the bag filled while it was out: no cry, no label, home it goes
do
  local cries, popups = 0, 0
  local f = newForager({ commitItem = function() return nil end, playCry = function() cries = cries + 1 end })
  local order = modesOf(f, 20, 400)
  walk(f, 40, 200, function(s) if s and s.popup then popups = popups + 1 end end)
  check(order:find("dig>back", 1, true) ~= nil, "it comes straight back (" .. order .. ")")
  eq(cries, 0, "no cry without a find")
  eq(popups, 0, "...and no label")
end

-- ------- the walking carried over: after a find the surplus counts toward the next
do
  local f = newForager(nil, setmetatable({ intervalMin = 50, intervalMax = 50 }, { __index = CFG }))
  local timerAtReact
  walk(f, 20, 600, function() if f.mode == "react" and not timerAtReact then timerAtReact = f.forageTimer end end)
  check(timerAtReact ~= nil and timerAtReact > 0 and timerAtReact < 200, "the timer keeps what was walked past the goal (" .. tostring(timerAtReact) .. ")")
end

-- ------- a map change cancels the trip but keeps the timer: the next map starts at once
do
  local f = newForager()
  walk(f, 20, 60)
  eq(f.mode, "perk", "sanity: a tell is under way")
  local timer = f.forageTimer
  f:mapChanged()
  eq(f.mode, "near", "a map change cancels the trip")
  eq(f.spot, nil, "...and its spot")
  check(f.forageTimer >= timer, "...but keeps the timer")
  f:step(env(100, true))
  eq(f.mode, "perk", "on the next allowed map it sets out at once")
end

-- ------- a trip that has begun is finished even if the player stops
do
  local f = newForager()
  walk(f, 20, 60)
  eq(f.mode, "perk", "sanity: a tell is under way")
  local reached = false
  for _ = 1, 500 do
    f:step(env(23, false))
    if f.mode == "react" then reached = true end
    if f.mode == "near" then break end
  end
  check(reached, "it still goes and digs its find")
  eq(f.mode, "near", "...and comes home")
end

-- ------- never into or across a wall, never onto a wild Pokemon
do
  local wild = {}
  local f = newForager({ occupied = function(x, y) return wild[x .. "," .. y] == true end })
  for x = 22, 30 do wild[x .. ",27"] = true end
  local bad = false
  walk(f, 36, 1200, function(s, _, _, e)
    if s then
      local wx, wy = e.fpx + s.dx, e.fpy + s.dy
      local cx, cy = math.floor(wx / 16 + 0.5), math.floor(wy / 16 + 0.5)
      if (f.mode == "out" or f.mode == "dig") and (not open(cx, cy) or wild[cx .. "," .. cy]) then bad = true end
    end
    if f.spot and (not open(f.spot.x, f.spot.y) or wild[f.spot.x .. "," .. f.spot.y]) then bad = true end
  end)
  check(not bad, "its spot and its way there are always open ground")
end

-- ------- reset
do
  local f = newForager()
  walk(f, 20, 60)
  f:reset()
  eq(f.mode, "near", "reset brings it home")
  eq(f.forageTimer, 0, "...and starts the timer over")
  eq(f.rolled, nil, "...dropping the find it had not bagged yet")
  check(not f:isBusy(), "...and it is not busy")
end

-- ------- the wait: always 1-3 minutes of walking, sooner the fonder it is
do
  local f = Forager.new({ cellFree = open, cfg = Config.FORAGE })
  local sum0, sum255, inRange = 0, 0, true
  local n = 200
  for i = 0, n - 1 do
    f.goalRoll = i / n
    local g0, g255 = f:goal(0), f:goal(255)
    if g0 < 3600 or g0 > 10800 or g255 < 3600 or g255 > 10800 then inRange = false end
    sum0, sum255 = sum0 + g0, sum255 + g255
  end
  check(inRange, "every wait is between 3600 and 10800 walking ticks (1-3 minutes)")
  local mean0, mean255 = sum0 / n / 60, sum255 / n / 60
  check(mean0 > 125 and mean0 < 155, string.format("friendship 0 waits ~140 s on average (%.0f s)", mean0))
  check(mean255 > 80 and mean255 < 100, string.format("friendship 255 waits ~90 s (%.0f s)", mean255))
  check(f:goal(nil) == f:goal(0), "no friendship counts as 0")
end

-- ------- the real defaults
do
  local F = Config.FORAGE
  for _, k in ipairs({ "minSpread", "maxSpread", "maxWalk", "intervalMin", "intervalMax", "skewLow", "skewHigh",
    "retryTicks", "allowedMapTypes", "perkMax", "perkMin", "forageSpeedMin", "forageSpeedMax", "runSpeed",
    "digTicks", "cryPause", "cryGap", "rarePause", "rarePause4", "popupTicks", "popupTicksRare", "popupTicksTop",
    "bands", "tierBase", "tierGate", "tierMult", "evoTop", "maxTmPrice" }) do
    check(F[k] ~= nil, "Config.FORAGE." .. k)
  end
  for _, k in ipairs({ "findChance", "wanderWaitMin", "wanderWaitMax", "lingerMin", "lingerMax", "forageMin", "forageMax" }) do
    eq(F[k], nil, "Config.FORAGE." .. k .. " is gone")
  end
  eq(F.minSpread, 3, "the find is 3 ...")
  eq(F.maxSpread, 5, "... to 5 cells from the player")
  eq(F.intervalMin, 3600, "one find per 1 ...")
  eq(F.intervalMax, 10800, "... to 3 minutes of walking")
  eq(F.tierGate[3], 130, "rare finds need friendship 130")
  eq(F.tierGate[4], 200, "very rare ones 200")
  check(F.allowedMapTypes[3] and F.allowedMapTypes[4], "routes (3) and caves (4) are allowed")
  check(not (F.allowedMapTypes[1] or F.allowedMapTypes[2] or F.allowedMapTypes[8]
    or F.allowedMapTypes[5] or F.allowedMapTypes[6]), "towns, cities, buildings and water are not")
end

if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("forager_unit_test: all passed")
