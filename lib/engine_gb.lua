-- The Gen 1 / Gen 2 engine layer: what lib/engine_patch.lua is for Gen 3, for Red / Blue /
-- Yellow (src/world/OverworldController.lua) and Gold / Silver / Crystal
-- (src/world/gen2/World.lua). lib/engine_patch.lua hands this module out in its place on a
-- Gen 1 / Gen 2 boot, so the rest of the mod (SpawnManager, BattleTrigger, FollowerAdapter,
-- the renderers) runs unchanged on every generation.
--
-- It answers the same API. The core is implemented: the player, the view, terrain and
-- encounters, the field's busy state, holding the player, wild battles, the follower.
-- What a Gen 1 / Gen 2 boot does not have yet is either a stub that answers "nothing"
-- (STUBS below) or left out on purpose: names the mod tests for with
-- `EnginePatch.x and EnginePatch.x()` (screenBusy, canStartInteraction, reachStart,
-- roamerNow ...) take their "no engine support" path when absent. EngineGb.supports()
-- says which optional systems main.lua builds here.
--
-- Engine seams (each probed first, reversible, pcall-guarded -- the engine_patch rules):
--   draw  -- OverworldState.drawWorld / World.drawPeople: for the duration of that call
--            one proxy per actor this mod collects is appended to the list the engine
--            y-sorts and draws (ow.entities / world.npcs) and removed again afterwards,
--            so our Pokemon depth-sort with the player and the NPCs (and get the
--            engine's own grass over their feet) while collision, NPC movement, trainer
--            sight and talking never see them.
--   tick  -- OverworldState.update / World.step: hooks.followerTick after the frame.
--   input -- OverworldState.handleInput / World.pollInput: no step starts while a
--            contact holds the player (EngineGb.lockField).
--   collision -- the public `movement.collision` hook, wired in main.lua through
--            EngineGb.collisionVerdict.
local V = ...
local GbColor = V.require("gb_color")

local EngineGb = { isGb = true }

local moduleCache = {}
local function loadModule(path)
  local cached = moduleCache[path]
  if cached then return cached end
  local ok, mod = pcall(require, path)
  if not ok then return nil, mod end
  moduleCache[path] = mod or nil
  return mod
end
EngineGb._loadModule = loadModule

function EngineGb.cacheModules(enabled)
  if not enabled then moduleCache = {} end
end

--- 1 or 2 on a Gen 1 / Gen 2 boot, else nil.
function EngineGb.generation()
  local GV = loadModule("src.core.GameVersion")
  if not (GV and type(GV.generation) == "function") then return nil end
  local ok, g = pcall(GV.generation)
  if ok and (g == 1 or g == 2) then return g end
  return nil
end

local adapters = {}
--- The running generation's adapter (lib/gb/gen1.lua | lib/gb/gen2.lua), or nil.
function EngineGb.adapter()
  local g = EngineGb.generation()
  if not g then return nil end
  local a = adapters[g]
  if not a then
    a = V.require(g == 1 and "gb/gen1" or "gb/gen2")
    a.init(loadModule)
    adapters[g] = a
  end
  return a
end
local A = EngineGb.adapter

-- the live world: the OverworldState / World the last wrapped frame ran on
EngineGb._world = nil
function EngineGb.world()
  return EngineGb._world
end

--- map.entered (main.lua): the world that just loaded `map`, adopted before anything reads
--- the map -- the wrapped frame that would remember it has not run yet (a boot, a save
--- loaded, a fresh overworld state). `game` is the live game (mod.world.game).
function EngineGb.noteMap(game, map)
  local a = A()
  if not (a and a.liveWorld) then return end
  local ok, w = pcall(a.liveWorld, game, map)
  if ok and w then EngineGb._world = w end
end

-- ------------------------------------------------------------------ boot

--- "gen1" | "gen2" | nil.
function EngineGb.layoutName()
  local a = A()
  return a and a.layout or nil
end

function EngineGb.isRse() return false end

function EngineGb.isSupported()
  return EngineGb.layoutName() ~= nil
end

--- The optional systems main.lua may build on this generation (the core -- spawns,
--- battles, the follower -- always runs): the adapter's FEATURES set (lib/gb/gen1.lua;
--- Gen 2 has none yet).
function EngineGb.supports(feature)
  local a = A()
  local f = a and a.FEATURES
  return f ~= nil and f[feature] == true
end

