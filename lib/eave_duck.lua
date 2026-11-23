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

--- Per column c0..c1: the lowest row holding a covering tile of a structure behind the
--- follower (lowestRow for that column alone), or false -- written into `out` (index 1 =
--- column c0).
function EaveDuck.columns(c0, c1, r0, feetRow, covers, solid, out)
  out = out or {}
  local n = 0
  for col = c0, c1 do
    n = n + 1
    out[n] = EaveDuck.lowestRow(col, col, r0, feetRow, covers, solid) or false
  end
  for k = #out, n + 1, -1 do out[k] = nil end
  return out
end

--- Per column c0..c1: does any covering tile (a structure behind it OR in front, a tree's
--- crown) lie over the art, rows r0 .. feetRow - 1? -- written into `out` (index 1 = c0).
function EaveDuck.coveredColumns(c0, c1, r0, feetRow, covers, out)
  out = out or {}
  local n = 0
  for col = c0, c1 do
    n = n + 1
    local hit = false
    for row = r0, feetRow - 1 do
      if covers(col, row) then hit = true break end
    end
    out[n] = hit
  end
  for k = #out, n + 1, -1 do out[k] = nil end
  return out
end

--- Squeezing SIDEWAYS through a gap (a big Pokemon walking up a path between trees): when the
--- columns over the art's middle (`cx`, world px) are clear and only columns to its sides hold
--- covering tiles behind it (`cols` from EaveDuck.columns, starting at column `c0`), the art
--- (`half` px each side of `cx`) is drawn narrower, `scale` of its width (>= `minScale`), and
--- slid `dx` px (at most `shiftMax`) toward the middle of the clear gap, so it fits between
--- them. `sides` (optional, EaveDuck.coveredColumns): every column with covering tiles over
--- the art, in front of it too -- the gap's edges are those (a tree it walks past hides a
--- wing the usual way, but squeezed it fits between the trees). Returns scale, dx -- 1, 0
--- when nothing is at its sides (or a tree in front covers its middle: hidden as usual), and
--- nil when a structure BEHIND it covers its middle column (squeezing cannot help: duck
--- instead). Pure.
function EaveDuck.squeeze(cx, half, c0, cols, minScale, shiftMax, sides)
  local n = #cols
  if n == 0 or not half or half <= 0 then return 1, 0 end
  local cc = math.floor(cx / CELL)
  local function behindAt(col)
    if col < c0 or col > c0 + n - 1 then return false end
    return cols[col - c0 + 1] ~= false
  end
  if behindAt(cc) then return nil end
  local function blocked(col)
    if col < c0 or col > c0 + n - 1 then return false end
    if sides then return sides[col - c0 + 1] == true or cols[col - c0 + 1] ~= false end
    return cols[col - c0 + 1] ~= false
  end
  if blocked(cc) then return 1, 0 end
  local L, R = cc, cc
  while L - 1 >= c0 and not blocked(L - 1) do L = L - 1 end
  while R + 1 <= c0 + n - 1 and not blocked(R + 1) do R = R + 1 end
  local leftOpen, rightOpen = not blocked(L - 1), not blocked(R + 1)
  if leftOpen and rightOpen then return 1, 0 end
  -- the gap's edges (an open side: as far as the art reaches, plus the room to slide over)
  local m = shiftMax or 8
  local A = leftOpen and (cx - half - m) or L * CELL
  local B = rightOpen and (cx + half + m) or (R + 1) * CELL
  local scale = math.max(minScale or 0.5, math.min(1, (B - A) / (2 * half)))
  local h = half * scale
  -- the squeezed box as near its own place as fits in the gap
  local centre = cx
  if centre - h < A then centre = A + h end
  if centre + h > B then centre = B - h end
  if B - A < 2 * h then centre = (A + B) / 2 end -- (too wide even squeezed: the middle)
  local dx = centre - cx
  if dx > m then dx = m elseif dx < -m then dx = -m end
  return scale, dx
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
