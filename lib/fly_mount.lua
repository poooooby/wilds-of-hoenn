-- Fly Mount: the Pokemon that uses Fly carries you, in place of the engine's black bird.
--
-- The engine plays Fly as two field-effect animations (field_effects.lua startFlyOut /
-- startFlyIn, shared by RSE and FRLG): a bird grows out of the player and flies off, swoops
-- in from the right, the player jumps on and rides off to the left; on arrival it swoops in
-- carrying the player, drops them, and comes back down into its ball. Its path stays the
-- engine's: this module reads each live bird (EnginePatch.flyAnims -- GBA screen px, the
-- player's spot at (120, 72)) and draws a Pokemon there, facing left, while the engine's
-- own drawFront skips the bird (lib/engine_patch.lua marks it `invisible` for that call
-- only, while `active()` says so).
--
-- Which Pokemon: the one chosen for Fly (Field.flyTo's `mon`, noted by `onFlyStarted`) when
-- it knows Fly, else the first party Pokemon that does, else Pidgeot (a mod lets you Fly
-- without the move). Pidgeot also flies for a Pokemon with no flying art at all
-- (Config.FLY_MOUNT.noFlight: Zekrom, Kyurem, Arceus, Golurk ... stand upright in every
-- PMDCollab animation; Doduo, Dodrio and Delibird do not fly). Drawn in the Sprite Style: PMD's "mount" sheet -- the down-left row of
-- its best flight animation, turned toward the camera like FireRed's own bird (baked for
-- every species that can learn Fly) -- else its "fly" sheet / Walk loop facing left; HGSS
-- flapping walk A / B facing left, like the birds in the sky (lib/sky_flyers.lua). The
-- rider sits on its SEAT (lib/fly_seats.lua, per frame, from tools/generate_fly_seats.py: its
-- back, or its head where the back will not take them -- Rayquaza), placed through the very
-- maths the renderers draw with, gen3-hd-sprites' size included. Carrying
-- the player, it is drawn just before them (same row, a smaller sortY), so they sit on its
-- back; otherwise over everything, as the engine's bird is. The bird's zoom (it grows 3.6x
-- flying off) is capped (Config.FLY_MOUNT.maxScale): the rider is never scaled.
local V = ...
local Config = V.require("config")
local EnginePatch = V.require("engine_patch")

local function soft(name)
  local ok, m = pcall(V.require, name)
  if ok then return m end
  return nil
end
local SpriteSource = soft("sprite_source")
local RendererFactory = soft("renderer_factory")
local FormSource = soft("form_source")
local ActorRenderer = soft("actor_renderer")
local PmdRenderer = soft("pmd_renderer")
local HdField = soft("hd_field")
local Seats = soft("fly_seats") or { pmd = {}, hgss = {} }

local FlyMount = {}
FlyMount.__index = FlyMount

local CELL = 16
local GBA_X, GBA_Y = 120, 72 -- the player's spot in the bird's GBA screen coordinates
local PENDING_TICKS = 3600   -- a Fly that never started its cutscene is forgotten after this

local function isEgg(mon)
  return mon.isEgg == true or mon.egg == true
end

--- The Pokemon that carries the player: `chosen` (the one used for Fly) when it is no egg
--- and `knows(mon)` says it knows Fly, else the first such in `party`, else nil (the
--- fallback species). Pure (tested).
function FlyMount.resolve(chosen, party, knows)
  if type(chosen) == "table" and not isEgg(chosen) and knows(chosen) then return chosen end
  for _, mon in ipairs(party or {}) do
    if type(mon) == "table" and not isEgg(mon) and knows(mon) then return mon end
  end
  return nil
end

--- Where a bird is in the world: its centre (world px) from the player's tile (px, py)
--- and the bird's GBA coordinates -- field_effects.lua draw_bird's own sum. Pure (tested).
function FlyMount.birdCentre(px, py, b)
  return px + 8 - GBA_X + (b.x or 0) + (b.x2 or 0), py - GBA_Y + (b.y or 0) + (b.y2 or 0)
end

--- The mount's scale for a bird's zoom (`aff.scale`, 256 = 1x), clamped. Pure (tested).
function FlyMount.scaleOf(b, cfg)
  local a = b.aff
  local s = (a and tonumber(a.scale)) and a.scale / 256 or 1
  return math.max(cfg.minScale or 0.05, math.min(cfg.maxScale or 1.6, s))
