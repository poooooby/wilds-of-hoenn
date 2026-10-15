-- Showcase director: plays a shot list for recording a trailer (POKEPORT_DRIVER).
-- Run it with showcase/run.sh. Each shot is staged (map, party, Pokemon, camera at its
-- start), then waits for you:
--   Page Down  roll the shot (again: go on to the next one once it is done)
--   Home       stage this shot again (a retake; also cuts a rolling shot short)
--   Page Up    back to the previous shot
-- The window title says where you are (READY / ROLLING / DONE); the footage itself
-- carries no text. Wild battles are switched off for the whole reel.
local U = require("tests.drivers.util")

local DIR = assert(os.getenv("SHOWCASE_DIR"), "SHOWCASE_DIR not set (use showcase/run.sh)")
local VERSION = os.getenv("POKEPORT_VERSION") or "emerald"
local Camera = dofile(DIR .. "/camera.lua")

local RETAKE = {} -- error value: Home pressed while rolling
-- testing the reel unattended: SHOWCASE_AUTO=<dir> rolls every shot by itself and saves a
-- frame every 90 while rolling (never needed for recording)
local AUTO = os.getenv("SHOWCASE_AUTO")
if AUTO == "" then AUTO = nil end
local AUTO_LAST = tonumber(os.getenv("SHOWCASE_LAST") or "")
local AUTO_EVERY = tonumber(os.getenv("SHOWCASE_AUTO_EVERY") or "") or 90

