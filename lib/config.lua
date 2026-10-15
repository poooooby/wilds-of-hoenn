-- Tunables and option helpers for wilds_of_hoenn.
local V = ...

local Config = {}

Config.DEFAULTS = {
  enabled = true,
  sprite_style = "pmd",
  classic_enc = true,
  wild_silhouettes = "off",
  species_sizes = true,
  spawn_amount = "normal",
  flyers = "full",
  smooth_follow = true,
  portraits = true,
  wild_reacts = true,
  water_life = true,
  local_scenes = true,
}

Config.STATE = {
  AVAILABLE = "available",
  ENCOUNTER_STARTING = "encounter_starting",
  DESPAWNED = "despawned",
  -- on its way out (SpawnManager:despawn with animate): still drawn, sinking back
  -- into the grass / fading, but no longer met, counted or fought
  LEAVING = "leaving",
}

-- How wild Pokemon arrive and leave (lib/spawn_fx.lua): rising out of the grass with a
-- rustle, surfacing with a ripple on water, a fade anywhere else; the same reversed when
-- one leaves. Ticks at 60 per second.
Config.SPAWN_FX = { appearTicks = 26, leaveTicks = 22 }

-- Density, per terrain (land and water each): MIN_VISIBLE plus one more Pokemon for
-- every TILES_PER_ADDITIONAL eligible tiles, at most MAX_VISIBLE. These are the
-- Normal values of the Spawn Amount option; SPAWN_AMOUNT holds Low and High.
Config.MIN_VISIBLE = 1
Config.MAX_VISIBLE = 8
Config.TILES_PER_ADDITIONAL = 20
Config.SPAWN_AMOUNT = {
  low = { min = 1, max = 4, tilesPer = 40 },     -- about half
  normal = { min = Config.MIN_VISIBLE, max = Config.MAX_VISIBLE, tilesPer = Config.TILES_PER_ADDITIONAL },
  high = { min = 2, max = 12, tilesPer = 13 },   -- about one and a half times
}

-- Sweet Scent used in the field while Show Wild Mons is on: instead of the engine's
-- instant wild battle, `min`..`max` wild Pokemon are called to free spawn cells
-- `minDist`..`maxDist` tiles from the player (the greater of the x / y distances). They
-- stay put, with rising hearts, for `lureTicks` (60 per second), then wander as usual;
-- a battle with one starts with the foe's evasion at `evasion` stages (-1 = 75%, like the
-- in-battle move). They come on top of the Spawn Amount target.
Config.SWEET_SCENT = { min = 2, max = 3, minDist = 1, maxDist = 4, lureTicks = 3600, evasion = -1 }

