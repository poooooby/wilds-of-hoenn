-- Which PMDCollab portrait emotion a party Pokemon is showing, from its real
-- state: HP, status condition and friendship (happiness). Pure -- reads plain
-- fields off a mon table (hp, maxHp, status/sleep, friendship/happiness,
-- isEgg) and never touches the engine, so it is directly unit-testable and
-- the same function serves the follower menu, any other portrait message and
-- other mods through mod.exports.portraitUI.
--
-- Priority, highest first (the most urgent thing about the mon wins):
--   1. fainted (HP 0)                  Teary-Eyed
--   2. critical HP (<= 10%)            Crying
--   3. a status condition              Pain      poison / bad poison
--                                      Shouting  burn
--                                      Stunned   paralysis, freeze
--                                      Dizzy     sleep
--   4. low HP (<= 25%)                 Pain
--   5. hurt (< 50%)                    Worried
--   6. friendship tier, when healthy   Angry     0-29
--                                      Sad       30-69
--                                      Normal    70-129
--                                      Happy     130-199   (200 = the engine's top tier)
--                                      Joyous    200-254
--                                      Inspired  255
--      ...and a Joyous/Inspired mon that is a little hurt (50-99% HP) only
--      manages Happy.
-- Determined and Surprised are not derived from state: callers pass them as
-- explicit moods for actions (e.g. Play -> Determined, a surprise -> Surprised).
--
-- MonMood.read returns the emotion AND a `reason` key naming why (for
-- dialogue, see lib/follower_dialogue.lua).
local MonMood = {}

MonMood.CRITICAL_HP = 0.10
MonMood.LOW_HP = 0.25
MonMood.HURT_HP = 0.50
-- ascending (minimum friendship, emotion)
MonMood.FRIENDSHIP_TIERS = {
  { 0, "Angry" }, { 30, "Sad" }, { 70, "Normal" }, { 130, "Happy" },
  { 200, "Joyous" }, { 255, "Inspired" },
}
MonMood.DEFAULT_FRIENDSHIP = 70 -- a mon with no friendship field at all

local STATUS_EMOTION = {
  poison = "Pain", burn = "Shouting", paralysis = "Stunned",
  freeze = "Stunned", sleep = "Dizzy",
}
local FRIENDSHIP_REASON = {
  Angry = "angry", Sad = "sad", Normal = "normal", Happy = "happy",
  Joyous = "joyous", Inspired = "inspired",
}

-- plain Lua 5.1 has no bit ops: is the bit with value `value` set in n?
local function hasBit(n, value)
  return math.floor(n / value) % 2 == 1
end

--- "poison" | "burn" | "paralysis" | "freeze" | "sleep" | nil. The engine
--- stores a mon's status as a string ("PSN", "TOX"/"TOXIC", "BRN", "PAR",
--- "SLP", "FRZ", also "POISON"...), as the GBA status bitfield (sleep turns
--- in bits 0-2, then PSN 8, BRN 16, FRZ 32, PAR 64, TOX 128), and/or as a
--- separate `sleep` turn counter -- all of them are understood here.
function MonMood.statusOf(mon)
  if type(mon) ~= "table" then return nil end
  local st = mon.status
  if type(st) == "string" then
    local s = st:upper()
    if s == "PSN" or s == "TOX" or s == "TOXIC" or s == "POISON" or s == "PSN_TOX" then return "poison" end
    if s == "BRN" or s == "BURN" then return "burn" end
    if s == "PAR" or s == "PARALYSIS" or s == "PARALYZED" then return "paralysis" end
    if s == "FRZ" or s == "FREEZE" or s == "FROZEN" then return "freeze" end
    if s == "SLP" or s == "SLEEP" or s == "ASLEEP" then return "sleep" end
    st = tonumber(st)
  end
  local n = tonumber(st) or 0
  if n > 0 then
    if n % 8 ~= 0 then return "sleep" end
    if hasBit(n, 8) or hasBit(n, 128) then return "poison" end
    if hasBit(n, 16) then return "burn" end
    if hasBit(n, 32) then return "freeze" end
    if hasBit(n, 64) then return "paralysis" end
  end
  if (tonumber(mon.sleep) or 0) > 0 then return "sleep" end
  return nil
end

--- HP as a 0..1 fraction, or nil when the mon has no usable HP fields.
function MonMood.hpFraction(mon)
  if type(mon) ~= "table" then return nil end
  local maxHp = tonumber(mon.maxHp) or tonumber(mon.maxhp)
  local hp = tonumber(mon.hp) or tonumber(mon.currentHp)
  if not maxHp or maxHp <= 0 or not hp then return nil end
  return math.max(0, math.min(1, hp / maxHp))
end

--- 0..255 friendship (the engine keeps it in both `friendship` and
--- `happiness`).
function MonMood.friendshipOf(mon)
  local f = type(mon) == "table" and (tonumber(mon.friendship) or tonumber(mon.happiness)) or nil
  if not f then return MonMood.DEFAULT_FRIENDSHIP end
  return math.max(0, math.min(255, f))
end

--- Emotion for the friendship alone (the tier table above).
function MonMood.friendshipEmotion(friendship)
  local emotion = MonMood.FRIENDSHIP_TIERS[1][2]
  for _, tier in ipairs(MonMood.FRIENDSHIP_TIERS) do
    if friendship >= tier[1] then emotion = tier[2] end
  end
  return emotion
end

--- (emotion, reason) for a party mon's current state (priority order in the
--- header). `reason` names WHY, for dialogue: "fainted", "critical",
--- "poison", "burn", "paralysis", "freeze", "sleep", "low", "hurt", then for a
--- healthy mon its friendship tier ("angry", "sad", "normal", "happy",
--- "joyous", "inspired") -- or "sore" for a Joyous/Inspired mon that is only
--- slightly hurt. A nil/unusable mon reads as "Normal", "normal".
function MonMood.read(mon)
  if type(mon) ~= "table" then return "Normal", "normal" end
  local frac = MonMood.hpFraction(mon)
  if frac and frac <= 0 then return "Teary-Eyed", "fainted" end
  if frac and frac <= MonMood.CRITICAL_HP then return "Crying", "critical" end
  local status = MonMood.statusOf(mon)
  if status then return STATUS_EMOTION[status], status end
  if frac and frac <= MonMood.LOW_HP then return "Pain", "low" end
  if frac and frac < MonMood.HURT_HP then return "Worried", "hurt" end
  local emotion = MonMood.friendshipEmotion(MonMood.friendshipOf(mon))
  if frac and frac < 1 and (emotion == "Joyous" or emotion == "Inspired") then
    return "Happy", "sore"
  end
  return emotion, FRIENDSHIP_REASON[emotion]
end

--- The portrait emotion for a party mon's current state.
function MonMood.emotionFor(mon)
  return (MonMood.read(mon))
end

return MonMood
