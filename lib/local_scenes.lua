-- Local Scenes (the Local Scenes option): little moments tied to one place, ambient, never
-- met or fought, nothing saved.
--
--   Lavender Town   -- a ghost (Gastly, now and then Haunter) fades in at the edge of the
--                      view, drifts across it -- through walls and over roofs -- dark and
--                      see-through, and fades out. Tell the girl who asks whether you believe
--                      in ghosts "No" and, 1 time in 4, a Gengar fades in two steps behind you
--                      (past your follower) and stays until she has finished talking.
--   Petalburg Woods -- Burmy is lowered on a silk thread from under a tree's crown, hangs a
--                      while and is reeled back up; Silcoon / Cascoon dangle the same way,
--                      spinning slowly; Slakoth naps on a tree top, "z"s floating up; and,
--                      rarely, Vigoroth leaps in onto a tree top from off screen, dances, and
--                      leaps away.
--   Fortree City    -- rarely, a big Tropius rises slowly out of the trees, walks a few steps
--                      over them, and sinks back under.
--
-- A place has "occasional" scenes (one about every 30 s) and "rare" ones (about every 2 min),
-- Config.LOCAL_SCENES; at most one of each cadence at a time. A new scene only starts while
-- the field is free and only in view. Tree tops come from lib/perch_spots.lua (the map's own
-- upper-layer cells). Drawn as plain field actors: a bug on its thread under the crown's
-- upper layer (the crown hides it until it comes down below it), anything on a tree top or a
-- drifting ghost over it. Sprites by national dex, so species the game itself does not have
-- (Burmy) are fine.
local V = ...
local Config = V.require("config")
local EnginePatch = V.require("engine_patch")
local SpriteSource = V.require("sprite_source")
local RendererFactory = V.require("renderer_factory")
local ActorRenderer = V.require("actor_renderer")
local FlightPath = V.require("flight_path")
local PerchSpots = V.require("perch_spots")
local RecallMath = V.require("recall_math")
local WildEmote = V.require("wild_emote")

local LocalScenes = {}
LocalScenes.__index = LocalScenes

-- the scenes of each place, by map id without its game prefix (EM_ / RU_ / SA_ / FR_ / LG_)
local PLACES = {
  LAVENDER_TOWN = { occasional = { "ghost" } },
  PETALBURG_WOODS = { occasional = { "burmy", "cocoon", "sleeper" }, rare = { "dancer" }, trees = true },
  FORTREE_CITY = { rare = { "tropius" }, trees = true },
}
LocalScenes.PLACES = PLACES
local RETRY = 120 -- ticks before trying again when a scene found no place to happen

local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

--- The place `mapId` is ("LAVENDER_TOWN" ...), without its game's prefix. Pure (tested).
function LocalScenes.placeName(mapId)
  if type(mapId) ~= "string" then return nil end
  return (mapId:gsub("^%u%u_", "", 1))
end

--- The scenes of `mapId`'s place, or nil.
function LocalScenes.placeOf(mapId)
  local name = LocalScenes.placeName(mapId)
  return name and PLACES[name] or nil
end

--- How visible a scene `t` ticks into `n` is when it fades in and out over `fade` ticks
--- (0..1). Pure (tested).
function LocalScenes.fade(t, n, fade)
  if fade <= 0 then return 1 end
  return math.max(0, math.min(1, t / fade, (n - t) / fade))
end

--- A bug on its thread `t` ticks in: how far below the tree's bottom edge it hangs (px),
--- its sideways swing and how visible it is. `c` = { drop, down, stay, up, top (px: where it
--- starts, up among the leaves; default HANG_START) }; cfg = its Config.LOCAL_SCENES.hang
--- row. It slides out of the leaves fading in, and back up into them fading out. Pure (tested).
local HANG_START = -12
function LocalScenes.hangState(c, cfg, t)
  local top = c.top or HANG_START
  local dy, dx, alpha = c.drop, 0, 1
  if t < c.down then
    local e = RecallMath.ease(t / c.down)
    dy = top + (c.drop - top) * e
    alpha = math.min(1, e / 0.5)
  elseif t < c.down + c.stay then
    local k = t - c.down
    local ramp = math.min(1, k / 60, (c.stay - k) / 60) -- the swing settles in and out
    dx = math.sin(k / cfg.swayTicks * math.pi * 2) * cfg.sway * ramp
    dy = c.drop + math.abs(math.sin(k / cfg.swayTicks * math.pi * 2)) * ramp -- a pendulum lifts at its ends
  else
    local e = RecallMath.ease(math.min(1, (t - c.down - c.stay) / c.up))
    dy = c.drop + (top - c.drop) * e
    alpha = math.min(1, (1 - e) / 0.5)
  end
  return dy, dx, alpha