-- Flying Pokemon in the sky (lib/sky_flyers.lua, lib/flight_path.lua, lib/sky_draw.lua),
-- 60 Hz ticks / px. The camera looks straight down, so a bird higher up is CLOSER to it:
-- bigger (`scale`), sliding faster across the ground (`parallax`, about the view's
-- centre) and out of focus (`blur`, px of the drawn sprite), hazed toward the sky and
-- see-through. `h` 0 = low (landing, perched), 0.5 = mid, 1 = high; between, interpolated.
Config.FLYERS = {
  layers = {
    { h = 0,   scale = 1.0, parallax = 1.0,  blur = 0,   alpha = 1.0,  haze = 0 },
    { h = 0.5, scale = 1.4, parallax = 1.25, blur = 1.0, alpha = 0.95, haze = 0.12 },
    { h = 1,   scale = 2.0, parallax = 1.6,  blur = 2.5, alpha = 0.85, haze = 0.25 },
  },
  sharpBelow = 0.15, sharpAbove = 0.25, -- low birds draw sharp (gen3-hd-sprites sized); crossfade between
  haze = { 0.86, 0.93, 1.0 },           -- the sky colour far birds fade toward
  flapTicks = 6,                        -- HGSS wing beat (walkA / walkB)
  -- the occasional bird overhead: one at a time, every 30-70 s, crossing the TOP of the screen
  -- (its feet within the top `band` of the view) on a gentle arc of `arc` px, never straight
  -- (the high one bobs up and down as it goes, `bob` px either way, a beat every `bobTicks`).
  -- It starts in the band, then moves in perspective as the view scrolls (not held there).
  passer = { every = { 1800, 4200 }, max = 1, maxHigh = 1, ticks = { 300, 480 }, highTicks = { 240, 360 },
             band = 0.22, arc = { 6, 16 }, bob = { 2, 4 }, bobTicks = { 40, 56 } },
  -- a swoop (landing, perching, diving, leaving) starts / ends off screen, mid or high up
  -- (startH, in hundredths), from any side, curving so its path never comes within
  -- `clearRadius` tiles of the player; a wild Pokemon that close arrives / leaves the usual way
  swoop = { startH = { 55, 100 }, clearRadius = 3, arc = { 10, 28 } },
  perch = { every = { 600, 1500 }, max = 2, stay = { 600, 2400 }, fidget = { 180, 480 },
            flyTicks = { 80, 110 }, scatter = 2, scatterRunning = 3, cryChance = 0.2 },
  dive = { every = { 900, 2400 }, under = { 120, 300 }, flyTicks = { 70, 90 }, sinkTicks = 14 },
  -- a wild Flying-type Pokemon arriving / leaving by air instead of rising out of the grass
  land = { flyTicks = { 80, 100 }, perchChance = 0.4, perchRange = 4, sit = { 180, 480 }, hopTicks = 22,
           groundStay = { 2700, 7200 } },
  hopHeight = 3, hopTicks = 12,         -- a perched bird's little hop
  perchLift = { canopy = 6, sign = 10 },
  stormSlowdown = 2,                    -- rain / sandstorm: everything comes this many times less often
  -- which Flying types are birds (lib/sky_flyers.lua SkyFlyers.flies): none taller than
  -- maxBirdHeightDm in the Pokedex (decimetres: Gyarados 65, Rayquaza 70), and none of
  -- `notBirds` (national dex): the flightless Doduo, Dodrio, Delibird, and those the flyer
  -- audit ruled out (no art that reads as flying; tools/generate_pmd_sprites.py FLY_SOURCE
  -- holds what the others fly with)
  notBirds = {
    [6] = true, [36] = true, [84] = true, [85] = true, [163] = true, [178] = true, [225] = true,
    [587] = true, [629] = true, [641] = true, [642] = true, [645] = true, [732] = true,
    [733] = true, [905] = true, [993] = true,
  },
  maxBirdHeightDm = 30,
  -- the real birds (national dex): only these dive into the sea (a Water / sea Flying type
  -- that is no bird -- Mantine, Gyarados, a Flying bug -- never does)
  realBirds = {
    [16] = true, [17] = true, [18] = true, [21] = true, [22] = true, [83] = true, [144] = true,
    [145] = true, [146] = true, [164] = true, [177] = true, [198] = true, [227] = true, [250] = true,
    [276] = true, [277] = true, [278] = true, [279] = true, [333] = true, [334] = true, [396] = true,
    [397] = true, [398] = true, [430] = true, [441] = true, [519] = true, [520] = true, [521] = true,
    [566] = true, [567] = true, [580] = true, [581] = true, [627] = true, [628] = true, [630] = true,
    [661] = true, [662] = true, [663] = true, [731] = true, [741] = true, [821] = true, [822] = true,
    [823] = true, [845] = true, [865] = true, [931] = true, [940] = true, [941] = true, [962] = true,
    [973] = true,
  },
  maxAmbientWidth = 56,                 -- px: bigger art stays out of the ambient sky (it would cover the view)
}