end

--- The tile (world px) to draw a renderer at so the middle of its art (`lift` px tall at
--- scale 1, grown `scale` about its feet) sits `seat` px below the bird's centre (cx, cy).
--- Pure (tested).
function FlyMount.tileFor(cx, cy, lift, scale, seat)
  local feet = cy + (seat or 0) + lift * scale / 2
  return cx - CELL / 2, feet - CELL
end

--- True when art key `key` (25, "646-black") has no flying art (`noFlight`: national dex ->
--- true for every form, "base" for the base form only). Pure (tested).
function FlyMount.cannotFly(key, noFlight)
  if not noFlight or key == nil then return false end
  local s = tostring(key)
  local v = noFlight[tonumber(s:match("^(%d+)"))]
  if v == true then return true end
  return v == "base" and not s:find("-", 1, true)
end

--- `deps` (tests): newRenderer(mod, key, shiny, style, presentation), flyAnims, playerPixel,
--- playerRide, partyMons, knows(mon), artKeyFor(mod, species), isShiny(mon), on(mod),
--- traveling().
function FlyMount.new(mod, deps)
  return setmetatable({ mod = mod, deps = deps or {}, anims = {}, actors = {}, flapClock = 0 }, FlyMount)
end

function FlyMount:_dep(name, fallback)
  local d = self.deps[name]
  if d ~= nil then return d end
  return fallback
end

function FlyMount:on()
  local on = self:_dep("on", Config.flyMountOn)
  return on(self.mod) ~= false
end

--- Field.flyTo was called (the wrap in lib/engine_patch.lua): `mon` = the Pokemon chosen.
function FlyMount:onFlyStarted(mon)
  self.chosen = mon
  self.renderer, self.key = nil, nil
  self.pending, self.seen, self.wait = true, false, 0
end

function FlyMount:_lift(on)
  if on == (self.lifted or false) then return end
  local lift = self:_dep("liftPlayer", EnginePatch.liftPlayer)
  if lift then lift(on) end
  self.lifted = on or nil
end

--- Forget everything (a save loaded).
function FlyMount:reset()
  self:_lift(false)
  self.chosen, self.renderer, self.key = nil, nil, nil
  self.pending, self.seen, self.wait = false, false, 0
  for i = #self.anims, 1, -1 do self.anims[i] = nil end
end

local function knowsFly(mon)
  return EnginePatch.knowsMove and EnginePatch.knowsMove(mon, EnginePatch.flyMoveId and EnginePatch.flyMoveId() or 19)
end

-- the renderer for this Fly, built on first need
function FlyMount:_renderer()
  if self.renderer ~= nil then return self.renderer or nil end
  local party = self:_dep("partyMons", EnginePatch.partyMons)
  local mon = FlyMount.resolve(self.chosen, party and party() or {}, self:_dep("knows", knowsFly))
  local key, shiny = nil, false
  if mon then
    local artKeyFor = self:_dep("artKeyFor", FormSource and FormSource.artKeyFor)
    key = artKeyFor and artKeyFor(self.mod, tonumber(mon.species)) or nil
    local isShiny = self:_dep("isShiny", function(m)
      return m.personality ~= nil and EnginePatch.isShiny(m.personality, tonumber(m.otId), tonumber(m.otSecretId)) == true
    end)
    shiny = isShiny(mon) == true
  end
  if key ~= nil and FlyMount.cannotFly(key, Config.FLY_MOUNT and Config.FLY_MOUNT.noFlight) then
    key, shiny = nil, false -- no flying art: Pidgeot flies for it
  end
  key = key or (Config.FLY_MOUNT and Config.FLY_MOUNT.fallbackDex) or 18
  local newRenderer = self:_dep("newRenderer", RendererFactory and RendererFactory.new)
  local land = SpriteSource and SpriteSource.PRESENTATION_LAND or "land"
  local r = newRenderer and newRenderer(self.mod, key, shiny, Config.spriteStyle(self.mod), land) or nil
  self.renderer, self.key, self.mon = r or false, key, mon
  return r
end