function EngineGb.probe()
  local a = A()
  if not a then return false, { "not a Gen 1 / Gen 2 boot" } end
  local missing = {}
  local function check(list)
    for name, spec in pairs(list) do
      local mod, err = loadModule(spec.mod)
      if not mod then
        missing[#missing + 1] = name .. " (" .. spec.mod .. " did not load: " .. tostring(err) .. ")"
      elseif type(mod[spec.field]) ~= "function" then
        missing[#missing + 1] = name .. " (" .. spec.mod .. "." .. spec.field .. " is "
          .. type(mod[spec.field]) .. ", expected function)"
      end
    end
  end
  check(a.TARGETS)
  check(a.READONLY)
  return #missing == 0, missing
end

-- ------------------------------------------------------------------ drawing

local CELL = 16

-- the canvas rect a true-colour mark covers around an actor drawn at world (x, y)
local MARK_W, MARK_UP, MARK_H = 64, 52, 68

-- draws one collected actor the way Gen 3's field_view does (field_view.lua:574)
local function drawActor(a, camX, camY)
  if a.draw then
    a:draw(camX, camY)
  elseif a.renderer then
    a.renderer:draw(a.x, a.y, camX, camY, a.facing, a.walkPhase or 0, false)
  end
end

-- a pooled proxy's draw: Gen 1 calls e:draw(camX, camY) inside the world canvas
local function drawGen1(p, camX, camY)
  local a = p.actor
  if not a then return end
  local lift = GbColor.FOOT_LIFT
  local x, y = (a.x or 0) - camX, (a.y or 0) - camY
  GbColor.draw(p.colorMode, p.paletteFx, function() drawActor(a, camX, camY + lift) end,
    math.floor(x + CELL / 2 - MARK_W / 2), math.floor(y - MARK_UP), MARK_W, MARK_H)
end

-- Gen 2 calls entity:draw(ox, oy, s, oamRow) (World:drawPersonEntry), ox/oy already the
-- screen offset of the map (camera included). Crystal draws a sprite standing in grass
-- in two halves around the grass ("bottom", grass over the feet, "top"): ours is drawn
-- whole on the "bottom" call so the grass goes over its feet, nothing on "top".
local function drawGen2(p, ox, oy, s, oamRow)
  local a = p.actor
  if not a or oamRow == "top" then return end
  local G = love.graphics
  G.push()
  G.translate(ox or 0, oy or 0)
  G.scale(s or 1, s or 1)
  local ok, err = pcall(drawActor, a, 0, GbColor.FOOT_LIFT)
  G.pop()
  if not ok then error(err, 0) end
end

local pool = {}
local scratch = {}

-- a proxy's pose() for a render pipeline mod (e:pose() -> sprite, px, py, facing, phase,
-- flip, the engine NPC's contract): the voxel sheet of its renderer (lib/voxel_sheets.lua)
local WALKING
local function walkPhase(pose)
  if not WALKING then
    local AR = V.require("actor_renderer")
    WALKING = { [AR.POSE_WALK_A] = 1, [AR.POSE_WALK_B] = 2, [AR.POSE_RUN_A] = 1, [AR.POSE_RUN_B] = 2 }
  end
  local w = WALKING[pose]
  return w and 1 or 0, w == 2
end

local function poseOf(p)
  local a = p.actor
  local phase, flip = walkPhase(a and a.walkPhase)
  return p.sprite, p.px, p.py, p.facing, phase, flip
end

-- the voxel sprite for a renderer (nil without the sheets, or a renderer with no art key)
local function voxelSprite(renderer, mode)
  local sheets = EngineGb.voxelSheets
  if not (sheets and renderer) then return nil end
  local ok, sprite = pcall(sheets.spriteFor, sheets, renderer, mode == "luma")
  return ok and sprite or nil
end

-- the proxies for this frame's actors (pooled: no garbage per frame). While a render
-- pipeline draws the world (`pipeline`), only the actors drawn by a renderer get one, with
-- the pose() it reads: the rest (emotes, grass tufts, bars) are 2D-only drawings.
local function buildProxies(world, hooks, pipeline)
  local a = A()
  local actors = scratch
  for i = #actors, 1, -1 do actors[i] = nil end
  if not (hooks and hooks.collectActors) then return 0 end
  local camX, camY = a.camera(world)
  hooks.collectActors(actors, camX or 0, camY or 0)
  local gen = a.generation
  local paletteFx = gen == 1 and loadModule("src.render.PaletteFX") or nil
  local mode = GbColor.mode(gen, paletteFx)
  local map = world and world.map
  local n = 0
  for i = 1, #actors do
    local act = actors[i]
    local sprite = pipeline and not act.draw and voxelSprite(act.renderer, mode) or nil
    if pipeline and not sprite then goto continue end
    n = n + 1
    local p = pool[n]
    if not p then
      p = { _wilds = true, passable = true, def = {}, pose = poseOf }
      pool[n] = p
    end
    p.sprite = sprite
    -- on water: a pipeline cuts it at the waterline (TERRARIUM: `surfing` = in the water)
    local r = act.renderer
    p.surfing = r ~= nil and (r.swimming == true or (r.presentation ~= nil and r.presentation ~= "land"))
    p.actor = act
    p.draw = gen == 1 and drawGen1 or drawGen2
    p.colorMode, p.paletteFx = mode, paletteFx
    p.px = act.x or 0
    -- the engines sort by py: the actor's own sort point
    p.py = act.sortY or act.y or 0
    p.facing = act.facing or "down"
    p.moving = false
    -- the main sprite of a wild Pokemon stands on a cell: the engine covers its feet when
    -- that cell is grass (Gen 1 queueGrass reads cellX/cellY; Gen 2 reads inGrass)
    if act.kind == "wild_mon" then
      local cx, cy = math.floor(((act.x or 0) + CELL / 2) / CELL), math.floor(((act.y or 0) + CELL / 2) / CELL)
      p.cellX, p.cellY = cx, cy
      p.inGrass = map ~= nil and map.isGrassCell ~= nil and map:isGrassCell(cx, cy) == true
    else
      p.cellX, p.cellY, p.inGrass = nil, nil, false
    end
    if pipeline then p.py = act.y or p.py end -- its tile, not its sort point
    ::continue::
  end
  return n
end

-- removes every proxy from an engine list (its order may have been sorted meanwhile)
local function stripProxies(list)
  if not list then return end
  local j = 0
  for i = 1, #list do
    local e = list[i]
    if not (type(e) == "table" and e._wilds) then
      j = j + 1
      list[j] = e
    end
  end
  for i = #list, j + 1, -1 do list[i] = nil end
end
EngineGb._stripProxies = stripProxies

local function listOf(world)
  local a = A()
  if not world then return nil end
  return a.generation == 1 and world.entities or world.npcs
end

--- Is a render pipeline mod drawing the world (src/render/Pipelines.lua)?
function EngineGb.pipelineActive()
  local Pipelines = loadModule("src.render.Pipelines")
  if not (Pipelines and Pipelines.worldPipeline) then return false end
  local ok, id = pcall(Pipelines.worldPipeline)
  return ok and id ~= nil
end

-- ------------------------------------------------------------------ install

local function safeCall(log, label, fn, ...)
  local ok, a, b, c = pcall(fn, ...)
  if not ok then
    if log then log:warn("[wilds_of_hoenn] %s wrapper error (falling back to engine behaviour): %s", label, tostring(a)) end
    return nil
  end
  return a, b, c
end

local holds = {}
local function held() return next(holds) ~= nil end

--- Installs the draw / tick / input wraps. `hooks`: collectActors(actors, camX, camY),
--- followerTick(game). The collision rule is a mod hook (main.lua, collisionVerdict).
function EngineGb.install(hooks, log)
  if EngineGb._installed then return true end
  local ok, missing = EngineGb.probe()
  if not ok then return false, missing end
  local a = A()
  local originals = {}

  -- runs `original(world, ...)` with this frame's proxies in `lists` (the engine lists it
  -- reads), taking them out again whatever happens
  local function withProxies(lists, pipeline, original, world, ...)
    local n = 0
    if lists[1] then
      local okP, count = pcall(buildProxies, world, hooks, pipeline)
      if okP then
        n = count
        for _, list in ipairs(lists) do
          local base = #list
          for i = 1, n do list[base + i] = pool[i] end
        end
      elseif log then
        log:warn("[wilds_of_hoenn] collectActors error: %s", tostring(count))
      end
    end
    local okD, r1, r2, r3 = pcall(original, world, ...)
    if n > 0 then
      for _, list in ipairs(lists) do stripProxies(list) end
      for i = 1, n do pool[i].actor, pool[i].sprite = nil, nil end
    end
    for i = #scratch, 1, -1 do scratch[i] = nil end
    if not okD then error(r1, 0) end
    return r1, r2, r3
  end

  local DrawMod = loadModule(a.TARGETS.draw.mod)
  local drawField = a.TARGETS.draw.field
  originals.draw = DrawMod[drawField]
  DrawMod[drawField] = function(world, ...)
    EngineGb._world = world
    -- a render pipeline mod (3D) draws the world from the entities' own engine sprites
    -- (pose()): our Pokemon then go in as voxel sheets (lib/voxel_sheets.lua). Gen 1 runs
    -- the pipeline inside drawWorld; Gen 2 from World:drawPipeline (below).
    local pipeline = a.generation == 1 and EngineGb.pipelineActive()
    EngineGb._pipeline = pipeline
    return withProxies({ listOf(world) }, pipeline, originals.draw, world, ...)
  end

  -- Gen 2: a pipeline (Stadium2) draws the world in World:drawPipeline, from the same lists
  -- Gold keeps its people in (world.npcs, world.entities). Optional: absent, Gen 2 keeps
  -- the flat path only.
  local pipe = a.PIPELINE
  local PipeMod = pipe and loadModule(pipe.mod)
  if PipeMod and type(PipeMod[pipe.field]) == "function" then
    originals.pipeline = PipeMod[pipe.field]
    PipeMod[pipe.field] = function(world, ...)
      EngineGb._world, EngineGb._pipeline = world, true
      local lists = {}
      if type(world.npcs) == "table" then lists[#lists + 1] = world.npcs end
      if type(world.entities) == "table" and world.entities ~= world.npcs then lists[#lists + 1] = world.entities end
      return withProxies(lists, true, originals.pipeline, world, ...)
    end
  end

  local TickMod = loadModule(a.TARGETS.tick.mod)
  local tickField = a.TARGETS.tick.field
  originals.tick = TickMod[tickField]
  TickMod[tickField] = a.tickWrapper(originals.tick, function(world, game)
    EngineGb._world = world
    if hooks.followerTick then safeCall(log, "followerTick", hooks.followerTick, game) end
  end)

  local InputMod = loadModule(a.TARGETS.input.mod)
  local inputField = a.TARGETS.input.field
  originals.input = InputMod[inputField]
  InputMod[inputField] = a.inputWrapper(originals.input, held)

  -- the A press: the mod's follower menu goes first (hooks.interact true = consumed).
  -- Yellow's own Pikachu talk (a.nativeTalk) passes through untouched.
  if a.TARGETS.interact and hooks.interact then
    local Mod = loadModule(a.TARGETS.interact.mod)
    local field = a.TARGETS.interact.field
    originals.interact = Mod[field]
    Mod[field] = function(world, ...)
      EngineGb._world = world
      local native = a.nativeTalk and select(2, pcall(a.nativeTalk, world)) == true
      if not native then
        local consumed = safeCall(log, "interact", hooks.interact, a.game and a.game() or nil)
        if consumed then return end
      end
      return originals.interact(world, ...)
    end
  end

  -- a dialogue box pauses the overworld state under it (Gen 1 routes update to the top
  -- state only): the mod's tick rides the box's update too, so the interaction's state
  -- machine, the spawns and the ambient life keep moving mid-conversation -- exactly what
  -- Gen 3 does under a Message
  if a.TARGETS.messageTick and hooks.followerTick then
    local Mod = loadModule(a.TARGETS.messageTick.mod)
    local field = a.TARGETS.messageTick.field
    originals.messageTick = Mod[field]
    Mod[field] = function(box, ...)
      local r1, r2 = originals.messageTick(box, ...)
      safeCall(log, "followerTick", hooks.followerTick, a.game and a.game() or nil)
      return r1, r2
    end
  end

  -- the portrait over the dialogue box: after every box draw (TextBox:draw(self))
  if a.TARGETS.messageDraw and hooks.messageDraw then
    local Mod = loadModule(a.TARGETS.messageDraw.mod)
    local field = a.TARGETS.messageDraw.field
    originals.messageDraw = Mod[field]
    Mod[field] = function(box, ...)
      local r1, r2 = originals.messageDraw(box, ...)
      safeCall(log, "messageDraw", hooks.messageDraw)
      return r1, r2
    end
  end

  EngineGb._originals = originals
  EngineGb._installed = true
  return true
end

function EngineGb.uninstall()
  if not EngineGb._installed then return end
  local a = A()
  local o = EngineGb._originals or {}
  if a then
    for key, spec in pairs(a.TARGETS) do
      local M = loadModule(spec.mod)
      if M and o[key] then M[spec.field] = o[key] end
    end
    local pipe = a.PIPELINE
    local P = pipe and loadModule(pipe.mod)
    if P and o.pipeline then P[pipe.field] = o.pipeline end
  end
  EngineGb._originals = {}
  EngineGb._installed = false
  holds = {}
end

--- The `movement.collision` rule (main.lua wraps the hook with it): a wild Pokemon on
--- the cell being entered blocks every mover but the player -- who steps onto it, the
--- contact that starts its battle (lib/battle_trigger.lua) -- and the party follower,
--- which only ever walks where the player walked. While the field is busy a scripted
--- character walks through (a wild Pokemon must never stall a cutscene).
function EngineGb.collisionVerdict(allowed, ctx, entityAt)
  if not allowed or type(ctx) ~= "table" or not entityAt then return allowed end
  local tx, ty = ctx.toX, ctx.toY
  if not (tx and ty) or not entityAt(tx, ty) then return allowed end
  local mover = ctx.mover
  local world = EngineGb.world()
  if mover ~= nil and world ~= nil and mover == world.player then return allowed end
  if type(mover) == "table" and (mover.pikachuFollower or mover.follower) then return allowed end
  if EngineGb.fieldBusy() then return allowed end
  ctx.reason = "entity"
  return false
end

-- ------------------------------------------------------------------ the field

function EngineGb.fieldBusy()
  local a, w = A(), EngineGb._world
  if not (a and w) then return true end
  local ok, busy = pcall(a.busy, w)
  return not ok or busy == true
end

function EngineGb.stepEventsBusy() return false end

function EngineGb.battleActive()
  return EngineGb._battle == true
end

--- main.lua's battle.started / battle.ended events.
function EngineGb.noteBattle(active)
  EngineGb._battle = active and true or false
end

function EngineGb.gameFree()
  return not EngineGb.fieldBusy() and not EngineGb.battleActive()
end

--- Tagged hold on the player's input (EngineGb.install's input wrap).
function EngineGb.lockField(tag)
  holds[tag or "?"] = true
  return true
end

function EngineGb.unlockField(tag)
  holds[tag or "?"] = nil
  return true
end

function EngineGb.isHeld() return held() end

--- The nurse's heal machine (Gen 1 ow.healAnim, Gen 2 world.healAnim): the follower goes
--- into its ball meanwhile.
function EngineGb.healingActive()
  local w = EngineGb._world
  return w ~= nil and w.healAnim ~= nil
end

--- A character walking with the player by script: Gen 2's `follow` (World:startFollow:
--- world.followState = { leader, follower }) with the player one of the pair. Gen 1 has no
--- such command.
--- A character walking with the player, or a cutscene moving someone: the companion keeps
--- out of the way in its ball (lib/follower_adapter.lua inCutscene reads this). Gen 2 =
--- the engine's follow; Gen 1 = scripted moves / the script runner (plain dialogue is
--- neither, so talking to someone leaves the companion out).
function EngineGb.leadingNpc()
  local w = EngineGb._world
  if not w then return false end
  local st = w.followState
  if st and w.player and (st.leader == w.player or st.follower == w.player) then return true end
  local a = A()
  if a and a.generation == 1 then
    if w.scriptMoves and #w.scriptMoves > 0 then return true end
    local runner = w.runner
    if runner and runner.isRunning then
      local ok, running = pcall(runner.isRunning, runner)
      if ok and running then return true end
    end
  end
  return false
