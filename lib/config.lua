-- Tunables and option helpers for wilds_of_hoenn.
local V = ...

local Config = {}

Config.DEFAULTS = {
  enabled = true,
  sprite_style = "pmd",
  classic_enc = true,
  wild_silhouettes = "off",
  shiny_rate = "native",
}

Config.STATE = {
  AVAILABLE = "available",
  ENCOUNTER_STARTING = "encounter_starting",
  DESPAWNED = "despawned",
}

-- Density: fixed in v1 (no "Spawn Amount" option -- see
-- docs/ARCHITECTURE.md's "what v1 deliberately leaves out").
Config.MIN_VISIBLE = 1
Config.MAX_VISIBLE = 8
Config.TILES_PER_ADDITIONAL = 20

-- Idle wing-flap for floating/flying species: logic ticks each pose of the
-- walkA/stand/walkB/stand cycle is held (~1.3s per full cycle at 60 ticks/s).
Config.IDLE_FLAP_TICKS = 20

-- Follower action scenes (lib/follower_actions.lua), all in 60 Hz ticks / px.
-- Pet: its Idle loop (capped), then one cry. Talk: `cries` cries in a row.
-- Play: a thrown ball, the follower runs to it, spins, runs back.
Config.ACTIONS = {
  maxTicks = 900,           -- hard cap: no scene may hold the field lock longer
  play = {
    ballDist = 3,           -- cells the ball may fly (stops short of obstacles)
    throwTicks = 26,        -- ball flight; the player's arms-up pose lasts through it
    playerPoseTicks = 24,
    runSpeed = 1.6,         -- px per tick, out and back
    spinTicksPerFacing = 6, -- ticks per quarter turn
    spins = 2,              -- full circles
    arcHeight = 18,         -- px, peak of the ball's arc
  },
  pet = { idleSpeed = 1.5, maxIdleTicks = 90, minIdleTicks = 36 },
  talk = { cries = 2, gap = 8, cryTimeout = 90 },
}

-- Battler role (lib/overworld_battle.lua): all ticks / px / cells.
Config.OW_BATTLE = {
  radius = 3,           -- a wild Pokemon this close to the PLAYER (cells) may be fought
  maxWalk = 8,          -- longest charge, in cells
  scanEvery = 12,       -- ticks between looks for a target (only while everything is still)
  cooldown = 90,        -- ticks of calm after a fight
  chaseSpeed = 2.4,     -- px per tick charging in / running back
  walkMul = 2,          -- how much faster its Walk animation plays while charging
  windup = 10,          -- ticks from the start of a turn to the blow landing
  turnTicks = 34,       -- one side's whole turn
  lunge = 7,            -- px the attacker leans toward its target
  flashTicks = 12,      -- red hit flash / hurt animation
  attackSpeed = 1.6,    -- animation rate of attack / hurt
  winPause = 36,        -- ticks the cry plays before the defeated Pokemon sinks
  sinkTicks = 40,       -- ... then it sinks into the ground over this long
  cryPause = 36,        -- the Battler's cry before it shrinks into the player
  recallTicks = 18,     -- shrinking in / growing back out (the PMD recall length)
  restCheck = 30,       -- ticks between "healed yet?" checks while resting
  popupTicks = 110,     -- "+EXP" label time
  expShare = 0.5,       -- fraction of the engine's EXP value a win is worth
  resumeFrac = 0.25,    -- healed past this share of max HP (with PP) it may fight again
}

-- Forager role (lib/forager.lua): all ticks / px / cells.
Config.FORAGE = {
  minSpread = 5,         -- a wander / forage spot is this many cells from the PLAYER ...
  maxSpread = 10,        -- ... to this many
  maxWalk = 14,          -- longest walk to a spot, in cells (the way round obstacles)
  forageMin = 600,       -- ticks of walking (10 s) between forages ...
  forageMax = 1800,      -- ... to 30 s (re-rolled each time; only counts where foraging is allowed)
  findChance = 0.2,      -- chance a forage turns up an item
  -- map types it may forage on: 3 = route (outside), 4 = underground (caves). Towns,
  -- cities, buildings, water and secret bases are off limits.
  allowedMapTypes = { [3] = true, [4] = true },
  wanderWaitMin = 40,    -- ticks it trots beside the player between wanders ...
  wanderWaitMax = 150,   -- ... to this many (only counted while the player moves)
  lingerMin = 25,        -- ticks it sniffs about at a wander spot ...
  lingerMax = 70,        -- ... to this many
  walkSpeed = 1.5,       -- px per tick going out on a wander
  forageSpeed = 2.2,     -- px per tick going out to forage
  runSpeed = 2.8,        -- px per tick running back to the player
  cryPause = 30,         -- ticks after the alert cry before it digs
  digTicks = 90,         -- digging at the spot
  popupTicks = 150,      -- the "found X" label stays up
  maxTmPrice = 3000,     -- TMs dearer than this are "high level" and never found
  blocklist = {},        -- extra item names to never find
}

-- PMDCollab style (lib/pmd_renderer.lua). The ground point of a PMD frame
-- (the shadow marker) is placed at the tile's horizontal centre and
-- PMD_GROUND_Y pixels below the tile's top edge (a 16px tile; 12 puts the
-- feet just above its bottom edge). PMD_SCALE multiplies the art, and
-- PMD_WALK_SPEED multiplies the Walk animation clock (1 = the durations in
-- AnimData.xml). All three are meant to be tuned by eye in game.
Config.PMD_SCALE = 1
-- The bake records a per-species upscale (HGSS true size / PMD height) in
-- index.json. It made big species look oversized, so it is OFF: every PMD
-- sprite draws at PMD_SCALE x 1. Set true to apply the baked scales again.
Config.PMD_TRUE_SIZE = false
Config.PMD_GROUND_Y = 12
Config.PMD_WALK_SPEED = 1
-- The PMDCollab follower: extra px of space kept behind the player on top of
-- the sprite's own overhang (a sprite wider/taller than the 16px tile would
-- otherwise overlap the player), and how many ticks it rests on the Idle
-- loop's first frame after stopping before the loop starts (300 ticks = 5 s
-- of no movement at 60 Hz), and how fast that Idle loop then plays (0.5 =
-- half speed). Wild Pokemon have no delay but play Idle at PMD_WILD_IDLE_SPEED
-- (0.75 = slowed down by 25%).
-- facing down, only this fraction of a tall sprite's overhang is kept behind
-- the player (a big sprite like Rayquaza otherwise trails too far above)
Config.PMD_FOLLOWER_DOWN_OVERHANG = 0.6
-- Fastest the follower's offset may slide when the player changes direction,
-- in px per tick (small sprites turn slower than this anyway; a big one takes
-- longer instead of snapping)
Config.PMD_FOLLOWER_TURN_SPEED = 1
Config.PMD_FOLLOWER_GAP_DOWN = 0 -- the gap while facing down (trailing above the player)
Config.PMD_FOLLOWER_GAP = 4
Config.PMD_FOLLOWER_IDLE_DELAY = 300
Config.PMD_FOLLOWER_IDLE_SPEED = 0.5
Config.PMD_WILD_IDLE_SPEED = 0.75

