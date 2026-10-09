-- The ONLY module in this mod that touches src/core/game3 internals.
--
-- Gen1Recomp's game3 (FRLG/RSE) engine has no mod seam for a visible
-- overworld actor: mod.world:spawnNpc returns "not supported", ow.entities
-- is a read-only snapshot rebuilt every access, the field renderer has no
-- draw hook, and collision has no mod hook (docs/rfcs/0014 proposes one but
-- it is not implemented). This mod ships before that lands, so it reaches
-- into the engine directly via the `engine_internals` permission, declared
-- in manifest.json.
--
-- Every patch here is:
--   1. probed first: we check the exact field we are about to wrap exists
--      and is a function, with a comment pinning the engine file/line we
--      read it from. If any probe fails, EnginePatch.install() returns
--      false and nothing is touched -- the caller (main.lua) must then
--      disable visible spawns and fall fully back to vanilla.
--   2. reversible: the original function is stored and install() can be
--      called again after uninstall() (hot reload) without double-wrapping.
--   3. pcall-guarded at the call site: a Lua error inside our wrapper logs
--      once and falls through to the original behaviour rather than
--      corrupting the engine's draw/collision/tick loop.
--
-- tests/engine_patch_probe_test.lua runs this file's probes against a real
-- gen1recomp checkout (luajit) so an engine update that moves one of these
-- fields fails loudly instead of silently breaking spawns in the field.

local EnginePatch = {}

-- name -> { mod = "src.core.game3.xxx", field = "yyy" }. Kept as data so the
-- probe test and install() share one list and can't drift apart.
EnginePatch.TARGETS = {
  -- field_view.lua:748 FieldEffects.collectActors(actors) runs every frame
  -- right before FieldView.applyDrawOrder; any actor it appends with a
  -- `renderer` field is drawn via renderer:draw(x,y,camX,camY,facing,
  -- walkPhase,false) (field_view.lua:569).
  collectActors = { mod = "src.core.game3.field_effects", field = "collectActors" },

  -- objects.lua:989 Objects.blocks(tx, ty, exceptLocalId, elevation) is the
  -- one choke point for "is this cell occupied by something solid": it
  -- backs player movement (collision.lua:1003 entityBlocks, called from
  -- Collision.canEnter), event-NPC movement (objects.lua:1536) and trainer
  -- sight lines (trainer_sight.lua:245). Wrapping it alone makes our wild
  -- Pokemon solid to the player, to NPCs, and invisible to trainer sight
  -- checks, all at once.
  blocks = { mod = "src.core.game3.objects", field = "blocks" },

  -- field.lua:238 calls Follower.update(game) every field tick, right after
  -- Player.update. We piggyback our own per-tick spawn/behavior update here
  -- so we don't need a second hook into the tick loop.
  followerUpdate = { mod = "src.world.game3.Follower", field = "update" },

  -- src/ui/game3/message.lua:414 Message.draw() paints the dialogue frame +
  -- text into the 240x160 canvas (ui_pass.lua:132, only while a message is
  -- open); the game has no portrait slot, so lib/portrait_ui.lua draws its
  -- picture right after this returns, in the same canvas pixels.
  messageDraw = { mod = "src.ui.game3.message", field = "draw" },

  -- party_menu.lua:1399 PartyMenu.update(dt) runs every frame the party menu is
  -- open. After it runs we add the Follow / Battle / Forage rows to a freshly
  -- built overworld action list (lib/party_roles.lua); there is no mod hook for
  -- the party menu's actions.
  partyMenuUpdate = { mod = "src.ui.game3.party_menu", field = "update" },

  -- field_moves.lua:804 FieldMoves.fromMenu(label, ctx) answers a field-move row
  -- chosen in the party menu ({ ok = false, text = ... } shows the text and
  -- returns to the list). Our three role rows are registered as such rows, so
  -- this wrap answers them and lets every real field move through untouched.
  fieldMovesFromMenu = { mod = "src.core.game3.field_moves", field = "fromMenu" },

  -- field.lua:865 Field.interact(game) is the A-button handler (talk to an
  -- NPC / read a sign ...). It never looks at the follower, which is not an
  -- Objects entity, so the follower interaction menu (lib/follower_
  -- interaction.lua) runs BEFORE it: when the follower stands in the cell the
  -- player is facing the hook takes the press, otherwise the original runs.
  interact = { mod = "src.core.game3.field", field = "interact" },

  -- battle_bridge.lua:740 BattleBridge.startWild(mod, game, encounter, opts)
  -- keeps personality/ivs/roamer, unlike mod.world:startWildBattle which
  -- only takes species+level. We call it directly so the battle is the
  -- exact mon the player saw standing in the grass.
  startWild = { mod = "src.core.game3.battle_bridge", field = "startWild" },
}