end

-- ------------------------------------------------------------------ the player

local function player()
  local w = EngineGb._world
  return w and w.player
end

function EngineGb.playerCell()
  local p = player()
  if not p or type(p.cellX) ~= "number" or type(p.cellY) ~= "number" then return nil end
  return {
    x = p.cellX, y = p.cellY, moving = p.moving == true,
    targetX = p.targetX, targetY = p.targetY,
    facing = type(p.facing) == "string" and p.facing or nil,
  }
end

function EngineGb.playerFacing()
  local p = player()
  local f = p and p.facing
  if f == "up" or f == "down" or f == "left" or f == "right" then return f end
  return nil
end

function EngineGb.playerPixel()
  local p = player()
  if not p or type(p.px) ~= "number" or type(p.py) ~= "number" then return nil end
  return p.px, p.py
end

function EngineGb.playerIsRunning() return false end -- no running in Gen 1 / Gen 2

function EngineGb.playerBiking()
  local a = A()
  return a ~= nil and a.isBiking(EngineGb._world) == true
end

function EngineGb.playerSurfState()
  local a = A()
  return { surfing = a ~= nil and a.isSurfing(EngineGb._world) == true, dismounting = false }
end

function EngineGb.playerElevation() return 3 end

function EngineGb.viewSize()
  local a = A()
  if not a then return 160, 144 end
  return a.viewSize(EngineGb._world)