--- True while a mount is drawn in the bird's place (the engine then skips its bird).
function FlyMount:active()
  return self:on() and #self.anims > 0 and self.renderer ~= nil and self.renderer ~= false
end

--- Once per field tick: reads the live Fly animations, builds the mount, flaps its wings.
function FlyMount:tick()
  local flyAnims = self:_dep("flyAnims", EnginePatch.flyAnims)
  local n = flyAnims and flyAnims(self.anims) or 0
  if n == 0 then
    self:_lift(false)
    -- between the cutscenes (the fly_out over, the map loading) the player is still
    -- travelling; once they are back on the ground after one, this Fly is over
    if self.pending or self.renderer ~= nil then
      self.wait = self.wait + 1
      local traveling = self:_dep("traveling", EnginePatch.playerTraveling)
      if (self.seen and not (traveling and traveling())) or self.wait > PENDING_TICKS then self:reset() end
    end
    return
  end
  self.seen, self.wait = true, 0
  if not self:on() then self:_lift(false) return end
  local r = self:_renderer()
  if not r then self:_lift(false) return end
  -- carrying the player: both over everything (the engine's bird drew over all)
  local carrying = false
  for i = 1, n do
    local b = self.anims[i].bird
    if b and b.attached and not b.invisible then carrying = true end
  end
  self:_lift(carrying)
  self.flapClock = self.flapClock + 1
  if r.isPmd then
    r.swimming = false
    -- its "mount" sheet (turned toward the camera, heading down-left, like FireRed's bird;
    -- tools/generate_pmd_sprites.py mount_meta), else its sky "fly" sheet / Walk facing left
    if r.info and r.info.mount then
      r:advanceAs("mount", 1, "walk")
    else
      r:advanceAs("fly", 1, "walk")
    end
  else
    if SpriteSource then r.presentation = SpriteSource.PRESENTATION_LAND end
    local cfg = Config.FLY_MOUNT or {}
    local beat = math.floor(self.flapClock / (cfg.flapTicks or 6)) % 2
    local A = ActorRenderer and ActorRenderer.POSE_WALK_A or "walkA"
    local B = ActorRenderer and ActorRenderer.POSE_WALK_B or "walkB"
    self.pose = beat == 0 and A or B
  end
end

-- the seats of a renderer's art (lib/fly_seats.lua, tools/generate_fly_seats.py): a flat
-- { x1, y1, x2, y2, ... } per frame, or nil
local function seatsOf(tbl, key)
  if not tbl or key == nil then return nil end
  return tbl[key] or tbl[tonumber(key)] or tbl[tostring(key)]
end

--- Where a seat point (px, py of the art drawn: a cell or frame) lands from the tile's
--- top-left when it is drawn at `s` (`origin` = where the art's px (0, 0) lands, `lp` = the
--- point gen3-hd-sprites grows it about, `k` its size). Pure (tested).
function FlyMount.seatPoint(ox, oy, s, k, lpx, lpy, px, py)
  return ox + (lpx + (px - lpx) * k) * s, oy + (lpy + (py - lpy) * k) * s
end

--- The rider's seat on renderer `r` drawn at scale `grow` (act.scale) facing `facing`:
--- its offset from the tile's top-left, as the renderer draws it (gen3-hd-sprites size
--- included). nil when the art has no seat (a sheet with no entry, HGSS not facing left).
function FlyMount:seatOffset(r, grow, facing)
  local seats = self.deps.seats or Seats
  if r.isPmd then
    if r.anim ~= "mount" or not (PmdRenderer and r.info) then return nil end
    local entry = r.info.mount
    local list = seatsOf(seats.pmd, r.dex)
    if type(entry) ~= "table" or not list then return nil end
    local col = PmdRenderer.frameAt(entry.durations, r.clock)
    local sx, sy = list[col * 2 + 1], list[col * 2 + 2]
    if not sx then sx, sy = list[1], list[2] end
    local s = PmdRenderer.scaleOf(r.info) * grow
    local ax, ay, foot = entry.ax, entry.ay, tonumber(entry.foot) or entry.ay
    local dx = math.floor(CELL / 2 - ax * s + 0.5)
    local dy = math.floor(PmdRenderer.groundOf(entry, s) - ay * s + 0.5)
    local path = SpriteSource and SpriteSource.pmdPath(r.info, "mount", r.dex, r.shiny)
    local k = (HdField and path and HdField.scaleOfPath(r.mod, path)) or 1
    return FlyMount.seatPoint(dx, dy, s, k, ax, ay + math.max(1, foot - ay), sx, sy)
  end
  if facing ~= "left" or not ActorRenderer then return nil end
  local list = seatsOf(seats.hgss, r.dex)
  if not list then return nil end
  local walkB = self.pose == (ActorRenderer.POSE_WALK_B or "walkB")
  local sx, sy = list[walkB and 3 or 1], list[walkB and 4 or 2]
  local path = r.imagePath and r:imagePath()
  local fw, fh = r.frameWidth and r:frameWidth(), r.frameHeight and r:frameHeight()
  if not (sx and path and fw and fh) then return nil end
  local pad = ActorRenderer.feetPadFor(r.mod, path, r.frameCount or 18) or 0
  local drawX, drawY = (CELL - fw) / 2, CELL - fh + pad
  local ox, oy = drawX + fw / 2 - fw / 2 * grow, drawY + fh - fh * grow
  local k = (HdField and HdField.scaleOfPath(r.mod, path)) or 1
  return FlyMount.seatPoint(ox, oy, grow, k, fw / 2, fh - pad, sx, sy)