end

--- `deps` (all optional, for tests): rng(a, b), viewSize(), playerCell(), fieldFree(),
--- perches() (-> a PerchSpots for the current map).
function LocalScenes.new(mod, deps)
  deps = deps or {}
  return setmetatable({
    mod = mod, rng = deps.rng or math.random,
    viewSize = deps.viewSize or function()
      if EnginePatch.viewSize then return EnginePatch.viewSize() end
      return 240, 160
    end,
    playerCell = deps.playerCell or function() return EnginePatch.playerCell and EnginePatch.playerCell() or nil end,
    fieldFree = deps.fieldFree or function()
      if EnginePatch.fieldBusy and EnginePatch.fieldBusy() then return false end
      if EnginePatch.battleActive and EnginePatch.battleActive() then return false end
      return true
    end,
    buildPerches = deps.perches or function() return PerchSpots.build() end,
    scenes = {}, nextId = 1, timers = {}, taken = {},
  }, LocalScenes)
end

local function between(rng, r) return rng(r[1], r[2]) end

function LocalScenes:clear()
  self.scenes, self.taken = {}, {}
end

function LocalScenes:onMapEntered(mapId)
  self:clear()
  self.mapId = mapId
  self.place = Config.localScenes(self.mod) and LocalScenes.placeOf(mapId) or nil
  self.perches = nil
  self.timers = {}
  if not self.place then return end
  if self.place.trees then self.perches = self.buildPerches() end
  local every = Config.LOCAL_SCENES.every
  for cadence in pairs(every) do
    if self.place[cadence] then self.timers[cadence] = math.floor(between(self.rng, every[cadence]) / 3) end
  end
end

function LocalScenes:onMapExited()
  self:clear()
  self.place, self.perches, self.timers = nil, nil, {}
end

function LocalScenes:onOptionChanged(mapId)
  if Config.localScenes(self.mod) then self:onMapEntered(mapId or self.mapId) else self:onMapExited() end
end

--- How many scenes of `cadence` (nil = all) are playing.
function LocalScenes:count(cadence)
  local n = 0
  for _, c in ipairs(self.scenes) do if not cadence or c.cadence == cadence then n = n + 1 end end
  return n
end

function LocalScenes:_renderer(dex)
  local r = RendererFactory.new(self.mod, dex, false, Config.spriteStyle(self.mod), SpriteSource.PRESENTATION_LAND)
  if r and r.isPmd then r.swimming = false end
  return r
end