end

-- ------------------------------------------------------------------ the map

function EngineGb.mapBounds()
  local w = EngineGb._world
  local map = w and w.map
  return tonumber(map and map.widthCells) or 0, tonumber(map and map.heightCells) or 0
end

function EngineGb.terrainAt(x, y)
  local a = A()
  if not a then return nil end
  local ok, t = pcall(a.terrainAt, EngineGb._world, x, y)
  return ok and t or nil
end

function EngineGb.isWater(x, y)
  local w = EngineGb._world
  local map = w and w.map
  if not (map and map.isWaterCell and map.inBounds and map:inBounds(x, y)) then return false end
  return map:isWaterCell(x, y) == true
end

function EngineGb.isGrass(x, y)
  local w = EngineGb._world
  local map = w and w.map
  if not (map and map.isGrassCell) then return false end
  return map:isGrassCell(x, y) == true
end

function EngineGb.isWarpCell(x, y)
  local w = EngineGb._world
  local map = w and w.map
  if not (map and map.warpAtCell) then return false end
  local ok, warp = pcall(map.warpAtCell, map, x, y)
  return ok and warp ~= nil
end

--- Gen 3's map types, as far as this mod reads them: 3 (a route: outdoors) or 4
--- (indoors, a cave). Never 5 (under the sea).
function EngineGb.mapType()
  local a = A()
  if not a then return nil end
  if a.mapTypeOf then
    local ok, mt = pcall(a.mapTypeOf, EngineGb._world)
    if ok and mt then return mt end
  end
  return a.isOutdoor(EngineGb._world) and 3 or 4