return function(game)
  for _ = 1, 900 do if game.phase == "boot" and game.boot then break end U.wait(1) end
  game:_handleBootAction({ action = "new_game", name = VERSION == "emerald" and "MAY" or "LEAF", gender = 1 })
  U.wait(240)
  local Map = require("src.core.game3.map")
  local MapIds = require("src.core.game3.map_ids")
  local Field = require("src.core.game3.field")
  local Message = require("src.ui.game3.message")
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Player = require("src.core.game3.player")
  local bit = require("bit")
  for _ = 1, 300 do if not Message.isOpen() then break end U.tap(game, "a") U.wait(2) end

  local loader = game.mods
  local woh = loader.exports.wilds_of_hoenn
  assert(woh and woh.spawnManager, "Wilds of Hoenn is not loaded")
  local EP = woh.enginePatch
  local sm, fa = woh.spawnManager, woh.followerAdapter
  local session = Runtime.getSession()
  local cam = Camera.new()
  -- 1x on any display: a driver run steps the game once per rendered frame, so the frame
  -- rate IS the game speed; the launcher asks for pacing (POKEPORT_DRIVER_PACED) and this
  -- pins it to 60 (the engine's own cap; "display" would follow a 144 Hz monitor)
  pcall(function() require("src.core.FrameCap").apply(60) end)

  -- ------- the reel's ground rules ---------------------------------------------
  local function option(k, v)
    loader.modOptions.wilds_of_hoenn = loader.modOptions.wilds_of_hoenn or {}
    loader.modOptions.wilds_of_hoenn[k] = v
    loader.events:emit("mod.options_changed", { mod = "wilds_of_hoenn", key = k, value = v })
  end
  for k, v in pairs({ sprite_style = os.getenv("SHOWCASE_STYLE") or "pmd", flyers = "full", water_life = true,
                      local_scenes = true, wild_reacts = true, classic_enc = false, species_sizes = true,
                      portraits = true, enabled = true, wild_silhouettes = "off", smooth_follow = true,
                      spawn_amount = "normal" }) do
    option(k, v)
  end
  -- no wild battles: touching or being caught by a wild Pokemon does nothing on camera
  local bt = woh.battleTrigger
  for _, m in ipairs({ "onPlayerStepped", "checkContact", "onChaserContact", "onPlayerBumped", "tick" }) do
    if type(bt[m]) == "function" then bt[m] = function() end end
  end
  -- Running Shoes from the start (hold B to run)
  Player.canDash = function() return true end

  -- ------- keys ----------------------------------------------------------------
  local KEYS = { pagedown = "next", home = "retake", pageup = "back" }
  local down, queue = {}, {}
  local function pollKeys()
    for key, action in pairs(KEYS) do
      local now = love.keyboard.isDown(key)
      if now and not down[key] then queue[#queue + 1] = action end
      down[key] = now
    end
  end
  local function takeKey()
    return table.remove(queue, 1)
  end

  local rolling = false
  local function title(s)
    if love.window and love.window.setTitle then love.window.setTitle("SHOWCASE  " .. s) end
    print("[showcase] " .. s)
  end

  -- ------- what a shot can use ---------------------------------------------------
  local ctx = { game = game, woh = woh, EP = EP, sm = sm, fa = fa, cam = cam, session = session,
                Player = Player, version = VERSION, U = U }

  --- Set one of Wilds' options for the reel (in memory only).
  ctx.option = option

  --- One frame: the camera moves, keys are read. Home while rolling: retake.
  local autoFrames, shotName = 0, ""
  function ctx.frame()
    pollKeys()
    if AUTO and rolling then
      autoFrames = autoFrames + 1
      if autoFrames % AUTO_EVERY == 0 and not game.capturePath then
        game.capturePath = ("%s/%s_%03d.png"):format(AUTO, shotName, math.floor(autoFrames / AUTO_EVERY))
      end
    end
    if rolling then
      for i = #queue, 1, -1 do
        if queue[i] == "retake" then queue = {} error(RETAKE, 0) end
        if queue[i] == "next" then table.remove(queue, i) end -- (no skipping mid-shot)
      end
    end
    cam:update()
    coroutine.yield()
  end

  function ctx.wait(n) for _ = 1, n or 1 do ctx.frame() end end

  --- Waits until `fn()` is true (at most `max` frames, 600).
  function ctx.waitUntil(fn, max)
    for _ = 1, max or 600 do
      local ok, v = pcall(fn)
      if ok and v then return true end
      ctx.frame()
    end
    return false
  end

  --- Hold a button (or a direction) for `frames`; `run` holds B too.
  function ctx.hold(btn, frames, run)
    for _ = 1, frames do
      table.insert(game.input.pressQueue, btn)
      game.input.state[btn] = true
      if run then game.input.state.b = true end
      ctx.frame()
    end
    game.input.state[btn] = false
    game.input.state.b = false
  end

  function ctx.tap(btn)
    table.insert(game.input.pressQueue, btn)
    ctx.frame()
    game.input.state[btn] = false
  end

  --- Walk (or run) `tiles` tiles toward `dir`.
  function ctx.walk(dir, tiles) ctx.hold(dir, 16 * (tiles or 1)) end
  function ctx.run(dir, tiles) ctx.hold(dir, 8 * (tiles or 1), true) end

  --- Turn to face `dir` without stepping (a short tap turns in place).
  function ctx.face(dir) ctx.hold(dir, 2) ctx.wait(8) end

  --- Load `mapConst` with the player on (x, y) facing `facing`.
  function ctx.go(mapConst, x, y, facing)
    Map.load(nil, game, MapIds.forConst(mapConst, VERSION), { x = x, y = y, facing = facing or "down" })
    session.x, session.y = x, y
    Field.unlock()
    ctx.wait(40)
  end

  --- The party: { {dex, level, shiny = bool, friendship = n, nick = s}, ... } (national dex).
  function ctx.party(list)
    session.party = {}
    local ids = EP.trainerIds and EP.trainerIds() or { otId = 0, otSecretId = 0 }
    for _, m in ipairs(list) do
      Party.giveMon(session, EP.speciesForNational(m[1]), m[2] or 30, m.nick or "MON")
      local mon = session.party[#session.party]
      if m.shiny then mon.personality = bit.lshift(bit.bxor(ids.otId or 0, ids.otSecretId or 0), 16) end
      if m.friendship then mon.friendship = m.friendship end
      if m.status then mon.status = m.status end
    end
    if fa.resetDisplay then fa:resetDisplay() end
  end

  --- Every wild Pokemon gone at once (no fx), and none coming back by themselves
  --- unless `refill` is true.
  function ctx.clearWild(refill)
    for id in pairs(sm.entities) do sm:despawn(id) end
    ctx.noRefill(not refill)
  end
  local realRefill = sm.refill
  function ctx.noRefill(on)
    sm.refill = on and function() end or realRefill
  end

  --- A wild Pokemon of national dex `dex` within `radius` tiles; returns its entity.
  function ctx.spawn(dex, level, opts)
    opts = opts or {}
    local before = {}
    for id in pairs(sm.entities) do before[id] = true end
    local ok = sm:spawnSpecies(EP.speciesForNational(dex), level or 10,
      { radius = opts.radius or 4, terrain = opts.terrain or "land" })
    if not ok then return nil end
    for id, e in pairs(sm.entities) do
      if not before[id] then
        if opts.shiny then e.shiny = true end
        return e
      end
    end
  end

  --- A walkable, non-grass, dry cell near (x, y) with at least `minGrass` encounter-grass
  --- cells within `r` tiles, nearest first: a path beside the grass for the camera.
  function ctx.pathBesideGrass(x, y, minGrass, r, search)
    r, search = r or 3, search or 14
    local best, bestD
    for yy = y - search, y + search do
      for xx = x - search, x + search do
        if EP.terrainAt(xx, yy) == nil and EP.cellFree(xx, yy) and not EP.isWater(xx, yy) then
          local n = 0
          for dy = -r, r do for dx = -r, r do
            if EP.terrainAt(xx + dx, yy + dy) == "land" then n = n + 1 end
          end end
          local d = math.abs(xx - x) + math.abs(yy - y)
          if n >= (minGrass or 8) and (not bestD or d < bestD) then best, bestD = { x = xx, y = yy }, d end
        end
      end
    end
    return best
  end

  --- World px centre of an entity / a cell.
  function ctx.centreOf(e) return (e.px or e.cellX * 16) + 8, (e.py or e.cellY * 16) + 8 end
  function ctx.cellCentre(x, y) return x * 16 + 8, y * 16 + 8 end

  --- Keep the partner facing `dir` while it stands (nil = let it be): the adapter clears
  --- its renderer's act every tick, so the facing is put back after each tick.
  function ctx.pinFollower(dir) ctx.pinnedFacing = dir end
  local realFaTick = fa.tick
  fa.tick = function(self, ...)
    local r = realFaTick(self, ...)
    if ctx.pinnedFacing and self.renderer and not self.action then
      self.renderer.act = { dx = 0, dy = 0, facing = ctx.pinnedFacing }
    end
    return r
  end

  --- Hide the map's people (a quiet set): every object event in view range of (x, y).
  function ctx.hidePeople()
    local Objects = require("src.core.game3.objects")
    local list = Objects.forDraw and Objects.forDraw() or {}
    for _, eo in ipairs(list) do
      local id = eo.localId or (eo.def and eo.def.localId)
      if id and Objects.hideObject then pcall(Objects.hideObject, id) end
    end
  end

  --- Close any open message / menu.
  function ctx.closeText()
    for _ = 1, 60 do
      if not Message.isOpen() then break end
      ctx.tap("b") ctx.wait(4)
    end
  end
  ctx.Message = Message

  -- ------- the reel ----------------------------------------------------------------
  local shots = dofile(DIR .. "/shots_" .. VERSION .. ".lua")(ctx)
  local i = math.max(1, math.min(#shots, tonumber(os.getenv("SHOWCASE_START") or "1") or 1))
  if os.getenv("SHOWCASE_ONLY") then
    for k, s in ipairs(shots) do if s.name == os.getenv("SHOWCASE_ONLY") then i = k end end
  end
  title(("%d shots loaded (%s)"):format(#shots, VERSION))

  local function stage(k)
    local s = shots[k]
    rolling = false
    queue = {}
    ctx.pinnedFacing = nil
    woh.waterLife._showcaseLoose, woh.skyFlyers._showcaseLoose = nil, nil
    ctx.closeText()
    ctx.noRefill(false)
    cam:reset()
    local ok, err = pcall(s.stage, ctx)
    if not ok then print("[showcase] stage error in " .. s.name .. ": " .. tostring(err)) end
    title(("%d/%d %s -- READY  (PgDn roll, Home restage, PgUp back)"):format(k, #shots, s.name))
  end

  local function awaitKey()
    if AUTO then
      for _ = 1, 30 do ctx.frame() end
      return "next"
    end
    while true do
      local a = takeKey()
      if a then return a end
      ctx.frame()
    end
  end

  stage(i)
  while true do
    local a = awaitKey()
    if a == "back" then
      i = math.max(1, i - 1) stage(i)
    elseif a == "retake" then
      stage(i)
    elseif a == "next" then
      local s = shots[i]
      title(("%d/%d %s -- ROLLING  (Home = cut, retake)"):format(i, #shots, s.name))
      rolling = true
      shotName, autoFrames = ("%02d_%s"):format(i, s.name), 0
      local ok, err = pcall(s.roll, ctx)
      rolling = false
      if not ok and err == RETAKE then
        stage(i)
      else
        if not ok then print("[showcase] roll error in " .. s.name .. ": " .. tostring(err)) end
        title(("%d/%d %s -- DONE  (PgDn next, Home retake, PgUp back)"):format(i, #shots, s.name))
        local b = awaitKey()
        if b == "retake" then stage(i)
        elseif b == "back" then i = math.max(1, i - 1) stage(i)
        elseif AUTO and AUTO_LAST and i >= AUTO_LAST then love.event.quit(0)
        elseif i < #shots then i = i + 1 stage(i)
        else
          title("THE END  (Home retake last, PgUp back)")
          if AUTO then love.event.quit(0) end
        end
      end
    end
  end
end