-- Follower interaction (lib/follower_interaction.lua, lib/interaction_limiter.lua).
-- All times are real seconds.
--   cooldown      gap needed since the last SUCCESSFUL use of that action
--   window / maxGains   at most `maxGains` successful interactions per rolling `window`
--   abuseWindow / abuseAttempts   this many selections (refused ones count)
--                 inside the window locks the menu
--   lockBase..lockMax   first lock length, doubled per repeat offence, capped
--   strikeReset   quiet time after which the repeat-offence count starts over
--   gain          friendship points for Play/Talk (Pet uses the engine's own
--                 MASSAGE friendship event, tier-aware, Soothe Bell etc. apply)
Config.INTERACT = {
  cooldown = { pet = 30, play = 45, talk = 15 },
  window = 600, maxGains = 6,
  abuseWindow = 45, abuseAttempts = 6,
  lockBase = 300, lockMax = 3600, strikeReset = 7200,
  gain = { play = 2, talk = 1 },
}

-- Reachable-only spawns (lib/reachability.lua): visible wild Pokemon appear
-- only on cells the player can actually get to from where they stand --
-- walking, hopping ledges, and surfing once Surf is usable; a Cut tree, rock
-- or boulder blocks until the matching move is usable. REACH_REBUILD_TICKS:
-- how often (while the player stands still) the area is re-measured, so
-- learning Surf or clearing a tree opens new ground (60 ticks = 1 s).
Config.REACHABLE_SPAWNS = true
Config.REACH_REBUILD_TICKS = 900

-- PMDCollab follower while the player surfs (PMD has no swim art): it shrinks
-- into the player like a recall, and grows back out once on land. Duration of
-- the shrink/grow in ticks (60 = 1 s), and how far (px) it rises toward the
-- player's body as it goes in.
Config.PMD_RECALL_TICKS = 18
Config.PMD_RECALL_LIFT = 8

-- Portrait box nudge in canvas pixels (lib/portrait_ui.lua), added to its
-- default spot above the left of the dialogue frame.
Config.PORTRAIT_X = 0
Config.PORTRAIT_Y = 0