end

--- Open sky over this map (the birds): outdoors.
function EngineGb.skyAllowed(_mapId)
  local a = A()
  if not (a and a.isOutdoor) then return false end
  local ok, out = pcall(a.isOutdoor, EngineGb._world)
  return ok and out == true
end

--- The ids of the maps joined to this one (the sky pulls their species into a town's pool).
function EngineGb.neighbourMapIds()
  local a = A()
  if not (a and a.neighbourIds) then return {} end
  local ok, ids = pcall(a.neighbourIds, EngineGb._world)
  return ok and type(ids) == "table" and ids or {}
end

--- Is an engine character (an NPC, the follower, a boulder) on cell (x, y)?
function EngineGb.objectOn(x, y)
  local a = A()
  if not (a and a.objectOn) then return false end
  local ok, on = pcall(a.objectOn, EngineGb._world, x, y)
  return ok and on == true
end

--- The map's signposts, { {x, y}, ... } (the birds perch on them).
function EngineGb.signCells()
  local a = A()
  if not (a and a.signCells) then return {} end
  local ok, cells = pcall(a.signCells, EngineGb._world)
  return ok and type(cells) == "table" and cells or {}
end

-- something standing on (x, y) that a wild Pokemon may not walk into: the player, an
-- NPC (or the follower), on its cell or the one it is stepping into
local function occupied(x, y)
  local w = EngineGb._world
  if not w then return true end
  local p = w.player
  if p and ((p.cellX == x and p.cellY == y) or (p.moving and p.targetX == x and p.targetY == y)) then return true end
  for _, e in ipairs(w.npcs or {}) do
    if not e._wilds and ((e.cellX == x and e.cellY == y) or (e.moving and e.targetX == x and e.targetY == y)) then
      return true
    end
  end
  return false
end

--- May a wild Pokemon step onto (x, y)? On the map, terrain it may stand on (the caller
--- checks it is its own), nobody there.
function EngineGb.canEnter(_game, x, y, opts)
  local w = EngineGb._world
  local map = w and w.map
  if not (map and map.inBounds and map:inBounds(x, y)) then return false end
  local surfing = opts and opts.surfing
  if surfing then
    if not map:isWaterCell(x, y) then return false end
  elseif not map:isWalkableCell(x, y) then
    return false
  end
  return not occupied(x, y)
end

function EngineGb.canEnterWhy(game, x, y, opts)
  if EngineGb.canEnter(game, x, y, opts) then return true end
  return false, "blocked"
end

function EngineGb.isProbingCanEnter() return false end

function EngineGb.cellFree(x, y)
  local w = EngineGb._world
  local map = w and w.map
  if not (map and map.inBounds and map:inBounds(x, y)) then return false end
  return map:isWalkableCell(x, y) and not map:isWaterCell(x, y) and not occupied(x, y)
end

function EngineGb.waterFree(x, y)
  local w = EngineGb._world
  local map = w and w.map
  if not (map and map.inBounds and map:inBounds(x, y)) then return false end
  return map:isWaterCell(x, y) and not occupied(x, y)
end

-- ------------------------------------------------------------------ encounters

function EngineGb.ensureEncountersLoaded() return true end

--- The map's encounter areas: presence markers at least ({ land = ..., water = ... });
--- Gen 1 carries slot lists too ({ slots = {{species = dex, level}} }, plus `fishing`),
--- which the ambient systems (the sky, the water) read for their species pools.
function EngineGb.tableFor(mapId)
  local a = A()
  if not a then return nil end
  local ok, t = pcall(a.tables, EngineGb._world, mapId)
  if not (ok and type(t) == "table") then return nil end
  local land, water = t.land, t.water
  return {
    land = type(land) == "table" and land or (land and true or nil),
    water = type(water) == "table" and water or (water and true or nil),
    fishing = type(t.fishing) == "table" and t.fishing or nil,
  }
end

function EngineGb.rollSweetScent(mapId, terrain)
  local a = A()
  if not a then return nil end
  local ok, enc = pcall(a.roll, EngineGb._world, mapId, terrain)
  if ok then return enc end
  return nil
end

function EngineGb.randomPersonality()
  return math.random(0, 65535) * 65536 + math.random(0, 65535)
end

function EngineGb.repelAllows(level)
  local a = A()
  if not a then return true end
  local ok, yes = pcall(a.repelAllows, EngineGb._world, level)
  return not ok or yes ~= false
end

function EngineGb.isSweetScentFacility() return false end
function EngineGb.safariActive() return false end

--- The wild battle against `enc` (the spawn's own species / level / DVs).
function EngineGb.startWild(_game, enc, opts)
  local a = A()
  if not (a and enc) then return nil, "no engine" end
  local w = EngineGb._world
  if not w then return nil, "no world" end
  local done = opts and opts.done
  local ok, started, err = pcall(a.startWild, w, enc, done)
  if not ok then return nil, tostring(started) end
  if started then EngineGb._battle = true end
  return started, err
end

-- ------------------------------------------------------------------ species

-- species are the data's string keys ("PIKACHU"); the art is keyed by national dex
local nationalCache, speciesCache = {}, nil

local function data()
  local a, w = A(), EngineGb._world
  if not a then return nil end
  if a.generation == 1 then return a.data() end
  return a.data(w)
end

function EngineGb.nationalFor(species)
  if species == nil then return nil end
  local n = tonumber(species)
  if n then return n > 0 and math.floor(n) or nil end
  local hit = nationalCache[species]
  if hit then return hit end
  local d = data()
  local def = d and type(d.pokemon) == "table" and d.pokemon[species]
  local dex = def and tonumber(def.dex)
  if dex and dex > 0 then
    nationalCache[species] = dex
    return dex
  end
  return nil
end

function EngineGb.speciesForNational(nat)
  nat = tonumber(nat)
  if not nat then return nil end
  if not speciesCache then
    local d = data()
    if not (d and type(d.pokemon) == "table") then return nil end
    speciesCache = {}
    for key, def in pairs(d.pokemon) do
      local dex = type(def) == "table" and tonumber(def.dex)
      if dex and type(key) == "string" and speciesCache[dex] == nil then speciesCache[dex] = key end
    end
  end
  return speciesCache[nat]
end

function EngineGb.isCaught(species)
  local a = A()
  if not a then return false end
  local ok, yes = pcall(a.isCaught, species, EngineGb._world)
  return ok and yes == true
end

--- Gen 2: the shiny DV pattern. Gen 1: never.
function EngineGb.shinyDvs(dvs)
  local a = A()
  return a ~= nil and a.shinyDvs ~= nil and a.shinyDvs(dvs) == true
end

--- Is this party Pokemon shiny (Gen 2: its DVs)?
function EngineGb.monShiny(mon)
  local a = A()
  return a ~= nil and a.isShiny(mon) == true
end

-- ------------------------------------------------------------------ the party / follower

function EngineGb.partyMons()
  local a = A()
  if not a then return {} end
  local party = a.party(EngineGb._world)
  if type(party) ~= "table" then return {} end
  -- the roles' combat and health bars read `maxHp`, which a GB mon does not carry
  -- (its maximum lives in stats.hp): mirrored here, the way friendship mirrors
  -- onto `happiness` (lib/gb_friendship.lua)
  for _, mon in ipairs(party) do
    if type(mon) == "table" and type(mon.stats) == "table" and tonumber(mon.stats.hp) then
      mon.maxHp = mon.stats.hp
    end
  end
  return party
end

function EngineGb.leadPartyMon()
  for _, mon in ipairs(EngineGb.partyMons()) do
    if type(mon) == "table" and not mon.isEgg and not mon.egg then return mon end
  end
  return nil
end

function EngineGb.leadPartySpecies()
  local mon = EngineGb.leadPartyMon()
  return mon and mon.species
end

function EngineGb.followerCurrent()
  local a = A()
  if not a then return nil end
  return a.follower(EngineGb._world)
end

-- the engine sprite a follower npc carries, for one of our renderers: draws it 4 px up
-- (GbColor.FOOT_LIFT) in the generation's colour mode, with the fields Gen 1's grass
-- strip and hop shadow read (a 16x16 walker's geometry). Anything else (`def`, `image`
-- ... what a render pipeline mod reads to texture its own geometry) comes from the npc's
-- own engine sprite, kept as `base`: a 3D pipeline then shows the vanilla follower.
local followerSprites = setmetatable({}, { __mode = "k" })
local VOXEL_KEYS = { def = true, resolveImage = true }
local SPRITE_META = { __index = function(s, k)
  if VOXEL_KEYS[k] and EngineGb._pipeline then
    local a = A()
    local mode = a and GbColor.mode(a.generation, a.generation == 1 and loadModule("src.render.PaletteFX") or nil)
    local vs = voxelSprite(rawget(s, "renderer"), mode)
    if vs then return vs[k] end
  end
  local base = rawget(s, "base")
  return base and base[k] or nil
end }

local function spriteDraw(s, px, py, camX, camY, facing, phase, _flip, _a, _b, _c, oamRow)
  local r = s.renderer
  if not r then return end
  -- re-created on the player's own cell at every map change (PikachuFollower /
  -- gen2/Follower.lua): it stays inside them until it trails out, never drawn over them
  local pl = EngineGb._world and EngineGb._world.player
  if pl and pl.px == px and pl.py == py then return end
  local a = A()
  local gen = a and a.generation or 2
  if gen == 2 then
    -- Gen 2's NPC:draw has already translated / scaled; Crystal's grass split as for a proxy
    if oamRow == "top" then return end
    return r:draw(px, py, camX or 0, (camY or 0) + GbColor.FOOT_LIFT, facing, phase or 0, false)
  end
  local paletteFx = loadModule("src.render.PaletteFX")
  local mode = GbColor.mode(1, paletteFx)
  local x, y = (px or 0) - (camX or 0), (py or 0) - (camY or 0)
  GbColor.draw(mode, paletteFx, function()
    r:draw(px, py, camX, (camY or 0) + GbColor.FOOT_LIFT, facing, phase or 0, false)
  end, math.floor(x + CELL / 2 - MARK_W / 2), math.floor(y - MARK_UP), MARK_W, MARK_H)
end

local function spriteOrigin(_s, px, py, camX, camY)
  return math.floor((px or 0) - (camX or 0)), math.floor((py or 0) - (camY or 0)) - GbColor.FOOT_LIFT
end

--- With no renderer (nothing of ours to show): the npc's own engine sprite back -- the
--- engines draw every npc's sprite unguarded, so it is never left nil.
function EngineGb.followerSprite(renderer, npc)
  local current = npc and npc.sprite
  if type(current) == "table" and not rawget(current, "_wilds") then npc._wildsBase = current end
  if not renderer then return npc and npc._wildsBase or nil end
  local s = followerSprites[renderer]
  if not s then
    s = setmetatable({
      _wilds = true, renderer = renderer, frameWidth = 16, frameHeight = 16, anchorX = 8, anchorY = 16,
      draw = spriteDraw, getScreenOrigin = spriteOrigin,
    }, SPRITE_META)
    followerSprites[renderer] = s
  end
  s.base = npc and npc._wildsBase or s.base
  return s
end

-- ------------------------------------------------------------------ talk / UI

local function adapterCall(name, ...)
  local a = A()
  local fn = a and a[name]
  if not fn then return nil end
  local ok, r1, r2, r3, r4 = pcall(fn, ...)
  if not ok then return nil end
  return r1, r2, r3, r4
end

function EngineGb.isMessageOpen() return adapterCall("isMessageOpen") == true end
function EngineGb.showMessage(text, opts) return adapterCall("showMessage", text, opts) == true end
function EngineGb.messageOnLastPage() return adapterCall("messageOnLastPage") == true end
function EngineGb.closeStayMessage() return adapterCall("closeStayMessage") == true end
function EngineGb.showChoice(options, defaultIdx, cb, _layout)
  return adapterCall("showChoice", options, defaultIdx, cb) == true
end
function EngineGb.choiceActive() return adapterCall("choiceActive") == true end

--- The dialogue box's place in 8 px tiles (the portrait sits above it).
function EngineGb.dialogueWindow()
  local win = adapterCall("dialogueWindow")
  return type(win) == "table" and win or nil
end

function EngineGb.screenBusy()
  local a = A()
  if not (a and a.screenBusy) then return true end
  local ok, busy = pcall(a.screenBusy, EngineGb._world)
  return not ok or busy == true
end

function EngineGb.canStartInteraction()
  local a = A()
  if not (a and a.canStartInteraction) then return false end
  local ok, yes = pcall(a.canStartInteraction, EngineGb._world)
  return ok and yes == true
end

local FACING_DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

--- The follower npc standing still on the cell the player faces, else nil.
function EngineGb.followerInFacingCell()
  local npc = EngineGb.followerCurrent()
  local p = EngineGb.playerCell()
  local d = p and FACING_DELTA[p.facing]
  if not (npc and d) then return nil end
  if npc.moving or npc.hidden then return nil end
  if npc.cellX == p.x + d[1] and npc.cellY == p.y + d[2] then return npc end
  return nil
end

--- Dry walkable empty cells in a row from (cx, cy) heading `dir` (a thrown ball).
function EngineGb.freeCellsAhead(cx, cy, dir, max)
  local d = FACING_DELTA[dir]
  if not d then return 0 end
  local n = 0
  for i = 1, max or 3 do
    local tx, ty = cx + d[1] * i, cy + d[2] * i
    if not EngineGb.cellFree(tx, ty) then break end
    n = n + 1
  end
  return n
end

function EngineGb.displayName(mon)
  local name = adapterCall("displayName", mon)
  return type(name) == "string" and name or "POKeMON"
end

--- Cures the status the way the engine's medicine does. Gen 1 keeps no separate sleep
--- counter outside `status`.
function EngineGb.clearStatus(mon)
  if type(mon) ~= "table" then return false end
  local had = mon.status ~= nil and mon.status ~= "" and mon.status ~= 0
  mon.status = nil
  if mon.sleep ~= nil then mon.sleep = 0 end
  return had
end

-- the mod-kept friendship (lib/gb_friendship.lua), handed over by main.lua on a GB boot
function EngineGb.setFriendshipStore(store) EngineGb._friendship = store end

function EngineGb.friendshipOf(mon)
  local store = EngineGb._friendship
  if store then
    local ok, v = pcall(store.valueOf, store, mon)
    if ok and tonumber(v) then return tonumber(v) end
  end
  return tonumber(type(mon) == "table" and (mon.friendship or mon.happiness)) or 0
end

function EngineGb.setFriendship(mon, value)
  local store = EngineGb._friendship
  if store then
    local ok, v = pcall(store.set, store, mon, value)
    if ok and tonumber(v) then return tonumber(v) end
  end
  return EngineGb.friendshipOf(mon)
end

--- A stable number standing in for Gen 3's personality (none exists here): the species'
--- national dex and the DVs. lib/companion.lua and lib/level_ready.lua key mons by it.
function EngineGb.monIdentity(mon)
  if type(mon) ~= "table" then return nil end
  local dex = EngineGb.nationalFor(mon.species) or 0
  local d, dv = mon.dvs, 0
  if type(d) == "table" then
    dv = (tonumber(d.attack) or 0) * 4096 + (tonumber(d.defense) or 0) * 256
      + (tonumber(d.speed) or 0) * 16 + (tonumber(d.special) or 0)
  elseif tonumber(d) then
    dv = tonumber(d) % 65536
  end
  return dex * 65536 + dv
end

--- Species facts for the ambient systems (string key or national dex number in).
function EngineGb.isWaterType(species)
  local a = A()
  if not (a and a.hasType) then return false end
  local ok, yes = pcall(a.hasType, species, "WATER")
  return ok and yes == true
end

function EngineGb.heightDm(species)
  local a = A()
  if not (a and a.heightDm) then return nil end
  local ok, dm = pcall(a.heightDm, species)
  return ok and dm or nil
end

function EngineGb.baseStatTotal(species)
  local a = A()
  if not (a and a.baseStatTotal) then return nil end
  local ok, sum = pcall(a.baseStatTotal, species)
  return ok and sum or nil
end

function EngineGb.playCry(species)
  local a = A()
  if a and a.playCry then pcall(a.playCry, species) end
  return nil
end

--- The engine sheets the mod's little drawings use. Gen 1 has the emote bubbles ("!" and
--- "?", lib/wild_emote.lua) and the dust puff (lib/hit_effect.lua); every other name
--- answers nil (a code-drawn fallback).
function EngineGb.fieldEffectSheet(name)
  local a = A()
  if not a then return nil end
  local fn
  if name == "exclamation_question_mark" then fn = a.emoteSheet
  elseif name == "ground_impact_dust" then fn = a.dustSheet end
  if not fn then return nil end
  local ok, sheet = pcall(fn)
  return ok and sheet or nil