-- Read-only engine calls we depend on but never wrap. Probed the same way
-- so a rename anywhere in this list is caught by the same test.
EnginePatch.READONLY = {
  rollSweetScent = { mod = "src.core.game3.encounters", field = "rollSweetScent" },
  terrainAt = { mod = "src.core.game3.encounters", field = "terrainAt" },
  ensureLoaded = { mod = "src.core.game3.encounters", field = "ensureLoaded" },
  tableFor = { mod = "src.core.game3.encounters", field = "tableFor" },
  isWater = { mod = "src.core.game3.collision", field = "isWater" },
  isGrass = { mod = "src.core.game3.collision", field = "isGrass" },
  canEnter = { mod = "src.core.game3.collision", field = "canEnter" },
  inBounds = { mod = "src.core.game3.collision", field = "inBounds" },
  national = { mod = "src.core.game3.pokemon", field = "national" },
  speciesFromNational = { mod = "src.core.game3.pokemon", field = "speciesFromNational" },
  speciesMeta = { mod = "src.core.game3.pokemon", field = "speciesMeta" },
  isShiny = { mod = "src.core.game3.pokemon", field = "isShiny" },
  gender = { mod = "src.core.game3.pokemon", field = "gender" },
  getSession = { mod = "src.core.game3.runtime", field = "getSession" },
  isCaught = { mod = "src.core.game3.dex", field = "isCaught" },
  layout = { mod = "src.core.GameVersion", field = "layout" },
  gameVersionGet = { mod = "src.core.GameVersion", field = "get" },

  -- message.lua:261 Message.isOpen() -- is a dialogue box up right now.
  isMessageOpen = { mod = "src.ui.game3.message", field = "isOpen" },
  -- message.lua:151 Message.show(text, opts) -- opts.done / opts.stay.
  showMessage = { mod = "src.ui.game3.message", field = "show" },
  -- chrome.lua:135 Chrome.dialogueWindow() -> left, top, width, height in
  -- 8px tiles: where the dialogue text window sits, so a portrait can be
  -- placed above it whatever frame style the game uses.
  dialogueWindow = { mod = "src.ui.game3.chrome", field = "dialogueWindow" },

  -- Reachability flood fill (lib/reachability.lua): the engine's own movement
  -- rules, called per step exactly as player.lua's beginStep does.
  -- collision.lua:~990 Collision.ledgeLanding(game, x, y, dir) -> landing cell
  -- of a ledge hop; :955 nextElevation(mapDef, cur, curX, curY, prevX, prevY);
  -- :914 isWalkable(x, y).
  ledgeLanding = { mod = "src.core.game3.collision", field = "ledgeLanding" },
  nextElevation = { mod = "src.core.game3.collision", field = "nextElevation" },
  isWalkable = { mod = "src.core.game3.collision", field = "isWalkable" },
  -- objects.lua:965 Objects.at(tx, ty) -> the visible event object on a cell
  -- (to tell a Cut tree / smashable rock / boulder from a plain NPC).
  objectAt = { mod = "src.core.game3.objects", field = "at" },
  -- field_moves.lua:313 partyMoveUser(party, move) / :333 hasBadge(ctx, key)
  -- -- can the player use Surf / Cut / Rock Smash / Strength right now.
  partyMoveUser = { mod = "src.core.game3.field_moves", field = "partyMoveUser" },
  hasBadge = { mod = "src.core.game3.field_moves", field = "hasBadge" },

  -- rng.lua Random32() -- the engine's own 32-bit random stream (a wild mon's
  -- personality when the encounter rules did not roll one; see randomPersonality).
  random32 = { mod = "src.core.game3.rng", field = "Random32" },
  -- safari.lua:118 Safari.isActive(session) -- is a Safari Zone visit running
  -- (its battles use balls/bait, not the normal wild battle this mod starts).
  safariIsActive = { mod = "src.core.game3.safari", field = "isActive" },

  -- choice.lua:62 Choice.multi(options, defaultIdx, cb, layout) -- the
  -- engine's own menu; cb(index0) on A, cb(127) on B.
  choiceMulti = { mod = "src.ui.game3.choice", field = "multi" },
  -- message.lua:265 Message.isWaiting() / :345 Message.closeStay() -- is the
  -- current page fully typed, and close a "stay" message.
  messageIsWaiting = { mod = "src.ui.game3.message", field = "isWaiting" },
  closeStayMessage = { mod = "src.ui.game3.message", field = "closeStay" },
  -- hud.lua:51 Hud.busy() -- a message, menu, fade, battle ... owns the screen.
  hudBusy = { mod = "src.ui.game3.hud", field = "busy" },
  -- Follower.lua:27 Follower.at(_, x, y) -> the follower npc standing still
  -- on that cell, or nil.
  followerAt = { mod = "src.world.game3.Follower", field = "at" },
  -- pokemon.lua: friendship accessors / the engine's own AdjustFriendship.
  setFriendship = { mod = "src.core.game3.pokemon", field = "setFriendship" },
  friendshipOf = { mod = "src.core.game3.pokemon", field = "friendshipOf" },
  displayName = { mod = "src.core.game3.pokemon", field = "displayName" },

  -- field_effects.lua:379 FieldEffects.loadSheet(name, fw, fh, frames) --
  -- the same cache-backed sprite-sheet loader the engine uses for its own
  -- field effects (grass, splashes, etc.), publicly exposed. We use it to
  -- draw the "grass overlapping feet" static tuft for our own wild
  -- Pokemon and the follower, the same art the engine already uses for
  -- the player and registered NPCs (see lib/grass_cover.lua) -- not a
  -- reimplementation of the sprite data, just a second caller of the same
  -- loader/cache.
  loadFieldEffectSheet = { mod = "src.core.game3.field_effects", field = "loadSheet" },

  -- audio.lua:1428 Audio.playCry(species, mode) / :1478 isCryFinished() -- the
  -- engine's own cry playback (a follower's Pet / Talk scenes).
  playCry = { mod = "src.core.game3.audio", field = "playCry" },
  cryFinished = { mod = "src.core.game3.audio", field = "isCryFinished" },
  -- field.lua:23/29 Field.lock(tag) / unlock(tag) -- tagged input locks.
  fieldLock = { mod = "src.core.game3.field", field = "lock" },
  fieldUnlock = { mod = "src.core.game3.field", field = "unlock" },
  -- player.lua:922 Player.startFieldMove(duration) -- the arms-up field-move
  -- pose (Gen 3 has no player throw pose; Play borrows this one).
  startFieldMove = { mod = "src.core.game3.player", field = "startFieldMove" },

  -- Overworld fights (lib/ow_combat.lua): the engine's own move table, damage
  -- formula, learnsets and experience maths -- nothing is reimplemented here.
  moveGet = { mod = "src.core.game3.battle.moves", field = "get" },
  damageCalc = { mod = "src.core.game3.battle.damage", field = "calc" },
  damageEnsureStats = { mod = "src.core.game3.battle.damage", field = "ensureStats" },
  movesAtLevel = { mod = "src.core.game3.pokemon", field = "movesAtLevel" },
  movePp = { mod = "src.core.game3.pokemon", field = "movePp" },
  moveName = { mod = "src.core.game3.pokemon", field = "moveName" },
  speciesTypes = { mod = "src.core.game3.pokemon", field = "types" },
  expGainFor = { mod = "src.core.game3.battle.experience", field = "gainFor" },
  expApply = { mod = "src.core.game3.battle.experience", field = "apply" },
  -- A companion that levels up cannot open the engine's learn / evolve screens
  -- mid-walk, so it asks the player to (lib/level_ready.lua): the moves it would
  -- learn at a level, whether it knows one, what it evolves into, and the three
  -- screens that do it (evolution scene, move relearner; Ruby / Sapphire's has its own).
  movesLearnedAt = { mod = "src.core.game3.pokemon", field = "movesLearnedAt" },
  knowsMove = { mod = "src.core.game3.pokemon", field = "knowsMove" },
  evolutionLevelTarget = { mod = "src.core.game3.evolution", field = "levelTarget" },
  moveLearnRelearnable = { mod = "src.core.game3.move_learn", field = "relearnableMoves" },
  evolutionSceneStart = { mod = "src.ui.game3.evolution_scene", field = "start" },
  moveRelearnerShow = { mod = "src.ui.game3.move_relearner", field = "show" },

  -- map.lua:23 Map.currentDef() -> the current map's header ({ mapType, ... }):
  -- a Forager only works on routes and in caves (see EnginePatch.forageAllowed).
  mapCurrentDef = { mod = "src.core.game3.map", field = "currentDef" },

  -- bag.lua:418 Bag.add(bag, id, qty) -> ok -- a Forager's find goes straight in.
  bagAdd = { mod = "src.core.game3.bag", field = "add" },
  -- items_data.lua: ItemsData.info(id) / fieldUseKind(id) / isHm(id) /
  -- isEvolutionStone(id) -- everything the Forager's item pool is built from.
  itemInfo = { mod = "src.core.game3.items_data", field = "info" },
  itemFieldUse = { mod = "src.core.game3.items_data", field = "fieldUseKind" },
  itemIsHm = { mod = "src.core.game3.items_data", field = "isHm" },
  itemIsTm = { mod = "src.core.game3.items_data", field = "isTm" },
  itemIsEvo = { mod = "src.core.game3.items_data", field = "isEvolutionStone" },
  -- audio.lua:973 Audio.playSe(id) and se_ids.lua's SE_SUCCESS (data).
  playSe = { mod = "src.core.game3.audio", field = "playSe" },
  seSuccess = { mod = "src.core.game3.se_ids", field = "SE_SUCCESS", kind = "data" },
  -- frlg_font.lua:1334 / :1209 -- the engine's own dialogue font (canvas pixels).
  fontDraw = { mod = "src.ui.game3.frlg_font", field = "draw" },
  fontMeasure = { mod = "src.ui.game3.frlg_font", field = "measure" },

  -- player.lua:62 -- a live boolean DATA FIELD, not a function (toggled at
  -- multiple call sites in that file as the player starts/stops running).
  -- The one exception to "every probed entry is a callable" -- see
  -- EnginePatch.probe()'s `kind` handling right below.
  playerRunning = { mod = "src.core.game3.player", field = "running", kind = "data" },
}

local function loadModule(path)
  local ok, mod = pcall(require, path)
  if not ok then return nil, mod end
  return mod
end

--- The running game's Gen 3 layout: "rse" (Ruby / Sapphire / Emerald),
--- "frlg" (FireRed / LeafGreen), or nil when it is not a Gen 3 game.
function EnginePatch.layoutName()
  local GameVersion = loadModule(EnginePatch.READONLY.layout.mod)
  if not GameVersion then return nil end
  local ok, id = pcall(GameVersion.get)
  if not ok then return nil end
  local okL, layout = pcall(GameVersion.layout, id)
  if okL and (layout == "rse" or layout == "frlg") then return layout end
  return nil
end

--- True on Ruby / Sapphire / Emerald (layout "rse").
function EnginePatch.isRse()
  return EnginePatch.layoutName() == "rse"
end

--- True on any game this mod runs on: Ruby / Sapphire / Emerald and FireRed /
--- LeafGreen. They share the game3 modules every patch here touches (the
--- encounter rules differ per layout but expose the same Encounters API --
--- see EnginePatch.rollSweetScent), so one install path serves all five.
--- main.lua calls this before EnginePatch.probe()/install().
function EnginePatch.isSupported()
  return EnginePatch.layoutName() ~= nil
end

