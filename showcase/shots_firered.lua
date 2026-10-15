-- The FireRed reel (showcase/director.lua): Kanto shots -- Pallet Town's birds and a tall
-- partner ducking under a roof, Lavender Town's ghosts and its Gengar, the Safari Zone.
-- Same shape as shots_emerald.lua: `stage(ctx)` sets the scene, `roll(ctx)` plays it.
return function(ctx)
  local woh, EP, sm, cam = ctx.woh, ctx.EP, ctx.sm, ctx.cam
  local sky, ls = woh.skyFlyers, woh.localScenes

  local function scene(kind)
    for _, c in ipairs(ls.scenes or {}) do if c.kind == kind then return c end end
  end
  local function startScene(kind, tries)
    for _ = 1, tries or 30 do
      if ls:start(kind) then return scene(kind) end
      ctx.wait(5)
    end
  end
  local function tries(fn, n)
    for _ = 1, n or 20 do
      local ok, v = pcall(fn)
      if ok and v then return v end
      ctx.wait(5)
    end
  end
  local function player() return cam.playerCentre() end
  local function partner()
    local npc = EP.followerCurrent and EP.followerCurrent()
    if npc and npc.px then return npc.px + 8, npc.py + 8 end
    return player()
  end
  local function between(ax, ay, bx, by) return (ax + bx) / 2, (ay + by) / 2 end

  -- talk to the partner (standing beside it, facing it); `row` under Interact (1 Pet,
  -- 2 Play, 3 Talk), or nil to only hear how it is doing
  local function interact(row)
    local fi = woh.followerInteraction
    local function menu(name)
      return fi.state == "menu" and fi.menuName == name and EP.choiceActive and EP.choiceActive()
    end
    ctx.tap("a")
    ctx.waitUntil(function() return menu("main") end, 400)
    ctx.wait(70)
    if not row then return end
    ctx.tap("a")
    ctx.waitUntil(function() return menu("interact") end, 120)
    ctx.wait(30)
    for _ = 2, row do ctx.tap("down") ctx.wait(12) end
    ctx.wait(20)
    ctx.tap("a")
    ctx.waitUntil(function() return fi.state == "result" end, 900)
  end

  return {
    -- 1. Pallet Town: birds on the roofs, one passing high over
    {
      name = "pallet_birds",
      stage = function()
        ctx.party({ { 25, 20, friendship = 255, nick = "PIKACHU" } })
        ctx.go("MAP_PALLET_TOWN", 12, 12, "down")
        sky:clear()
        cam:engineZoom(-1)
        cam:set({ panY = -24, zoom = 1.2 })
        ctx.wait(30)
        tries(function() return sky:_spawnPercher() end, 10)
        tries(function() return sky:_spawnPercher() end, 10)
      end,
      roll = function()
        ctx.wait(20)
        tries(function() return sky:_spawnPasser() end, 5)
        cam:move({ panY = 16, zoom = 1, frames = 480 })
        ctx.wait(520)
      end,
    },
    -- 2. A tall partner ducks under the roof's edge -- and tells you it's cramped
    {
      name = "pallet_duck",
      stage = function()
        ctx.party({ { 130, 40, friendship = 200, nick = "GYARADOS" } })
        ctx.go("MAP_PALLET_TOWN", 14, 8, "left")
        ctx.hidePeople()
        cam:engineZoom(1)
        cam:set({ panX = -16 })
      end,
      roll = function()
        ctx.wait(30)
        ctx.walk("left", 3) -- along the front of the house: it crouches, sweating
        ctx.wait(60)
        ctx.face("right")
        local px, py = player()
        local fx, fy = partner()
        cam:move({ at = { between(px, py, fx, fy) }, frames = 60 })
        ctx.wait(30)
        interact(nil) -- "it's a bit cramped here"
        ctx.wait(150)
        ctx.closeText()
        ctx.wait(30)
        ctx.walk("down", 3) -- out in the open: it stands tall again
        ctx.wait(90)
      end,
    },
    -- 3. Talk: a Pikachu that loves you
    {
      name = "pikachu_talk",
      stage = function()
        ctx.party({ { 25, 20, friendship = 255, nick = "PIKACHU" } })
        ctx.go("MAP_PALLET_TOWN", 12, 13, "left")
        ctx.hidePeople()
        ctx.walk("left", 1)
        ctx.wait(30)
        ctx.face("right")
        cam:engineZoom(1)
        local px, py = player()
        local fx, fy = partner()
        cam:set({ at = { between(px, py, fx, fy) } })
      end,
      roll = function()
        ctx.wait(30)
        interact(3)
        ctx.wait(160)
        ctx.tap("a")
        ctx.wait(40)
        ctx.closeText()
        ctx.wait(40)
      end,
    },
    -- 4. Lavender Town: ghosts drifting through walls and over roofs
    {
      name = "lavender_ghosts",
      stage = function()
        ctx.party({ { 25, 20, nick = "PIKACHU" } })
        ctx.go("MAP_LAVENDER_TOWN", 15, 12, "up")
        ls.timers = {}
        ls:clear()
        cam:set({ zoom = 1.1 })
      end,
      roll = function()
        local g = startScene("ghost")
        if g then cam:track(function() return g.x + 8, g.y + 8 end, { zoom = 1.4, lag = 0.03 }) end
        ctx.wait(240)
        startScene("ghost")
        ctx.waitUntil(function() return not scene("ghost") end, 1200)
        cam:still()
        ctx.wait(30)
      end,
    },
    -- 5. "Do you believe in ghosts?" ... "No." -- and something rises up behind you
    {
      name = "lavender_gengar",
      stage = function()
        ctx.party({ { 25, 20, nick = "PIKACHU" } })
        -- a FRESH load puts her on her start cell (19,10) -- coming from another map, since
        -- she wanders -- then stand just below wherever she is, facing up
        ctx.go("MAP_PALLET_TOWN", 12, 12, "down")
        ctx.go("MAP_LAVENDER_TOWN", 19, 11, "up")
        local Objects = require("src.core.game3.objects")
        local girl = Objects.find(1)
        if girl and girl.cellX and not (girl.cellX == 19 and girl.cellY == 10) then
          ctx.go("MAP_LAVENDER_TOWN", girl.cellX, girl.cellY + 1, "up")
        end
        ls.timers = {}
        ls:clear()
        cam:engineZoom(1)
        cam:set({ panY = 8 })
      end,
      roll = function()
        local saved = ls.rng
        ls.rng = function(a, _b) return a end -- (the 1 in 4 always comes up, for the camera)
        local Choice = package.loaded["src.ui.game3.choice"]
        ctx.tap("a")
        local seen = false
        for t = 1, 1500 do
          ctx.frame()
          if Choice and Choice.isOpen and Choice.isOpen() then
            ctx.wait(40)
            ctx.tap("b") -- "No."
          elseif ctx.Message.isOpen() and t % 50 == 0 then
            ctx.tap("a")
          end
          if scene("gengar") and not seen then
            seen = true
            cam:move({ panY = 24, frames = 90 })
          end
          if seen and not scene("gengar") then break end
          if not seen and t > 200 and not ctx.Message.isOpen() then break end
        end
        ls.rng = saved
        ctx.wait(60)
      end,
    },
    -- 6. The Safari Zone, full of visible Pokemon
    {
      name = "safari",
      stage = function()
        ctx.party({ { 25, 20, nick = "PIKACHU" } })
        ctx.go("MAP_SAFARI_ZONE_CENTER", 26, 28, "up")
        cam:set({ panY = -32, zoom = 1.25 })
      end,
      roll = function()
        cam:move({ panX = -40, panY = -48, zoom = 1.05, frames = 420 })
        ctx.wait(460)
      end,
    },
    -- 7. Finale: Pallet Town from up high
    {
      name = "kanto_finale",
      stage = function()
        ctx.party({ { 25, 20, friendship = 255, nick = "PIKACHU" } })
        ctx.go("MAP_PALLET_TOWN", 12, 12, "down")
        sky:clear()
        cam:set({ zoom = 1.8 })
      end,
      roll = function()
        ctx.wait(20)
        tries(function() return sky:_spawnPasser() end, 5)
        cam:move({ panY = -24, zoom = 1, frames = 480 })
        ctx.wait(520)
      end,
    },
  }
end