end

-- ------------------------------------------------------------------ roles
-- The Battler, the Forager and the level-up follow-through (lib/overworld_battle.lua,
-- lib/forage_source.lua, lib/level_ready.lua): each engine fact is the adapter's
-- (lib/gb/gen1.lua; Gen 2 has none yet, so everything answers "nothing" there).

function EngineGb.moveNumber(m)
  return (adapterCall("moveNumber", m))
end

function EngineGb.moveRow(id)
  local row = adapterCall("moveRow", id)
  return type(row) == "table" and row or nil
end

function EngineGb.battlerOf(mon)
  return (adapterCall("battlerOf", mon))
end

function EngineGb.moveDamage(attacker, defender, moveId, rng, noCrit)
  local dmg, info = adapterCall("moveDamage", attacker, defender, moveId, rng, noCrit)
  if dmg == nil then return nil end
  return tonumber(dmg), info
end

function EngineGb.buildWildFighter(species, level, personality)
  return (adapterCall("buildWildFighter", species, level, personality))
end

function EngineGb.expGain(species, level)
  return tonumber(adapterCall("expGain", species, level)) or 0
end

function EngineGb.expApply(mon, amount)
  local result = adapterCall("expApply", mon, amount)
  return type(result) == "table" and result or nil
end

function EngineGb.movesLearnedAt(mon, level)
  local list = adapterCall("movesLearnedAt", mon, level)
  return type(list) == "table" and list or {}