-- Wild Pokemon reacting to a player who runs or bikes close by (the Wild Reacts option,
-- lib/wild_reactions.lua). 60 Hz ticks; distances in tiles (the greater of the x / y
-- distances). Strength is level x base-stat total against the lead Pokemon's: under
-- `weakRatio` it is startled ("!") and flees (a bird takes off), over `strongRatio` it gets
-- angry and chases; an even match in between is not bothered.
Config.REACT = {
  radius = 4, bikeRadius = 5,     -- how close the running / biking player has to come
  aggroRadius = 2, bikeAggroRadius = 3, -- ...for a stronger one to get angry: much closer
  weakRatio = 0.7, strongRatio = 1.3,
  -- how likely it reacts at all, by how far past its threshold the ratio is: `minChance` %
  -- just past it, rising evenly to 100% at `weakSure` (fleeing) / `strongSure` (chasing).
  -- One roll as the player comes in range; a miss rests `missCooldown` ticks
  minChance = 25, weakSure = 0.4, strongSure = 2.0, missCooldown = 300,
  alertTicks = 24,                -- "!" before fleeing / taking off
  turnTicks = 22,                 -- a stronger one's pause before it turns to the player
  angerTicks = 36,                -- then the anger mark, then the chase
  emoteTicks = 50,                -- how long an emote stays up
  hopTicks = 12, hopPx = 3,       -- a startled little hop
  -- running pace; at the end of its run, `vanishChance` % of them disappear -- in grass
  -- shrinking into it with a rustle, in a cave fading out (lib/spawn_manager.lua fleeVanish)
  flee = { steps = { 3, 6 }, frames = 8, vanishChance = 30 },
  chase = { frames = 7,           -- a touch faster than a running player (8)
            leash = { 4, 10 },    -- tiles it follows before giving up: rolled every chase
            -- PMDCollab: it charges with its Attack animation while it chases and on until
            -- its battle opens; no battle within `chargeTicks` of catching up -> it calms down
            chargeTicks = 90,
            secondsPerTile = 1.2, -- the matching time limit (leash x this)
            noPathTicks = 60, returnSteps = { 2, 4 } },
  cooldown = 600, chaseCooldown = 900, -- before the same Pokemon reacts again
}

-- Life in the water (the Water Life option, lib/water_life.lua): ambient, never met or
-- fought, drawn from the map's own fishing and Surf tables. 60 Hz ticks / px.
--   leapers -- small fish (the Water 2 egg group -- the fish -- under `maxFishHeightDm`,
--              plus `fishExtra`, minus `notFish`, national dex) jump out of the water and
--              back in with a splash;
--   whales  -- `whales` (Wailmer, Wailord) rise to the surface, drift or lie still a while,
--              blow a spray from their blowhole, and sink back under.
Config.WATER_LIFE = {
  maxFishHeightDm = 10,
  fishExtra = { [349] = true },                                -- Feebas (Water 1 / Dragon egg groups)
  notFish = { [116] = true, [224] = true, [686] = true },      -- Horsea, Octillery, Inkay
  whales = { [320] = true, [321] = true },                     -- Wailmer, Wailord
  leap = { every = { 420, 1200 }, max = 2, ticks = { 34, 44 }, height = 18, pmdHeight = 8, drift = 12 },
  whale = { every = { 1500, 3300 }, max = 1, riseTicks = 50, stay = { 240, 480 }, drift = { 0, 1 },
            sprays = { 1, 2 }, sprayTicks = 48 },
  minPlayerDist = 2,                                           -- tiles kept clear of the player
  -- Finizen (national dex `species`, drawn by its own art whether or not the game has it), rare,
  -- on a SEA map only (its Surf / fishing tables hold one of `seaMarkers`): a dolphin -- it
  -- surfaces with a puff from its blowhole, porpoises along in `leaps` arcs `leapDist` px
  -- apart (gliding at the surface `glideTicks` between them, puffing now and then), and dives.
  -- Now and then (`podChance` %) a pod of `pod` instead: they surface together, swim round in
  -- a ring (`ring` = x / y radius px; a lap every `lapTicks`) taking turns to leap for
  -- `play` ticks, then go under. `surfaceShow`: how much of a Finizen at the surface shows above the water (its back and fin).
  -- Drawn at its Species Sizes size (HGSS_scale / PMD_scale), never enlarged.
  dolphin = { species = 963, every = { 5400, 10800 }, leaps = { 2, 4 }, leapDist = 26, leapTicks = 30,
              height = 16, pmdHeight = 11, glideTicks = 14, glideDist = 8, riseTicks = 18,
              puffTicks = 16, puffPower = 0.55, puffChance = 50, surfaceShow = 0.45,
              podChance = 12, pod = { 3, 5 }, ring = { 26, 10 }, lapTicks = 170, play = { 480, 720 },
              podLeapEvery = 95, podStagger = 12 },
  seaMarkers = { [72] = true, [73] = true, [222] = true, [278] = true, [279] = true, [318] = true,
                 [319] = true, [320] = true, [321] = true, [370] = true },
  -- under the sea (Dive maps): every fish the game knows, National Dex included (Water 2 egg group, no
  -- legendary -- the Undiscovered group -- nothing over swim.maxHeightDm) swim across as dark
  -- shadows of themselves, wiggling, trailing bubbles; small ones sometimes in a school.
  -- Like the birds, depth is distance from the camera: near the surface (h 1) bigger,
  -- sliding faster, softer and fainter; down by the seabed (h 0) smaller and sharper.
  swim = { every = { 240, 600 }, max = 3, ticks = { 360, 600 }, maxHeightDm = 20,
           schoolChance = 40, school = { 3, 4 }, schoolMaxHeightDm = 6, schoolSpread = 14,
           wave = { amp = 6, cycles = { 3, 5 } }, curve = 30, bubbleEvery = { 18, 36 }, bubbleTicks = 50,
           -- the body's own wiggle while it swims: a quick side to side sway across its way,
           -- `px` either side, a full beat every `ticks`
           wiggle = { px = 2, ticks = 14 },
           layers = {
             { h = 0, scale = 0.85, parallax = 1.0, blur = 0,   alpha = 0.5,  haze = 0 },
             { h = 1, scale = 1.35, parallax = 1.2, blur = 1.5, alpha = 0.32, haze = 0 },
           } },
}

