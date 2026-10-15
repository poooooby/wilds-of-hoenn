-- A tall follower ducking under a roof's edge.
--
-- Gen 3 draws the map's "covers characters" layer (roof edges, eaves, tree crowns) after
-- every character, which is how the player walks behind a house or a tree. Our follower is
-- drawn with the characters, so a sprite taller than its tile -- a PMDCollab Gyarados, with
-- Species Sizes off ~70 px -- standing in FRONT of a house had its head cut off by the
-- house's eave, which is behind it. Instead it ducks: lib/follower_adapter.lua eases it a
-- few px down (`nudge`) and squashes it toward its feet for the rest of the way, so its top
-- just clears the eave, and stands back up once past.
--
-- A covering tile only counts when the thing it belongs to is BEHIND the follower: down
-- from that tile its column runs through covering / solid tiles (the eave, the wall) to
-- walkable ground at or above the follower's own row -- a house it stands in front of. A
-- tree or building whose covering tiles and solid base go on south past the follower's row
-- is in front of it: there it is hidden the usual way and does not duck.
-- Pure (the map is asked through `covers(x, y)` / `solid(x, y)`).
local EaveDuck = {}

local CELL = 16

--- Is the structure a covering tile at (x, y) belongs to behind a follower whose feet are on
--- row `feetRow`? Walks down the column through covering / solid tiles to where it meets
--- open ground: behind when that is at or above the follower's row.
function EaveDuck.behind(x, y, feetRow, covers, solid)
  local r = y
  while r <= feetRow + 4 and (covers(x, r) or solid(x, r)) do r = r + 1 end
  return r <= feetRow
end

--- How many px of the follower's art (world px: `left`..`right`, `top` down to the feet on
--- row `feetRow`) lie under covering tiles of structures behind it: the drop that would
--- clear them all (0 = none). Tiles on the follower's own row and below never count.
function EaveDuck.overlap(left, right, top, feetRow, covers, solid)
  local c0, c1, r0 = EaveDuck.window(left, right, top)
  return EaveDuck.need(EaveDuck.lowestRow(c0, c1, r0, feetRow, covers, solid), top)
end

--- The tiles the art spans: columns c0..c1, rows from r0 down. Only these (and the feet
--- row) decide `lowestRow`, so a caller can keep its answer until one of them changes.
function EaveDuck.window(left, right, top)
  return math.floor(left / CELL), math.floor((right - 1) / CELL), math.floor(top / CELL)
end

--- The lowest row (largest y) holding a covering tile of a structure behind the follower,
--- over columns c0..c1, rows feetRow - 1 up to r0; nil = none.
function EaveDuck.lowestRow(c0, c1, r0, feetRow, covers, solid)
  local best
  for col = c0, c1 do
    for row = feetRow - 1, r0, -1 do
      if best and row <= best then break end -- cannot beat what another column found
      if covers(col, row) and EaveDuck.behind(col, row, feetRow, covers, solid) then
        best = row
        break -- the lowest one in this column decides it
      end
    end
  end
  return best
end

--- The px of art (top at world y `top`) under row `row`'s tiles: 0 when nil.
function EaveDuck.need(row, top)
  if not row then return 0 end
  return math.max(0, (row + 1) * CELL - top)
end

--- From the overlap and the art's height (px above its feet): the px it moves down and how
--- much it squashes (0..1, like act.sink), within `cfg` = { nudge, minScale }.
function EaveDuck.split(need, height, cfg)
  if need <= 0 or not height or height <= 0 then return 0, 0 end
  local nudge = math.min(need, cfg.nudge)
  local rest = need - nudge
  local squash = math.min(1 - cfg.minScale, rest / height)
  return nudge, math.max(0, squash)
end

return EaveDuck