end

function EngineGb.knowsMove(mon, moveId)
  return adapterCall("knowsMove", mon, moveId) == true
end

function EngineGb.evolutionTarget(mon)
  return (adapterCall("evolutionTarget", mon))
end

function EngineGb.startEvolution(mon, target, onDone)
  return adapterCall("startEvolution", mon, target, onDone) == true
end

function EngineGb.startMoveLearn(mon, moveIds, onDone)
  return adapterCall("startMoveLearn", mon, moveIds, onDone) == true
end

function EngineGb.itemCatalog(_mod)
  local catalog = adapterCall("itemCatalog")
  return type(catalog) == "table" and catalog or {}
end

function EngineGb.bagAdd(id, qty)
  return adapterCall("bagAdd", id, qty) == true
end

function EngineGb.bagCanAdd(id, qty)
  return adapterCall("bagCanAdd", id, qty) == true
end

--- May the Forager set out here: an allowed map type (routes and caves), the
--- player neither surfing nor standing in water. The same rule Gen 3 applies
--- (there is no Safari Zone session on a GB boot).
function EngineGb.forageAllowed(allowedTypes)
  local mt = EngineGb.mapType()
  if not (mt and allowedTypes and allowedTypes[mt]) then return false end
  local surf = EngineGb.playerSurfState()
  if surf.surfing or surf.dismounting then return false end
  local cell = EngineGb.playerCell()
  if cell and EngineGb.isWater(cell.x, cell.y) then return false end
  return true
