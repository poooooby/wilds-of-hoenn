-- The mod's own wild double battle: two wild Pokemon at once (a sea bird and the fish it caught,
-- lib/battle_trigger.lua). Gen1Recomp only runs wild battles single, so lib/engine_patch.lua
-- (EnginePatch.startWildDouble) bends its wild battle into the trainer-doubles layout for the
-- length of one battle; this module holds the pure decisions it needs (tested without the engine):
--
--   * the wild intro, built for one foe, made to bring out both (and the player's second
--     Pokemon): `patchIntroSteps`
--   * while both foes stand a Poke Ball is refused (our line, nothing used) and running
--     fails ("Can't escape!")
--   * once one is down it stays a double -- the player's Pokemon both stay out -- but a ball
--     is thrown at the one left (`lastFoe`) and running goes by a wild battle's odds
--
-- Gen 3's battle screen has two places a side, so this is as many as one battle shows.
local WildDouble = {}

-- `list` with every "enemy" / "player" key swapped for the ids it stands for
local function expand(list, foeIds, playerIds)
  local out = {}
  for _, k in ipairs(list) do
    if k == "enemy" or k == 1 then
      for _, id in ipairs(foeIds) do out[#out + 1] = id end
    elseif k == "player" or k == 0 then
      for _, id in ipairs(playerIds) do out[#out + 1] = id end
    else
      out[#out + 1] = k
    end
  end
  return out
end

--- Rewrites a wild single's intro steps (IntroSeq._steps, in place) so they bring out every
--- foe in `foeIds` (battler ids 1, 3) and every player Pokemon in `playerIds` (0, 2): the
--- shiny checks, cries, front / back animations, Poke Ball throw and health boxes. Messages,
--- the background slide and fades are left alone. Returns how many steps it changed.
function WildDouble.patchIntroSteps(steps, foeIds, playerIds)
  local n = 0
  for _, step in ipairs(steps or {}) do
    local d = step.data or {}
    step.data = d
    local k = step.kind
    local enemy = (d.side or "enemy") == "enemy"
    if (k == "shiny_check" or k == "healthbox") and not d.ids then
      d.ids = enemy and foeIds or playerIds
      n = n + 1
    elseif k == "cry" and not d.ids and enemy then
      d.ids = foeIds
      n = n + 1
    elseif k == "player_throw" and not d.ids then
      d.ids = playerIds
      n = n + 1
    elseif (k == "mon_anim" or k == "mon_anim_wait") and type(d.ids) == "table" then
      d.ids = expand(d.ids, foeIds, playerIds)
      n = n + 1
    end
  end
  return n
end

--- The foe a Poke Ball is thrown at: the one still standing (`alive[1]` / `alive[3]`), or
--- nil while both stand (a ball is refused then) or neither does.
function WildDouble.lastFoe(alive)
  alive = alive or {}
  if alive[1] and alive[3] then return nil end
  if alive[1] then return 1 end
  if alive[3] then return 3 end
  return nil
end

--- What a Poke Ball does in this battle with `foes` foes standing: "refuse" (two: no clear
--- shot, nothing used) or "throw" (one: thrown at that one).
function WildDouble.ballRule(foes)
  return (tonumber(foes) or 0) >= 2 and "refuse" or "throw"
end

--- May the player run, with `foes` foes standing? Never from two ("Can't escape!"); from the
--- last one by a wild battle's odds.
function WildDouble.canTryRun(foes)
  return (tonumber(foes) or 0) <= 1
end

--- Does a run from the last foe get away? A wild single's odds (pokefirered battle_util.c
--- IsRunningFromBattleImpossible / TryRunFromBattle): faster always does, else speed x 128 /
--- the foe's, plus 30 for each failed try -- not counting `blocked` tries made while both foes
--- stood ("Can't escape!", which the engine counts all the same) -- against `roll` 0..255.
function WildDouble.escapes(pSpd, eSpd, attempts, blocked, roll)
  local p, e = tonumber(pSpd) or 0, tonumber(eSpd) or 0
  if p >= e then return true end
  local tries = math.max(0, (tonumber(attempts) or 0) - (tonumber(blocked) or 0))
  local odds = (math.floor(p * 128 / math.max(1, e)) + tries * 30) % 256
  return odds > (tonumber(roll) or 0)
end

-- the engine's lines for a ball thrown in a double (battle/init.lua D.useBag: "used ...",
-- "The TRAINER blocked the BALL!", "Don't be a thief!"): silenced for a ball we throw ourselves
WildDouble.BLOCKED_BALL_TEXT = {
  STRINGID_PLAYERUSEDITEM = true, STRINGID_TRAINERBLOCKEDBALL = true, STRINGID_DONTBEATHIEF = true,
}

return WildDouble
