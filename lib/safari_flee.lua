-- Safari Zone flee rates for species the Safari Zone never had (pure).
--
-- FireRed / LeafGreen give each Safari species its own flee rate (BaseStats
-- safariZoneFleeRate); every other species has 0, which the engine (like the game)
-- turns into the lowest escape factor, so one that wanders into the Safari Zone -- a
-- visible spawn or a classic encounter Modern Spawns brought there, or a National Dex
-- species with no entry at all -- would almost never run. The real table follows the
-- catch rate: easy-to-catch Pokemon (catch rate 150+) flee at 50, middling ones (60-149)
-- at 75, rare ones (under 60) at 125 (only Magikarp 25 and Dratini 100 stray from it).
-- A species without its own rate gets the one its catch rate's band has in that table.
-- Ruby / Sapphire / Emerald have no per-species rate (one escape factor for all), so
-- this is FRLG only (lib/engine_patch.lua fitSafariFlee).
local V = ...
local Config = V.require("config")

local SafariFlee = {}

--- The flee rate a species with catch rate `catchRate` would have in the FRLG table.
function SafariFlee.rateFor(catchRate)
  local c = tonumber(catchRate) or 45
  for _, band in ipairs(Config.SAFARI_FLEE) do
    if c >= band[1] then return band[2] end
  end
  return Config.SAFARI_FLEE[#Config.SAFARI_FLEE][2]
end

--- The engine's escape factor for flee rate `rate` (battle/rules.lua escapeFactor,
--- pokefirered battle_main.c:2285): rate * 100 / 1275, at least 2.
function SafariFlee.escapeFactor(rate)
  local f = math.floor((tonumber(rate) or 0) * 100 / 1275)
  if f <= 1 then f = 2 end
  return f
end

--- The flee rate to use for a species: its own (`ownRate` > 0), else its band's.
function SafariFlee.fitted(ownRate, catchRate)
  local own = tonumber(ownRate) or 0
  if own > 0 then return own, false end
  return SafariFlee.rateFor(catchRate), true
end

return SafariFlee