-- Local Scenes (the Local Scenes option, lib/local_scenes.lua): little moments tied to a
-- place, ambient, never met. 60 Hz ticks / px. `every` = the wait before the next scene of
-- each cadence (an "occasional" one about every 30 s, a "rare" one about every 2 min).
Config.LOCAL_SCENES = {
  every = { occasional = { 1500, 2100 }, rare = { 6000, 8400 } },
  minPlayerDist = 2,                     -- tiles kept clear of the player
  -- Lavender Town: a ghost fades in somewhere in view, wanders about a little (through
  -- walls: `moves` drifts of `step` cells, `stepTicks` a cell, a `pause` between), fades out
  ghost = { species = { 92, 92, 93 }, alpha = 0.55, fade = 60, shade = { 0.55, 0.45, 0.75 },
            moves = { 3, 5 }, step = { 1, 2 }, stepTicks = 40, pause = { 20, 80 } },
  -- ...and Gengar behind the player when the girl who asks about ghosts is told "No"
  -- (her No line's text key: FireRed, LeafGreen)
  gengar = { species = 94, chance = 25, behind = 2, alpha = 0.85, fade = 40, linger = 30,
             noText = { ["g3:0817f568"] = true, ["g3:0817f544"] = true } },
  -- Petalburg Woods: a bug lowered on a silk thread from under a tree's crown, hanging a
  -- while, then reeled back up. `drop` px below the crown's bottom edge.
  -- `scale`: drawn smaller than a wild Pokemon, so it hangs clear of the leaves
  hang = { burmy = { species = { 412 }, scale = 0.65, drop = { 6, 12 }, down = 90, stay = { 240, 480 }, up = 120, sway = 2, swayTicks = 150 },
           cocoon = { species = { 266, 268 }, scale = 0.65, drop = { 8, 14 }, down = 60, stay = { 300, 540 }, up = 90, sway = 4, swayTicks = 120 } },
  -- ...Slakoth asleep on a tree top
  sleeper = { species = 287, scale = 0.7, ticks = { 1200, 2400 }, fade = 30, zzzEvery = 40 },
  -- ...Vigoroth leaping onto a tree top from off screen, dancing, leaping off
  dancer = { species = 288, leapTicks = 50, leapHeight = 40, loops = 2, hgssTicks = 240 },
  -- Fortree City: a big Tropius rises out of the trees, walks a little over them, sinks back
  -- only the top `half` (70%) of it above the leaves (cut there), leaves rustling round it as it moves
  -- (PMDCollab: only the Idle frames with its wings all the way down, `wingsDown`, `poseTicks`
  -- each, walking too -- its Walk spreads them, the rest of its Idle raises them)
  -- `southHalf`: facing south (PMDCollab) it is shorter (seen from the front), so more shows
  tropius = { species = 357, scale = 1.5, half = 0.7, southHalf = 0.85, wingsDown = { 1, 4, 7, 10 }, poseTicks = 18, rise = 180, steps = { 2, 4 }, stepTicks = 48, rest = { 60, 150 } },
}

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

-- Swapping the companion (lib/follower_swap.lua): all ticks / px.
Config.SWAP = {
  poseTicks = 26,    -- the player's arm-up pose, a Poke Ball in hand, per phase
  recallDelay = 10,  -- ticks of holding the ball up before the old one shrinks in
  sendDelay = 12,    -- ... before the new one grows out
  ballLift = 19,     -- px the ball is held above the player's feet
  ballX = 6,         -- px to the side: the raised hand
  maxTicks = 240,    -- hard cap: the scene may not hold the field lock longer
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

-- Forager role (lib/forager.lua, lib/forage_items.lua): all ticks / px / cells.
-- It only ever leaves the player's side for a find, and every trip finds something.
Config.FORAGE = {
  minSpread = 3,         -- the find is this many cells from the PLAYER ...
  maxSpread = 5,         -- ... to this many
  maxWalk = 12,          -- longest walk to it, in cells (round obstacles; the player keeps walking during the tell)
  -- one find per 1-3 minutes of WALKING (only counted where foraging is allowed). The wait
  -- leans long at low friendship and short at high: goal = min + (max - min) * r ^ e, with
  -- e = skewLow at friendship 0 rising to skewHigh at 255 (mean ~140 s -> ~90 s).
  intervalMin = 3600,
  intervalMax = 10800,
  skewLow = 0.5,
  skewHigh = 3.0,
  retryTicks = 60,       -- no spot / nothing that fits the bag yet: look again this much later
  -- map types it may forage on: 3 = route (outside), 4 = underground (caves). Towns,
  -- cities, buildings, water and secret bases are off limits.
  allowedMapTypes = { [3] = true, [4] = true },
  -- the tell: it stops and perks up (a sparkle shows where it is going), then dashes there;
  -- both get more eager with friendship
  perkMax = 45,          -- ticks of the tell at friendship 0 ...
  perkMin = 30,          -- ... down to this at 255
  forageSpeedMin = 2.2,  -- px per tick dashing out at friendship 0 ...
  forageSpeedMax = 3.0,  -- ... up to this at 255
  runSpeed = 2.8,        -- px per tick running back to the player
  digTicks = 90,         -- digging at the spot
  cryPause = 30,         -- after a common find: the cry, then this pause
  cryGap = 40,           -- a rare find cries twice, this far apart ...
  rarePause = 70,        -- ... and stays put this long (tier 3)
  rarePause4 = 90,       -- ... or this long (tier 4)
  popupTicks = 150,      -- the "Found X!" label (tiers 1-2) ...
  popupTicksRare = 240,  -- ... tier 3
  popupTicksTop = 300,   -- ... tier 4
  -- what it finds (lib/forage_items.lua): first a TIER by friendship, then an item in it.
  -- bands are MonMood.FRIENDSHIP_TIERS (0 Angry, 30 Sad, 70 Normal, 130 Happy, 200 Joyous,
  -- 255 Inspired); a tier below its gate never comes up.
  bands = { 0, 30, 70, 130, 200, 255 },
  tierBase = { 100, 35, 12, 3 },
  tierGate = { 0, 0, 130, 200 },
  tierMult = {             -- per band: { T1, T2, T3, T4 }
    { 1.00, 1.00, 0, 0 },  -- 0-29
    { 0.95, 1.10, 0, 0 },  -- 30-69
    { 0.90, 1.25, 0, 0 },  -- 70-129
    { 0.80, 1.35, 1.0, 0 },-- 130-199
    { 0.70, 1.40, 1.6, 1.0 }, -- 200-254
    { 0.60, 1.40, 2.6, 2.5 }, -- 255
  },
  evoTop = 3000,         -- an evolution item this dear (or dearer) is tier 4, else tier 3
  maxTmPrice = 3000,     -- TMs dearer than this are "high level" and never found
  blocklist = {},        -- extra item names to never find
}

-- PMDCollab style (lib/pmd_renderer.lua). A PMD frame stands on the ground like
-- the player: centred on the 16px tile, its feet (the bake's `foot` line: where the
-- art rests most of the time) PMD_FEET_Y px below the tile's top edge -- 15, the
-- player's own feet, 1 px above the tile's bottom edge
-- (PmdRenderer.groundOf: a flyer hovering above its shadow keeps the hover). A non-flyer
-- whose art hovers over its shadow point is grounded on its art first
-- (SpriteSource.groundPmd). PMD_SCALE multiplies the art, and
-- PMD_WALK_SPEED multiplies the Walk animation clock (1 = the durations in
-- AnimData.xml). All three are meant to be tuned by eye in game.
Config.PMD_SCALE = 1
-- The bake records a per-species upscale (HGSS true size / PMD height) in
-- index.json. It made big species look oversized, so it is OFF: every PMD
-- sprite draws at PMD_SCALE x 1. Set true to apply the baked scales again.
Config.PMD_TRUE_SIZE = false
Config.PMD_FEET_Y = 15
-- A swimming PMD sprite (lib/pmd_renderer.lua) stands on its WATERLINE, the bottom of
-- its foam bowl, instead of its feet: this many px below the tile's top edge.
Config.PMD_SWIM_Y = 18
-- The HGSS / PokeMMO swimming sheets are drawn this many px lower than usual, so they
-- sit as low in the water as a PMD swimmer (PMD_SWIM_Y).
Config.SWIM_DROP = 4

-- Water reflections of wild Pokemon and the follower (lib/reflection.lua). The engine
-- recolours an NPC's reflection with a paler, bluer reflection palette; our art has
-- none, so each pixel is blended REFLECTION_MIX of the way toward REFLECTION_TINT.
-- OVERLAP: how far up the feet the mirrored image starts, like the engine's (2 px).
Config.REFLECTION_TINT = { 0.78, 0.86, 1.0 }
Config.REFLECTION_MIX = 0.45
Config.REFLECTION_OVERLAP = 2
Config.PMD_WALK_SPEED = 1
-- Ticks the Walk animation keeps playing after movement stops, so the one-tick
-- gaps between chained steps do not flick the sprite to the Idle pose and back.
Config.PMD_WALK_LINGER = 8
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
-- facing left or right, the same idea for a wide sprite (a long-tailed Tyranitar
-- otherwise trails nearly two tiles behind): only this fraction of its overhang is
-- kept behind the player. 1 = the full overhang (the old behaviour).
Config.PMD_FOLLOWER_SIDE_OVERHANG = 0.6
-- Fastest the follower's offset may slide when the player changes direction,
-- in px per tick (small sprites turn slower than this anyway; a big one takes
-- longer instead of snapping)
Config.PMD_FOLLOWER_TURN_SPEED = 1
Config.PMD_FOLLOWER_GAP_DOWN = 0 -- the gap while facing down (trailing above the player)
Config.PMD_FOLLOWER_GAP = 4
-- A tall follower in front of a house ducks under its eave (lib/eave_duck.lua): down by up
-- to `nudge` px first, then squashed toward its feet for the rest, never below `minScale`
-- of its height (anything still over is cut by the eave as before); a little wider while
-- squashed (`widen` x the squash), easing in and out by `ease` of the way each tick.
-- While it crouches more than `sweatFrom` it sweats (lib/sweat_drop.lua): one drop for a light
-- crouch, up to `sweatMax` drops, cycling faster, the harder it is squashed.
Config.FOLLOWER_DUCK = { nudge = 4, minScale = 0.5, widen = 0.15, ease = 0.2, sweatFrom = 0.03, sweatMax = 3 }
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
  gain = { play = 3, pet = 2, talk = 1 },
  petHealChance = 0.25, -- petting a Pokemon with a status condition: chance to cure it
}

-- Reachable-only spawns (lib/reachability.lua): visible wild Pokemon on LAND
-- appear only on cells the player can walk to from where they stand (ledges
-- hop one way; a Cut tree, rock or boulder blocks until the matching move is
-- usable). Surf plays no part: water Pokemon spawn on every lake and sea for
-- atmosphere, and land across the water fills in once the player is there.
-- The area is re-measured only when what it depends on changes (a tree cut, a
-- rock smashed, a boulder pushed, Cut / Rock Smash / Strength becoming usable):
-- checked every REACH_CHECK_TICKS, acted on once unchanged for REACH_SETTLE_TICKS
-- (a boulder puzzle's pushes cost one re-measure, after the player pauses).
-- REACH_REBUILD_TICKS: the plain timer used only if the engine hides its object
-- list (60 ticks = 1 s).
Config.REACHABLE_SPAWNS = true
Config.REACH_CHECK_TICKS = 60
Config.REACH_SETTLE_TICKS = 180
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
  -- (nor portraits: they are PMDCollab art too)
  if not Config.hasPmdArt(mod) then Config.withoutPmdStyle(schema) Config.withoutRow(schema, "portraits") end
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

--- The Smooth Follow option: the follower is spaced out behind the player either way;
--- on, it glides to its place on a turn, off it snaps there. On unless switched off.
--- Removes the row `key` from an option schema (in place).
function Config.withoutRow(schema, key)
  for i = #schema, 1, -1 do
    if schema[i].key == key then table.remove(schema, i) end
  end
  return schema
end

--- The Portraits option: the partner's portrait above its messages (lib/portrait_ui.lua).
function Config.portraitsEnabled(mod)
  return optGet(mod, "portraits") ~= false
end

function Config.smoothFollow(mod)
  return optGet(mod, "smooth_follow") ~= false
end

--- The Wild Reacts option: wild Pokemon flee from / chase a player running or biking
--- close by. On unless switched off.
function Config.wildReacts(mod)
  return optGet(mod, "wild_reacts") ~= false
end

--- The Water Life option: fish leaping, whales surfacing (lib/water_life.lua). On unless
--- switched off.
function Config.waterLife(mod)
  return optGet(mod, "water_life") ~= false
end

--- The Local Scenes option: little moments tied to a place (lib/local_scenes.lua). On
--- unless switched off.
function Config.localScenes(mod)
  return optGet(mod, "local_scenes") ~= false
end

function Config.classicEncEnabled(mod)
  return optGet(mod, "classic_enc") == true
end

--- The Spawn Amount option's density row ({ min, max, tilesPer }); Normal for
--- anything unknown.
function Config.spawnAmount(mod)
  local v = optGet(mod, "spawn_amount")
  return Config.SPAWN_AMOUNT[v] or Config.SPAWN_AMOUNT.normal, Config.SPAWN_AMOUNT[v] and v or "normal"
end

--- The Flying Mons option: birds in the sky, perching, and wild Flying-type Pokemon
--- arriving / leaving by air. On unless switched off.
--- The Flying Mons option: "full" (everything, the high birds too), "ambient" (no high
--- birds) or "off". A save from when it was an on / off toggle reads true -> full, false -> off.
function Config.flyersMode(mod)
  local v = optGet(mod, "flyers")
  if v == true then return "full" end
  if v == false then return "off" end
  if v == "full" or v == "ambient" or v == "off" then return v end
  return "full"
end

function Config.flyersOn(mod)
  return Config.flyersMode(mod) ~= "off"
end

--- The big blurred passers high overhead (lib/sky_flyers.lua): Flying Mons on Full only.
function Config.highBirdsOn(mod)
  return Config.flyersMode(mod) == "full"
end

local VALID_SILHOUETTE ={ off = true, undiscovered = true, all = true }
function Config.silhouetteMode(mod)
  local v = optGet(mod, "wild_silhouettes")
  if VALID_SILHOUETTE[v] then return v end
  return Config.DEFAULTS.wild_silhouettes
end

--- There is no Follower option any more: a companion is always out (who, and
--- what it does, is chosen from the party menu -- lib/companion.lua). Kept as a
--- function so the callers that ask stay one-liners.
function Config.followerEnabled(_mod)
  return true
end

return Config