end

function EngineGb.playSuccess()
  return adapterCall("playSuccess") == true
end

function EngineGb.playSelect()
  return adapterCall("playSelect") == true
end

--- The engine font, for the little overworld labels (lib/popup_text.lua). The
--- layout name "gb" tells the shared drawing code the glyphs sit at the pen
--- position (no Gen 3 cell drop, no pen codes).
function EngineGb.measureText(text, _opts)
  return tonumber(adapterCall("measureText", text)) or 0
end

function EngineGb.drawText(text, x, y, _opts)
  return tonumber(adapterCall("drawText", text, x, y)) or 0
end

function EngineGb.fontLayout()
  local a = A()
  return (a and a.measureText) and "gb" or nil
end

-- ------------------------------------------------------------------ stubs
-- Called without an existence check somewhere in the mod, not there on Gen 1 / Gen 2
-- (yet): each answers "nothing" (nil). The systems that need them are not built here
-- (EngineGb.supports), so these only keep a stray call harmless.
local STUBS = {
  "hmUsable", "sweetScentFail", "setFoeStage", "encounters", "collision", "pokemon",
  "trainerIds", "isShiny", "genderOf", "grassSheet", "reflectionKind", "reflectiveAt",
  "reflectionWobble", "coverReflections", "startRipple", "moveDisplayName",
  "speciesTypes", "eggGroups", "partyMenu", "playerPose", "grassRustle",
}
for _, name in ipairs(STUBS) do
  if EngineGb[name] == nil then EngineGb[name] = function() return nil end end
end
--- Flying-type (the sky's birds); string key or national dex number in.
function EngineGb.isFlying(species)
  local a = A()
  if not (a and a.hasType) then return false end
  local ok, yes = pcall(a.hasType, species, "FLYING")
  return ok and yes == true
end
function EngineGb.cryFinished() return true end

return EngineGb