function LocalScenes:_add(c)
  c.id, c.t, c.alpha = self.nextId, 0, c.alpha or 1
  self.nextId = self.nextId + 1
  self.scenes[#self.scenes + 1] = c
  return c
end

-- the cells in view (with `margin` tiles kept inside each edge): x0, y0, x1, y1, or nil
function LocalScenes:_viewCells(margin)
  local cam = self.cam
  if not cam then return nil end
  local vw, vh = self.viewSize()
  local x0, y0 = math.ceil(cam.x / 16) + margin, math.ceil(cam.y / 16) + margin
  local x1, y1 = math.floor((cam.x + vw) / 16) - 1 - margin, math.floor((cam.y + vh) / 16) - 1 - margin
  if x1 < x0 or y1 < y0 then return nil end
  return x0, y0, x1, y1
end

-- a free tree-top spot in view, away from the player, passing `accept`
function LocalScenes:_treeSpot(accept, margin)
  if not self.perches then return nil end
  local x0, y0, x1, y1 = self:_viewCells(margin or 1)
  if not x0 then return nil end
  local p = self.playerCell()
  local minD = Config.LOCAL_SCENES.minPlayerDist
  return self.perches:pick(function(s)
    if s.kind ~= "canopy" or s.x < x0 or s.x > x1 or s.y < y0 or s.y > y1 then return false end
    if p and math.max(math.abs(p.x - s.x), math.abs(p.y - s.y)) <= minD then return false end
    return not accept or accept(s)
  end, self.taken, 60, self.rng)
end

-- a tree top with crown on both sides (not a crown's rounded edge by a path)
function LocalScenes:_inCrown()
  local perches = self.perches
  return function(s)
    local l, r = perches:at(s.x - 1, s.y), perches:at(s.x + 1, s.y)
    return l ~= nil and r ~= nil and l.kind == "canopy" and r.kind == "canopy"
  end
end

-- ------- Lavender Town ---------------------------------------------------------------

function LocalScenes:_startGhost()
  local cfg, rng = Config.LOCAL_SCENES.ghost, self.rng
  local x0, y0, x1, y1 = self:_viewCells(1)
  if not x0 then return false end
  local r = self:_renderer(cfg.species[rng(1, #cfg.species)])
  if not r then return false end
  r.shade = cfg.shade
  -- where it appears: anywhere in view (walls and roofs too), not right by the player
  local p = self.playerCell()
  local minD = Config.LOCAL_SCENES.minPlayerDist + 1
  local cx, cy
  for _ = 1, 30 do
    local x, y = rng(x0, x1), rng(y0, y1)
    if not (p and math.max(math.abs(p.x - x), math.abs(p.y - y)) <= minD) then cx, cy = x, y break end
  end
  if not cx then return false end
  local function at(x, y) return { x = x * 16, y = y * 16 } end
  local phases = { { type = "sit", at = at(cx, cy), n = cfg.fade, fidget = { 1e9, 1e9 } } }
  local dirs = { "up", "down", "left", "right" }
  for _ = 1, between(rng, cfg.moves) do
    local d = DELTA[dirs[rng(1, 4)]]
    local len = between(rng, cfg.step)
    local nx = math.max(x0, math.min(x1, cx + d[1] * len))
    local ny = math.max(y0, math.min(y1, cy + d[2] * len))
    local cells = math.abs(nx - cx) + math.abs(ny - cy)
    if cells > 0 then
      phases[#phases + 1] = { type = "fly", from = at(cx, cy), to = at(nx, ny), n = cells * cfg.stepTicks }
      cx, cy = nx, ny
    end
    phases[#phases + 1] = { type = "sit", at = at(cx, cy), n = between(rng, cfg.pause), fidget = { 1e9, 1e9 } }
  end
  phases[#phases + 1] = { type = "sit", at = at(cx, cy), n = cfg.fade, fidget = { 1e9, 1e9 } }
  local n = 0
  for _, ph in ipairs(phases) do n = n + ph.n end
  local first = phases[1].at
  self:_add({ kind = "ghost", cadence = "occasional", renderer = r, over = true, n = n, alpha = 0,
              x = first.x, y = first.y, facing = "down", plan = FlightPath.plan(phases, rng) })
  return true
end

function LocalScenes:_tickGhost(c)
  local cfg = Config.LOCAL_SCENES.ghost
  local s = FlightPath.step(c.plan)
  if not s then return false end
  c.x, c.y, c.facing = s.x, s.y, s.facing
  c.alpha = cfg.alpha * LocalScenes.fade(c.t, c.n, cfg.fade)
  c.act = { dy = math.floor(math.sin(c.t / 24) * 2 - 2) } -- a slow bob
  self:_animate(c, s.flapping == true)
  return c.t < c.n
end

--- Open ground for Gengar to stand on: walkable, nothing drawn over it (not a roof), no object.
local function openGround(x, y)
  if EnginePatch.isWall and EnginePatch.isWall(x, y) then return false end
  if EnginePatch.coversActors and EnginePatch.coversActors(x, y) == true then return false end
  return not (EnginePatch.objectOn and EnginePatch.objectOn(x, y))
end

--- Where Gengar appears behind a player on (px, py) facing along `d`: `behind` cells back
--- (past a follower) when that is open ground, else the open cell nearest to it within two
--- cells (never the player's own cell, the follower's just behind, or the one in front); nil
--- when there is none. Pure over EnginePatch (tested).
function LocalScenes.behindCell(px, py, d, behind)
  local ix, iy = px - d[1] * behind, py - d[2] * behind
  local best, bestD
  for dy = -2, 2 do
    for dx = -2, 2 do
      local x, y = ix + dx, iy + dy
      local reserved = (x == px and y == py) or (x == px - d[1] and y == py - d[2]) or (x == px + d[1] and y == py + d[2])
      if not reserved and openGround(x, y) then
        -- nearest the ideal spot first; on a tie, the one further behind
        local dist = dx * dx + dy * dy - 0.1 * ((x - px) * -d[1] + (y - py) * -d[2])
        if not bestD or dist < bestD then best, bestD = { x, y }, dist end
      end
    end
  end
  if best then return best[1], best[2] end
  return nil
end

--- The girl in Lavender Town who asks about ghosts was told "No" (her reply's text key
--- `textKey`, from main.lua's script.command hook): 1 time in 4 a Gengar appears behind
--- the player. `force` (tests, drivers) skips the roll. Returns true when it appeared.
function LocalScenes:onScriptText(textKey, force)
  local cfg = Config.LOCAL_SCENES.gengar
  if not (textKey and cfg.noText[textKey]) then return false end
  if LocalScenes.placeName(self.mapId) ~= "LAVENDER_TOWN" or not Config.localScenes(self.mod) then return false end
  if not force and self.rng(1, 100) > cfg.chance then return false end
  for _, c in ipairs(self.scenes) do if c.kind == "gengar" then return false end end
  local p = self.playerCell()
  local d = p and DELTA[p.facing or "down"]
  if not d then return false end
  local r = self:_renderer(cfg.species)
  if not r then return false end
  local cx, cy = LocalScenes.behindCell(p.x, p.y, d, cfg.behind)
  if not cx then return false end
  local c = self:_add({ kind = "gengar", renderer = r, x = cx * 16, y = cy * 16, cx = cx, cy = cy,
                        facing = p.facing or "down", alpha = 0, freeFor = 0 })
  c.n = math.huge
  return true
end

--- A script finished (the `script.ended` event): a Gengar behind the player fades away.
function LocalScenes:onScriptEnded()
  for _, c in ipairs(self.scenes) do
    if c.kind == "gengar" and not c.leaving then c.leaving = 0 end
  end
end

function LocalScenes:_tickGengar(c)
  local cfg = Config.LOCAL_SCENES.gengar
  if c.leaving then
    c.leaving = c.leaving + 1
    c.alpha = cfg.alpha * math.max(0, 1 - c.leaving / cfg.fade)
    self:_animate(c, false)
    return c.leaving < cfg.fade
  end
  c.alpha = cfg.alpha * math.min(1, c.t / cfg.fade)
  -- backstop: the talk is over (field free a while) though no script.ended came
  if self.fieldFree() then c.freeFor = c.freeFor + 1 else c.freeFor = 0 end
  if c.freeFor >= cfg.linger then c.leaving = 0 end
  self:_animate(c, false)
  return true
end

-- ------- Petalburg Woods: bugs on silk threads ---------------------------------------

--- Is (x, y) the bottom cell of a tree, over open ground: a wall drawn in the map's lower
--- layer (a Gen 3 tree's lower leaves; the crown above it is drawn over actors), more tree
--- above it, a free walkable cell below it. Pure over EnginePatch (tested).
function LocalScenes.treeEdge(x, y)
  local wall, covers = EnginePatch.isWall, EnginePatch.coversActors
  if not (wall and covers) then return false end
  if not wall(x, y) or covers(x, y) == true then return false end
  if not (wall(x, y - 1) or covers(x, y - 1) == true) then return false end
  if wall(x, y + 1) or covers(x, y + 1) == true then return false end
  return not (EnginePatch.objectOn and EnginePatch.objectOn(x, y + 1))
end

--- A tree's bottom edge in view that a bug can be lowered from (nothing hanging there yet,
--- away from the player), or nil.
function LocalScenes:_hangSpot()
  local x0, y0, x1, y1 = self:_viewCells(1)
  if not x0 then return nil end
  local p = self.playerCell()
  local minD = Config.LOCAL_SCENES.minPlayerDist
  local options = {}
  for y = y0, y1 - 2 do -- room below it to hang into
    for x = x0, x1 do
      local free = not (p and math.max(math.abs(p.x - x), math.abs(p.y - y - 1)) <= minD)
      for _, c in ipairs(self.scenes) do
        if c.spot and math.abs(c.spot.x - x) <= 1 and math.abs(c.spot.y - y) <= 1 then free = false end
      end
      if free and LocalScenes.treeEdge(x, y) then options[#options + 1] = { x = x, y = y, lift = 0, kind = "edge" } end
    end
  end
  if #options == 0 then return nil end
  return options[self.rng(1, #options)]
end

function LocalScenes:_startHang(kind)
  local cfg, rng = Config.LOCAL_SCENES.hang[kind], self.rng
  local spot = self:_hangSpot()
  if not spot then return false end
  local r = self:_renderer(cfg.species[rng(1, #cfg.species)])
  if not r then return false end
  local head = ((r.headLift and r:headLift()) or 16) * (cfg.scale or 1)
  local c = self:_add({ kind = kind, cadence = "occasional", renderer = r, spot = spot,
                        x = spot.x * 16, y = spot.y * 16, facing = "down", alpha = 0,
                        top = -math.floor(head * 0.8), -- its body up among the leaves
                        drop = between(rng, cfg.drop), down = cfg.down, stay = between(rng, cfg.stay), up = cfg.up })
  c.n = c.down + c.stay + c.up
  return true
end

function LocalScenes:_tickHang(c)
  local cfg = Config.LOCAL_SCENES.hang[c.kind]
  local dy, dx, alpha = LocalScenes.hangState(c, cfg, c.t)
  c.act, c.alpha = { dx = dx, dy = dy, scale = cfg.scale }, alpha
  local r = c.renderer
  local hanging = c.t >= c.down and c.t < c.down + c.stay
  if r.isPmd then
    if c.kind == "cocoon" and hanging then r:advanceAs("rotate", 0.5, "idle") else r:advance(false) end
  else
    c.pose = ActorRenderer.POSE_STAND
  end
  return c.t < c.n
end

-- the silk thread: from up in the crown down to the bug's head
local function threadActor(c)
  local r = c.renderer
  local head = ((r.headLift and r:headLift()) or 16) * (Config.LOCAL_SCENES.hang[c.kind].scale or 1)
  local x = c.spot.x * 16 + 8 + math.floor((c.act and c.act.dx or 0) + 0.5)
  local top = c.spot.y * 16 - 14 -- up in the leaves, where it fades out
  local bottom = c.spot.y * 16 + 16 + math.floor((c.act and c.act.dy or 0) + 0.5) - math.floor(head * 0.85)
  return {
    kind = "ow_silk", x = x, y = c.spot.y * 16, sortY = c.spot.y * 16 - 1, elevation = 3, i = 98500 + c.id,
    draw = function(_, camX, camY)
      if not (love and love.graphics and love.graphics.rectangle) or bottom <= top then return end
      local g = love.graphics
      local r0, g0, b0, a0 = g.getColor()
      -- fading into the leaves: unseen at its top, solid from the tree's bottom edge down
      local a = 0.75 * math.min(1, (c.alpha or 1) * 2)
      local sx = math.floor(x - camX)
      local edge = math.min(bottom, c.spot.y * 16 + 16)
      local span = math.max(1, edge - top)
      for yy = top, edge - 1 do
        g.setColor(0.92, 0.92, 0.96, a * ((yy - top + 1) / span) ^ 1.5)
        g.rectangle("fill", sx, math.floor(yy - camY), 1, 1)
      end
      if bottom > edge then
        g.setColor(0.92, 0.92, 0.96, a)
        g.rectangle("fill", sx, math.floor(edge - camY), 1, bottom - edge)
      end
      g.setColor(r0, g0, b0, a0)
    end,
  }
end

-- ------- Petalburg Woods: Slakoth asleep on a tree top --------------------------------

function LocalScenes:_startSleeper()
  local cfg = Config.LOCAL_SCENES.sleeper
  local spot = self:_treeSpot(self:_inCrown(), 1)
  if not spot then return false end
  local r = self:_renderer(cfg.species)
  if not r then return false end
  local c = self:_add({ kind = "sleeper", cadence = "occasional", renderer = r, spot = spot, over = true,
                        x = spot.x * 16, y = spot.y * 16, facing = "down", n = between(self.rng, cfg.ticks), alpha = 0 })
  self.taken[spot] = c
  return true
end

function LocalScenes:_tickSleeper(c)
  local cfg = Config.LOCAL_SCENES.sleeper
  c.alpha = LocalScenes.fade(c.t, c.n, cfg.fade)
  c.act = { dy = -c.spot.lift, scale = cfg.scale }
  local r = c.renderer
  if r.isPmd then r:advanceAs("sleep", 1, "idle") else c.pose = ActorRenderer.POSE_STAND end
  return c.t < c.n
end

-- how far above the tile's ground line a sleeper's head is (its Sleep pose lies low)
local function sleeperHead(r)
  if r.isPmd and r.info and r.info.sleep then return r:headLift({ "sleep" }) end
  return (r.headLift and r:headLift() or 16) * 0.7
end

-- ------- Petalburg Woods: Vigoroth dancing on a tree top -----------------------------

local function danceTicks(r, cfg)
  local d = r.isPmd and r.info and r.info.dance and r.info.dance.durations
  if not d then return cfg.hgssTicks end
  local sum = 0
  for _, v in ipairs(d) do sum = sum + v end
  return sum * cfg.loops
end
LocalScenes._danceTicks = danceTicks

function LocalScenes:_startDancer()
  local cfg, rng = Config.LOCAL_SCENES.dancer, self.rng
  local spot = self:_treeSpot(self:_inCrown(), 2)
  if not spot or not self.cam then return false end
  local r = self:_renderer(cfg.species)
  if not r then return false end
  local vw = self.viewSize()
  local fromLeft = rng(0, 1) == 0
  local leftX, rightX = self.cam.x - 40, self.cam.x + vw + 24
  local sx, ex = fromLeft and leftX or rightX, fromLeft and rightX or leftX
  local y = spot.y * 16
  local at = { x = spot.x * 16, y = y, lift = spot.lift }
  local dance = danceTicks(r, cfg)
  local plan = FlightPath.plan({
    { type = "hop", from = { x = sx, y = y - 24, lift = 0 }, to = at, n = cfg.leapTicks, height = cfg.leapHeight },
    { type = "sit", at = at, n = dance, fidget = { 1e9, 1e9 }, facing = "down", event = "dance" },
    { type = "hop", from = at, to = { x = ex, y = y - 24, lift = 0 }, n = cfg.leapTicks, height = cfg.leapHeight },
  }, rng)
  local c = self:_add({ kind = "dancer", cadence = "rare", renderer = r, spot = spot, over = true,
                        x = sx, y = y - 24, facing = fromLeft and "right" or "left", plan = plan, dance = dance, danceT = 0 })
  c.n = cfg.leapTicks * 2 + dance
  self.taken[spot] = c
  return true
end

function LocalScenes:_tickDancer(c)
  local s = FlightPath.step(c.plan)
  if not s then return false end
  c.x, c.y, c.facing = s.x, s.y, s.facing
  local r = c.renderer
  c.act = { dy = -((s.lift or 0) + (s.hop or 0)) }
  if s.sitting then
    if r.isPmd then
      r:advanceAs("dance", 1, "idle")
      c.facing = "down"
    else
      -- no dance art: turning this way and that with a little hop on each beat
      local beat = math.floor(c.danceT / 12)
      c.facing = ({ "left", "down", "right", "down" })[beat % 4 + 1]
      local k = c.danceT % 12
      c.act.dy = c.act.dy - (k < 6 and math.sin(k / 6 * math.pi) * 3 or 0)
      c.pose = ActorRenderer.POSE_STAND
    end
    c.danceT = (c.danceT or 0) + 1
  else
    c.danceT = 0
    self:_animate(c, true)
  end
  return true
end

-- ------- Fortree City: Tropius over the trees ----------------------------------------

--- A tree top deep enough in the trees for Tropius (drawn big, its top half rising above its
--- cell): tree tops all round it and two rows up, so it never hangs over a path, a bridge or
--- the edge of the trees. Pure over PerchSpots (tested).
function LocalScenes.deepCanopy(perches, x, y)
  for dy = -2, 1 do
    for dx = -1, 1 do
      local o = perches:at(x + dx, y + dy)
      if not (o and o.kind == "canopy") then return false end
    end
  end
  return true
end

function LocalScenes:_startTropius()
  local cfg, rng = Config.LOCAL_SCENES.tropius, self.rng
  local perches = self.perches
  -- deep in the trees, with more such tree tops round it to walk on
  local spot = self:_treeSpot(function(s)
    if not LocalScenes.deepCanopy(perches, s.x, s.y) then return false end
    local n = 0
    for _, d in pairs(DELTA) do
      if LocalScenes.deepCanopy(perches, s.x + d[1], s.y + d[2]) then n = n + 1 end
    end
    return n >= 1
  end, 2)
  if not spot then return false end
  local r = self:_renderer(cfg.species)
  if not r then return false end
  -- its walk: a few steps from tree top to tree top, never back on itself
  local x0, y0, x1, y1 = self:_viewCells(1)
  local cells, seen = { spot }, { [spot] = true }
  for _ = 1, between(rng, cfg.steps) do
    local cur, options = cells[#cells], {}
    for _, d in pairs(DELTA) do
      local o = perches:at(cur.x + d[1], cur.y + d[2])
      if o and LocalScenes.deepCanopy(perches, o.x, o.y) and not seen[o] and not self.taken[o]
        and o.x >= x0 and o.x <= x1 and o.y >= y0 and o.y <= y1 then options[#options + 1] = o end
    end
    if #options == 0 then break end
    table.sort(options, function(a, b) return a.y * 4096 + a.x < b.y * 4096 + b.x end)
    local nx = options[rng(1, #options)]
    seen[nx] = true
    cells[#cells + 1] = nx
  end
  local function at(s) return { x = s.x * 16, y = s.y * 16, lift = s.lift } end
  local phases = { { type = "rise", at = at(spot), n = cfg.rise } }
  for i = 2, #cells do
    phases[#phases + 1] = { type = "sit", at = at(cells[i - 1]), n = between(rng, cfg.rest), fidget = { 1e9, 1e9 } }
    phases[#phases + 1] = { type = "fly", from = at(cells[i - 1]), to = at(cells[i]), n = cfg.stepTicks }
  end
  phases[#phases + 1] = { type = "sit", at = at(cells[#cells]), n = between(rng, cfg.rest), fidget = { 1e9, 1e9 } }
  phases[#phases + 1] = { type = "sink", at = at(cells[#cells]), n = cfg.rise }
  local n = 0
  for _, ph in ipairs(phases) do n = n + ph.n end
  local c = self:_add({ kind = "tropius", cadence = "rare", renderer = r, over = true, x = spot.x * 16, y = spot.y * 16,
                        facing = "down", plan = FlightPath.plan(phases, rng), cells = cells, n = n })
  for _, s in ipairs(cells) do self.taken[s] = c end
  return true
end

--- How much of Tropius shows above the trees (its `act.reveal`): `head` (its top half) while
--- it walks, eased
--- up from nothing as it rises and back down as it sinks (`sink` 1 = all under). Pure (tested).
function LocalScenes.tropiusReveal(sink, head)
  return head * (1 - math.max(0, math.min(1, sink or 0)))
end

function LocalScenes:_tickTropius(c)
  local cfg = Config.LOCAL_SCENES.tropius
  local s = FlightPath.step(c.plan)
  if not s then return false end
  c.x, c.y, c.facing = s.x, s.y, s.facing
  -- a rise / sink phase carries no lift of its own: it stands on the tree tops all along
  local lift = s.lift ~= 0 and s.lift or (c.cells[1].lift or 0)
  local r = c.renderer
  local south = r.isPmd and (c.facing or "down") == "down"
  local reveal = LocalScenes.tropiusReveal(s.sink, south and cfg.southHalf or cfg.half)
  c.act = { dy = -lift, reveal = reveal, scale = cfg.scale }
  c.hidden = reveal <= 0.01
  local stirring = s.flapping == true or ((s.sink or 0) > 0 and (s.sink or 0) < 1)
  if r.isPmd then
    -- only its Idle frames with the wings all the way down, walking too (Walk spreads them)
    local d = r.info and r.info.idle and r.info.idle.durations
    if d then
      local frame = cfg.wingsDown[math.floor(c.t / cfg.poseTicks) % #cfg.wingsDown + 1]
      local start = 0
      for i = 1, math.min(frame, #d) do start = start + d[i] end
      r.anim, r.clock, r.idleHold = "idle", start + 0.5, 0
    end
  else
    self:_animate(c, s.flapping == true)
  end
  -- the leaves round its neck: they stir and throw bits of leaf while it moves
  c.stir = stirring and math.min(1, (c.stir or 0) + 0.1) or math.max(0, (c.stir or 0) - 0.05)
  c.bits = c.bits or {}
  if stirring and c.t % 4 == 0 then
    local rng = self.rng
    c.bits[#c.bits + 1] = { x = rng(-9, 9), y = 0, vx = rng(-6, 6) / 10, vy = -rng(8, 16) / 10, age = 0 }
  end
  local keep = {}
  for _, b in ipairs(c.bits) do
    b.age, b.x, b.y, b.vy = b.age + 1, b.x + b.vx, b.y + b.vy, b.vy + 0.12
    if b.age < 26 then keep[#keep + 1] = b end
  end
  c.bits = keep
  return true
end

-- leaf colours of a tree top: dark, mid, light
local LEAF = { { 0.16, 0.36, 0.14 }, { 0.30, 0.56, 0.22 }, { 0.56, 0.78, 0.32 } }

-- the leaves round Tropius's neck where it comes up through the trees, and the bits of leaf
-- it stirs up, drawn over it
local function leavesActor(c)
  local r, cfg = c.renderer, Config.LOCAL_SCENES.tropius
  local groundY = r.isPmd and (Config.PMD_GROUND_Y or 12) or 16
  local cx = c.x + 8
  local cy = c.y + groundY + math.floor(((c.act and c.act.dy) or 0) + 0.5)
  local hd = (r.hdScale and r:hdScale()) or 1
  local half = math.floor(10 * (cfg.scale or 1) * hd * 0.8) + 2
  local wob = (c.stir or 0) * math.sin(c.t / 3)
  local bits = c.bits or {}
  -- it grows with the head coming up, and is gone with it
  local show = math.min(1, ((c.act and c.act.reveal) or 0) / 0.3)
  local span = math.floor(half * show + 0.5)
  return {
    kind = "ow_leaves", x = cx, y = c.y, sortY = c.y + 0.5, elevation = 3, oamPriority = 1, i = 98800 + c.id,
    draw = function(_, camX, camY)
      if not (love and love.graphics and love.graphics.rectangle) then return end
      local g = love.graphics
      local r0, g0, b0, a0 = g.getColor()
      local bx, by = math.floor(cx - camX), math.floor(cy - camY)
      if span <= 0 and #bits == 0 then return end
      -- a mound of leaves pushed up round its neck: highest in the middle, a dark edge on
      -- top, a light speckle, swaying while it moves
      for i = -span, span do
        local k = math.abs(i) / math.max(1, span)
        local h = math.floor((1 - k * k) * 2 + 1 + ((i * 7 + 3) % 3) * 0.5)
        local sway = math.floor(wob * (1 - k) + 0.5)
        local x, top = bx + i + sway, by - h
        g.setColor(LEAF[1][1], LEAF[1][2], LEAF[1][3], 1)
        g.rectangle("fill", x, top, 1, 1)
        g.setColor(LEAF[2][1], LEAF[2][2], LEAF[2][3], 1)
        g.rectangle("fill", x, top + 1, 1, h + 1)
        if (i * 5 + 1) % 4 == 0 then
          g.setColor(LEAF[3][1], LEAF[3][2], LEAF[3][3], 1)
          g.rectangle("fill", x, top + 1 + ((i * 3) % 2), 1, 1)
        end
      end
      for k, b in ipairs(bits) do
        local col = LEAF[(k % 2) + 2]
        g.setColor(col[1], col[2], col[3], math.max(0, 1 - b.age / 26))
        g.rectangle("fill", math.floor(bx + b.x + 0.5), math.floor(by - 2 + b.y + 0.5), 2, 1)
      end
      g.setColor(r0, g0, b0, a0)
    end,
  }
end

-- ------- common ----------------------------------------------------------------------

-- the walk / idle loop (PMD) or the A / B walk poses (HGSS)
function LocalScenes:_animate(c, moving)
  local r = c.renderer
  c.walkClock = (c.walkClock or 0) + 1
  if r.isPmd then
    r:advance(moving)
  elseif moving then
    c.pose = (math.floor(c.walkClock / 10) % 2 == 0) and ActorRenderer.POSE_WALK_A or ActorRenderer.POSE_WALK_B
  else
    c.pose = ActorRenderer.POSE_STAND
  end
end

local STARTERS = {
  ghost = LocalScenes._startGhost,
  burmy = function(self) return self:_startHang("burmy") end,
  cocoon = function(self) return self:_startHang("cocoon") end,
  sleeper = LocalScenes._startSleeper,
  dancer = LocalScenes._startDancer,
  tropius = LocalScenes._startTropius,
}
local TICKERS = {
  ghost = LocalScenes._tickGhost, gengar = LocalScenes._tickGengar,
  burmy = LocalScenes._tickHang, cocoon = LocalScenes._tickHang,
  sleeper = LocalScenes._tickSleeper, dancer = LocalScenes._tickDancer, tropius = LocalScenes._tickTropius,
}

--- Starts scene `kind` now (tests, drivers); true when it found a place to happen.
function LocalScenes:start(kind)
  local f = STARTERS[kind]
  return f ~= nil and f(self) == true
end

--- One tick: new scenes on their timers, every one a step on.
function LocalScenes:tick()
  if self.place and self.cam then
    local every = Config.LOCAL_SCENES.every
    for cadence, t in pairs(self.timers) do
      t = t - 1
      if t <= 0 then
        t = between(self.rng, every[cadence])
        if self:count(cadence) > 0 or not self.fieldFree() then
          t = RETRY
        else
          local kinds = self.place[cadence]
          if not self:start(kinds[self.rng(1, #kinds)]) then t = RETRY end
        end
      end
      self.timers[cadence] = t
    end
  end
  local keep = {}
  for _, c in ipairs(self.scenes) do
    c.t = c.t + 1
    local tickFn = TICKERS[c.kind]
    if tickFn and tickFn(self, c) then
      keep[#keep + 1] = c
    else
      if c.spot then self.taken[c.spot] = nil end
      for _, s in ipairs(c.cells or {}) do self.taken[s] = nil end
    end
  end
  self.scenes = keep
end

local function spriteActor(c)
  local r, x, y, act = c.renderer, c.x, c.y, c.act
  local alpha = c.alpha
  return {
    kind = "ow_local_scene", x = x, y = y, sortY = y, elevation = 3,
    i = 98000 + c.id, oamPriority = c.over and 1 or nil, facing = c.facing, walkPhase = "stand",
    draw = function(_, camX, camY)
      local oldAct, oldAlpha = r.act, r.alpha
      r.act, r.alpha = act, alpha
      r:draw(x, y, camX, camY, c.facing or "down", c.pose or ActorRenderer.POSE_STAND)
      r.act, r.alpha = oldAct, oldAlpha
    end,
  }
end

--- Appends every scene's actors; remembers the camera for placing new ones.
function LocalScenes:collectActors(actors, camX, camY)
  if camX ~= nil and camY ~= nil then self.cam = { x = camX, y = camY } end
  for _, c in ipairs(self.scenes) do
    if not c.hidden and (c.alpha or 1) > 0.01 then
      if c.kind == "burmy" or c.kind == "cocoon" then actors[#actors + 1] = threadActor(c) end
      actors[#actors + 1] = spriteActor(c)
      if c.kind == "tropius" then actors[#actors + 1] = leavesActor(c) end
      if c.kind == "sleeper" and c.t > Config.LOCAL_SCENES.sleeper.fade then
        actors[#actors + 1] = WildEmote.zzzActor(c.t - Config.LOCAL_SCENES.sleeper.fade, c.x, c.y,
          sleeperHead(c.renderer) * (Config.LOCAL_SCENES.sleeper.scale or 1) + c.spot.lift, c.id, true, Config.LOCAL_SCENES.sleeper.zzzEvery, c.alpha)
      end
    end
  end
end

return LocalScenes
