-- Run: lua tests/follower_adapter_unit_test.lua
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

local fakeEngine = {}
local modules = {}
local optionStore = { follower = true }
local fakeImageWidth = 48 -- wide by default; set nil to simulate no loaded art
local mod = {
  options = { get = function(_, k) return optionStore[k] end },
  read = function(_, rel)
    local f = io.open(rel, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
  end,
  assets = {
    image = function(_, _path)
      if fakeImageWidth == nil then return nil end
      return { getDimensions = function() return fakeImageWidth, 864 end }
    end,
  },
}
local V = { path = "." }
function V.require(name)
  if modules[name] ~= nil then return modules[name] end
  if name == "engine_patch" then
    modules[name] = fakeEngine
    return fakeEngine
  end
  local chunk = assert(loadfile("lib/" .. name .. ".lua"))
  local value = chunk(V)
  modules[name] = value
  return value
end

local npc = nil
fakeEngine.followerCurrent = function() return npc end
fakeEngine.leadPartySpecies = function() return 999 end
fakeEngine.nationalFor = function(id) if id == 999 then return 252 end return nil end
fakeEngine.isWater = function() return false end
fakeEngine.playerIsRunning = function() return false end
fakeEngine.isGrass = function() return false end
fakeEngine.grassSheet = function() return nil end

local FollowerAdapter = V.require("follower_adapter")
-- these tests are about the Walk <-> Idle switch itself: no grace period (see the linger tests in pmd_renderer_unit_test.lua)
V.require("config").PMD_WALK_LINGER = 0
local fa = FollowerAdapter.new(mod)

-- ------- shouldSpawn: always (there is no Follower option; the party menu picks who is out)
eq(fa:shouldSpawn(), true, "shouldSpawn is always true")
optionStore.follower = false
eq(fa:shouldSpawn(), true, "...even with a stale saved Follower value")
optionStore.follower = true

-- ------- tick() with no follower spawned does nothing
fa:tick()
eq(fa.renderer, nil, "no renderer built when no follower is spawned")

-- ------- tick() with a follower spawned sets npc.sprite to a renderer
-- for the current party lead's national dex
npc = { sprite = nil }
fa:tick()
check(npc.sprite ~= nil, "npc.sprite is set once a follower exists")
check(fa.renderer == npc.sprite, "FollowerAdapter tracks the renderer it installed")
eq(fa.renderer.dex, 252, "renderer uses the party lead's NATIONAL dex, not the internal id")

-- ------- tick() does not rebuild the renderer every call for the same lead
local same = npc.sprite
fa:tick()
check(npc.sprite == same, "same lead species -> renderer is not rebuilt")

-- ------- a lead species change rebuilds the renderer
fakeEngine.leadPartySpecies = function() return 1 end
fakeEngine.nationalFor = function(id) if id == 1 then return 1 end if id == 999 then return 252 end return nil end
fa:tick()
check(npc.sprite ~= same, "a new lead species rebuilds the renderer")
eq(fa.renderer.dex, 1, "renderer now uses the new lead's national dex")

-- ------- a Sprite Style change rebuilds the renderer even with the same
-- lead species, and takes effect without waiting for a species change
npc = { sprite = nil }
fakeEngine.leadPartySpecies = function() return 999 end
fakeEngine.nationalFor = function(id) if id == 999 then return 252 end return nil end
-- a view of the mod with PMD art (a fake one-species index; hermetic: a dev
-- checkout may or may not have a real bake on disk)
local EARLY_INDEX = [[{"version":1,"dex":{"252":{
  "walk":{"cw":30,"ch":26,"cols":4,"durations":[6,10,6,10],"ax":15.5,"ay":19.5,"shiny":false},
  "idle":{"cw":29,"ch":31,"cols":3,"durations":[40,4,2],"ax":15.5,"ay":25.5,"shiny":false}}}}]]
local function withPmd(base)
  return setmetatable({
    read = function(self, rel)
      if rel == "assets/pmd/index.json" then return EARLY_INDEX end
      return base.read(self, rel)
    end,
  }, { __index = base })
end
optionStore.sprite_style = "pokemmo"
fa = FollowerAdapter.new(withPmd(mod))
fa:tick()
eq(fa.renderer.style, "pokemmo", "renderer starts in the HGSS / PokeMMO style")
local beforeStyleSwitch = npc.sprite
optionStore.sprite_style = "pmd"
fa:tick()
check(npc.sprite ~= beforeStyleSwitch, "a style change rebuilds the renderer, same lead species")
check(fa.renderer.isPmd == true, "renderer now uses the new (PMDCollab) style")
eq(fa.renderer.dex, 252, "dex is unchanged by a pure style switch")
optionStore.sprite_style = "pokemmo" -- back to HGSS / PokeMMO for the pose tests below
fa:tick()
check(not fa.renderer.isPmd, "switching back rebuilds the HGSS / PokeMMO renderer")

-- ------- pose: not moving -> stand, and A/B alternates per step (edge, not
-- per tick), walking vs running picked by EnginePatch.playerIsRunning()
local ActorRenderer = V.require("actor_renderer")
npc = { sprite = nil, moving = false, cellX = 0, cellY = 0 }
fa = FollowerAdapter.new(mod)
fa:tick()
eq(fa.renderer.poseOverride, ActorRenderer.POSE_STAND, "not moving -> stand pose")

npc.moving = true
fa:tick()
local firstWalkPose = fa.renderer.poseOverride
check(firstWalkPose == ActorRenderer.POSE_WALK_A or firstWalkPose == ActorRenderer.POSE_WALK_B,
  "moving, not running -> a walk pose")

fa:tick() -- still moving, SAME step (no edge) -- parity must not flip
eq(fa.renderer.poseOverride, firstWalkPose, "pose does not alternate mid-step, only on a new step")

npc.moving = false
fa:tick()
npc.moving = true
fa:tick() -- a NEW step (edge) -- parity flips
check(fa.renderer.poseOverride ~= firstWalkPose, "a new step alternates walkA/walkB")

fakeEngine.playerIsRunning = function() return true end
npc.moving = false
fa:tick()
npc.moving = true
fa:tick()
local runPose = fa.renderer.poseOverride
check(runPose == ActorRenderer.POSE_RUN_A or runPose == ActorRenderer.POSE_RUN_B,
  "moving while the player is running -> a run pose")
fakeEngine.playerIsRunning = function() return false end

-- ------- presentation: follows EnginePatch.isWater(npc.cellX, npc.cellY)
eq(fa.renderer.presentation, "land", "land presentation when not over water")
fakeEngine.isWater = function() return true end
fa:tick()
eq(fa.renderer.presentation, "swimming", "water presentation defaults to swimming")
fakeEngine.isWater = function() return false end

-- ------- collectActors appends the "sinking into grass" overlay
-- (lib/grass_cover.lua) for the follower's CURRENT cell, standing in
-- grass, without touching the follower's own sprite (pushed separately by
-- the engine itself, not by this module -- see FollowerAdapter:collectActors).
npc.cellX, npc.cellY, npc.py, npc.elevation = 2, 3, 3 * 16, 3
fakeEngine.isGrass = function() return true end
fakeEngine.grassSheet = function() return { image = "fake_image", quadsFront = { [4] = "fake_quad" } } end
local followerActors = {}
fa:collectActors(followerActors)
eq(#followerActors, 1, "collectActors appends exactly one grass overlay for the follower")
eq(followerActors[1].kind, "field_effect_wild_grass", "the appended actor is the grass overlay")
fakeEngine.isGrass = function() return false end
fakeEngine.grassSheet = function() return nil end

-- collectActors on a hidden follower appends nothing.
npc.hidden = true
local hiddenActors = {}
fa:collectActors(hiddenActors)
eq(#hiddenActors, 0, "a hidden follower gets no grass overlay")
npc.hidden = nil

-- collectActors with no follower spawned appends nothing, never throws.
local savedNpc = npc
npc = nil
local noFollowerActors = {}
fa:collectActors(noFollowerActors)
eq(#noFollowerActors, 0, "no follower spawned -> no grass overlay, no error")
npc = savedNpc

-- ------- "spacing out" a large (True Size) follower: lib/actor_renderer.lua's
-- largePushback gets sized from the renderer's own loaded art width, gated
-- on STYLE_POKEMMO (lib/actor_renderer.lua's frameWidth/behindOffset handle
-- the actual draw-time math; this just checks FollowerAdapter computes and
-- assigns the right value each tick).
fakeImageWidth = 48 -- wider than one tile (CELL=16): (48-16)/2 = 16
optionStore.sprite_style = "pokemmo"
fa = FollowerAdapter.new(mod)
fa:tick()
eq(fa.renderer.largePushback, 16, "a wide True Size sprite gets a nonzero pushback")

-- A True Size sprite no wider than one tile gets no pushback.
fakeImageWidth = 16
optionStore.sprite_style = "pokemmo"
fa = FollowerAdapter.new(mod)
fa:tick()
eq(fa.renderer.largePushback, 0, "a one-tile-wide True Size sprite gets no pushback")

-- Turning glides: the applied offset eases toward the new facing's target
-- (a full 180-degree swing = 2 * pushback = 32px over 16 ticks) instead of
-- flipping in one tick.
fakeImageWidth = 48
optionStore.sprite_style = "pokemmo"
fa = FollowerAdapter.new(mod)
npc.facing = "down"
fa:tick()
eq(fa.renderer.pushY, -16, "first tick snaps to the facing's offset (no glide from nothing)")
npc.facing = "up"
fa:tick()
eq(fa.renderer.pushY, -14, "a turn moves the offset by one eased step, not all 32px")
for _ = 1, 15 do fa:tick() end
eq(fa.renderer.pushY, 16, "the offset reaches the new target after one step's worth of ticks")
eq(fa.renderer.pushX, 0, "the untouched axis stays put")
fakeImageWidth = 16 -- fits in one tile: nothing to push back
fa = FollowerAdapter.new(mod)
fa:tick()
check(fa.renderer.pushX == nil and fa.renderer.pushY == nil, "no pushback -> no eased offset (draw falls back)")

-- No art loaded yet (frameWidth nil) -> no pushback, never throws.
fakeImageWidth = nil
fa = FollowerAdapter.new(mod)
fa:tick()
eq(fa.renderer.largePushback, 0, "no loaded art -> no pushback, no error")
fakeImageWidth = 48 -- restore for safety

-- ------- a floating/flying lead flaps slowly while standing still; a ground
-- lead stays on the stand pose; moving keeps the walk pose either way
local SS = V.require("sprite_source")
local realIsFloater = SS.isFloater
SS.isFloater = function() return true end
npc = { sprite = nil, moving = false }
fa = FollowerAdapter.new(mod)
local seen = {}
for _ = 1, 100 do fa:tick() seen[fa.renderer.poseOverride] = true end
check(seen.walkA and seen.walkB and seen.stand, "idle floater cycles walkA/stand/walkB")
npc.moving = true
fa:tick()
check(fa.renderer.poseOverride == "walkA" or fa.renderer.poseOverride == "walkB", "a moving floater uses the real walk pose")
SS.isFloater = function() return false end
npc = { sprite = nil, moving = false }
fa = FollowerAdapter.new(mod)
for _ = 1, 50 do fa:tick() end
eq(fa.renderer.poseOverride, "stand", "a ground lead stays on stand while idle")
SS.isFloater = realIsFloater

-- ------- PMDCollab style: the follower's renderer animates itself (Walk
-- while stepping, Idle while standing) and skips the pose/pushback logic
local PMD_INDEX = [[{"version":1,"dex":{"252":{
  "walk":{"cw":30,"ch":26,"cols":4,"durations":[6,10,6,10],"ax":15.5,"ay":19.5,"shiny":false},
  "idle":{"cw":29,"ch":31,"cols":3,"durations":[40,4,2],"ax":15.5,"ay":25.5,"shiny":false}}}}]]
local pmdMod = {
  id = "wilds_of_hoenn", options = mod.options,
  read = function(_, rel) if rel == "assets/pmd/index.json" then return PMD_INDEX end return mod.read(_, rel) end,
}
V.mod = pmdMod
optionStore.sprite_style = "pmd"
npc = { sprite = nil, moving = false, cellX = 0, cellY = 0, facing = "down" }
fa = FollowerAdapter.new(pmdMod)
fa:tick()
check(fa.renderer and fa.renderer.isPmd, "pmd style builds a PmdRenderer for the lead")
eq(npc.sprite, fa.renderer, "and hands it to the engine's follower npc")
for _ = 1, 5 do fa:tick() end
eq(fa.renderer.anim, "idle", "a standing follower plays Idle")
-- the follower rests on Idle's first frame for the 10 s delay before the
-- loop starts, so the clock is still held at 0 here
eq(fa.renderer.clock, 0, "its Idle loop is held during the idle delay")
check(fa.renderer.idleHold > 0 and fa.renderer.idleHold < V.require("config").PMD_FOLLOWER_IDLE_DELAY,
  "and the delay counts down each tick")
for _ = 1, V.require("config").PMD_FOLLOWER_IDLE_DELAY do fa:tick() end
check(fa.renderer.clock > 0 and fa.renderer.clock < 5, "once it is over the Idle loop plays, slowly")
npc.moving = true
fa:tick()
eq(fa.renderer.anim, "walk", "a stepping follower plays Walk")
eq(fa.renderer.poseOverride, nil, "no ActorRenderer pose is pushed onto it")
npc.moving = false
fa:tick()
eq(fa.renderer.anim, "idle", "and returns to Idle")
-- spacing: kept behind the player, eased on a turn; idle starts after a delay
npc = { sprite = nil, moving = false, cellX = 0, cellY = 0, facing = "down" }
fa = FollowerAdapter.new(pmdMod)
fa:tick()
local Cfg = V.require("config")
eq(fa.renderer.idleDelay, Cfg.PMD_FOLLOWER_IDLE_DELAY, "the follower's PMD renderer gets the idle delay")
eq(Cfg.PMD_FOLLOWER_IDLE_DELAY, 300, "the idle delay is 5 seconds of ticks")
eq(fa.renderer.idleSpeed, 0.5, "and the follower's Idle plays at 50% speed")
-- PMD_INDEX walk cell is 30x26; content = cell - 4px of gutter. Facing
-- up/down uses the HEIGHT (22), left/right the width (26).
local expect = math.max(0, (22 - 16) / 2) * Cfg.PMD_FOLLOWER_DOWN_OVERHANG + Cfg.PMD_FOLLOWER_GAP_DOWN
eq(fa.renderer.pushY, -expect, "facing down: pushed back (up) by overhang + gap")
eq(fa.renderer.pushX, 0, "and not sideways")
npc.facing = "up"
fa:tick()
check(fa.renderer.pushY > -expect and fa.renderer.pushY < expect, "a turn eases the offset instead of snapping")
for _ = 1, 40 do fa:tick() end
eq(fa.renderer.pushY, math.max(0, (22 - 16) / 2) + Cfg.PMD_FOLLOWER_GAP, "settles on the new side (facing up -> pushed down)")
npc.facing = "left"
for _ = 1, 40 do fa:tick() end
eq(fa.renderer.pushX, math.max(0, (26 - 16) / 2) + Cfg.PMD_FOLLOWER_GAP, "left/right uses the sprite's width")
optionStore.sprite_style = "pokemmo"
V.mod = mod

-- ------- PMDCollab recall: no swim art, so while the player surfs the follower
-- shrinks into them and grows back out on land
do
  local surf = { surfing = false, dismounting = false }
  local water = {}
  local pixel = { 40, 48 }
  local realIsWater, realSurf, realPixel = fakeEngine.isWater, fakeEngine.playerSurfState, fakeEngine.playerPixel
  fakeEngine.isWater = function(x, y) return water[x .. "," .. y] == true end
  fakeEngine.playerSurfState = function() return surf end
  fakeEngine.playerPixel = function() return pixel[1], pixel[2] end
  local Cfg = V.require("config")
  local T = Cfg.PMD_RECALL_TICKS

  optionStore.sprite_style = "pmd"
  V.mod = pmdMod
  npc = { sprite = nil, moving = false, cellX = 3, cellY = 3, facing = "down" }
  local fr = FollowerAdapter.new(pmdMod)
  fr:tick()
  eq(fr.renderer.recall, 1, "on land the follower starts fully out")
  check(not fr:isRecalled(), "...and is not recalled")
  eq(fr.renderer.recallX, 40, "the recall knows where the player is (x)")
  eq(fr.renderer.recallY, 48, "...(y)")

  -- the player hops onto the water: it shrinks in over PMD_RECALL_TICKS
  surf.surfing = true
  fr:tick()
  check(fr.renderer.recall < 1 and fr.renderer.recall > 0, "surfing starts shrinking it (not a snap)")
  for _ = 1, T do fr:tick() end
  eq(fr.renderer.recall, 0, "fully inside the player after the recall time")
  check(fr:isRecalled(), "isRecalled is true once it is inside")

  -- the player steps onto land (dismounting) but the follower still trails over the water
  surf.surfing = false
  water["3,3"] = true
  for _ = 1, T do fr:tick() end
  eq(fr.renderer.recall, 0, "it stays in while the follower itself is still over water")
  water["3,3"] = false
  water["4,3"] = true
  npc.moving, npc.targetX, npc.targetY = true, 4, 3
  fr:tick()
  eq(fr.renderer.recall, 0, "...or is still stepping onto a water tile")
  npc.moving, npc.targetX, npc.targetY = false, nil, nil
  water["4,3"] = false

  -- on land at last: it grows back out over PMD_RECALL_TICKS
  fr:tick()
  check(fr.renderer.recall > 0 and fr.renderer.recall < 1, "back on land it starts growing out (not a snap)")
  for _ = 1, T do fr:tick() end
  eq(fr.renderer.recall, 1, "fully out again after the grow time")
  check(not fr:isRecalled(), "no longer recalled")
  local before = fr.renderer.recall
  fr:tick()
  eq(fr.renderer.recall, before, "and it stays out")

  -- dismounting counts as land: the grow begins once the follower is off the water
  surf.surfing, surf.dismounting = true, true
  fr.wasRecalled = false
  fr:tick()
  eq(fr.renderer.recall, 1, "a dismount in progress does not recall it")
  surf.surfing, surf.dismounting = false, false

  -- a freshly built sprite appears in the right state, no shrink animation
  surf.surfing = true
  npc = { sprite = nil, moving = false, cellX = 3, cellY = 3, facing = "down" }
  local fr2 = FollowerAdapter.new(pmdMod)
  fr2:tick()
  eq(fr2.renderer.recall, 0, "entering a map while surfing: the follower starts inside the player")
  surf.surfing = false

  -- an engine without the helpers is simply never recalled (no error)
  fakeEngine.playerSurfState, fakeEngine.playerPixel = nil, nil
  npc = { sprite = nil, moving = false, cellX = 3, cellY = 3, facing = "down" }
  local fr3 = FollowerAdapter.new(pmdMod)
  check(pcall(function() fr3:tick() fr3:tick() end), "no surf helpers: ticking never errors")
  eq(fr3.renderer.recall, 1, "...and the follower stays out")

  -- the ActorRenderer styles are untouched by all of it
  optionStore.sprite_style = "pokemmo"
  fakeEngine.playerSurfState = function() return { surfing = true, dismounting = false } end
  npc = { sprite = nil, moving = false, cellX = 3, cellY = 3, facing = "down" }
  local fr4 = FollowerAdapter.new(pmdMod)
  fr4:tick()
  check(not fr4.renderer.isPmd and (fr4.renderer.recall or 1) == 1 and not fr4:isRecalled(), "HGSS / PokeMMO keeps its swim art: never recalled")

  fakeEngine.isWater, fakeEngine.playerSurfState, fakeEngine.playerPixel = realIsWater, realSurf, realPixel
  optionStore.sprite_style = "pokemmo"
  V.mod = mod
end

-- ------- the follower vanishing (map transition) clears the tracked state
npc = nil
fa:tick()
eq(fa.leadSpecies, nil, "leadSpecies cleared once the follower is gone")

-- ------- scenes (lib/follower_actions.lua): the adapter drives them onto the renderer
do
  local cries = {}
  local ahead = 2
  fakeEngine.playerFacing = function() return "down" end
  fakeEngine.freeCellsAhead = function(_x, _y, _dir, _max) return ahead end
  fakeEngine.playCry = function(species) cries[#cries + 1] = species return true end
  fakeEngine.cryFinished = function() return true end
  optionStore.sprite_style = "pmd"
  npc = { sprite = nil, moving = false, cellX = 4, cellY = 4, px = 64, py = 64, facing = "down", elevation = 3 }
  local fs = FollowerAdapter.new(pmdMod)
  fs:tick()

  check(fs:startAction("play") ~= nil, "startAction returns the scene")
  check(fs:actionActive(), "...and it is active")
  local actors = {}
  fs:tick()
  check(fs.renderer.act ~= nil, "a running scene hands its offset to the renderer")
  fs:collectActors(actors)
  local ball
  for _, a in ipairs(actors) do if a.kind == "follower_action_ball" then ball = a end end
  check(ball ~= nil, "the thrown ball is collected as a field actor")
  eq(npc.moving, false, "the engine's own follower state is never touched")
  eq(npc.px, 64, "...nor its position")

  local sawWalk, sawSpin, maxDy = false, {}, 0
  for _ = 1, 400 do
    fs:tick()
    if fs.renderer.anim == "walk" then sawWalk = true end
    if fs.renderer.act then
      maxDy = math.max(maxDy, fs.renderer.act.dy or 0)
      if fs.renderer.act.facing then sawSpin[fs.renderer.act.facing] = true end
    end
    if not fs:actionActive() then break end
  end
  check(sawWalk, "the PMD follower plays Walk while it runs and spins")
  eq(maxDy, 32, "it runs the free distance (2 cells) down the throw line")
  check(sawSpin.down and sawSpin.left and sawSpin.up and sawSpin.right, "it faces all four ways while spinning")
  check(not fs:actionActive(), "the scene ends by itself")
  eq(fs.renderer.act, nil, "...and the renderer's offset is cleared")
  actors = {}
  fs:collectActors(actors)
  check(#actors == 0 or actors[1].kind ~= "follower_action_ball", "no ball once the scene is over")

  -- pet: quick idle (hold skipped, sped up), then a cry
  fs:startAction("pet")
  fs.renderer.idleHold = 300
  fs:tick()
  eq(fs.renderer.idleHold, 0, "pet skips the follower's idle-delay hold")
  eq(fs.renderer.idleSpeed, V.require("config").ACTIONS.pet.idleSpeed, "...and plays Idle at the pet speed")
  for _ = 1, 400 do fs:tick() if not fs:actionActive() then break end end
  eq(#cries, 1, "pet plays the cry once")
  eq(cries[1], 999, "...with the lead's own (internal) species id")
  fs:tick()
  eq(fs.renderer.idleSpeed, V.require("config").PMD_FOLLOWER_IDLE_SPEED, "idle speed returns to normal afterwards")

  -- talk: two cries
  cries = {}
  fs:startAction("talk")
  for _ = 1, 600 do fs:tick() if not fs:actionActive() then break end end
  eq(#cries, 2, "talk plays the cry twice")

  -- cancel clears everything at once
  fs:startAction("play")
  fs:tick()
  fs:cancelAction()
  check(not fs:actionActive() and fs.renderer.act == nil, "cancelAction stops a scene and clears the offset")

  -- no follower: nothing to animate
  local keep = npc
  npc = nil
  check(fs:startAction("play") == nil, "no follower -> no scene")
  npc = keep

  -- HGSS / PokeMMO: walks in place with the A/B pose; pet bounces
  optionStore.sprite_style = "pokemmo"
  npc = { sprite = nil, moving = false, cellX = 4, cellY = 4, px = 64, py = 64, facing = "down", elevation = 3 }
  local fh = FollowerAdapter.new(mod)
  fh:tick()
  fh:startAction("play")
  local poses = {}
  for _ = 1, 120 do
    fh:tick()
    if fh.renderer.poseOverride then poses[fh.renderer.poseOverride] = true end
  end
  check(poses[V.require("actor_renderer").POSE_WALK_A] and poses[V.require("actor_renderer").POSE_WALK_B],
    "HGSS walks in place alternating the A and B poses during Play")
  fh:cancelAction()
  fh:startAction("pet")
  local bounced = {}
  for _ = 1, 40 do
    fh:tick()
    bounced[fh.renderer.poseOverride] = true
  end
  check(bounced[V.require("actor_renderer").POSE_WALK_A] or bounced[V.require("actor_renderer").POSE_WALK_B],
    "HGSS Pet bounces through the idle-flap poses")
  optionStore.sprite_style = "pokemmo"
end

-- ------- a companion with a role: the role's behaviour drives the follower
do
  fakeEngine.partyMons = function() return {} end
  fakeEngine.playerCell = function() return { x = 5, y = 5, moving = false } end
  local role = "forage"
  local companion = { resolve = function() return { species = 999 }, role end }
  local resets, last, popupOn = 0, nil, false
  local behavior = {
    step = function(_, env)
      last = env
      if not env.still then return nil end
      local s = { dx = 16, dy = 0, facing = "right", moving = true }
      if popupOn then s.popup = { text = "Found Potion!", age = 3 } end
      return s
    end,
    isBusy = function() return last ~= nil and last.still end,
    reset = function() resets = resets + 1 end,
  }
  optionStore.sprite_style = "pmd"
  npc = { sprite = nil, moving = false, cellX = 4, cellY = 4, px = 64, py = 64, facing = "down", elevation = 3 }
  local fb = FollowerAdapter.new(pmdMod, companion)
  fb.behaviors.forage = behavior
  fb:tick()
  eq(fb.role, "forage", "the companion's role is read each tick")
  eq(fb.leadSpecies, 999, "...and its species decides the sprite")
  eq(last.fx, 4, "the behaviour is told where the follower stands")
  eq(last.px, 5, "...and where the player is")
  check(last.still, "...and whether everything is standing still")
  eq(fb.renderer.act.dx, 16, "its offset reaches the renderer")
  eq(fb.renderer.act.facing, "right", "...and its facing")
  eq(fb.renderer.anim, "walk", "a moving behaviour plays Walk")
  check(fb:isBusy(), "the follower is busy while the behaviour is away")

  popupOn = true
  fb:tick()
  local actors = {}
  fb:collectActors(actors)
  local popup
  for _, a in ipairs(actors) do if a.kind == "follower_popup" then popup = a end end
  check(popup ~= nil, "a find's label becomes a field actor")
  eq(popup.x, 64 + 16 + 8, "...above the follower's offset position")
  popupOn = false

  -- the behaviour is told whether foraging is allowed here (routes / caves only)
  fakeEngine.forageAllowed = function(set) fakeEngine.allowedAsked = set return false end
  fb:tick()
  eq(last.forageOk, false, "forageOk reaches the behaviour (false in a town / building / on water)")
  check(fakeEngine.allowedAsked and fakeEngine.allowedAsked[3] and fakeEngine.allowedAsked[4],
    "...asked with the routes-and-caves set from the config")
  fakeEngine.forageAllowed = function() return true end
  fb:tick()
  eq(last.forageOk, true, "...and true on a route")
  fakeEngine.forageAllowed = nil

  -- a map change: behaviours with a mapChanged hook keep their state, others reset
  local kept, wiped = 0, 0
  fb.behaviors.forage = { step = behavior.step, isBusy = behavior.isBusy,
    mapChanged = function() kept = kept + 1 end, reset = function() wiped = wiped + 1 end }
  fb:mapChanged()
  eq(kept, 1, "a map change calls the behaviour's mapChanged ...")
  eq(wiped, 0, "...instead of wiping it")
  fb.behaviors.forage = behavior
  local before = resets
  fb:mapChanged()
  eq(resets, before + 1, "a behaviour without one is reset")

  npc.moving = true
  fakeEngine.playerCell = function() return { x = 5, y = 5, moving = true } end
  fb:tick()
  check(not last.still, "a walking player/follower is reported as not still")
  eq(fb.renderer.act, nil, "a behaviour that returns nothing clears the offset")

  role = "follow"
  npc.moving = false
  fb:tick()
  check(resets >= 1, "changing role resets the old behaviour")
  fb:resetBehaviors()
  eq(fb.renderer.act, nil, "resetBehaviors clears the offset")

  -- a scene wins over a behaviour
  role = "forage"
  fakeEngine.playerCell = function() return { x = 5, y = 5, moving = false } end
  fb:tick()
  fakeEngine.playerFacing = function() return "down" end
  fakeEngine.freeCellsAhead = function() return 1 end
  fakeEngine.playCry = function() return true end
  fakeEngine.cryFinished = function() return true end
  fb:startAction("talk")
  fb:tick()
  check(fb:isBusy(), "a scene counts as busy too")
  fb:cancelAction()
  optionStore.sprite_style = "pokemmo"
end

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("follower_adapter_unit_test: all passed")
