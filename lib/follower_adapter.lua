-- Party follower sprite: the engine's own single-follower seam already
-- supports this with no patching. main.lua wires FOLLOWERS up via the
-- public `world.follower.spawn` hook (mod.hooks:wrap); this module only
-- answers "should one be visible right now" and keeps its sprite in sync
-- with the current party lead, reusing the same walker art as wild spawns.
--
-- Pose and presentation (walking/running A-B alternation, land/water art)
-- are computed HERE, every tick, and pushed onto the renderer via
-- `renderer.poseOverride`/`renderer.presentation` -- NOT via the draw()
-- call's own `walkPhase` argument. The engine builds that argument itself
-- fresh every frame (src/world/game3/Follower.lua's `actor()`: `walkPhase
-- = npc.moving and 1 or 0`), and its own stepFlip is hardcoded false for
-- every non-player actor (src/core/game3/field_view.lua), so neither A/B
-- alternation nor running can come from arguments the engine controls --
-- this module owns the follower's `npc` directly (EnginePatch.followerCurrent)
-- and tracks the real state itself. See lib/actor_renderer.lua's draw().
local V = ...
local Config = V.require("config")
local EnginePatch = V.require("engine_patch")
local ActorRenderer = V.require("actor_renderer")
local RendererFactory = V.require("renderer_factory")
local SpriteSource = V.require("sprite_source")
local FormSource = V.require("form_source")
local GrassCover = V.require("grass_cover")
local FollowerActions = V.require("follower_actions")
local EaveDuck = V.require("eave_duck")
local SweatDrop = V.require("sweat_drop")
local MoodFx = V.require("mood_fx")
local PopupText = V.require("popup_text")
local ShinySparkle = V.require("shiny_sparkle")
local PartnerFx = V.require("partner_fx")
local FollowerSwap = V.require("follower_swap")

local FollowerAdapter = {}
FollowerAdapter.__index = FollowerAdapter

local CELL = 16
local POPUP_GAP = 3 -- px of air between the top of its head and a label's tail
local SWAP_LOCK = "wilds_of_hoenn_follower_swap"
FollowerAdapter.STEP_TICKS = 16 -- logic ticks per one-tile step

function FollowerAdapter.new(mod, companion)
  return setmetatable({
    mod = mod, companion = companion, role = "follow",
    behaviors = {}, -- role -> behaviour object (lib/forager.lua ...), set by main.lua
    leadSpecies = nil, style = nil, renderer = nil,
    stepParity = false, wasMoving = false,
    isFloater = false, flapClock = 0, wasRecalled = false,
  }, FollowerAdapter)
end

--- Start a Pet / Play / Talk scene (lib/follower_actions.lua) on the follower.
--- Returns the scene, or nil when there is no follower to animate. The scene
--- is stepped from tick() below; `actionActive()` says when it is over.
function FollowerAdapter:startAction(kind)
  local npc = EnginePatch.followerCurrent()
  if not (npc and self.renderer) or self.emerge then return nil end
  local species = self.leadSpecies
  local facing = EnginePatch.playerFacing() or npc.facing
  local ctx = {
    facing = facing,
    cellsAhead = EnginePatch.freeCellsAhead(npc.cellX, npc.cellY, facing, Config.ACTIONS.play.ballDist),
    idleTicks = FollowerAdapter.idleLoopTicks(self.renderer),
    playCry = function() EnginePatch.playCry(species) end,
    cryFinished = EnginePatch.cryFinished,
  }
  self.action = FollowerActions.new(kind, ctx)
  self.actState, self.actClock = nil, 0
  return self.action
end

--- Length in ticks of the follower's Idle loop (PMD: from its art; HGSS has no
--- Idle, so one flap cycle's worth).
function FollowerAdapter.idleLoopTicks(renderer)
  local idle = renderer and renderer.info and renderer.info.idle
  if type(idle) == "table" and type(idle.durations) == "table" then
    local sum = 0
    for _, d in ipairs(idle.durations) do sum = sum + (tonumber(d) or 0) end
    if sum > 0 then return sum end
  end
  return Config.IDLE_FLAP_TICKS * 4
end

function FollowerAdapter:actionActive()
  return self.action ~= nil
end

--- Is the follower away from its place or mid-scene (so the Pet / Play / Talk
--- menu must not open on it)?
function FollowerAdapter:isBusy()
  if self.action ~= nil or self.swap ~= nil then return true end
  local b = self.behaviors and self.behaviors[self.role]
  return b ~= nil and b.isBusy ~= nil and b:isBusy() == true
end

-- What the companion is waiting for after levelling up (lib/level_ready.lua):
-- re-read every READY_REFRESH ticks (it asks the engine), shown by collectActors.
local READY_REFRESH = 30
function FollowerAdapter:_tickReady()
  local lr = self.levelReady
  if not lr then return end
  self.readyClock = (self.readyClock or 0) + 1
  if self.readyClock % READY_REFRESH == 1 or self.readyMon ~= self.mon or self.readyVersion ~= lr.version then
    self.readyMon, self.readyVersion = self.mon, lr.version
    self.readyPending = self.mon and lr:pending(self.mon) or nil
  end
end

--- The text floating over the follower's head ("New move ready!" ...), or nil.
function FollowerAdapter:readyLabel()
  if not self.levelReady or self.away or self.action or self.swap then return nil end
  return V.require("level_ready").textFor(self.readyPending, self.readyClock)
end

-- Walking out of a doorway. On a map change the engine makes a fresh follower ON
-- THE PLAYER'S CELL (src/world/game3/Follower.lua); after a door / cave / stairs exit
-- that is the doorway, and the player is walked one step out while the follower
-- stays there until their next step -- drawn on the door, over the building. So a
-- fresh follower on a warp tile (EnginePatch.isWarpCell) is hidden while it stands
-- in it and fades in (renderer.alpha 0 -> 1) over the step it takes out. A map-edge
-- connection, Fly, a fall or a save load never lands on a warp tile: no change there.
-- Returns true while it is still coming out.
function FollowerAdapter:_tickEmerge(npc)
  if npc ~= self.lastNpc then
    self:_endEmerge(self.lastNpc)
    self.lastNpc = npc
    if EnginePatch.isWarpCell and EnginePatch.isWarpCell(npc.cellX, npc.cellY) then
      self.emerge = { x = npc.cellX, y = npc.cellY }
    end
  end
  local em = self.emerge
  if not em then return false end
  if npc.cellX ~= em.x or npc.cellY ~= em.y then -- out of the doorway
    self:_endEmerge(npc)
    return false
  end
  local r = self.renderer
  if npc.moving then
    -- stepping out: visible again, fading in over the step
    if self.hidByUs then npc.hidden, self.hidByUs = false, false end
    if r then r.alpha = math.max(0, math.min(1, (tonumber(npc.progress) or 0) / math.max(1, tonumber(npc.stepFrames) or 16))) end
  else
    -- still in the doorway: not drawn (the engine's own flag; we only ever undo it
    -- if we set it)
    if not npc.hidden then npc.hidden, self.hidByUs = true, true end
    if r then r.alpha = 0 end
  end
  return true
end

function FollowerAdapter:_endEmerge(npc)
  if self.hidByUs and npc then npc.hidden = false end
  self.hidByUs, self.emerge = false, nil
  if self.renderer then self.renderer.alpha = nil end
end

--- Still walking out of a doorway?
function FollowerAdapter:isEmerging() return self.emerge ~= nil end

--- A new map: each behaviour drops what it was doing there (a Forager keeps its
--- timer, see lib/forager.lua's mapChanged).
function FollowerAdapter:mapChanged()
  self.away = false
  self:resetDisplay()
  for _, b in pairs(self.behaviors or {}) do
    if b.mapChanged then b:mapChanged() elseif b.reset then b:reset() end
  end
  if not self.action then
    self.actState = nil
    if self.renderer then self.renderer.act = nil end
  end
end

--- Forget every role behaviour's progress (save load, role change).
function FollowerAdapter:resetBehaviors()
  self.away = false
  for _, b in pairs(self.behaviors or {}) do
    if b.reset then b:reset() end
  end
  if not self.action then
    self.actState = nil
    if self.renderer then self.renderer.act = nil end
  end
end

-- The companion's role behaviour for this tick (Forager ...): its state in the
-- same shape a scene returns, mirrored onto the renderer the same way. nil
-- while the role has none or it is just standing with the player.
function FollowerAdapter:_tickBehavior(npc)
  if self.action or self.swap then return nil end
  if self.role ~= self.lastRole then
    self:resetBehaviors()
    self.lastRole = self.role
  end
  local b = self.behaviors and self.behaviors[self.role]
  local state
  if b and not self.surfRecall then
    local pc = EnginePatch.playerCell()
    local playerMoving = pc and pc.moving or false
    local forageOk -- nil = the engine pieces are missing: no restriction
    if EnginePatch.forageAllowed then
      forageOk = EnginePatch.forageAllowed(Config.FORAGE.allowedMapTypes)
    end
    state = b:step({
      still = not (npc.moving or false) and not playerMoving,
      fx = npc.cellX, fy = npc.cellY, px = pc and pc.x, py = pc and pc.y,
      -- where the follower is DRAWN (its tile plus the spacing the renderer adds)
      fpx = npc.px + (self.renderer and self.renderer.pushX or 0),
      fpy = npc.py + (self.renderer and self.renderer.pushY or 0),
      mon = self.mon, renderer = self.renderer,
      -- 0-255: a Forager finds sooner and rarer the fonder it is
      friendship = self.mon and EnginePatch.friendshipOf and EnginePatch.friendshipOf(self.mon) or 0,
      -- routes and caves only (EnginePatch.forageAllowed); nil without the engine pieces
      forageOk = forageOk,
    })
  end
  self.away = state ~= nil and state.away == true
  if not state then
    self.actState = nil
    if self.renderer then self.renderer.act = nil end
    return nil
  end
  self.actState = state
  self.actClock = (self.actClock or 0) + 1
  self.renderer.act = { dx = state.dx or 0, dy = state.dy or 0, facing = state.facing,
    sink = state.sink, flash = state.flash }
  return state
end

--- Drop a running scene at once (the interaction was aborted).
function FollowerAdapter:cancelAction()
  self.action, self.actState = nil, nil
  if self.renderer then self.renderer.act = nil end
end

-- Steps the running scene one tick and mirrors it onto the renderer
-- (`renderer.act` = offset + facing override). Returns this tick's state, or
-- nil when no scene is running / it just ended.
function FollowerAdapter:_tickAction()
  local act = self.action
  if not act then return nil end
  local state = act:step()
  if not state then
    self:cancelAction()
    return nil
  end
  self.actState = state
  self.actClock = (self.actClock or 0) + 1
  self.renderer.act = { dx = state.dx or 0, dy = state.dy or 0, facing = state.facing }
  return state
end

--- Is the follower inside its "ball" right now (shrunk into the player while
--- they surf)? True while the recall is more than half closed.
function FollowerAdapter:isRecalled()
  local r = self.renderer
  return r ~= nil and (r.recall or 1) < 0.5
end

--- Is the follower squished under a roof's edge (crouched enough to sweat,
--- `_tickDuck`)? Its interaction then says it's cramped (lib/follower_interaction.lua).
function FollowerAdapter:isCramped()
  local r = self.renderer
  return r ~= nil and (r.duck or 0) > Config.FOLLOWER_DUCK.sweatFrom
end

--- Is the follower DRAWN over water this tick? Its own tile, or -- while a role
--- behaviour or scene moves it away from that tile (the Battler swimming out to a wild
--- Pokemon) -- the tile it is drawn on.
function FollowerAdapter:_drawnOnWater(npc)
  local cx, cy = npc.cellX, npc.cellY
  local scene = self.sceneNow
  if scene and ((scene.dx or 0) ~= 0 or (scene.dy or 0) ~= 0) and npc.px and npc.py then
    local r = self.renderer
    cx = math.floor((npc.px + ((r and r.pushX) or 0) + scene.dx + CELL / 2) / CELL)
    cy = math.floor((npc.py + ((r and r.pushY) or 0) + scene.dy + CELL / 2) / CELL)
  end
  return EnginePatch.isWater(cx, cy) == true
end

--- PMDCollab has no swim art of its own: on a water tile the follower is drawn
--- swimming (cut off at its baked waterline with foam, lib/pmd_renderer.lua) and
--- trails the surfing player like the HGSS swim sprites do; a true flyer
--- (lib/pmd_water.lua) is drawn whole. Only art without waterline data (an old
--- bake) falls back to the recall: while the player surfs the follower shrinks
--- into them and grows back out once they walk on land. It stays in until the
--- FOLLOWER itself is off the water too (it trails a step or two behind, so it
--- would otherwise reappear standing on a water tile).
function FollowerAdapter:_tickRecall(npc, r)
  local recalled = false
  local swims = r.isPmd and r.canSwim and r:canSwim()
  if swims then
    local onWater = self:_drawnOnWater(npc)
    r.swimming = onWater and not SpriteSource.pmdFlies(r.dex)
  elseif r.isPmd then
    -- only PMD needs it while surfing: the HGSS art has its own swim sprites
    local surf = EnginePatch.playerSurfState and EnginePatch.playerSurfState()
    recalled = surf ~= nil and surf.surfing and not surf.dismounting
    if not recalled and self.wasRecalled then
      local overWater = EnginePatch.isWater(npc.cellX, npc.cellY)
        or (npc.moving and npc.targetX ~= nil and EnginePatch.isWater(npc.targetX, npc.targetY))
      recalled = overWater == true
    end
  end
  self.wasRecalled = recalled
  -- on a bike the companion rides in its ball (any art style) until the player gets off;
  -- its role (Forage, Battle) pauses meanwhile, like while surfing
  local biking = EnginePatch.playerBiking and EnginePatch.playerBiking() or false
  if biking then recalled = true end
  -- at the nurse's counter it goes into its ball for the heal machine, and comes back out
  if EnginePatch.healingActive and EnginePatch.healingActive() then recalled = true end
  -- a cutscene (a script moving anyone: the player, an NPC, both -- or Gen 2's `follow`),
  -- it stays out of the way inside its ball; plain dialogue moves nobody and leaves it out
  if self:inCutscene() then recalled = true end
  self.surfRecall = recalled
  -- a Battler out of strength rests inside the player (any art style)
  if self.away then recalled = true end
  -- a recalled companion stays inside the player
  if self.role == "recall" then recalled = true end

  local want = recalled and 0 or 1
  if self.swap and self.swapState then want = self.swapState.want end
  if self.swapFresh then
    -- the new sprite begins inside the ball, whatever it is about to do
    r.recall, r.recallPlaced, self.swapFresh = 0, true, false
  end
  if r.recallPlaced then
    local step = 1 / math.max(1, Config.PMD_RECALL_TICKS)
    r.recall = ActorRenderer.approach(r.recall, want, step)
  else
    r.recall, r.recallPlaced = want, true -- a new sprite starts in its right state
  end
  local px, py = nil, nil
  if EnginePatch.playerPixel then px, py = EnginePatch.playerPixel() end
  r.recallX, r.recallY = px, py
  self:_tickDuck(npc, r)
end

-- the art's width as drawn (px), for which columns of tiles it spans
local function drawnWidth(r)
  if r.isPmd then
    local PmdRenderer = V.require("pmd_renderer")
    local w = PmdRenderer.contentSize(r.info, r.hdScale and r:hdScale() or 1)
    return (w and w > 0) and w or CELL
  end
  return (r.visualWidth and r:visualWidth()) or CELL
end

--- A tall follower in front of a house ducks under the eave the map draws over characters
--- (lib/eave_duck.lua): `r.duckDy` px down, `r.duck` squashed toward its feet, eased in and
--- out. Gen 3's covering tiles only (EnginePatch.coversActors); nothing while recalled.
--- The map is only asked again when the tiles the art spans change (a new tile window, or
--- a new map: the engine makes a new npc on every map change); otherwise a few sums.
local function coversTile(x, y) return EnginePatch.coversActors(x, y) == true end
local function solidTile(x, y) return EnginePatch.isWall(x, y) == true end

function FollowerAdapter:_tickDuck(npc, r)
  local cfg = Config.FOLLOWER_DUCK
  local wantDy, wantDuck = 0, 0
  if EnginePatch.coversActors and EnginePatch.isWall and (r.recall or 1) >= 1 and npc.px and npc.py then
    local height = r.headLift and r:headLift() or nil
    if height and height > CELL then
      local cx = npc.px + CELL / 2 + (r.pushX or 0)
      local half = drawnWidth(r) / 2
      local feetY = npc.py + CELL + (r.pushY or 0)
      local feetRow = math.floor((feetY - 1) / CELL)
      local top = feetY - height
      local c0, c1, r0 = EaveDuck.window(cx - half, cx + half, top)
      local s = self.duckScan
      if not (s and s.npc == npc and s.c0 == c0 and s.c1 == c1 and s.r0 == r0 and s.feetRow == feetRow) then
        s = s or {}
        s.npc, s.c0, s.c1, s.r0, s.feetRow = npc, c0, c1, r0, feetRow
        s.row = EaveDuck.lowestRow(c0, c1, r0, feetRow, coversTile, solidTile)
        self.duckScan = s
      end
      wantDy, wantDuck = EaveDuck.split(EaveDuck.need(s.row, top), height, cfg)
    end
  end
  local k = cfg.ease
  r.duckDy = (r.duckDy or 0) + (wantDy - (r.duckDy or 0)) * k
  r.duck = (r.duck or 0) + (wantDuck - (r.duck or 0)) * k
  if math.abs(r.duckDy - wantDy) < 0.05 then r.duckDy = wantDy end
  if math.abs(r.duck - wantDuck) < 0.002 then r.duck = wantDuck end
  -- crouching (not just dipping): a sweat drop by its head (collectActors)
  if r.duck > Config.FOLLOWER_DUCK.sweatFrom then
    self.sweatAge = (self.sweatAge or 0) + 1
  else
    self.sweatAge = nil
  end
end

--- Gen 3 cutscenes: main.lua's `script.command` wrap reports every `applymovement` target
--- (local id; 0xFF = the player). A script that moves anyone -- the player, an NPC, the
--- player walking with someone -- is a cutscene, so the companion goes into its ball until
--- the script ends (`onScriptEnded`, or the field being free again). Talking to someone
--- (text, `faceplayer`) moves nobody: it stays out.
FollowerAdapter.LOCALID_PLAYER = 0xFF

function FollowerAdapter:onScriptMovement(localId)
  if tonumber(localId) then self.cutscene = true end
end

function FollowerAdapter:onScriptEnded()
  self.cutscene = false
end

--- Is a cutscene running (or a character following the player), so the companion keeps
--- out of the way in its ball?
function FollowerAdapter:inCutscene()
  if self.cutscene then
    -- no script running any more (an end we did not hear): let go
    if EnginePatch.fieldBusy and not EnginePatch.fieldBusy() then
      self:onScriptEnded()
      return false
    end
    return true
  end
  return EnginePatch.leadingNpc ~= nil and EnginePatch.leadingNpc() == true
end

--- The callback passed to mod.hooks:wrap("world.follower.spawn", ...).
function FollowerAdapter:shouldSpawn()
  return Config.followerEnabled(self.mod)
end

-- ----------------------------------------------------------------- swapping
-- What the player sees out is `self.disp` ({ mon, role, species, key }). It
-- follows the companion (lib/companion.lua) only through a swap scene
-- (lib/follower_swap.lua): the party menu changes the companion at once, but
-- the old one keeps standing there until the menu is closed, then goes into
-- its ball and the new one comes out of another.

-- Is this party Pokemon shiny? The same real check the wild spawns use, against
-- ITS OWN trainer ids (a traded or gifted one is judged by its original trainer).
local function monShiny(mon)
  if type(mon) ~= "table" or mon.personality == nil then return false end
  return EnginePatch.isShiny(mon.personality, tonumber(mon.otId), tonumber(mon.otSecretId)) == true
end

local function dispOf(mon, role)
  local id = tostring(mon and (mon.personality or ("species" .. tostring(mon.species))))
  return {
    mon = mon, role = role, species = mon and tonumber(mon.species) or nil,
    shiny = monShiny(mon),
    id = id .. ":" .. tostring(mon and mon.species),
    key = id .. ":" .. tostring(role),
  }
end

-- The same Pokemon, out in the field before and after, only its job changed (follow ->
-- battle ...): nothing to put away or send out, it just takes up the new role.
local function sameMonNewJob(disp, target, renderer)
  return disp.id == target.id and disp.role ~= "recall" and target.role ~= "recall"
    and renderer ~= nil and (renderer.recall or 1) > 0.5
end

--- May a swap scene begin now? (No menu, message or fade, and the player
--- standing still.) A field so tests can answer for the engine.
function FollowerAdapter.canSwap()
  return not EnginePatch.screenBusy() and EnginePatch.canStartInteraction()
end

--- Forget what is displayed (a save was loaded / a map was entered): the next
--- tick shows the companion as it is, with no scene.
function FollowerAdapter:resetDisplay()
  self:_endSwap()
  self.disp = nil
end

function FollowerAdapter:_endSwap()
  if self.swap then
    EnginePatch.unlockField(SWAP_LOCK)
    self.swap, self.swapState = nil, nil
  end
end

-- Begins the scene from the displayed companion to `target`.
function FollowerAdapter:_beginSwap(target)
  local r = self.renderer
  local hasOld = self.disp.role ~= "recall" and r ~= nil and (r.recall or 1) > 0.5
  self.swap = FollowerSwap.new({ hasOld = hasOld, hasNew = target.role ~= "recall" })
  self.swapTarget = target
  EnginePatch.lockField(SWAP_LOCK)
end

-- One tick of the scene: raises the arm, switches the displayed companion at
-- the right moment, drives the shrink / grow. Returns the state, or nil when
-- the scene is over (the target is then fully displayed).
function FollowerAdapter:_tickSwap()
  local sw = self.swap
  local s = sw:step()
  if s == nil then
    self.disp = self.swapTarget
    self:_endSwap()
    return nil
  end
  if s.pose then EnginePatch.playerPose(Config.SWAP.poseTicks) end
  if s.switch then
    self.disp = self.swapTarget
    self.swapFresh = true -- the new sprite starts inside the player
  end
  if s.cry and self.disp.species then EnginePatch.playCry(self.disp.species) end
  self.swapState = s
  return s
end

--- Called every field tick, after the engine's own Follower.update has run
--- (engine_patch's `followerTick` hook) -- keeps npc.sprite pointed at a
--- renderer for the CURRENT party lead in the CURRENT Sprite Style,
--- rebuilding it only when either actually changes (a party-menu swap or
--- an options-menu style switch, not every tick), then refreshes that
--- renderer's pose/presentation for THIS tick (cheap field writes, no
--- rebuild -- see module header).
function FollowerAdapter:tick()
  local npc = EnginePatch.followerCurrent()
  if not npc then
    self.leadSpecies, self.style = nil, nil
    self.wasMoving = false
    self.lastNpc, self.emerge, self.hidByUs = nil, nil, false
    self:resetDisplay()
    if self.actState then self:resetBehaviors() end
    return
  end
  -- while you Pet / Play / Talk with it: the effect matching its face (lib/mood_fx.lua)
  local moodKind = self.interaction and self.interaction.moodKind and self.interaction:moodKind() or nil
  if moodKind ~= self.moodKind then
    self.moodKind, self.moodAge = moodKind, 0
  elseif moodKind then
    self.moodAge = self.moodAge + 1
  end
  self.fxClock = (self.fxClock or 0) + 1
  -- with you (Pet / Play / Talk: its message, the menu, the scene): its type's puff runs
  local st = self.interaction and self.interaction.state
  if st == "report" or st == "menu" or st == "anim" or st == "result" then
    self.withYouAge = (self.withYouAge or -1) + 1
  else
    self.withYouAge = nil
  end
  local mon, role
  if self.companion then
    mon, role = self.companion:resolve(EnginePatch.partyMons())
  else
    local sp = EnginePatch.leadPartySpecies()
    mon, role = sp and { species = sp } or nil, "follow"
  end
  -- the same Pokemon as last tick (same table, personality, species, role): its record
  -- again instead of a new one (and a shiny check) every tick
  local last = self._lastTarget
  local target
  if last and last.mon == mon and last.role == role and mon and last.pid == mon.personality
      and last.sp == mon.species then
    target = last.target
  else
    target = dispOf(mon, role)
    self._lastTarget = { mon = mon, role = role, pid = mon and mon.personality, sp = mon and mon.species,
                         target = target }
  end
  if not self.disp then
    self.disp = target
  elseif self.swap then
    self:_tickSwap()
  elseif target.key ~= self.disp.key then
    if sameMonNewJob(self.disp, target, self.renderer) then
      self.disp = target
    elseif not (EnginePatch.screenBusy and EnginePatch.canStartInteraction) then
      self.disp = target -- no engine to hold a scene in: just change over
    elseif FollowerAdapter.canSwap() and not self.action then
      self:_beginSwap(target)
      self:_tickSwap()
    end
  elseif mon then
    self.disp.mon = mon -- the same companion: keep its live data
  end
  local species = self.disp.species
  self.role, self.mon = self.disp.role, self.disp.mon
  self:_tickReady()
  local style = Config.spriteStyle(self.mod)
  local shiny = self.disp.shiny == true
  if species ~= self.leadSpecies or style ~= self.style or shiny ~= self.leadShiny
      or npc.sprite ~= self.renderer then
    self.leadSpecies, self.style, self.leadShiny = species, style, shiny
    local dex = species and FormSource.artKeyFor(self.mod, species) or nil
    if not dex then
      self.renderer = nil
      npc.sprite = nil
    else
      self.isFloater = SpriteSource.isFloater(self.mod, dex)
      self.renderer = RendererFactory.new(self.mod, dex, shiny, style)
      npc.sprite = self.renderer
    end
  end
  if not self.renderer then
    self.action, self.actState = nil, nil
    return
  end
  -- walking out of a doorway: hidden in it, fading in as it steps out; nothing
  -- else (a scene, a Forager trip ...) starts until it is out
  self:_tickRipple(npc)
  local emerging = self:_tickEmerge(npc)
  local scene = nil
  if not emerging then scene = self:_tickAction() or self:_tickBehavior(npc) end
  self.sceneNow = scene

  -- PMDCollab: the renderer animates itself from a tick clock (Walk while
  -- the follower steps, Idle while it stands) -- none of the pose, grass
  -- pushback or glide handling below applies to it.
  if self.renderer.isPmd then
    local r = self.renderer
    if r.idleDelay ~= Config.PMD_FOLLOWER_IDLE_DELAY then
      -- first tick of a new sprite: it waits the full delay before idling too
      r.idleDelay = Config.PMD_FOLLOWER_IDLE_DELAY
      if r.anim == "idle" then r.idleHold = r.idleDelay end
    end
    r.idleSpeed = Config.PMD_FOLLOWER_IDLE_SPEED
    local moving = npc.moving or false
    if scene then
      -- a scene drives the animation: Walk while it runs, a quick Idle for Pet
      moving = scene.moving == true
      if scene.bounce then
        r.idleHold, r.idleSpeed = 0, scene.idleSpeed or 1
      end
    end
    r.walkMul = scene and scene.walkMul or 1
    if scene and scene.anim and scene.anim ~= "idle" then
      r:advanceAs(scene.anim, scene.animSpeed)
    else
      r:advance(moving)
    end
    -- Space it out: kept behind the player along its facing by its own
    -- overhang past the 16px tile plus a gap, eased so a turn glides
    -- (same recipe as the pushback of the ActorRenderer styles below).
    local PmdRenderer = V.require("pmd_renderer")
    local cw, ch = PmdRenderer.contentSize(r.info, r:hdScale())
    local vertical = npc.facing == "up" or npc.facing == "down"
    local overhang = math.max(0, ((vertical and ch or cw) - CELL) / 2)
    -- walking down the follower trails ABOVE the player, and its art already
    -- extends upward from its feet, so it gets a smaller gap there
    local gap = npc.facing == "down" and Config.PMD_FOLLOWER_GAP_DOWN or Config.PMD_FOLLOWER_GAP
    if npc.facing == "down" then overhang = overhang * Config.PMD_FOLLOWER_DOWN_OVERHANG end
    if not vertical then overhang = overhang * (Config.PMD_FOLLOWER_SIDE_OVERHANG or 1) end
    local push = overhang + gap
    local tx, ty = ActorRenderer.behindOffset(npc.facing, push)
    if not Config.smoothFollow(self.mod) then
      -- Smooth Follow off: spaced out the same, but no glide -- it snaps to its place
      -- behind the player on a turn, step for step like the original games
      r.pushX, r.pushY, r.pushPlaced = tx, ty, true
      self:_tickRecall(npc, r)
      return
    end
    -- a turn takes the same time for every sprite, which makes a big one's
    -- offset race across the screen: cap the speed so it glides instead
    -- (the speed goes by the larger of the new push and the offset it is leaving, never
    -- by the new push alone: a small sprite facing down has a push of 0, which would
    -- make the speed 0 and leave it stuck off to the side after a sideways turn)
    local travel = math.max(push, math.abs(r.pushX or 0), math.abs(r.pushY or 0))
    -- (with a floor, so it lands exactly instead of easing toward the target forever)
    local maxStep = math.min(math.max((travel * 2) / FollowerAdapter.STEP_TICKS, 0.25), Config.PMD_FOLLOWER_TURN_SPEED)
    if r.pushPlaced then
      r.pushX = ActorRenderer.approach(r.pushX, tx, maxStep)
      r.pushY = ActorRenderer.approach(r.pushY, ty, maxStep)
    else
      r.pushX, r.pushY, r.pushPlaced = tx, ty, true -- a new sprite starts in place
    end
    self:_tickRecall(npc, r)
    return
  end

  -- Alternates walkA/walkB (or runA/runB) once per STEP, on the
  -- not-moving -> moving edge -- not every tick -- mirroring
  -- lib/behavior.lua's own entity.stepParity toggle for wild Pokemon.
  local moving = npc.moving or false
  local standHalf = false -- moving, in the stand-frame half of a step
  if scene then
    -- a scene walks in place: alternate the A/B walk pose every half step
    moving = scene.moving == true
    if moving then self.stepParity = math.floor(self.actClock / (FollowerAdapter.STEP_TICKS / 2)) % 2 == 0 end
    self.wasMoving = moving
  else
    if moving and not self.wasMoving then
      self.stepParity = not self.stepParity
      self.stepClock = 0
    end
    self.wasMoving = moving
    -- the Gen 3 walk cycle: the step's walk frame for its first half, the stand frame for
    -- the second (walkA, stand, walkB, stand ...). The engine's follower is "not moving" for
    -- a tick between one step and the next; that tick falls in the stand half.
    if moving then
      self.stepClock = (self.stepClock or 0) + 1
      local half = (EnginePatch.playerIsRunning() and FollowerAdapter.STEP_TICKS / 2 or FollowerAdapter.STEP_TICKS) / 2
      standHalf = self.stepClock > half
    end
  end

  local pose = ActorRenderer.POSE_STAND
  if scene and scene.bounce then
    pose = ActorRenderer.idleFlapPose(self.actClock, scene.flapTicks or Config.IDLE_FLAP_TICKS)
  elseif moving and not standHalf then
    if EnginePatch.playerIsRunning() then
      pose = self.stepParity and ActorRenderer.POSE_RUN_A or ActorRenderer.POSE_RUN_B
    else
      pose = self.stepParity and ActorRenderer.POSE_WALK_A or ActorRenderer.POSE_WALK_B
    end
  end
  -- A floating/flying lead keeps flapping slowly while standing still.
  if not moving and self.isFloater then
    self.flapClock = self.flapClock + 1
    pose = ActorRenderer.idleFlapPose(self.flapClock, Config.IDLE_FLAP_TICKS)
  end
  self.renderer.poseOverride = pose

  self.renderer.presentation = self:_drawnOnWater(npc)
    and SpriteSource.DEFAULT_WATER_PRESENTATION or SpriteSource.PRESENTATION_LAND

  -- "Spacing out" a large (True Size) follower so it doesn't visually
  -- overlap the player ahead of it -- the single-follower analog of Wilds
  -- of Kanto Revival's multi-trailer convoy spacing. Cosmetic-only, applied
  -- entirely inside ActorRenderer:draw() (largePushback/behindOffset) --
  -- this mod does NOT own the follower's movement (src/world/game3/
  -- Follower.lua does), so nudging npc.px/py/cellX/cellY here would get
  -- baked into the engine's OWN fromX/targetX bookkeeping on the next step
  -- and compound every subsequent step; never touch those fields for this.
  -- Only a sprite wider than one tile needs it: a no-op for the species
  -- whose HGSS / PokeMMO art fits in 16px.
  local pushback = 0
  if self.renderer.style == SpriteSource.STYLE_POKEMMO then
    local fw = self.renderer:visualWidth()
    if fw and fw > CELL then
      pushback = (fw - CELL) / 2
    end
  end
  self.renderer.largePushback = pushback

  -- Ease the applied offset toward the facing's target instead of letting it
  -- flip in one frame on a turn (the same glide Wilds of Kanto Revival gives
  -- its trailers). A full 180-degree swing (2 * pushback) takes about one
  -- step (STEP_TICKS logic ticks). Cosmetic only, same reason as above.
  local r = self.renderer
  local tx, ty = ActorRenderer.behindOffset(npc.facing, pushback)
  if pushback == 0 then
    r.pushX, r.pushY = nil, nil
  elseif not Config.smoothFollow(self.mod) then
    r.pushX, r.pushY = tx, ty -- Smooth Follow off: the same spacing, no glide on a turn
  else
    local maxStep = (pushback * 2) / FollowerAdapter.STEP_TICKS
    r.pushX = ActorRenderer.approach(r.pushX, tx, maxStep)
    r.pushY = ActorRenderer.approach(r.pushY, ty, maxStep)
  end
  self:_tickRecall(npc, r)
end

--- Called from the same `collectActors` hook as lib/spawn_manager.lua's
--- own (engine_patch's `collectActors` hook, main.lua) -- appends the
--- "sinking into grass" overlay (lib/grass_cover.lua) for the follower's
--- CURRENT cell, if it's standing in one right now. The follower's own
--- actor entry is pushed by the engine itself (src/world/game3/Follower.lua's
--- actor(), called directly by field_view.lua BEFORE our wrapped
--- collectActors runs) -- this only adds the extra overlay, never the
--- follower's own sprite. `idBase = 0`, distinct from every wild-mon id
--- (lib/spawn_manager.lua's ids start at 1).
--- Each tile the follower steps onto that ripples for the player (pond water, a
--- puddle) gets the engine's ripple too. A fresh follower (a map change re-creates it)
--- is only noted, so appearing on water makes no ripple.
function FollowerAdapter:_tickRipple(npc)
  local cx, cy = npc.cellX, npc.cellY
  if npc ~= self.rippleNpc then
    self.rippleNpc, self.rippleX, self.rippleY = npc, cx, cy
    return
  end
  if cx == self.rippleX and cy == self.rippleY then return end
  self.rippleX, self.rippleY = cx, cy
  if npc.hidden or self:isRecalled() then return end
  if EnginePatch.ripplesAt and EnginePatch.ripplesAt(cx, cy) then EnginePatch.startRipple(cx, cy) end
end

--- The follower's water reflection, for lib/reflection.lua (the drawBehind hook).
function FollowerAdapter:reflections(list)
  local npc = EnginePatch.followerCurrent()
  local r = self.renderer
  if not (npc and r and r.reflectionGeometry) or npc.hidden then return end
  local geo = r:reflectionGeometry(npc.px or npc.cellX * CELL, npc.py or npc.cellY * CELL,
    npc.facing, ActorRenderer.POSE_STAND)
  if not geo then return end
  local moving = npc.moving and npc.targetX ~= nil
  list[#list + 1] = {
    geo = geo,
    cell = { cx = moving and npc.targetX or npc.cellX, cy = moving and npc.targetY or npc.cellY,
             pcx = npc.cellX, pcy = npc.cellY },
  }
end

function FollowerAdapter:collectActors(actors)
  local npc = EnginePatch.followerCurrent()
  if not npc or npc.hidden then return end
  local ball = self.actState and self.actState.ball
  if ball then
    actors[#actors + 1] = FollowerActions.ballActor(ball, npc.px, npc.py, npc.elevation)
  end
  local held = self.swapState and self.swapState.ball
  if held then
    local px, py = EnginePatch.playerPixel()
    if px then
      actors[#actors + 1] = FollowerActions.ballActor(held, px, py, EnginePatch.playerElevation())
    end
  end
  local role = self.behaviors and self.behaviors[self.role]
  if role and role.collectActors and not self.away then role:collectActors(actors) end
  local popup = self.actState and self.actState.popup
  local ready = not popup and (self.renderer and (self.renderer.recall or 1) >= 0.5) and self:readyLabel() or nil
  if popup or ready then
    -- over where the sprite is actually drawn: tile + spacing + the act's offset
    local r = self.renderer
    local act = r and r.act
    local state = self.actState or {}
    -- just over its head as drawn (headLift: the highest point its art reaches, Species Sizes
    -- included; squashed under an eave), not a fixed height
    local head = (r and r.headLift and r:headLift()) or CELL
    head = head * (1 - ((r and r.duck) or 0))
    local lift = math.max(2, math.floor(head - CELL + POPUP_GAP + 0.5))
    local a = PopupText.actor(popup and popup.text or ready,
      npc.px + ((r and r.pushX) or 0) + ((act and act.dx) or state.dx or 0),
      npc.py + ((r and r.pushY) or 0) + ((r and r.duckDy) or 0) + ((act and act.dy) or state.dy or 0),
      npc.elevation, lift, popup and 0 or 1,
      popup and popup.age or self.readyClock) -- its age animates a level-up
    if a then actors[#actors + 1] = a end
  end
  -- a shiny partner twinkles now and then (not while recalled into the player, nor while it
  -- stands on the player's own spot -- just after a map change -- hidden behind them)
  local sr = self.renderer
  local ppx, ppy
  if EnginePatch.playerPixel then ppx, ppy = EnginePatch.playerPixel() end -- (both values: `a and f()` keeps one)
  local underPlayer = ppx ~= nil and ppy ~= nil and npc.px ~= nil and math.abs(npc.px - ppx) < 1
    and math.abs(npc.py - ppy) < 1
  if self.leadShiny and sr and npc.px and npc.py and (sr.recall or 1) >= 1 and sr.headLift and not npc.hidden
      and not underPlayer then
    self.sparkleAge = (self.sparkleAge or 0) + 1
    local act = sr.act
    local feetY = npc.py + CELL + (sr.pushY or 0) + (sr.duckDy or 0) + ((act and act.dy) or 0)
    local lift = (sr:headLift() or CELL) * (1 - (sr.duck or 0))
    local a = ShinySparkle.actor(self.sparkleAge, 0, npc.px + CELL / 2 + (sr.pushX or 0) + ((act and act.dx) or 0),
      feetY - lift, lift * 0.85, ShinySparkle.bodyWidth(sr) * 0.5 * 0.8, feetY + 1, npc.elevation)
    if a then actors[#actors + 1] = a end
  end
  -- its own touches (lib/partner_fx.lua): sparkles while it is ready to evolve; a puff of its
  -- type while you Pet / Play / Talk with it, or now and then with the Type Aura option
  if sr and npc.px and npc.py and (sr.recall or 1) >= 1 and sr.headLift and not underPlayer then
    local act = sr.act
    local x = npc.px + (sr.pushX or 0) + ((act and act.dx) or 0)
    local y = npc.py + (sr.pushY or 0) + (sr.duckDy or 0) + ((act and act.dy) or 0)
    local lift = (sr:headLift() or CELL) * (1 - (sr.duck or 0))
    local parts
    local pending = self.readyPending
    if pending and pending.evolve then parts = PartnerFx.evolveParts(self.fxClock or 0) end
    local species = self.disp and self.disp.species
    if species ~= self.fxSpecies then self.fxSpecies, self.fxKind = species, species and PartnerFx.kindFor(species) end
    local puff
    if self.fxKind and self.withYouAge then
      puff = PartnerFx.typePuffParts(self.fxKind, self.withYouAge, PartnerFx.PUFF_PERIOD)
    elseif self.fxKind and Config.typeAura(self.mod) and not self.action then
      puff = PartnerFx.typePuffParts(self.fxKind, self.fxClock or 0, PartnerFx.AURA_PERIOD)
    end
    if puff and #puff > 0 then
      if parts then for _, p in ipairs(puff) do parts[#parts + 1] = p end else parts = puff end
    end
    local a = parts and PartnerFx.actor(parts, x, y, lift, npc.elevation, 3)
    if a then actors[#actors + 1] = a end
  end
  -- crouching under a roof's edge: a sweat drop at the top corner of its (squashed) head
  -- talking with it: hearts, notes, a rain cloud ... over the top of its head
  if self.moodKind and sr and (sr.recall or 1) >= 0.5 and sr.headLift then
    local act = sr.act
    local feetY = npc.py + CELL + (sr.pushY or 0) + (sr.duckDy or 0) + ((act and act.dy) or 0)
    local top = feetY - (sr:headLift() or CELL) * (1 - (sr.duck or 0))
    local x = npc.px + CELL / 2 + (sr.pushX or 0) + ((act and act.dx) or 0)
    -- (headLift is its highest frame, an idle hop or raised ears included: a little lower
    -- sits just over the head as it usually stands)
    actors[#actors + 1] = MoodFx.actor(self.moodKind, self.moodAge or 0, x, top + 3, feetY + 1, math.min(1, (self.moodAge or 0) / 10))
  end
  if self.sweatAge and sr and (sr.recall or 1) >= 0.5 and sr.headLift then
    local height = sr:headLift() or CELL
    local squashed = height * (1 - (sr.duck or 0))
    local half = drawnWidth(sr) / 2
    -- on the side it faces (its head), touching the top of it
    local facing = (sr.act and sr.act.facing) or npc.facing
    local side = facing == "left" and -1 or 1
    local x = npc.px + CELL / 2 + (sr.pushX or 0) + side * math.floor(half * 0.35) - (side < 0 and 5 or 0)
    local feetY = npc.py + CELL + (sr.pushY or 0) + (sr.duckDy or 0)
    local cfg = Config.FOLLOWER_DUCK
    local fade = math.min(1, ((sr.duck or 0) - cfg.sweatFrom) / 0.08)
    -- the harder it is squashed, the more it sweats (1 .. sweatMax drops, faster)
    local intensity = ((sr.duck or 0) - cfg.sweatFrom) / math.max(0.01, (1 - cfg.minScale) - cfg.sweatFrom)
    -- the other drops on the other side of its head (toward its middle when it faces away)
    local span = side * -math.max(8, math.floor(math.min(half, 24) * 0.7))
    local drops = SweatDrop.drops(self.sweatAge, intensity, cfg.sweatMax, span)
    actors[#actors + 1] = SweatDrop.actor(drops, x, feetY - squashed + 3, feetY + 1, 1, fade)
  end
  -- the grass goes on the tiles under the sprite's real feet: it is spaced away
  -- from its own tile (and a scene may slide it), and a big one is wider than a tile
  local r = self.renderer
  if r and (r.recall or 1) < 0.5 then return end -- inside the player: no grass
  local act = r and r.act
  local offX = (r and r.pushX or 0) + (act and act.dx or 0)
  local offY = (r and r.pushY or 0) + (act and act.dy or 0)
  local width, ground = CELL, CELL -- the ground point's depth in the tile
  if r and r.isPmd then
    local PmdRenderer = V.require("pmd_renderer")
    width = PmdRenderer.contentSize(r.info, r:hdScale())
    ground = PmdRenderer.groundOf(r.info and r.info.walk, PmdRenderer.scaleOf(r.info))
  elseif r and r.frameWidth then
    width = r:visualWidth() or CELL
  end
  local npx, npy = npc.px or npc.cellX * CELL, npc.py or npc.cellY * CELL
  GrassCover.appendFeet(actors, npx + CELL / 2 + offX, npy + ground + offY,
    width * 0.6, npy, npc.elevation, 0)

end

return FollowerAdapter