--- Reads and compiles options.lua fresh (not cached -- this only runs once
--- at boot) and hands the schema table to the Mod Manager. Same pattern as
--- Wilds of Kanto Revival's lib/config.lua: the manifest's
--- "options_schema" field is a hint for external tooling, not something
--- the engine auto-registers for a mod -- the mod must call
--- mod.options:define itself.
function Config.defineOptions(mod)
  local source = mod:read("options.lua")
  if not source then
    error("wilds_of_hoenn: options.lua is missing", 0)
  end
  local loadcode = loadstring or load
  local chunk, err = loadcode(source, "@" .. mod.path .. "/options.lua")
  if not chunk then
    error(("wilds_of_hoenn: options.lua did not compile: %s"):format(tostring(err)), 0)
  end
  local schema = chunk()
  -- The HGSS-only release ships no PMDCollab art: don't offer a style that
  -- would silently draw HGSS anyway.
  if not Config.hasPmdArt(mod) then Config.withoutPmdStyle(schema) end
  mod.options:define(schema)
end

-- Is PMDCollab art installed? (assets/pmd/index.json -- shipped loose even in an
-- atlas build -- exists in the HGSS + PMDCollab release and in a dev checkout
-- with a bake, and not in the HGSS-only release.) Cached per mod.
local pmdArtCache = setmetatable({}, { __mode = "k" })
function Config.hasPmdArt(mod)
  if type(mod) ~= "table" then return false end
  local hit = pmdArtCache[mod]
  if hit ~= nil then return hit end
  local has = false
  if type(mod.read) == "function" then
    local ok, data = pcall(mod.read, mod, "assets/pmd/index.json")
    has = ok and data ~= nil
  end
  pmdArtCache[mod] = has
  return has
end

--- Removes the PMDCollab choice from the Sprite Style row of an option schema
--- (in place) and makes HGSS / PokeMMO its default.
function Config.withoutPmdStyle(schema)
  for _, row in ipairs(schema) do
    if row.key == "sprite_style" and type(row.choices) == "table" then
      local kept = {}
      for _, choice in ipairs(row.choices) do
        if choice[2] ~= "pmd" then kept[#kept + 1] = choice end
      end
      row.choices = kept
      row.default = "pokemmo"
      if type(row.description) == "string" then
        row.description = row.description:gsub("%s*PMDCollab uses.*$", "")
      end
    end
  end
  return schema
end

local function optGet(mod, key)
  if mod and mod.options and type(mod.options.get) == "function" then
    local v = mod.options:get(key)
    if v ~= nil then return v end
  end
  return Config.DEFAULTS[key]
end

function Config.get(mod, key)
  return optGet(mod, key)
end

function Config.enabled(mod)
  return optGet(mod, "enabled") == true
end

local VALID_SPRITE_STYLE = { pokemmo = true, pmd = true }

--- PMDCollab when its art is installed, else HGSS / PokeMMO.
function Config.defaultSpriteStyle(mod)
  return Config.hasPmdArt(mod) and "pmd" or "pokemmo"
end

function Config.spriteStyle(mod)
  local v = optGet(mod, "sprite_style")
  if not VALID_SPRITE_STYLE[v] then return Config.defaultSpriteStyle(mod) end
  -- a save made with the PMDCollab release, loaded in the HGSS-only one
  if v == "pmd" and not Config.hasPmdArt(mod) then return "pokemmo" end
  return v
end

function Config.classicEncEnabled(mod)
  return optGet(mod, "classic_enc") == true
end

local VALID_SILHOUETTE = { off = true, undiscovered = true, all = true }
function Config.silhouetteMode(mod)
  local v = optGet(mod, "wild_silhouettes")
  if VALID_SILHOUETTE[v] then return v end
  return Config.DEFAULTS.wild_silhouettes
end

-- "native" = trust whatever the engine's own roll already decided (no
-- reroll). "rNNNN" = reroll a non-shiny encounter at that chance (see
-- lib/shiny.lua's RATE_DENOM). "all" = always shiny. Matches Wilds of
-- Kanto Revival's SHINY RATE tiering; no "off" -- see options.lua.
local VALID_SHINY_RATE = {
  native = true, r4096 = true, r2048 = true, r1024 = true, r500 = true, r100 = true, r10 = true,
  all = true,
}
function Config.shinyRate(mod)
  local v = optGet(mod, "shiny_rate")
  if VALID_SHINY_RATE[v] then return v end
  return Config.DEFAULTS.shiny_rate
end

--- There is no Follower option any more: a companion is always out (who, and
--- what it does, is chosen from the party menu -- lib/companion.lua). Kept as a
--- function so the callers that ask stay one-liners.
function Config.followerEnabled(_mod)
  return true
end

return Config