--- Checks every target + readonly entry resolves to a function, without
--- installing anything. Used by install() and reused verbatim by the probe
--- test so the two can never check different things.
function EnginePatch.probe()
  local missing = {}
  local function check(list)
    for name, spec in pairs(list) do
      local mod, err = loadModule(spec.mod)
      if not mod then
        missing[#missing + 1] = name .. " (" .. spec.mod .. " did not load: " .. tostring(err) .. ")"
      elseif spec.kind == "data" then
        -- The one exception to "every probed entry is a callable" (see
        -- TARGETS/READONLY comments on the entries that opt into this) --
        -- a data field just needs to exist, not be a function.
        if mod[spec.field] == nil then
          missing[#missing + 1] = name .. " (" .. spec.mod .. "." .. spec.field .. " is nil, expected a data field)"
        end
      elseif type(mod[spec.field]) ~= "function" then
        missing[#missing + 1] = name .. " (" .. spec.mod .. "." .. spec.field .. " is "
          .. type(mod[spec.field]) .. ", expected function)"
      end
    end
  end
  check(EnginePatch.TARGETS)
  check(EnginePatch.READONLY)
  return #missing == 0, missing
end

local function safeCall(log, label, fn, ...)
  local ok, a, b, c = pcall(fn, ...)
  if not ok then
    log:warn("[wilds_of_hoenn] %s wrapper error (falling back to engine behaviour): %s",
      label, tostring(a))
    return nil
  end
  return a, b, c
end

--- Installs every wrap. `hooks` is a table of callbacks this mod supplies:
---   hooks.collectActors(actors)       -- append our wild-mon actors
---   hooks.blocks(tx, ty, exceptId, elevation) -> true/false
---   hooks.followerTick(game)          -- run after the real Follower.update
---   hooks.messageDraw()               -- run after Message.draw (portraits)
---   hooks.interact(game) -> true       -- run BEFORE Field.interact; true = handled
---   hooks.partyMenuUpdate(PartyMenu)   -- run after PartyMenu.update (role rows)
---   hooks.partyMenuInput(PartyMenu, input) -> true  -- run BEFORE PartyMenu.handleInput; true = consumed
---   hooks.fromMenu(label, ctx) -> res  -- first say on a party-menu field-move row
--- install() does nothing destructive until probe() has already passed;
--- main.lua is expected to call probe() first and only call install() when
--- it returns true.
function EnginePatch.install(hooks, log)
  if EnginePatch._installed then return true end
  local ok, missing = EnginePatch.probe()
  if not ok then
    return false, missing
  end

  local originals = {}

  local FieldEffects = loadModule(EnginePatch.TARGETS.collectActors.mod)
  originals.collectActors = FieldEffects.collectActors
  FieldEffects.collectActors = function(actors)
    originals.collectActors(actors)
    if hooks.collectActors then
      safeCall(log, "collectActors", hooks.collectActors, actors)
    end
  end

  local Objects = loadModule(EnginePatch.TARGETS.blocks.mod)
  originals.blocks = Objects.blocks
  Objects.blocks = function(tx, ty, exceptLocalId, elevation)
    if originals.blocks(tx, ty, exceptLocalId, elevation) then return true end
    if hooks.blocks then
      local blocked = safeCall(log, "blocks", hooks.blocks, tx, ty, exceptLocalId, elevation)
      if blocked then return true end
    end
    return false
  end

  local Follower = loadModule(EnginePatch.TARGETS.followerUpdate.mod)
  originals.followerUpdate = Follower.update
  Follower.update = function(game)
    originals.followerUpdate(game)
    if hooks.followerTick then
      safeCall(log, "followerTick", hooks.followerTick, game)
    end
  end

  local Message = loadModule(EnginePatch.TARGETS.messageDraw.mod)
  originals.messageDraw = Message.draw
  Message.draw = function(...)
    local a, b, c = originals.messageDraw(...)
    if hooks.messageDraw then safeCall(log, "messageDraw", hooks.messageDraw) end
    return a, b, c
  end

  local Field = loadModule(EnginePatch.TARGETS.interact.mod)
  originals.interact = Field.interact
  Field.interact = function(game, ...)
    if hooks.interact then
      local handled = safeCall(log, "interact", hooks.interact, game)
      if handled then return true end
    end
    return originals.interact(game, ...)
  end

  local PartyMenu = loadModule(EnginePatch.TARGETS.partyMenuUpdate.mod)
  originals.partyMenuUpdate = PartyMenu.update
  PartyMenu.update = function(...)
    local a, b, c = originals.partyMenuUpdate(...)
    if hooks.partyMenuUpdate then safeCall(log, "partyMenuUpdate", hooks.partyMenuUpdate, PartyMenu) end
    return a, b, c
  end

  -- party_menu.lua:1514 PartyMenu.handleInput(input) reads the buttons (hud.lua calls
  -- it with the frame's input). The ROLE row opens a submenu of our own, so this
  -- wrap sees A / B first and may consume them (lib/party_roles.lua onInput). Not
  -- a probed target: without it the ROLE submenu just never opens.
  originals.partyMenuInput = PartyMenu.handleInput
  if type(originals.partyMenuInput) == "function" then
    PartyMenu.handleInput = function(input, ...)
      if hooks.partyMenuInput then
        local consumed = safeCall(log, "partyMenuInput", hooks.partyMenuInput, PartyMenu, input)
        if consumed then return end
      end
      return originals.partyMenuInput(input, ...)
    end
  end

  local FieldMoves = loadModule(EnginePatch.TARGETS.fieldMovesFromMenu.mod)
  originals.fromMenu = FieldMoves.fromMenu
  FieldMoves.fromMenu = function(label, ctx, ...)
    if hooks.fromMenu then
      local res = safeCall(log, "fromMenu", hooks.fromMenu, label, ctx)
      if res then return res end
    end
    return originals.fromMenu(label, ctx, ...)
  end

  EnginePatch._originals = originals
  EnginePatch._installed = true
  return true
end

--- Restores every wrapped function to what it was before install(). Safe to
--- call when not installed (no-op). Used by hot reload and tests.
function EnginePatch.uninstall()
  if not EnginePatch._installed then return end
  local originals = EnginePatch._originals

  local FieldEffects = loadModule(EnginePatch.TARGETS.collectActors.mod)
  if FieldEffects and originals.collectActors then
    FieldEffects.collectActors = originals.collectActors
  end

  local Objects = loadModule(EnginePatch.TARGETS.blocks.mod)
  if Objects and originals.blocks then
    Objects.blocks = originals.blocks
  end

  local Follower = loadModule(EnginePatch.TARGETS.followerUpdate.mod)
  if Follower and originals.followerUpdate then
    Follower.update = originals.followerUpdate
  end

  local Message = loadModule(EnginePatch.TARGETS.messageDraw.mod)
  if Message and originals.messageDraw then
    Message.draw = originals.messageDraw
  end

  local Field = loadModule(EnginePatch.TARGETS.interact.mod)
  if Field and originals.interact then
    Field.interact = originals.interact
  end

  local PartyMenu = loadModule(EnginePatch.TARGETS.partyMenuUpdate.mod)
  if PartyMenu and originals.partyMenuInput then
    PartyMenu.handleInput = originals.partyMenuInput
  end
  if PartyMenu and originals.partyMenuUpdate then
    PartyMenu.update = originals.partyMenuUpdate
  end

  local FieldMoves = loadModule(EnginePatch.TARGETS.fieldMovesFromMenu.mod)
  if FieldMoves and originals.fromMenu then
    FieldMoves.fromMenu = originals.fromMenu
  end

  EnginePatch._originals = {}
  EnginePatch._installed = false
end

--- Message.isOpen(): true while any dialogue box is up. Never throws.
function EnginePatch.isMessageOpen()
  local Message = loadModule(EnginePatch.TARGETS.messageDraw.mod)
  if not Message then return false end
  local ok, open = pcall(Message.isOpen)
  return ok and open == true
end

--- Message.show(text, opts): the engine's own dialogue box (typewriter text,
--- A/B handling and input capture come with it). Returns true on success.
function EnginePatch.showMessage(text, opts)
  local Message = loadModule(EnginePatch.TARGETS.messageDraw.mod)
  if not Message then return false end
  return (pcall(Message.show, text, opts))
end

--- Chrome.dialogueWindow() as { left, top, width, height } in 8px tiles, or
--- nil when unavailable.
function EnginePatch.dialogueWindow()
  local Chrome = loadModule(EnginePatch.READONLY.dialogueWindow.mod)
  if not Chrome then return nil end
  local ok, left, top, width, height = pcall(Chrome.dialogueWindow)
  if not ok or type(left) ~= "number" or type(top) ~= "number" then return nil end
  return { left = left, top = top, width = width, height = height }
end

--- Collision.canEnter through the same "this is only a probe" flag
--- EnginePatch.canEnter sets, but keeping its REASON ("bounds" | "tile" |
--- "elevation" | "entity" | "water"). The flag matters: our own `blocks`
--- hook must not mistake a probe for the player bumping into a wild Pokemon.
function EnginePatch.canEnterWhy(game, tx, ty, opts)
  local Collision = EnginePatch.collision()
  if not Collision then return false, "unavailable" end
  EnginePatch._probingCanEnter = true
  local ok, enter, why = pcall(Collision.canEnter, game, tx, ty, opts)
  EnginePatch._probingCanEnter = false
  if not ok then return false, "error" end
  return enter == true, why
end

--- Can the player use this field move (a badge key: "SURF", "CUT",
--- "ROCK_SMASH", "STRENGTH") right now: badge owned AND a party Pokemon that
--- knows the move. Fails OPEN -- anything unreadable counts as usable -- so a
--- changed engine can only make reachability more generous, never hide
--- every waterway.
function EnginePatch.hmUsable(key)
  local FieldMoves = loadModule(EnginePatch.READONLY.partyMoveUser.mod)
  if not FieldMoves then return true end
  local Space = package.loaded["src.core.game3.scripting.space"]
  if not (Space and Space.store) then return true end
  local okB, badge = pcall(FieldMoves.hasBadge, { store = Space.store }, key)
  if not okB then return true end
  if not badge then return false end
  local Runtime = loadModule(EnginePatch.READONLY.getSession.mod)
  local okS, session = pcall(Runtime and Runtime.getSession)
  if not (okS and type(session) == "table" and type(session.party) == "table") then return true end
  local okM, mon = pcall(FieldMoves.partyMoveUser, session.party, key)
  if not okM then return true end
  return mon ~= nil
end

--- Where a reachability flood fill starts: the player's cell and the state
--- they are in ({ surfing, elev }), or nil without a loaded field.
function EnginePatch.reachStart()
  local Player = loadModule(EnginePatch.READONLY.playerRunning.mod)
  if not Player or type(Player.cellX) ~= "number" or type(Player.cellY) ~= "number" then
    return nil
  end
  return {
    x = Player.cellX, y = Player.cellY,
    state = { surfing = Player.surfing == true or Player.underwater == true,
              elev = Player.currentElevation },
  }
end

local REACH_DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
-- event-object graphics that are obstacles until the matching field move can
-- be used (field_moves.lua GFX_IDS name -> badge key)
local OBSTACLE_MOVE = { CUT_TREE = "CUT", ROCK_SMASH_ROCK = "ROCK_SMASH", PUSHABLE_BOULDER = "STRENGTH" }

--- The `move` function for lib/reachability.lua: where does one step from
--- (x, y) in `state` ({ surfing, elev }) take the player, per the engine's
--- own rules. Walking uses Collision.canEnter with the player's elevation,
--- a ledge becomes the hop to its landing cell (one-way), water is entered
--- as surfing when Surf is usable, and an object in the way (NPC, item ball)
--- does not count as a wall -- except a Cut tree / smashable rock / boulder
--- whose move the player cannot use yet. Returns nil when the engine's
--- collision module is unavailable.
function EnginePatch.reachMover(game)
  local Collision = EnginePatch.collision()
  if not Collision then return nil end
  local surfUsable = EnginePatch.hmUsable("SURF")
  local obstacleGfx = {}
  local FieldMoves = loadModule(EnginePatch.READONLY.partyMoveUser.mod)
  if FieldMoves and FieldMoves.GFX_IDS then
    for name, move in pairs(OBSTACLE_MOVE) do
      local okG, id = pcall(function() return FieldMoves.GFX_IDS[name] end)
      if okG and id and not EnginePatch.hmUsable(move) then obstacleGfx[id] = true end
    end
  end
  local Objects = loadModule(EnginePatch.READONLY.objectAt.mod)

  local function obstacleAt(tx, ty)
    if not (Objects and Objects.at) then return false end
    local okO, obj = pcall(Objects.at, tx, ty)
    if not (okO and type(obj) == "table") then return false end
    local def = type(obj.def) == "table" and obj.def or {}
    local gfx = obj.graphicsId or obj.gfx or def.graphicsId or def.gfx
    return gfx ~= nil and obstacleGfx[gfx] == true
  end

  local function terrainOpen(tx, ty, surfing)
    local okW, water = pcall(Collision.isWater, tx, ty)
    local okK, walkable = pcall(Collision.isWalkable, tx, ty)
    if not (okW and okK) then return false end
    if surfing then return water or walkable end
    return (not water) and walkable
  end

  local function nextElevation(state, tx, ty, fromX, fromY)
    local cur = state and state.elev
    if Collision.nextElevation then
      local okE, elev = pcall(Collision.nextElevation, Collision._mapDef, cur or 0, tx, ty, fromX, fromY)
      if okE and elev ~= nil then return elev end
    end
    return cur
  end

  return function(x, y, dir, state)
    local delta = REACH_DELTA[dir]
    if not delta then return nil end
    local surfing = state and state.surfing == true
    local elev = state and state.elev

    if not surfing and Collision.ledgeLanding then
      local okL, lx, ly = pcall(Collision.ledgeLanding, game, x, y, dir)
      if okL and lx then
        return lx, ly, { surfing = false, elev = nextElevation(state, lx, ly, x, y) }
      end
    end

    local tx, ty = x + delta[1], y + delta[2]
    local opts = { fromX = x, fromY = y, dir = dir, surfing = surfing, elevation = elev }
    local ok, why = EnginePatch.canEnterWhy(game, tx, ty, opts)
    if not ok and why == "water" and not surfing and surfUsable then
      opts.surfing = true -- the shore: hop on and surf
      ok, why = EnginePatch.canEnterWhy(game, tx, ty, opts)
    end
    if not ok and why == "entity" and not obstacleAt(tx, ty) and terrainOpen(tx, ty, opts.surfing) then
      ok = true
    end
    if not ok then return nil end

    local okW, water = pcall(Collision.isWater, tx, ty)
    return tx, ty, { surfing = okW and water == true, elev = nextElevation(state, tx, ty, x, y) }
  end
end

--- Whether nothing else owns the player right now, mirroring the checks at
--- the top of Field.interact (field running and unlocked, no script, message,
--- menu, fade or battle up, the player standing still). Any engine piece that
--- is missing counts as "not blocking", except a field that is not running.
function EnginePatch.canStartInteraction()
  local Field = loadModule(EnginePatch.TARGETS.interact.mod)
  if not Field or not Field.running or Field.locked then return false end
  local Hud = loadModule(EnginePatch.READONLY.hudBusy.mod)
  if Hud then
    local ok, busy = pcall(Hud.busy)
    if not ok or busy then return false end
  end
  local Runtime = loadModule(EnginePatch.READONLY.getSession.mod)
  if Runtime and Runtime.uiBusy then
    local ok, busy = pcall(Runtime.uiBusy)
    if not ok or busy then return false end
  end
  local Space = package.loaded["src.core.game3.scripting.space"]
  if Space and Space.vm and Space.vm.isRunning then
    local ok, running = pcall(Space.vm.isRunning, Space.vm)
    if not ok or running then return false end
  end
  local Player = loadModule(EnginePatch.READONLY.playerRunning.mod)
  if not Player or Player.moving or Player.boulderPush then return false end
  return true
end

--- True while the field is not running normally on its own: a battle, a menu,
--- a message or a fade owns the screen. (Our own Field.lock does NOT count --
--- that is what a follower scene holds.) Used to drop a scene that something
--- else interrupted.
function EnginePatch.screenBusy()
  local Field = loadModule(EnginePatch.TARGETS.interact.mod)
  if not Field or not Field.running then return true end
  local Hud = loadModule(EnginePatch.READONLY.hudBusy.mod)
  if Hud then
    local ok, busy = pcall(Hud.busy)
    if not ok or busy then return true end
  end
  return false
end

local FACING_DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

--- The follower npc when it stands still on the cell the player is facing,
--- else nil.
function EnginePatch.followerInFacingCell()
  local Player = loadModule(EnginePatch.READONLY.playerRunning.mod)
  local Follower = loadModule(EnginePatch.READONLY.followerAt.mod)
  if not (Player and Follower and Follower.at) then return nil end
  local d = FACING_DELTA[Player.facing]
  if not d or type(Player.cellX) ~= "number" or type(Player.cellY) ~= "number" then return nil end
  local ok, npc = pcall(Follower.at, nil, Player.cellX + d[1], Player.cellY + d[2])
  if ok and type(npc) == "table" and not npc.hidden then return npc end
  return nil
end

--- Choice.multi(options, defaultIdx, cb, layout). Returns true on success.
function EnginePatch.showChoice(options, defaultIdx, cb, layout)
  local Choice = loadModule(EnginePatch.READONLY.choiceMulti.mod)
  if not Choice then return false end
  return (pcall(Choice.multi, options, defaultIdx, cb, layout))
end

--- Is the engine's choice menu up (Choice.active is a live data field).
function EnginePatch.choiceActive()
  local Choice = loadModule(EnginePatch.READONLY.choiceMulti.mod)
  return Choice ~= nil and Choice.active == true
end

--- True once the open message has typed out its LAST page and is waiting for
--- the player (a menu can open under it now). The page fields are private to
--- message.lua; when they cannot be read, a waiting message counts as done.
function EnginePatch.messageOnLastPage()
  local Message = loadModule(EnginePatch.TARGETS.messageDraw.mod)
  if not Message then return false end
  local ok, waiting = pcall(Message.isWaiting)
  if not (ok and waiting) then return false end
  local pages, page = Message._pages, Message._page
  if type(pages) == "table" and type(page) == "number" then return page >= #pages end
  return true
end

--- Closes a "stay" message (one opened with opts.stay), if one is up.
function EnginePatch.closeStayMessage()
  local Message = loadModule(EnginePatch.TARGETS.messageDraw.mod)
  if not Message then return false end
  local ok, closed = pcall(Message.closeStay)
  return ok and closed == true
end

local function pokemonFn(name)
  local Pokemon = EnginePatch.pokemon()
  return Pokemon and Pokemon[name], Pokemon
end

--- The mon's display name (nickname, else species name). Never nil.
function EnginePatch.displayName(mon)
  local fn = pokemonFn("displayName")
  if fn then
    local ok, name = pcall(fn, mon)
    if ok and type(name) == "string" and name ~= "" then return name end
  end
  return "POKeMON"
end

function EnginePatch.friendshipOf(mon)
  local fn = pokemonFn("friendshipOf")
  if fn then
    local ok, v = pcall(fn, mon)
    if ok and tonumber(v) then return tonumber(v) end
  end
  return tonumber(mon and (mon.friendship or mon.happiness)) or 0
end

--- Sets the mon's friendship (clamped to 0..255 by the engine). Returns the
--- new value.
function EnginePatch.setFriendship(mon, value)
  local fn = pokemonFn("setFriendship")
  if not fn then return EnginePatch.friendshipOf(mon) end
  local ok, v = pcall(fn, mon, value)
  return ok and tonumber(v) or EnginePatch.friendshipOf(mon)
end


--- Cures the Pokemon's status condition the way the engine's own medicine does
--- (item_use.lua clearStatus: status and the sleep counter back to nothing).
--- Returns true when there was something to cure.
function EnginePatch.clearStatus(mon)
  if type(mon) ~= "table" then return false end
  local had = mon.status ~= nil and mon.status ~= 0 and mon.status ~= "" or (tonumber(mon.sleep) or 0) > 0
  mon.status = nil
  mon.sleep = 0
  return had
end

--- BattleBridge.startWild is called directly, not wrapped -- we never need
--- to intercept other callers of it, only to call it ourselves with a full
--- encounter record (species, level, personality, ivs, roamer).
function EnginePatch.startWild(game, encounter, opts)
  local BattleBridge = loadModule(EnginePatch.TARGETS.startWild.mod)
  if not BattleBridge then return nil, "battle_bridge unavailable" end
  return BattleBridge.startWild(nil, game, encounter, opts)
end

--- Thin read-only accessors so the rest of this mod never calls `require`
--- directly -- every engine touch point is listed above and visible in one
--- file.
function EnginePatch.encounters()
  return loadModule(EnginePatch.READONLY.rollSweetScent.mod)
end

function EnginePatch.collision()
  return loadModule(EnginePatch.READONLY.isWater.mod)
end

function EnginePatch.pokemon()
  return loadModule(EnginePatch.READONLY.national.mod)
end

--- The current map's cell bounds, read off Collision's own internal grid
--- state (collision.lua:30, set on every map load) the same way the
--- engine's own Encounters.encounterTypeAt reads Collision._mapDef. Not a
--- public accessor -- there isn't one -- so this is proxied by the
--- `inBounds` probe above rather than probed directly: both are "Collision
--- still tracks per-map bounds the shape we expect" checks. Returns 0, 0
--- with no map loaded (matches the fields' own reset default).
function EnginePatch.mapBounds()
  local Collision = loadModule(EnginePatch.READONLY.isWater.mod)
  if not Collision then return 0, 0 end
  return tonumber(Collision._widthCells) or 0, tonumber(Collision._heightCells) or 0
end

--- Engine-internal species id -> national dex number (e.g. internal 277 ->
--- national 252, Treecko). pokemon.lua:293. Returns nil for an id the
--- current game doesn't know (egg placeholder, SPECIES_NONE).
function EnginePatch.nationalFor(speciesId)
  local Pokemon = EnginePatch.pokemon()
  if not Pokemon then return nil end
  local ok, nat = pcall(Pokemon.national, speciesId)
  if ok and type(nat) == "number" and nat > 0 then return nat end
  return nil
end

--- National dex number -> engine-internal species id. pokemon.lua:281.
function EnginePatch.speciesForNational(nat)
  local Pokemon = EnginePatch.pokemon()
  if not Pokemon then return nil end
  local ok, id = pcall(Pokemon.speciesFromNational, nat)
  if ok and type(id) == "number" and id > 0 then return id end
  return nil
end

--- The live save's { trainerId = publicId, secretId = secretId }, or nil
--- with no session (no save loaded, or between field sessions).
function EnginePatch.trainerIds()
  local Runtime = loadModule(EnginePatch.READONLY.getSession.mod)
  local ok, session = pcall(Runtime and Runtime.getSession)
  if not (ok and type(session) == "table") then return nil end
  return { otId = tonumber(session.trainerId) or 0, otSecretId = tonumber(session.secretId) or 0 }
end

--- pokemon.lua:1397 Pokemon.isShiny({personality, otId, otSecretId}).
--- `otId`/`otSecretId` default to the live save's trainer when omitted, so
--- a wild encounter's shiny-ness always matches the player who would catch
--- it, exactly like the real game.
function EnginePatch.isShiny(personality, otId, otSecretId)
  local Pokemon = EnginePatch.pokemon()
  if not Pokemon then return false end
  if otId == nil or otSecretId == nil then
    local ids = EnginePatch.trainerIds()
    otId = otId or (ids and ids.otId) or 0
    otSecretId = otSecretId or (ids and ids.otSecretId) or 0
  end
  local ok, shiny = pcall(Pokemon.isShiny, { personality = personality, otId = otId, otSecretId = otSecretId })
  return ok and shiny == true
end

--- pokemon.lua:396 Pokemon.gender(species, personality) -> MON_MALE (0x00) |
--- MON_FEMALE (0xFE) | MON_GENDERLESS (0xFF).
function EnginePatch.genderOf(species, personality)
  local Pokemon = EnginePatch.pokemon()
  if not Pokemon then return nil end
  local ok, g = pcall(Pokemon.gender, species, personality)
  if ok then return g end
  return nil
end

--- encounters.lua:170 terrainAt(cx, cy) -> "land" | "water" | nil. The
--- authoritative per-cell encounter classification: ROM metatile encounter
--- type, falling back to Collision.isWater/isGrass. Never reimplemented.
function EnginePatch.terrainAt(cx, cy)
  local Encounters = EnginePatch.encounters()
  if not Encounters then return nil end
  local ok, t = pcall(Encounters.terrainAt, cx, cy)
  return ok and t or nil
end

function EnginePatch.isWater(cx, cy)
  local Collision = EnginePatch.collision()
  if not Collision then return false end
  local ok, w = pcall(Collision.isWater, cx, cy)
  return ok and w == true
end

function EnginePatch.isGrass(cx, cy)
  local Collision = EnginePatch.collision()
  if not Collision then return false end
  local ok, g = pcall(Collision.isGrass, cx, cy)
  return ok and g == true
end

--- field_effects.lua:379 FieldEffects.loadSheet("tall_grass", 16, 16, 5) --
--- the static feet-tuft sheet (frame 4 of 5 is the non-animated "sitting
--- in grass" pose; frames 0-3 are the player-only rustle sequence, see
--- lib/grass_cover.lua). Memoized by the engine itself, so calling this
--- every frame is cheap. Returns nil before the field-effects cache is
--- installed (no map loaded yet) or if the ROM extract is missing it.
function EnginePatch.grassSheet()
  local FieldEffects = loadModule(EnginePatch.READONLY.loadFieldEffectSheet.mod)
  if not FieldEffects then return nil end
  local ok, sheet = pcall(FieldEffects.loadSheet, "tall_grass", 16, 16, 5)
  if ok then return sheet end
  return nil
end

--- Any field-effect sheet by name through the same cache-backed loader the engine
--- uses (field_effects.lua:379): { image, quads[0..], fw, fh, frames } or nil.
function EnginePatch.fieldEffectSheet(name, fw, fh, frames)
  local FieldEffects = loadModule(EnginePatch.READONLY.loadFieldEffectSheet.mod)
  if not FieldEffects then return nil end
  local ok, sheet = pcall(FieldEffects.loadSheet, name, fw, fh, frames)
  if ok then return sheet end
  return nil
end

--- collision.lua:1035 canEnter(game, tx, ty, opts). Read-only here: our
--- wild Pokemon use this to decide their OWN steps, the same rules the
--- player follows (ledges, elevation, water/land dismount).
---
--- collision.lua's canEnter ALWAYS resolves occupancy through its own
--- internal entityBlocks(), which ALWAYS calls Objects.blocks(tx, ty, nil,
--- elevation) -- passing nil for exceptLocalId no matter who the caller
--- is (confirmed directly in the engine source; there is no "the player's
--- own movement passes nil, everyone else passes their id" distinction
--- for THIS path, only for direct callers of Objects.blocks itself). The
--- `blocks` wrap (main.lua) uses `exceptLocalId == nil` as its "this is a
--- real player bump" signal -- so without this flag, a ROAMING wild
--- Pokemon merely CONSIDERING a step onto the player's own tile (a normal
--- part of Behavior.tick, requiring no player movement at all) would
--- trigger a battle through the exact same nil-exceptLocalId path a real
--- bump does. `EnginePatch.isProbingCanEnter()` lets that wrap tell the
--- two apart and skip the battle side effect for our own internal probe,
--- while still answering "occupied" correctly so the wild Pokemon
--- doesn't actually path onto the player.
EnginePatch._probingCanEnter = false
function EnginePatch.isProbingCanEnter()
  return EnginePatch._probingCanEnter == true
end

function EnginePatch.canEnter(game, tx, ty, opts)
  local Collision = EnginePatch.collision()
  if not Collision then return false end
  EnginePatch._probingCanEnter = true
  local ok, enter = pcall(Collision.canEnter, game, tx, ty, opts)
  EnginePatch._probingCanEnter = false
  return ok and enter == true
end

--- encounters.lua:314 tableFor(mapId) -> the map's { land, water, rocks }
--- areas, already resolved through Altering Cave variants (pick_variant).
function EnginePatch.tableFor(mapId)
  local Encounters = EnginePatch.encounters()
  if not Encounters then return nil end
  local ok, t = pcall(Encounters.tableFor, mapId)
  if ok then return t end
  return nil
end

function EnginePatch.ensureEncountersLoaded()
  local Encounters = EnginePatch.encounters()
  if not Encounters then return false end
  local ok, loaded = pcall(Encounters.ensureLoaded)
  return ok and loaded == true
end

--- encounter_rules/rse.lua:494 rollSweetScent(mapId, terrain): a full
--- encounter (species, level, personality, ivs, roamer) with ability bias,
--- Synchronize/Cute Charm, outbreaks and roamers all applied, but WITHOUT
--- the per-step encounter-rate gate -- exactly what a visible spawn needs
--- (it is generated once, not re-rolled every tile). `terrain` is "land" or
--- "water".
function EnginePatch.rollSweetScent(mapId, terrain)
  local Encounters = EnginePatch.encounters()
  if not Encounters then return nil end
  local ok, enc = pcall(Encounters.rollSweetScent, mapId, terrain)
  if ok then return enc end
  return nil
end

--- A random 32-bit personality from the engine's own stream, for an encounter
--- whose rules did not roll one. FireRed / LeafGreen's rollSweetScent returns
--- only { species, level, item }; the engine itself then draws
--- `Rng.Random32()` when it builds the battle mon (battle/init.lua
--- foe_mon_from), so rolling it here first -- and handing it to startWild --
--- makes the Pokemon you saw (shiny, nature, gender) the one you fight. nil
--- when the engine's rng is unavailable.
function EnginePatch.randomPersonality()
  local Rng = loadModule(EnginePatch.READONLY.random32.mod)
  if not Rng then return nil end
  local ok, value = pcall(Rng.Random32)
  if ok and type(value) == "number" then return value end
  return nil
end

--- True during a Safari Zone visit (RSE and FRLG both have one): wild battles
--- there are special (balls, bait, no fighting) and belong to the engine, so
--- this mod spawns nothing on those maps.
function EnginePatch.safariActive()
  local Safari = loadModule(EnginePatch.READONLY.safariIsActive.mod)
  if not Safari then return false end
  local Runtime = loadModule(EnginePatch.READONLY.getSession.mod)
  local okS, session = pcall(Runtime and Runtime.getSession)
  local ok, active = pcall(Safari.isActive, okS and session or nil)
  return ok and active == true
end

--- encounter_rules/rse.lua:478 sweetScentFacility(mapId): true on Battle
--- Pike / Battle Pyramid maps, where wild generation is special-cased and
--- this mod does not add visible spawns (see docs/ARCHITECTURE.md).
function EnginePatch.isSweetScentFacility(mapId)
  local Encounters = EnginePatch.encounters()
  if not (Encounters and Encounters.rules) then return false end
  local ok, rules = pcall(Encounters.rules)
  if not ok then return false end
  local f = rules and rules.sweetScentFacility
  if type(f) ~= "function" then return false end
  local okF, result = pcall(f, mapId)
  return okF and result == true
end

--- encounters.lua's internal H.wild_level_allowed_by_repel(level): false
--- when a Repel is active and `level` is below the lead party mon's level
--- (pokefirered/src/wild_encounter.c:601). Honoured the same way the
--- vanilla step roll does, without reimplementing the Repel rule.
function EnginePatch.repelAllows(level)
  local Encounters = EnginePatch.encounters()
  local h = Encounters and Encounters._h
  if not (h and h.wild_level_allowed_by_repel) then return true end
  local ok, allowed = pcall(h.wild_level_allowed_by_repel, level)
  if ok then return allowed ~= false end
  return true
end

--- The first healthy, non-egg party member's engine-internal species id, or
--- nil with no session/party/eligible mon. Mirrors the same "lead" scan
--- Encounters._h.wild_level_allowed_by_repel does over session.party --
--- read-only data access, not a function call, so it is covered by the
--- `getSession` probe above rather than its own entry.
function EnginePatch.leadPartyMon()
  local Runtime = loadModule(EnginePatch.READONLY.getSession.mod)
  local ok, session = pcall(Runtime and Runtime.getSession)
  if not (ok and type(session) == "table" and type(session.party) == "table") then
    return nil
  end
  for i = 1, 6 do
    local mon = session.party[i]
    if type(mon) == "table" and (tonumber(mon.hp) or tonumber(mon.currentHp) or 1) > 0
        and not mon.isEgg and not mon.egg then
      return mon
    end
  end
  return nil
end

-- ---------------------------------------------------------------- overworld fights

local function moveNumber(m)
  if type(m) == "table" then m = m.id or m.move or m.moveId or m.num or m[1] end
  return tonumber(m)
end
EnginePatch.moveNumber = moveNumber

--- A wild Pokemon built for an overworld fight: stats, moves and PP from the
--- engine's own learnset at its level, hp full. Returns the mon table, or nil.
function EnginePatch.buildWildFighter(species, level, personality)
  local Pokemon = loadModule(EnginePatch.READONLY.movesAtLevel.mod)
  local Damage = loadModule(EnginePatch.READONLY.damageEnsureStats.mod)
  if not (Pokemon and Damage) then return nil end
  local ok, mon = pcall(function()
    local moves, pp, maxPp = Pokemon.movesAtLevel(species, level)
    if not moves or #moves == 0 then return nil end
    local rnd = EnginePatch.randomPersonality() or 0
    local m = {
      species = species, level = level, personality = personality or rnd,
      ivs = { hp = rnd % 32, atk = math.floor(rnd / 32) % 32, def = math.floor(rnd / 1024) % 32,
              spe = math.floor(rnd / 32768) % 32, spa = math.floor(rnd / 1048576) % 32,
              spd = math.floor(rnd / 33554432) % 32 },
      moves = moves, pp = pp, maxPp = maxPp,
    }
    Damage.ensureStats(m, level)
    if not m.maxHp or m.maxHp <= 0 then return nil end
    m.hp = m.maxHp
    return m
  end)
  if ok then return mon end
  return nil
end

--- The battler shape the damage formula wants: the mon plus its types.
function EnginePatch.battlerOf(mon)
  local Pokemon = loadModule(EnginePatch.READONLY.speciesTypes.mod)
  local t1, t2 = 0, 0
  if Pokemon and Pokemon.types then
    local ok, types = pcall(Pokemon.types, mon.species)
    if ok and type(types) == "table" then t1, t2 = types[1] or 0, types[2] or 0 end
  end
  return { mon = mon, type1 = t1, type2 = t2, level = mon.level }
end

--- { power, accuracy, type, pp } for a move id, or nil.
function EnginePatch.moveRow(moveId)
  local Moves = loadModule(EnginePatch.READONLY.moveGet.mod)
  local id = moveNumber(moveId)
  if not (Moves and id) then return nil end
  local ok, row = pcall(Moves.get, id)
  if not ok or type(row) ~= "table" then return nil end
  return { power = tonumber(row.power) or 0, accuracy = tonumber(row.accuracy) or 0,
           type = tonumber(row.type) or 0, pp = tonumber(row.pp) or 0 }
end

--- The engine's damage formula between two battlers; `rng(lo, hi)` picks the
--- rolls. Returns damage, info (nil, nil on any trouble).
function EnginePatch.moveDamage(attacker, defender, moveId, rng, noCrit)
  local Damage = loadModule(EnginePatch.READONLY.damageCalc.mod)
  local id = moveNumber(moveId)
  if not (Damage and id) then return nil end
  local ok, dmg, info = pcall(Damage.calc, attacker, defender, id, { rng = rng, noCrit = noCrit })
  if not ok then return nil end
  return tonumber(dmg), info
end

function EnginePatch.moveDisplayName(moveId)
  local Pokemon = loadModule(EnginePatch.READONLY.moveName.mod)
  if not Pokemon then return tostring(moveId) end
  local ok, name = pcall(Pokemon.moveName, moveNumber(moveId))
  return ok and name or tostring(moveId)
end

--- EXP the engine says a wild `species` at `level` is worth (one participant).
function EnginePatch.expGain(species, level)
  local Experience = loadModule(EnginePatch.READONLY.expGainFor.mod)
  if not Experience then return 0 end
  local ok, n = pcall(Experience.gainFor, species, level, {})
  return ok and tonumber(n) or 0
end

--- Gives `amount` EXP to a party mon (levels it up, recalculates stats).
--- Returns the engine's result table ({ gained, fromLevel, toLevel, ...}) or nil.
function EnginePatch.expApply(mon, amount)
  local Experience = loadModule(EnginePatch.READONLY.expApply.mod)
  if not Experience then return nil end
  local ok, result = pcall(Experience.apply, mon, amount)
  if ok and type(result) == "table" then return result end
  return nil
end

--- Moves `mon`'s species learns at exactly `level` (engine learnset), as ids.
function EnginePatch.movesLearnedAt(mon, level)
  local Pokemon = loadModule(EnginePatch.READONLY.movesLearnedAt.mod)
  if not (Pokemon and type(mon) == "table") then return {} end
  local species = tonumber(mon.species or mon.speciesId)
  local ok, list = pcall(Pokemon.movesLearnedAt, species, level)
  return (ok and type(list) == "table") and list or {}
end

--- Does `mon` already know `moveId`?
function EnginePatch.knowsMove(mon, moveId)
  local Pokemon = loadModule(EnginePatch.READONLY.knowsMove.mod)
  if not Pokemon then return false end
  local ok, knows = pcall(Pokemon.knowsMove, mon, moveId)
  return ok and knows == true
end

--- What `mon` evolves into at its current level (a level-up evolution), or nil.
function EnginePatch.evolutionTarget(mon)
  local Evolution = loadModule(EnginePatch.READONLY.evolutionLevelTarget.mod)
  local Runtime = loadModule(EnginePatch.READONLY.getSession.mod)
  if not (Evolution and type(mon) == "table") then return nil end
  local okS, session = pcall(Runtime and Runtime.getSession)
  local ok, target = pcall(Evolution.levelTarget, mon, okS and session or nil)
  if ok and target and target ~= 0 then return target end
  return nil
end

--- Opens the engine's evolution scene for `mon` -> `target` (the player may stop
--- it, as after a battle). `onDone` runs once, when the scene closes. Returns
--- false (and never calls `onDone`) when the scene could not open.
function EnginePatch.startEvolution(mon, target, onDone)
  local Scene = loadModule(EnginePatch.READONLY.evolutionSceneStart.mod)
  local Runtime = loadModule(EnginePatch.READONLY.getSession.mod)
  if not (Scene and Scene.start) then return false end
  local okS, session = pcall(Runtime and Runtime.getSession)
  session = okS and session or nil
  local okAudio, Audio = pcall(require, "src.core.game3.audio")
  local ok = pcall(Scene.start, mon, target, {
    canStop = true, session = session, bag = type(session) == "table" and session.bag or nil,
    savedSong = okAudio and Audio and Audio._mapSong or nil,
    onDone = function() if onDone then onDone() end end,
  })
  return ok and Scene.isOpen and Scene.isOpen() == true
end

--- Opens the engine's move relearner for `mon`, listing only `moveIds` (the moves
--- a companion skipped, not everything it could ever relearn). Picks Ruby /
--- Sapphire's own screen on those games. `onDone(learned)` runs once when it
--- closes. Returns false (and never calls `onDone`) when it could not open.
function EnginePatch.startMoveLearn(mon, moveIds, onDone)
  local MoveLearn = loadModule(EnginePatch.READONLY.moveLearnRelearnable.mod)
  local Runtime = loadModule(EnginePatch.READONLY.getSession.mod)
  if not (MoveLearn and type(moveIds) == "table" and #moveIds > 0) then return false end
  local okS, session = pcall(Runtime and Runtime.getSession)
  session = okS and session or nil
  local version = type(session) == "table" and session.version or nil
  local screen = "src.ui.game3.move_relearner"
  if version == "ruby" or version == "sapphire" then
    screen = "src.ui.game3.rs.move_relearner"
  elseif EnginePatch.layoutName() == "rse" then
    screen = "src.ui.game3.rse.move_relearner"
  end
  local okUi, Relearner = pcall(require, screen)
  if not (okUi and type(Relearner) == "table" and Relearner.show) then return false end
  -- the screen asks MoveLearn for its list, again after each declined move: answer
  -- with the skipped moves only (the ones the mon does not know yet) while it is open
  local original = MoveLearn.relearnableMoves
  local function only(m)
    local out = {}
    for _, id in ipairs(moveIds) do
      if not EnginePatch.knowsMove(m, id) then out[#out + 1] = id end
    end
    return out
  end
  MoveLearn.relearnableMoves = only
  local function restore()
    if MoveLearn.relearnableMoves == only then MoveLearn.relearnableMoves = original end
  end
  local okShow = pcall(Relearner.show, mon, {
    session = session,
    onDone = function(learned)
      restore()
      if onDone then onDone(learned == true) end
    end,
  })
  -- Ruby / Sapphire's screen is a skin on the shared RSE one, which holds the open flag
  local isOpen = Relearner.isOpen
  if not isOpen then
    local okBase, Base = pcall(require, "src.ui.game3.rse.move_relearner")
    isOpen = okBase and type(Base) == "table" and Base.isOpen or nil
  end
  if not (okShow and isOpen and isOpen()) then restore() return false end
  return true
end

--- The current map's type id (include/constants/map_types.h: 1 town, 2 city,
--- 3 route, 4 underground, 5 underwater, 6 ocean route, 8 indoor, 9 secret
--- base), or nil when unknown.
function EnginePatch.mapType()
  local Map = loadModule(EnginePatch.READONLY.mapCurrentDef.mod)
  if not Map then return nil end
  local ok, def = pcall(Map.currentDef)
  if not (ok and type(def) == "table") then return nil end
  return tonumber(def.mapType)
end

--- May a Forager work here and now: the map's type is one of `allowedTypes`
--- (a set, e.g. { [3] = true, [4] = true } = routes and caves), it is not a
--- Safari Zone visit, and the player is neither surfing nor standing in water.
--- An unknown map type counts as NOT allowed.
function EnginePatch.forageAllowed(allowedTypes)
  local mt = EnginePatch.mapType()
  if not (mt and allowedTypes and allowedTypes[mt]) then return false end
  if EnginePatch.safariActive() then return false end
  local surf = EnginePatch.playerSurfState()
  if surf.surfing or surf.dismounting then return false end
  local cell = EnginePatch.playerCell()
  if cell and EnginePatch.isWater(cell.x, cell.y) then return false end
  return true
end

--- Puts `qty` of item `id` into the player's bag. False when the bag is full or
--- the id is unknown (nothing is added).
function EnginePatch.bagAdd(id, qty)
  local Runtime = loadModule(EnginePatch.READONLY.getSession.mod)
  local Bag = loadModule(EnginePatch.READONLY.bagAdd.mod)
  local okS, session = pcall(Runtime and Runtime.getSession)
  if not (Bag and okS and type(session) == "table" and session.bag) then return false end
  local ok, added = pcall(Bag.add, session.bag, id, qty or 1)
  return ok and added == true
end

--- Every item the Forager may consider (see lib/forage_items.lua): the game's
--- own items by number, plus every item another mod registered with an index
--- from 900 up -- those are the extra evolution items National Dex Gen 3 adds.
function EnginePatch.itemCatalog(mod)
  local ItemsData = loadModule(EnginePatch.READONLY.itemInfo.mod)
  local out = {}
  if not ItemsData then return out end
  local seen = {}
  for num = 1, 400 do
    local okI, info = pcall(ItemsData.info, num)
    if okI and type(info) == "table" and type(info.name) == "string"
        and info.name ~= "" and not info.name:find("^%?") then
      local okU, use = pcall(ItemsData.fieldUseKind, num)
      local okH, hm = pcall(ItemsData.isHm, num)
      local okT, tm = pcall(ItemsData.isTm, num)
      local okE, evo = pcall(ItemsData.isEvolutionStone, num)
      out[#out + 1] = {
        id = num, name = info.name, pocket = info.pocket, price = info.price,
        use = okU and use or "none", isHm = okH and hm == true,
        isTm = okT and tm == true, isEvo = okE and evo == true,
      }
      seen[num] = true
    end
  end
  local items = mod and mod.content and mod.content.items
  if items and type(items.each) == "function" then
    pcall(function()
      for id, value in items:each() do
        local index = type(value) == "table" and tonumber(value.index) or nil
        if index and index >= 900 and not seen[id] then
          seen[id] = true
          out[#out + 1] = {
            id = value.id or id, name = value.name or tostring(id), pocket = "ITEMS",
            price = tonumber(value.price) or 0, use = "evo", extra = true,
          }
        end
      end
    end)
  end
  return out
end

--- A sound effect by its SE_* name (only SE_SUCCESS is probed). No-op when absent.
function EnginePatch.playSuccess()
  local Audio = loadModule(EnginePatch.READONLY.playSe.mod)
  local Ids = loadModule(EnginePatch.READONLY.seSuccess.mod)
  if not (Audio and Audio.playSe and Ids and Ids.SE_SUCCESS) then return false end
  return (pcall(Audio.playSe, Ids.SE_SUCCESS))
end

--- The menu cursor's click (SE_SELECT). No-op when the audio pieces are absent.
function EnginePatch.playSelect()
  local Audio = loadModule(EnginePatch.READONLY.playSe.mod)
  local Ids = package.loaded["src.core.game3.se_ids"]
  if not (Audio and Audio.playSe and Ids and Ids.resolve) then return false end
  return (pcall(function() Audio.playSe(Ids.resolve("SE_SELECT")) end))
end

--- Width in px of `text` in the engine's dialogue font (0 when unavailable).
function EnginePatch.measureText(text, opts)
  local Font = loadModule(EnginePatch.READONLY.fontMeasure.mod)
  if not (Font and Font.measure) then return 0 end
  local ok, w = pcall(Font.measure, text, opts)
  return ok and tonumber(w) or 0
end

--- Which game layout the dialogue font is set up for: "rs" (Ruby / Sapphire /
--- Emerald) or "frlg" (FireRed / LeafGreen), nil without the font module. Its
--- small face sits in a different place in its cell on each. Only the Ruby /
--- Sapphire / Emerald profile hands the font a spec (with nativeLayout = "rs");
--- FireRed / LeafGreen have none, so `_spec` is nil there -- that is NOT "unknown".
function EnginePatch.fontLayout()
  local Font = loadModule(EnginePatch.READONLY.fontMeasure.mod)
  if not Font then return nil end
  local spec = Font.sync and Font.sync() or Font._spec
  return (type(spec) == "table" and spec.nativeLayout == "rs") and "rs" or "frlg"
end

--- Draws `text` in the engine's dialogue font at canvas pixel (x, y); returns the
--- text's width (0 when the font is unavailable).
function EnginePatch.drawText(text, x, y, opts)
  local Font = loadModule(EnginePatch.READONLY.fontDraw.mod)
  if not (Font and Font.draw and Font.measure) then return 0 end
  local ok, w = pcall(Font.measure, text, opts)
  local width = ok and tonumber(w) or 0
  -- the engine's default text colour is white (made for its dark message frames):
  -- unless the caller picked one, use the dark "normal" colours so it reads on a light plate
  if not (opts and (opts.colors or opts.color)) and Font.COLOR and Font.COLOR.NORMAL then
    local copy = {}
    for k, v in pairs(opts or {}) do copy[k] = v end
    copy.colors = Font.COLOR.NORMAL
    opts = copy
  end
  pcall(Font.draw, text, x, y, opts)
  return width
end

--- Can a creature stand on this cell: dry, walkable, nothing on it.
function EnginePatch.cellFree(cx, cy)
  local Collision = EnginePatch.collision()
  if not (Collision and Collision.isWalkable) then return false end
  local okK, walkable = pcall(Collision.isWalkable, cx, cy)
  if not (okK and walkable) then return false end
  local okW, water = pcall(Collision.isWater, cx, cy)
  if okW and water then return false end
  local Objects = loadModule(EnginePatch.READONLY.objectAt.mod)
  if Objects and Objects.at then
    local okO, obj = pcall(Objects.at, cx, cy)
    if okO and obj then return false end
  end
  return true
end

--- The party menu module (the role rows edit its ACTIONS list).
function EnginePatch.partyMenu()
  return loadModule(EnginePatch.TARGETS.partyMenuUpdate.mod)
end

--- The party as a plain list (slot order), or {} without a session.
function EnginePatch.partyMons()
  local Runtime = loadModule(EnginePatch.READONLY.getSession.mod)
  local ok, session = pcall(Runtime and Runtime.getSession)
  local out = {}
  if not (ok and type(session) == "table" and type(session.party) == "table") then return out end
  for i = 1, 6 do
    if type(session.party[i]) == "table" then out[#out + 1] = session.party[i] end
  end
  return out
end

--- True while a battle owns the screen (the party menu's switch rows differ).
function EnginePatch.battleActive()
  local Battle = package.loaded["src.core.game3.battle"]
  if not (Battle and Battle.isActive) then return false end
  local ok, active = pcall(Battle.isActive)
  return ok and active == true
end

function EnginePatch.leadPartySpecies()
  local mon = EnginePatch.leadPartyMon()
  return mon and tonumber(mon.species) or nil
end

--- src/world/game3/Follower.lua's current npc record (nil when no
--- follower is spawned -- e.g. the option is off or mid-map-transition).
--- `npc.sprite` is a renderer, read by Follower.actor() at draw time; see
--- lib/follower_adapter.lua's followerTick.
function EnginePatch.followerCurrent()
  local Follower = loadModule(EnginePatch.TARGETS.followerUpdate.mod)
  if not (Follower and Follower.current) then return nil end
  local ok, npc = pcall(Follower.current)
  if ok then return npc end
  return nil
end

--- The player's surf state: { surfing, dismounting } -- `surfing` is true from
--- the hop onto the water until the dismount onto land begins (player.lua
--- Player.surfHopping / surfing / dismounting). Both false without a player.
function EnginePatch.playerSurfState()
  local Player = loadModule(EnginePatch.READONLY.playerRunning.mod)
  if not Player then return { surfing = false, dismounting = false } end
  return {
    surfing = Player.surfing == true or Player.surfHopping == true,
    dismounting = Player.dismounting == true,
  }
end

--- The player's world pixel position (tile top-left, interpolated mid-step),
--- or nil without a player.
function EnginePatch.playerPixel()
  local Player = loadModule(EnginePatch.READONLY.playerRunning.mod)
  if not Player or type(Player.px) ~= "number" or type(Player.py) ~= "number" then return nil end
  return Player.px, Player.py
end

--- player.lua:62 Player.running -- true while the player is actively
--- running (held Run button / Running Shoes engaged). Read directly, not
--- wrapped -- see the `playerRunning` READONLY entry's `kind = "data"`.
--- Used by lib/follower_adapter.lua to pick walk vs run frames for the
--- follower (wild Pokemon never run).
function EnginePatch.playerIsRunning()
  local Player = loadModule(EnginePatch.READONLY.playerRunning.mod)
  if not Player then return false end
  return Player.running == true
end

--- The player's cell as { x, y, moving, targetX, targetY }, or nil when the
--- Player module is unavailable. player.lua only updates cellX/cellY when a
--- step FINISHES (finishStep), so `x, y` is where the player is standing
--- right now; while `moving` the cell being stepped into is target*.
function EnginePatch.playerCell()
  local Player = loadModule(EnginePatch.READONLY.playerRunning.mod)
  if not Player or type(Player.cellX) ~= "number" or type(Player.cellY) ~= "number" then
    return nil
  end
  return {
    x = Player.cellX, y = Player.cellY, moving = Player.moving == true,
    targetX = Player.targetX, targetY = Player.targetY,
  }
end

--- Whether the player's Pokedex has `speciesId` (engine-internal id) seen
--- as caught/owned. dex.lua:242. Returns false with no session/dex.
function EnginePatch.isCaught(speciesId)
  local Runtime = loadModule(EnginePatch.READONLY.getSession.mod)
  local Dex = loadModule(EnginePatch.READONLY.isCaught.mod)
  if not (Runtime and Dex) then return false end
  local ok, session = pcall(Runtime.getSession)
  if not (ok and type(session) == "table" and session.dex) then return false end
  local okC, caught = pcall(Dex.isCaught, session.dex, speciesId)
  return okC and caught == true
end

--- Plays the species' cry through the engine's own audio (internal species
--- id, as the field-move "show mon" scene passes it). False when unavailable.
function EnginePatch.playCry(speciesId)
  local Audio = loadModule(EnginePatch.READONLY.playCry.mod)
  if not (Audio and Audio.playCry) then return false end
  return (pcall(Audio.playCry, speciesId, 0))
end

--- Has the last cry finished? True when it cannot be told (no audio), so a
--- caller never waits on a cry that will not end.
function EnginePatch.cryFinished()
  local Audio = loadModule(EnginePatch.READONLY.cryFinished.mod)
  if not (Audio and Audio.isCryFinished) then return true end
  local ok, done = pcall(Audio.isCryFinished)
  return not ok or done == true
end

--- Tagged field input lock (Field.lock / unlock). No-ops without the field.
function EnginePatch.lockField(tag)
  local Field = loadModule(EnginePatch.READONLY.fieldLock.mod)
  if not (Field and Field.lock) then return false end
  return (pcall(Field.lock, tag))
end

function EnginePatch.unlockField(tag)
  local Field = loadModule(EnginePatch.READONLY.fieldUnlock.mod)
  if not (Field and Field.unlock) then return false end
  return (pcall(Field.unlock, tag))
end

--- The arms-up field-move pose for `ticks` ticks (also holds the player still).
function EnginePatch.playerPose(ticks)
  local Player = loadModule(EnginePatch.READONLY.startFieldMove.mod)
  if not (Player and Player.startFieldMove) then return false end
  return (pcall(Player.startFieldMove, ticks))
end

--- The player's elevation layer (what an actor drawn with them must match).
function EnginePatch.playerElevation()
  local Player = loadModule(EnginePatch.READONLY.playerRunning.mod)
  return Player and tonumber(Player.elevation) or 3
end

--- The player's facing ("up" | "down" | "left" | "right"), or nil.
function EnginePatch.playerFacing()
  local Player = loadModule(EnginePatch.READONLY.playerRunning.mod)
  local f = Player and Player.facing
  if f == "up" or f == "down" or f == "left" or f == "right" then return f end
  return nil
end

--- How many cells in a row, starting NEXT to (cx, cy) and heading `dir`, are
--- dry walkable ground with nothing standing on them -- capped at `max`. A
--- thrown ball lands that far out (see lib/follower_actions.lua).
function EnginePatch.freeCellsAhead(cx, cy, dir, max)
  local d = FACING_DELTA[dir]
  local Collision = EnginePatch.collision()
  if not (d and Collision and Collision.isWalkable) then return 0 end
  local Objects = loadModule(EnginePatch.READONLY.objectAt.mod)
  local n = 0
  for i = 1, max or 3 do
    local tx, ty = cx + d[1] * i, cy + d[2] * i
    local okK, walkable = pcall(Collision.isWalkable, tx, ty)
    local okW, water = pcall(Collision.isWater, tx, ty)
    if not (okK and walkable) or (okW and water) then break end
    if Objects and Objects.at then
      local okO, obj = pcall(Objects.at, tx, ty)
      if okO and obj then break end
    end
    n = n + 1
  end
  return n
end

return EnginePatch
