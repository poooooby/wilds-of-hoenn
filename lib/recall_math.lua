-- The "shrink into the player" math shared by both renderers (a recalled
-- companion: a surfing PMD follower, a Battler that ran out of strength).
-- Pure.
local RecallMath = {}

--- Smoothstep: eases a recall so it starts and ends gently.
function RecallMath.ease(t)
  t = tonumber(t) or 0
  if t < 0 then t = 0 elseif t > 1 then t = 1 end
  return t * t * (3 - 2 * t)
end

--- Where a recalled companion is drawn. `recall` runs 1 (out, at its own tile
--- fx, fy) to 0 (inside the player at px, py); it slides toward the player and
--- rises `lift` px toward their body as it shrinks. Returns the tile top-left
--- (world px) and the scale multiplier.
function RecallMath.blend(recall, fx, fy, px, py, lift)
  local e = RecallMath.ease(recall)
  return px + (fx - px) * e, py + (fy - py) * e - (lift or 0) * (1 - e), e
end

return RecallMath