end

local function liftOf(r)
  if r.isPmd then return r:headLift({ "mount", "fly", "walk" }) or CELL end
  return (r.headLift and r:headLift()) or CELL
end

-- one pooled actor per bird slot, drawing the shared renderer with that bird's look
local function actorFor(self, i)
  local a = self.actors[i]
  if a then return a end
  a = { kind = "fly_mount", elevation = 3 }
  a.draw = function(_, camX, camY)
    local r = self.renderer
    if not r then return end
    local act = r.act
    a.look = a.look or {}
    a.look.scale = a.scale
    r.act = a.look
    local ok = pcall(r.draw, r, a.tileX, a.tileY, camX, camY, a.facing, self.pose)
    r.act = act
    if not ok then a.tileX = nil end
  end
  self.actors[i] = a
  return a
end

--- Appends the mount for each live bird (`actors` = the field's list for this frame).
function FlyMount:collectActors(actors)
  if not self:active() then return end
  local r = self.renderer
  local playerPixel = self:_dep("playerPixel", EnginePatch.playerPixel)
  local px, py = playerPixel()
  if not (px and py) then return end
  local playerRide = self:_dep("playerRide", EnginePatch.playerRide)
  local ox, oy, elevation = playerRide()
  local cfg = Config.FLY_MOUNT or {}
  local lift = liftOf(r)
  for i = 1, #self.anims do
    local b = self.anims[i].bird
    if b and not b.invisible then
      local a = actorFor(self, i)
      local cx, cy = FlyMount.birdCentre(px, py, b)
      a.scale = FlyMount.scaleOf(b, cfg)
      a.facing = b.cb == "return" and "down" or "left"
      -- its seat under the rider: the rider's lower edge is 8 px below the bird's centre
      -- (field_effects.lua bird_attach_player puts the player 8 px above it)
      local okS, offX, offY = pcall(self.seatOffset, self, r, a.scale, a.facing)
      if okS and offX then
        a.tileX, a.tileY = cx - offX, cy + 8 - offY
      else
        a.tileX, a.tileY = FlyMount.tileFor(cx, cy, lift, a.scale, cfg.seat)
      end
      a.i = 95500 + i
      if b.attached then
        -- carrying the player: over everything with them, drawn just before them (the
        -- player is lifted to subpriority 1 in tick; a higher one draws first), so they
        -- sit on its back
        a.fixedPriority, a.priority, a.subpriority = true, 1, 2
        a.elevation = elevation or 3
        a.x, a.y = px + (ox or 0), py + (oy or 0)
        a.sortY = py - 0.5
      else
        -- in the open sky, over everything, as the engine's bird
        a.fixedPriority, a.priority, a.subpriority = true, 1, 0
        a.elevation = 3
        a.x, a.y, a.sortY = cx, cy, cy
      end
      actors[#actors + 1] = a
    end
  end
end

return FlyMount
