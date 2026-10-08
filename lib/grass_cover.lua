-- Static "grass overlapping feet" tuft for entities the engine doesn't
-- know about (our wild Pokemon, the follower) -- neither is a registered
-- Objects event-object, so neither is picked up by the engine's own two
-- grass-feet mechanisms in src/core/game3/field_effects.lua's
-- collectActors:
--   1) the player's own ACTIVE rustle (parting/un-parting as you walk
--      through) -- tracked in a single global slot (FieldEffects._fx),
--      genuinely a singleton keyed to one tile at a time. We do NOT
--      replicate this: calling the engine's own trigger for a wild
--      Pokemon or the follower would stomp the player's own rustle state
--      whenever both are in grass at once. This matches how the actual
--      games behave too -- only the player gets the animated rustle; NPCs
--      just show the plain tuft below.
--   2) the STATIC tuft the engine already draws over any REGISTERED NPC
--      standing in grass (same file, "Grass feet cover for NPCs" block) --
--      this one IS safely per-entity (no shared state), so this module
--      reimplements that exact geometry/visibility check for entities the
--      engine's own loop (which only walks Objects.forDraw()) never sees.
--
-- Same sprite data the engine uses for its own effect
-- (EnginePatch.grassSheet() -> FieldEffects.loadSheet("tall_grass", 16,
-- 16, 5), frame 4 of 5 is the non-animated "sitting in grass" pose) --
-- not a reimplementation of the art, just a second caller of the same
-- cache-backed loader.
local V = ...
local EnginePatch = V.require("engine_patch")

local GrassCover = {}

local CELL = 16
local FEET_H = 8

--- Appends a grass-tuft overlay actor to `actors` if (cellX, cellY) is a
--- grass tile AND the entity's feet (derived from `py`, its world-pixel Y)
--- currently fall within the tuft's draw band -- the same two conditions
--- the engine's own NPC-grass-cover block checks. No-ops silently if the
--- tile isn't grass, the entity's feet aren't in the band, or the sheet
--- isn't loaded yet (no map, or missing ROM extract) -- the overlay is
--- purely cosmetic, never required for anything else to work.
---
--- `idBase` must be a stable, caller-distinct integer (keeps draw-order
--- subpriority deterministic across frames and collision-free against
--- other callers -- lib/spawn_manager.lua uses each entity's own id,
--- lib/follower_adapter.lua uses a fixed 0, which no wild-mon id is).
function GrassCover.append(actors, cellX, cellY, py, elevation, idBase)
  if type(cellX) ~= "number" or type(cellY) ~= "number" or type(py) ~= "number" then return end
  if not EnginePatch.isGrass(cellX, cellY) then return end
  local sheet = EnginePatch.grassSheet()
  if not (sheet and sheet.quadsFront) then return end
  local qStatic = sheet.quadsFront[4]
  if not qStatic then return end

  local feetY = py + CELL
  local grassTop = cellY * CELL
  local grassBot = grassTop + CELL
  if feetY < grassTop + FEET_H or feetY > grassBot + 2 then return end

  local gx, gy = cellX * CELL, cellY * CELL + (CELL - FEET_H)
  actors[#actors + 1] = {
    kind = "field_effect_wild_grass",
    elevation = elevation or 3,
    sortY = py + 0.5,
    x = gx, y = gy,
    i = 90000 + (tonumber(idBase) or 0),
    draw = function(_, camX, camY)
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(sheet.image, qStatic, gx - camX, gy - camY)
    end,
  }
end

--- The same tuft for a sprite drawn away from its own tile (the follower trails
--- the player by its own overhang): it goes on the grass TILES under the sprite's
--- real feet -- `fx` the feet's centre x, `fy` their y (world px), `width` the
--- width of the feet -- one tuft per grass tile they touch, in front of the body's
--- lower edge. Every tuft stays snapped to its tile, never between tiles, so
--- the grass is where the grass is and the sprite is covered only by grass it
--- stands in. For a sprite on its own tile this is exactly GrassCover.append.
function GrassCover.appendFeet(actors, fx, fy, width, py, elevation, idBase)
  if type(fx) ~= "number" or type(fy) ~= "number" or type(py) ~= "number" then return end
  local sheet = EnginePatch.grassSheet()
  if not (sheet and sheet.quadsFront) then return end
  local qStatic = sheet.quadsFront[4]
  if not qStatic then return end
  local row = math.floor((fy - FEET_H) / CELL)
  if fy < row * CELL + FEET_H or fy > row * CELL + CELL + 2 then return end
  local half = math.max(1, (tonumber(width) or CELL) / 2)
  local first = math.floor((fx - half) / CELL)
  local last = math.floor((fx + half - 1) / CELL)
  for col = first, math.min(last, first + 2) do
    if EnginePatch.isGrass(col, row) then
      local gx, gy = col * CELL, row * CELL + (CELL - FEET_H)
      actors[#actors + 1] = {
        kind = "field_effect_wild_grass",
        elevation = elevation or 3,
        sortY = py + 0.5,
        x = gx, y = gy,
        i = 90000 + (tonumber(idBase) or 0),
        draw = function(_, camX, camY)
          love.graphics.setColor(1, 1, 1, 1)
          love.graphics.draw(sheet.image, qStatic, gx - camX, gy - camY)
        end,
      }
    end
  end
end

return GrassCover
