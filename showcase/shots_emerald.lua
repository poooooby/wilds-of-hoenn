-- The Emerald reel (showcase/director.lua). Each shot: `stage(ctx)` sets the scene and
-- the camera's first frame while the director waits for Page Down; `roll(ctx)` plays it.
-- Camera: ctx.cam:set / :move{at = {wx, wy} | panX, panY, zoom, frames, ease} / :track(fn,
-- {zoom, lag}) / :engineZoom(step). Pan is in world px from the player's tile centre.
return function(ctx)
  local woh, EP, sm, fa, cam = ctx.woh, ctx.EP, ctx.sm, ctx.fa, ctx.cam
  local sky, wl, ls = woh.skyFlyers, woh.waterLife, woh.localScenes

  local function scene(kind)
    for _, c in ipairs(ls.scenes or {}) do if c.kind == kind then return c end end
  end
  local function creature(kind)
    for _, c in ipairs(wl.creatures or {}) do if c.kind == kind then return c end end
  end
  local function startScene(kind, tries)
    for _ = 1, tries or 30 do
      if ls:start(kind) then return scene(kind) end
      ctx.wait(5)
    end
  end
  local function tries(fn, n)
    for _ = 1, n or 20 do
      local ok, v = pcall(fn)
      if ok and v then return v end
      ctx.wait(5)
    end
  end
  local function player() return ctx.cam.playerCentre() end
  local function partner()
    local npc = EP.followerCurrent and EP.followerCurrent()
    if npc and npc.px then return npc.px + 8, npc.py + 8 end
    return player()
  end
  local function between(ax, ay, bx, by) return (ax + bx) / 2, (ay + by) / 2 end
  -- along the path: the side with the longest open run (no grass, nothing in the way)
  local function openRun(x, y)
    local best, bestN = "left", 0
    for _, d in ipairs({ { "left", -1, 0 }, { "right", 1, 0 }, { "up", 0, -1 }, { "down", 0, 1 } }) do
      local n = 0
      while n < 8 and EP.terrainAt(x + d[2] * (n + 1), y + d[3] * (n + 1)) == nil
        and EP.cellFree(x + d[2] * (n + 1), y + d[3] * (n + 1)) do n = n + 1 end
      if n > bestN then best, bestN = d[1], n end
    end
    return best, bestN
  end
  local BACK = { left = "right", right = "left", up = "down", down = "up" }
  local chaser
  local fieldSpot -- the grass path the field shots share (findFieldSpot, below)

  -- a patch of open sea near the player wide enough for a Finizen pod (7 x 3 water, no
  -- rocks or objects), nearest to `want` tiles out to the side: world px of its centre
  local function openSea(wantDx)
    local p = EP.playerCell()
    local best, bestD
    for y = p.y - 14, p.y + 14 do
      for x = p.x - 24, p.x + 24 do
        local ok = math.max(math.abs(x - p.x), math.abs(y - p.y)) >= 5
        for dy = -1, 1 do
          for dx = -3, 3 do
            if ok and not EP.isWater(x + dx, y + dy) then ok = false end
          end
        end
        if ok and EP.objectOn and EP.objectOn(x, y) then ok = false end
        if ok then
          local d = math.abs((x - p.x) - (wantDx or -7)) + math.abs(y - p.y)
          if not bestD or d < bestD then best, bestD = { x, y }, d end
        end
      end
    end
    if best then return best[1] * 16 + 8, best[2] * 16 + 8 end
  end

  -- talk to the partner (standing beside it, facing it) and pick `row` (1 Pet, 2 Play,
  -- 3 Talk) under Interact; returns once its reply is up
  local function interact(row)
    local fi = woh.followerInteraction
    local function menu(name)
      return fi.state == "menu" and fi.menuName == name and EP.choiceActive and EP.choiceActive()
    end
    ctx.tap("a")       -- how it is doing: its portrait and face, then the menu
    ctx.waitUntil(function() return menu("main") end, 400)
    ctx.wait(70)
    ctx.tap("a")       -- Interact
    ctx.waitUntil(function() return menu("interact") end, 120)
    ctx.wait(30)
    for _ = 2, row do ctx.tap("down") ctx.wait(12) end
    ctx.wait(20)
    ctx.tap("a")       -- it acts it out, then says how it liked it
    ctx.waitUntil(function() return fi.state == "result" end, 900)
  end
  -- stand beside the partner on the path, facing it
  local function besidePartner()
    local dir = openRun(fieldSpot.x, fieldSpot.y)
    ctx.walk(dir, 1)
    ctx.wait(30)
    ctx.face(BACK[dir])
    return dir
  end
  -- the partner's job (follow / battle / forage), as the party menu sets it
  local function role(r)
    local mon = ctx.session.party[1]
    local c = woh.companion
    if c and mon and c:set(mon, r) then
      -- this is the lead now, so the new-leader rule does not put it back on follow
      c.state.lead = tonumber(mon.personality) or 0
      c:_persist()
    end
  end

  -- the grass path the field shots share (Route 101: no trainers), found once: a dry,
  -- walkable cell with plenty of grass round it and a long open run along the path
  local function findFieldSpot()
    local w, h = EP.mapBounds()
    local best, bestScore
    for y = 2, (h or 40) - 3 do
      for x = 2, (w or 40) - 3 do
        if EP.terrainAt(x, y) == nil and EP.cellFree(x, y) and not EP.isWater(x, y) then
          local g = 0
          for dy = -3, 3 do for dx = -3, 3 do
            if EP.terrainAt(x + dx, y + dy) == "land" then g = g + 1 end
          end end
          local _, run = openRun(x, y)
          if g >= 10 and run >= 5 then
            local score = g + run * 3
            if not bestScore or score > bestScore then best, bestScore = { x = x, y = y }, score end
          end
        end
      end
    end
    return best
  end
  -- the walkable tall-grass cell with the longest straight run of grass from it
  local grassCache
  local function grassSpot()
    if grassCache then return grassCache end
    local w, h = EP.mapBounds()
    local best
    for y = 2, (h or 40) - 3 do
      for x = 2, (w or 40) - 3 do
        if EP.terrainAt(x, y) == "land" and EP.cellFree(x, y) then
          for _, d in ipairs({ { "left", -1, 0 }, { "right", 1, 0 }, { "up", 0, -1 }, { "down", 0, 1 } }) do
            local n = 0
            while n < 8 and EP.terrainAt(x + d[2] * (n + 1), y + d[3] * (n + 1)) == "land"
              and EP.cellFree(x + d[2] * (n + 1), y + d[3] * (n + 1)) do n = n + 1 end
            if not best or n > best.run then best = { x = x, y = y, dir = d[1], run = n } end
          end
        end
      end
    end
    grassCache = best
    return best
  end
  local function goField()
    ctx.go("MAP_ROUTE101", 10, 10, "down")
    fieldSpot = fieldSpot or findFieldSpot() or { x = 10, y = 10 }
    ctx.go("MAP_ROUTE101", fieldSpot.x, fieldSpot.y, (openRun(fieldSpot.x, fieldSpot.y)))
    ctx.hidePeople()
  end

  return {
    -- 1. Establishing: Petalburg City from up high, birds on the roofs and passing over
    {
      name = "open_petalburg",
      stage = function()
        ctx.party({ { 254, 50, friendship = 255, nick = "SCEPTILE" } })
        ctx.go("MAP_PETALBURG_CITY", 15, 12, "down")
        sky:clear()
        cam:engineZoom(-1)
        cam:set({ panX = 40, panY = -24, zoom = 1.15 })
        ctx.wait(30)
        tries(function() return sky:_spawnPercher() end, 10)
        tries(function() return sky:_spawnPercher() end, 10)
      end,
      roll = function()
        ctx.wait(20)
        tries(function() return sky:_spawnPasser() end, 5)
        cam:move({ panX = -40, panY = 8, zoom = 1, frames = 480 })
        ctx.wait(520)
      end,
    },
    -- 2. Wild Pokemon rise out of the grass
    {
      name = "spawns_arrive",
      stage = function()
        ctx.party({ { 252, 12, nick = "TREECKO" } })
        goField()
        ctx.clearWild(false)
        cam:set({ panY = -24, zoom = 1.35 })
      end,
      roll = function()
        ctx.wait(40)
        ctx.noRefill(false) -- they come back: rising out of the grass, rustling
        cam:move({ panY = -8, zoom = 1.15, frames = 300 })
        ctx.wait(360)
      end,
    },
    -- 3. Your partner follows you: walking and running along the path
    {
      name = "partner_walk",
      stage = function()
        ctx.party({ { 254, 50, friendship = 220, nick = "SCEPTILE" } })
        goField()
        cam:set({ zoom = 1.6 })
      end,
      roll = function()
        local dir, n = openRun(fieldSpot.x, fieldSpot.y)
        n = math.max(2, math.min(6, n))
        cam:track(player, { zoom = 1.3, lag = 0.1 })
        ctx.walk(dir, n)
        ctx.wait(20)
        ctx.run(BACK[dir], n)
        ctx.wait(20)
        ctx.walk(dir, math.max(2, n - 1))
        ctx.wait(30)
        cam:move({ zoom = 1.8, frames = 90 })
        ctx.wait(120)
      end,
    },
    -- 4. Pet your partner: its portrait, hearts and sparkles
    {
      name = "partner_pet",
      stage = function()
        ctx.party({ { 254, 50, friendship = 250, nick = "SCEPTILE" } })
        goField()
        local dir = openRun(fieldSpot.x, fieldSpot.y)
        ctx.walk(dir, 1)
        ctx.wait(30)
        ctx.face(BACK[dir])
        -- a close-up with the text box whole: the engine's own zoom (the world only), no
        -- post zoom (that would crop the box and the portrait)
        cam:engineZoom(1)
        local px, py = player()
        local fx, fy = partner()
        cam:set({ at = { between(px, py, fx, fy) } })
      end,
      roll = function()
        ctx.wait(30)
        interact(1)
        ctx.wait(150)
        ctx.tap("a")
        ctx.wait(40)
        ctx.closeText()
        ctx.wait(40)
      end,
    },
    -- 4b. Play: a ball thrown, the partner dashing after it and back
    {
      name = "partner_play",
      stage = function()
        ctx.party({ { 254, 50, friendship = 200, nick = "SCEPTILE" } })
        goField()
        ctx.clearWild(false)
        besidePartner()
        local px, py = player()
        local fx, fy = partner()
        cam:set({ at = { between(px, py, fx, fy) }, zoom = 1 })
      end,
      roll = function()
        ctx.wait(30)
        interact(2)
        ctx.wait(150)
        ctx.tap("a")
        ctx.wait(40)
        ctx.closeText()
        ctx.wait(40)
      end,
    },
    -- 4c. The Battle job: the partner takes on a wild Pokemon by itself
    {
      name = "battler",
      stage = function()
        ctx.party({ { 253, 22, friendship = 200, nick = "GROVYLE" } })
        role("battle")
        goField()
        ctx.clearWild(false)
        cam:set({ zoom = 1.2 })
      end,
      roll = function()
        -- its opponents arrive once the camera rolls (a close match: a few exchanges)
        ctx.spawn(263, 14, { radius = 3 })
        ctx.wait(20)
        local function action()
          local fx, fy = partner()
          local b = woh.battler
          if b and b.wx then return b.wx + 8, b.wy + 8 end
          return fx, fy
        end
        cam:track(action, { zoom = 1.5, lag = 0.05 })
        for k = 1, 12 do
          ctx.wait(60)
          if k == 5 then ctx.spawn(261, 13, { radius = 3 }) end
          if os.getenv("SHOWCASE_DEBUG") then
            local b = woh.battler
            print(("[dbg] battler role %s mode %s cooldown %s targets %d companion %s"):format(tostring(fa.role),
              tostring(b and b.mode), tostring(b and b.cooldown), #sm:fightTargets(),
              tostring(woh.companion.state and woh.companion.state.role)))
          end
        end
        cam:still()
        ctx.wait(60)
      end,
    },
    -- 4d. The Forage job: it perks up, dashes off, digs, and finds something
    {
      name = "forage",
      stage = function()
        ctx.party({ { 254, 40, friendship = 230, nick = "SCEPTILE" } })
        role("forage")
        goField()
        ctx.clearWild(false)
        cam:set({ zoom = 1.3 })
      end,
      roll = function()
        local dir, n = openRun(fieldSpot.x, fieldSpot.y)
        local f = woh.forager
        if f then f.forageTimer, f.retry = 1e6, 0 end -- the next steps find something
        local function action()
          if f and f.wx and f.mode ~= "near" then return f.wx + 8, f.wy + 8 end
          return player()
        end
        cam:track(action, { lag = 0.05 })
        ctx.walk(dir, math.max(1, math.min(2, n)))
        ctx.waitUntil(function() return f and f.mode == "near" and f.popup == nil and f.spot == nil end, 900)
        ctx.wait(120)
      end,
    },
    -- 5. A shiny partner twinkles
    {
      name = "shiny",
      stage = function()
        ctx.party({ { 258, 15, shiny = true, nick = "MUDKIP" } })
        goField()
        local dir = openRun(fieldSpot.x, fieldSpot.y)
        ctx.walk(dir, 1)
        ctx.wait(40)
        cam:set({ at = { partner() }, zoom = 1.5 })
      end,
      roll = function()
        cam:move({ at = { partner() }, zoom = 2.4, frames = 180 })
        ctx.wait(420)
      end,
    },
    -- 6. Run past weaker Pokemon: they startle and flee
    {
      name = "reacts_flee",
      stage = function()
        ctx.party({ { 254, 60, nick = "SCEPTILE" } })
        goField()
        ctx.clearWild(false)
        for _, d in ipairs({ 263, 265, 261, 263 }) do ctx.spawn(d, 3, { radius = 3 }) end
        ctx.wait(60)
        cam:set({ zoom = 1.25 })
      end,
      roll = function()
        local dir, n = openRun(fieldSpot.x, fieldSpot.y)
        n = math.max(2, math.min(5, n))
        ctx.wait(30)
        cam:track(player, { lag = 0.06 })
        ctx.run(dir, n)
        cam:still()
        ctx.wait(200) -- '!', then off they run
        cam:track(player, { lag = 0.06 })
        ctx.run(BACK[dir], n)
        cam:still()
        ctx.wait(200)
      end,
    },
    -- 7. ...a much stronger one gets angry and gives chase
    {
      name = "reacts_chase",
      stage = function()
        ctx.party({ { 252, 5, nick = "TREECKO" } })
        goField()
        -- a chaser follows over its own terrain (the grass): this one plays out in a patch
        -- of tall grass (no battles on the reel, so running through it is safe)
        local g = grassSpot()
        if g then ctx.go("MAP_ROUTE101", g.x, g.y, g.dir) ctx.hidePeople() end
        ctx.clearWild(false)
        -- beside or behind the player, never on the line it is about to run along
        local V = { left = { -1, 0 }, right = { 1, 0 }, up = { 0, -1 }, down = { 0, 1 } }
        local dv = V[(g and g.dir) or "left"]
        for _ = 1, 15 do
          chaser = ctx.spawn(262, 40, { radius = 2 })
          if not chaser then break end
          local p = EP.playerCell()
          local ax, ay = chaser.cellX - p.x, chaser.cellY - p.y
          if ax * dv[1] + ay * dv[2] <= 0 then break end
          sm:despawn(chaser.id)
          chaser = nil
        end
        ctx.wait(60)
        cam:set({ zoom = 1.4 })
      end,
      roll = function()
        local g = grassSpot()
        local dir, n = (g and g.dir) or "left", (g and g.run) or 4
        local function both()
          local px, py = player()
          if chaser and chaser.px then return between(px, py, chaser.px + 8, chaser.py + 8) end
          return px, py
        end
        cam:track(both, { zoom = 1.15, lag = 0.06 })
        if os.getenv("SHOWCASE_DEBUG") then
          local p = EP.playerCell()
          print(("[dbg] chaser %s at %s,%s player %d,%d dir %s"):format(tostring(chaser ~= nil),
            tostring(chaser and chaser.cellX), tostring(chaser and chaser.cellY), p.x, p.y, dir))
          local g = ctx.game
          for k = 1, 24 do
            table.insert(g.input.pressQueue, dir)
            g.input.state[dir] = true
            g.input.state.b = true
            ctx.frame()
            if k % 3 == 0 then
              print(("[dbg] running %s moving %s react %s at %d,%d"):format(tostring(EP.playerIsRunning()),
                tostring(EP.playerCell().moving), tostring(chaser and chaser.react and chaser.react.mode),
                EP.playerCell().x, EP.playerCell().y))
            end
          end
          g.input.state[dir], g.input.state.b = false, false
        end
        ctx.run(dir, 1)
        ctx.wait(80) -- it turns to you, the anger mark...
        ctx.run(dir, math.max(2, math.min(6, n - 1)))
        ctx.wait(260) -- ...and it comes after you
      end,
    },
    -- 8. Sweet Scent calls them over
    {
      name = "sweet_scent",
      stage = function()
        ctx.party({ { 254, 50, nick = "SCEPTILE" } })
        goField()
        ctx.clearWild(false)
        cam:set({ zoom = 1.3 })
      end,
      roll = function()
        ctx.wait(30)
        sm:sweetScent()
        cam:move({ zoom = 1.7, frames = 200 })
        ctx.wait(420)
      end,
    },
    -- 9. A wild Flying type swoops in to land
    {
      name = "swoop_landing",
      stage = function()
        ctx.party({ { 254, 50, nick = "SCEPTILE" } })
        goField()
        sky:clear()
        ctx.clearWild(false)
        cam:set({ zoom = 1.1 })
      end,
      roll = function()
        ctx.wait(20)
        local e
        for _ = 1, 20 do
          e = ctx.spawn(276, 6, { radius = 7 })
          if e and e.fx and e.fx.kind == "land" then break end
          if e then sm:despawn(e.id) e = nil end
          ctx.wait(5)
        end
        if e then cam:track(function() return ctx.centreOf(e) end, { zoom = 1.4, lag = 0.05 }) end
        ctx.wait(300)
        cam:still()
        ctx.wait(60)
      end,
    },
    -- 10. Out at sea: leaping fish, a diving bird, Wailmer, a Finizen pod
    {
      name = "sea_life",
      stage = function()
        ctx.party({ { 254, 50, nick = "SCEPTILE" } })
        ctx.go("MAP_ROUTE109", 11, 16, "left")
        wl:clear()
        sky:clear()
        cam:set({ panX = -48, zoom = 1.25 })
      end,
      roll = function()
        tries(function() return wl:_spawnLeaper() end, 10)
        ctx.wait(70)
        tries(function() return sky:_spawnDiver() end, 10)
        ctx.wait(50)
        tries(function() return wl:_spawnWhale() end, 10)
        cam:move({ panX = -72, zoom = 1.1, frames = 300 })
        ctx.wait(160)
        ctx.wait(300)
        tries(function() return wl:_spawnLeaper() end, 5)
        ctx.wait(120)
      end,
    },
    -- 10b. Finizen out at sea: a pod surfacing to play, then one porpoising along
    {
      name = "finizen",
      stage = function()
        ctx.party({ { 254, 50, nick = "SCEPTILE" } })
        ctx.go("MAP_ROUTE109", 11, 16, "left")
        wl:clear()
        sky:clear()
        ctx.clearWild(false) -- (the route's own swimmers would take up the open water)
        -- the view over a patch of open sea, clear of the rocks
        local sx, sy = openSea(-7)
        if os.getenv("SHOWCASE_DEBUG") then print("[dbg] open sea " .. tostring(sx) .. "," .. tostring(sy)) end
        if sx then cam:set({ at = { sx, sy }, zoom = 1.15 }) else cam:set({ panX = -96, zoom = 1.15 }) end
        ctx.wait(20)
      end,
      roll = function()
        local pod = tries(function() return wl:_spawnPod() and creature("pod") end, 80)
        if os.getenv("SHOWCASE_DEBUG") then print("[dbg] finizen pod " .. tostring(pod ~= nil)) end
        if pod then cam:move({ at = { ctx.cellCentre(pod.cx, pod.cy) }, zoom = 1.5, frames = 150 }) end
        ctx.waitUntil(function() return not creature("pod") end, 800)
        cam:move({ zoom = 1.15, frames = 90 })
        local one = tries(function() return wl:_spawnDolphin() and creature("dolphin") end, 40)
        if os.getenv("SHOWCASE_DEBUG") then print("[dbg] finizen run " .. tostring(one ~= nil)) end
        if one then cam:move({ at = { ctx.cellCentre(one.cx, one.cy) }, frames = 120 }) end
        ctx.waitUntil(function() return not creature("dolphin") end, 900)
        cam:still()
        ctx.wait(40)
      end,
    },
    -- 11. Petalburg Woods: something hangs from the trees, someone naps, someone dances
    {
      name = "petalburg_woods",
      stage = function()
        ctx.party({ { 254, 50, nick = "SCEPTILE" } })
        ctx.go("MAP_PETALBURG_WOODS", 16, 35, "up")
        ls.timers = {}
        ls:clear()
        cam:set({ panY = -24, zoom = 1.3 })
      end,
      roll = function()
        local b = startScene("burmy")
        if b then cam:move({ at = { b.x + 8, b.y + 8 }, zoom = 1.6, frames = 150 }) end
        ctx.wait(220)
        local s = startScene("sleeper")
        if s then cam:move({ at = { s.x + 8, s.y + 8 }, zoom = 1.6, frames = 150 }) end
        ctx.wait(240)
        local c = startScene("cocoon")
        if c then cam:move({ at = { c.x + 8, c.y + 8 }, zoom = 1.6, frames = 150 }) end
        ctx.wait(200)
        local d = startScene("dancer")
        if d then cam:track(function() return d.x + 8, d.y + 8 end, { zoom = 1.4, lag = 0.04 }) end
        ctx.wait(420)
      end,
    },
    -- 12. Fortree City: something big moves through the treetops
    {
      name = "fortree_tropius",
      stage = function()
        ctx.party({ { 254, 50, nick = "SCEPTILE" } })
        ctx.go("MAP_FORTREE_CITY", 22, 13, "down")
        ls.timers = {}
        ls:clear()
        -- the view over the treetops south of the fence: Tropius rises where the canopy
        -- is deep and in view
        cam:set({ panY = 56, zoom = 1.1 })
      end,
      roll = function()
        local t = startScene("tropius")
        print(("[showcase] tropius: %s (place %s, perches %s, scenes %d)"):format(tostring(t ~= nil),
          tostring(ls.place ~= nil), tostring(ls.perches ~= nil), #(ls.scenes or {})))
        if t then cam:track(function() return t.x + 8, t.y end, { zoom = 1.6, lag = 0.04 }) end
        ctx.waitUntil(function() return not scene("tropius") end, 1500)
        cam:still()
        ctx.wait(60)
      end,
    },
    -- 13. Under the sea: shadows of fish, one swimming in to take shape
    {
      name = "under_the_sea",
      stage = function()
        ctx.party({ { 260, 50, nick = "SWAMPERT" } })
        ctx.go("MAP_UNDERWATER_ROUTE124", 20, 20, "down")
        wl:clear()
        cam:set({ zoom = 1.2 })
      end,
      roll = function()
        tries(function() return wl:_spawnSwimmer() end, 10)
        ctx.wait(60)
        tries(function() return wl:_spawnSwimmer() end, 10)
        cam:move({ panX = 24, zoom = 1.35, frames = 360 })
        ctx.wait(80)
        local e = ctx.spawn(319, 30, { radius = 9, terrain = "water" })
        if e then cam:track(function() return ctx.centreOf(e) end, { lag = 0.04 }) end
        ctx.wait(360)
      end,
    },
    -- 14. Finale: the coast from up high
    {
      name = "finale",
      stage = function()
        ctx.party({ { 254, 50, friendship = 255, nick = "SCEPTILE" } })
        ctx.go("MAP_ROUTE109", 11, 16, "left")
        wl:clear()
        sky:clear()
        cam:set({ zoom = 1.8 })
      end,
      roll = function()
        ctx.wait(20)
        tries(function() return sky:_spawnPasser() end, 5)
        tries(function() return wl:_spawnLeaper() end, 5)
        cam:move({ panX = -32, panY = -16, zoom = 1, frames = 480 })
        ctx.wait(520)
      end,
    },
    -- 19. EVERYTHING AT ONCE, in 8 seconds (showcase only -- nothing like this can happen
    -- in the game): Route 104's south end, Mr. Briney's cottage between the sea and the
    -- woods. 1.5 s tight on the player and Pikachu, a 3 s zoom out, 3.5 s wide -- while
    -- every ambient feature is set going at once: fish leaping, two Wailmer, a Finizen pod,
    -- diving / perching / passing birds, wild Pokemon rising all over the grass and Taillows
    -- swooping in, Burmy and the cocoons on their threads, Slakoth asleep, Vigoroth's dance,
    -- Tropius rising through the treetops, ghosts, and Gengar looming up behind you.
    {
      name = "everything",
      stage = function()
        ctx.party({ { 25, 20, friendship = 255, nick = "PIKACHU" } })
        ctx.option("spawn_amount", "high")
        -- Pikachu beside the player: step one tile so it trails to the side, then turn
        -- to the camera
        local MAPC, X, Y = "MAP_ROUTE104", 18, 26
        ctx.go(MAPC, X + 1, Y, "left")
        ctx.walk("left", 1)
        ctx.wait(20)
        local p = EP.playerCell()
        if not (p and p.x == X and p.y == Y) then
          ctx.go(MAPC, X - 1, Y, "right")
          ctx.walk("right", 1)
          ctx.wait(20)
        end
        ctx.face("down")
        ctx.pinFollower("down")
        ctx.hidePeople()
        ctx.clearWild(false)
        -- every system staged by hand: the woods' and Fortree's scenes here, perches for
        -- the birds, whales and dolphins in the water, nobody's own timers
        ls.timers = {}
        ls:clear()
        ls.place = { trees = true }
        ls.perches = ls.buildPerches()
        sky:clear()
        sky.perches = ls.perches
        sky.timers = { passer = 1e9, perch = 1e9, dive = 1e9 }
        -- the route's sky pool may hold no flyer at this hour (Modern Spawns rewrites the
        -- table by time of day) and no sea bird flagged for diving: Wingull and Taillow are
        -- this beach's birds regardless, kept through the pool's periodic re-read
        if not sky._showcaseRefresh then
          sky._showcaseRefresh = sky._refreshPool
          sky._refreshPool = function(self)
            self:_showcaseRefresh()
            if self._showcaseSea then
              if #self.pool == 0 then
                self.pool = { { species = EP.speciesForNational(278), weight = 2, sea = true },
                              { species = EP.speciesForNational(276), weight = 2, sea = false } }
              end
              if #self.seaPool == 0 then
                self.seaPool = { { species = EP.speciesForNational(278), weight = 1, sea = true } }
              end
            end
          end
        end
        sky._showcaseSea = true
        sky:_refreshPool()
        wl:clear()
        wl.timers = { leap = 1e9, whale = 1e9, dolphin = 1e9 }
        if not wl._showcaseRefresh then
          wl._showcaseRefresh = wl._refreshPool
          wl._refreshPool = function(self)
            self:_showcaseRefresh()
            if self._showcaseSea then
              self.sea = true
              self.whales = { EP.speciesForNational(320) }
              if #self.fish == 0 then self.fish = { EP.speciesForNational(129), EP.speciesForNational(118) } end
            end
          end
        end
        wl._showcaseSea = true
        wl:_refreshPool()
        -- the per-kind caps (two leaps, one whale, two perched birds, one passer, one
        -- diver) are what keep a real route calm; here the schedule is the only limit
        if not wl._showcaseCount then
          wl._showcaseCount = wl.count
          wl.count = function(self, kind)
            if self._showcaseLoose and (kind == "leap" or kind == "whale") then return 0 end
            return self:_showcaseCount(kind)
          end
        end
        if not sky._showcaseCount then
          sky._showcaseCount = sky._count
          sky._count = function(self, kind, highOnly)
            if self._showcaseLoose and (kind == "perch" or kind == "passer" or kind == "dive") then return 0 end
            return self:_showcaseCount(kind, highOnly)
          end
        end
        wl._showcaseLoose, sky._showcaseLoose = true, true
        -- the opening frame: tight on the two of them, from the wide (OUT2) engine view
        cam:engineZoom(-2)
        local px, py = player()
        local fx, fy = partner()
        cam:set({ at = { between(px, py, fx, fy) }, zoom = 4 })
      end,
      roll = function()
        local DBG = os.getenv("SHOWCASE_DEBUG")
        local t0 = love.timer.getTime()
        local function say(what, ok)
          if DBG then print(("[dbg] everything: %s -> %s"):format(what, tostring(ok))) end
        end
        -- the view's centre halfway between the sea and the deep trees (the player stays
        -- near the middle: at most 6 tiles off)
        local p = EP.playerCell()
        local wx, wy, nw, tx, ty, nt = 0, 0, 0, 0, 0, 0
        for y = p.y - 12, p.y + 12 do
          for x = p.x - 16, p.x + 16 do
            if EP.isWater(x, y) then wx, wy, nw = wx + x, wy + y, nw + 1 end
            if ls.deepCanopy(ls.perches, x, y) then tx, ty, nt = tx + x, ty + y, nt + 1 end
          end
        end
        local panX, panY = 0, 0
        if nw > 0 and nt > 0 then
          local cx, cy = (wx / nw + tx / nt) / 2, (wy / nw + ty / nt) / 2
          panX = math.max(-96, math.min(96, (cx - p.x) * 16))
          panY = math.max(-96, math.min(96, (cy - p.y) * 16))
        end

        local function perched()
          local out = {}
          for _, b in ipairs(sky.birds) do if b.sitting and b.perch then out[#out + 1] = b end end
          return out
        end
        local function gengar()
          local saved = ls.mapId
          ls.mapId = "LAVENDER_TOWN"
          local ok = ls:onScriptText("g3:0817f568", true)
          ls.mapId = saved
          if ok then
            local c = scene("gengar")
            if c then c.freeFor = -900 end -- looms there for the whole shot
          end
          return ok
        end
        local function taillow()
          for _ = 1, 20 do
            local e = ctx.spawn(276, 6, { radius = 16 })
            if not e then return false end
            if e.fx and e.fx.kind == "land" then return true end
            sm:despawn(e.id)
          end
          return false
        end
        local function shiny()
          local best, bd
          local pc = EP.playerCell()
          for _, id in ipairs(sm.order) do
            local e = sm.entities[id]
            if e and not e.fx then
              local d = math.abs(e.cellX - pc.x) + math.abs(e.cellY - pc.y)
              if not bd or d < bd then best, bd = e, d end
            end
          end
          if best then best.shiny = true return true end
        end
        local function flyOff()
          local list = perched()
          if #list > 0 then sky:_scatter(list[1]) return true end
        end
        local function hang(kind) return function() return ls:start(kind) end end
        local function start(kind) return function() return ls:start(kind) end end

        -- the 8 seconds, as { tick, name, fn }: the slow starters first (Tropius takes 3 s
        -- to rise), the rest spread over the first second so no single frame stalls
        local plan = {
          { 0, "wild", function() ctx.noRefill(false) return true end },
          { 0, "tropius", start("tropius") },
          { 0, "slakoth", start("sleeper") },
          { 0, "whale", function() return wl:_spawnWhale() end },
          { 0, "finizen pod", function() return wl:_spawnPod() end },
          { 2, "vigoroth", start("dancer") },
          { 4, "burmy", hang("burmy") },
          { 6, "percher", function() return sky:_spawnPercher() end },
          { 8, "diver", function() return sky:_spawnDiver() end },
          { 10, "passer", function() return sky:_spawnPasser() end },
          { 12, "ghost", start("ghost") },
          { 14, "cocoon", hang("cocoon") },
          { 16, "percher", function() return sky:_spawnPercher() end },
          { 18, "taillow", taillow },
          { 20, "ghost", start("ghost") },
          { 22, "passer", function() return sky:_spawnPasser() end },
          { 24, "burmy", hang("burmy") },
          { 26, "percher", function() return sky:_spawnPercher() end },
          { 28, "whale", function() return wl:_spawnWhale() end },
          { 30, "gengar", gengar },
          { 34, "ghost", start("ghost") },
          { 36, "percher", function() return sky:_spawnPercher() end },
          { 40, "taillow", taillow },
          { 50, "passer", function() return sky:_spawnPasser() end },
          { 70, "sweet scent", function() return sm:sweetScent() ~= nil end },
          { 110, "a shiny", shiny },
          { 200, "diver", function() return sky:_spawnDiver() end },
          { 240, "taillow", taillow },
          { 300, "fly off", flyOff },
          { 330, "passer", function() return sky:_spawnPasser() end },
          { 370, "fly off", flyOff },
          { 420, "gengar fades", function()
              local c = scene("gengar")
              if c then c.leaving = 0 return true end
            end },
        }
        -- fish leaping every 25 ticks the whole way through (two or three in the air at once)
        for k = 10, 470, 25 do plan[#plan + 1] = { k, "leap", function() return wl:_spawnLeaper() end, 0 } end
        table.sort(plan, function(a, b) return a[1] < b[1] end)

        local HOLD, ZOOM, WIDE = 90, 180, 210 -- 1.5 s + 3 s + 3.5 s = 8 s
        local i = 1
        for t = 0, HOLD + ZOOM + WIDE - 1 do
          if t == HOLD then cam:move({ panX = panX, panY = panY, zoom = 1, frames = ZOOM }) end
          while plan[i] and plan[i][1] <= t do
            local job = plan[i]
            local ok, res = pcall(job[3])
            say(("t=%d %s"):format(t, job[2]), ok and res)
            i = i + 1
            -- a water / tree spot is picked at random and may miss: try again in a moment
            local tries = job[4] or 10
            if not (ok and res) and tries > 0 then
              local again = { t + 3, job[2], job[3], tries - 1 }
              local k = i
              while plan[k] and plan[k][1] <= again[1] do k = k + 1 end
              table.insert(plan, k, again)
            end
          end
          ctx.frame()
        end
        cam:still()
        print(("[showcase] everything: %d frames in %.1f s of real time"):format(HOLD + ZOOM + WIDE,
          love.timer.getTime() - t0))
      end,
    },
  }
end
