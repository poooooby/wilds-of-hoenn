-- Run: lua tests/wild_herd_unit_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local failures = 0
local function check(cond, msg)
  if not cond then
    failures = failures + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  else
    print("ok  " .. tostring(msg))
  end
end
local function eq(a, b, msg)
  check(a == b, string.format("%s (got %s expected %s)", msg, tostring(a), tostring(b)))
end

local WildHerd = assert(loadfile("lib/wild_herd.lua"))({})

-- ------- members: the leader's own-species group, never the leader, at most MAX - 1
do
  local ents = {}
  local function mon(id, sp) ents[id] = { id = id, species = sp, level = 5 + id, personality = 100 + id } return ents[id] end
  local leader = mon(1, 263)
  for id = 2, 7 do mon(id, 263) end
  leader.group = { leader = 1, members = { 1, 2, 3, 4, 5, 6, 7 } }
  local h = WildHerd.members(leader, ents)
  eq(#h, WildHerd.MAX - 1, "at most MAX - 1 others (MAX on screen with the leader)")
  eq(h[1].species, 263, "...each with its species")
  eq(h[1].personality, 102, "...personality (its pic: a Spinda's spots)")
  eq(h[1].id, 2, "...and id, the leader never among them")
  ents[3] = nil
  leader.group.members = { 1, 2, 3 }
  eq(#WildHerd.members(leader, ents), 1, "a member gone meanwhile is skipped")
  ents[2].species = 264
  eq(#WildHerd.members(leader, ents), 0, "another species (not one group of a kind) is not shown")
  ents[2].species = 263
  leader.group.escort = { dex = 1 }
  eq(#WildHerd.members(leader, ents), 0, "an escort's companions: no herd battle")
  leader.group.escort = nil
  eq(#WildHerd.members(ents[2], ents), 0, "a member is no leader")
  eq(#WildHerd.members({ id = 9, species = 263 }, ents), 0, "no group: no herd")
  eq(#WildHerd.members(leader, nil), 0, "no entities: no herd")
end

-- ------- slots: a loose pack behind the leader, on the screen
do
  for n = 1, WildHerd.MAX - 1 do eq(#WildHerd.slots(n), n, n .. " others: " .. n .. " places") end
  eq(#WildHerd.slots(0), 0, "none: no places")
  eq(#WildHerd.slots(9), WildHerd.MAX - 1, "more than fit: the most there are")
  for n = 1, WildHerd.MAX - 1 do
    local s = WildHerd.slots(n)
    local left, right = false, false
    for i, p in ipairs(s) do
      if i > 1 then check(s[i - 1][2] <= p[2], n .. " others: drawn farthest (highest) first, slot " .. i) end
      -- (the leader stands at x 176 on a 240 px screen; a 64 px pic at SCALE)
      check(176 + p[1] <= 240 and 176 + p[1] - 32 * WildHerd.SCALE >= 0,
        n .. " others: on the screen (" .. p[1] .. ")")
      check(math.abs(p[1]) <= 60, n .. " others: close behind it (" .. p[1] .. ")")
      check(p[2] < 0 and p[2] > -24, n .. " others: behind it, a little higher up (" .. p[2] .. ")")
      if p[1] < 0 then left = true end
      if p[1] > 0 then right = true end
      for j = 1, i - 1 do
        local q = s[j]
        local d = math.sqrt((p[1] - q[1]) ^ 2 + (p[2] - q[2]) ^ 2)
        check(d >= 21, n .. " others: slots " .. j .. " and " .. i .. " not hugging (" .. string.format("%.1f", d) .. " px)")
      end
    end
    if n >= 2 then check(left and right, n .. " others: on both sides of it") end
  end
  check(not WildHerd.FLIP, "facing the player, as the leader does")
  check(WildHerd.SCALE < 1, "smaller than the leader (in the background)")
  for n = 1, WildHerd.MAX - 1 do
    local full, near = WildHerd.slots(n), WildHerd.slots(n, true)
    eq(#near, n, n .. " others, compact: as many places")
    for i = 1, n do
      check(math.abs(near[i][1]) <= math.abs(full[i][1]), n .. " others, compact: nearer the leader")
      check(near[i][2] <= 0 and near[i][2] >= full[i][2], n .. " others, compact: no farther back")
    end
  end
  check(WildHerd.slots(4)[1][1] == WildHerd.SLOTS[4][1][1], "the places table itself is never changed")
end

-- ------- cheering: hops and barks, each to its own rhythm
do
  local c = WildHerd.CHEER
  local hopped, barked, squashed, together = {}, {}, {}, 0
  local firstHop = {}
  for t = 0, 600 do
    local up = 0
    for k = 1, WildHerd.MAX - 1 do
      local dy, sx, sy, bark = WildHerd.cheer(t, k)
      check(dy <= 0 and dy >= -c.height - 1e-9, "a hop stays within its height") 
      if dy < 0 then hopped[k] = true up = up + 1 if not firstHop[k] then firstHop[k] = t end end
      if bark then barked[k] = true check(bark >= 0 and bark < c.barkTicks, "a bark's age in range") end
      if sy < 1 then squashed[k] = true check(sx > 1, "a squash widens it as it flattens") end
    end
    if up == WildHerd.MAX - 1 then together = together + 1 end
  end
  for k = 1, WildHerd.MAX - 1 do
    check(hopped[k] and barked[k] and squashed[k], "member " .. k .. " hops, lands and barks")
  end
  local distinct = {}
  for k = 1, WildHerd.MAX - 1 do distinct[firstHop[k]] = true end
  local n = 0
  for _ in pairs(distinct) do n = n + 1 end
  check(n >= 3, "they start cheering at different times (individually, not all at once)")
  check(together < 20, "hardly ever all in the air at once (" .. together .. " ticks)")
  local w0, w1 = WildHerd.barkWaves(0), WildHerd.barkWaves(c.barkTicks - 1)
  eq(#w0, 3, "a bark: three sound waves")
  check(w1[2][1] > w0[2][1] and w1[2][4] < w0[2][4], "...moving away from its mouth, fading")
  local buf = WildHerd.barkWaves(0)
  local e1 = buf[1]
  local again = WildHerd.barkWaves(5, buf)
  check(again == buf and buf[1] == e1 and #buf == 3, "...filled in place when handed a list (no garbage)")
end

-- ------- kinds: all behind the leader
do
  local birds = { [16] = true, [278] = true }
  eq(WildHerd.kindOf({ dex = 263, terrain = "land" }, birds), "land", "Zigzagoon: land")
  eq(WildHerd.kindOf({ dex = 16, terrain = "land", isFlyer = true }, birds), "bird", "Pidgey: a bird")
  eq(WildHerd.kindOf({ dex = 278, terrain = "water", isFlyer = true }, birds), "bird", "a Wingull on the water: still a bird")
  eq(WildHerd.kindOf({ dex = 81, terrain = "land" }, birds), "float", "Magnemite: floats (HOVER)")
  eq(WildHerd.kindOf({ dex = 92, terrain = "land", floater = true }, birds), "float", "Gastly: a levitating sprite")
  eq(WildHerd.kindOf({ dex = 41, terrain = "land", isFlyer = true }, birds), "float", "Zubat: a flier, not a bird")
  eq(WildHerd.kindOf({ dex = 129, terrain = "water" }, birds), "swim", "Magikarp: swims")
  eq(WildHerd.kindOf({ dex = 226, terrain = "water", isFlyer = true }, birds), "swim", "a Mantine pod on the water: swims")
  eq(WildHerd.kindOf({ dex = "479-heat", terrain = "land", floater = true }, birds), "float", "a form key reads its dex")
  eq(WildHerd.kindOf(nil, birds), "land", "nothing: land")
  local land = WildHerd.styleOf("land")
  for _, kind in ipairs({ "float", "bird", "swim" }) do
    local st = WildHerd.styleOf(kind)
    check(st.scale < 1, kind .. ": smaller than the leader (in the background)")
    check(not st.flip, kind .. ": facing the player, as the leader does")
    for n = 1, WildHerd.MAX - 1 do
      local s = WildHerd.slots(n, false, kind)
      eq(#s, n, kind .. ", " .. n .. " others: " .. n .. " places")
      local left, right = false, false
      for i, p in ipairs(s) do
        check(p[2] < 0, kind .. ": behind the leader (higher up), place " .. i)
        check(math.abs(p[1]) <= 40, kind .. ": close behind it, place " .. i)
        if i > 1 then check(p[2] >= s[i - 1][2], kind .. ": farthest back first") end
        if p[1] < 0 then left = true end
        if p[1] > 0 then right = true end
      end
      if n >= 2 then check(left and right, kind .. ", " .. n .. " others: on both sides of it") end
    end
  end
  eq(WildHerd.styleOf("nope"), land, "an unknown kind: land")
  eq(WildHerd.slots(2, false, "nope")[1][1], WildHerd.SLOTS[2][1][1], "...and its places")
end

-- ------- poses: hovering, bobbing, birds hopping about, the land pack cheering
do
  local out = {}
  local lo, hi, rots = 0, 0, 0
  for t = 0, 240 do
    WildHerd.pose("float", 1, t, {}, out)
    lo, hi = math.min(lo, out.dy), math.max(hi, out.dy)
    if out.rot ~= 0 then rots = rots + 1 end
    check(out.bark == nil, "float: never barks") ; if out.bark then break end
  end
  check(lo < -2 and hi <= 0, "float: hovers up and down")
  check(rots > 0, "...tilting a little")
  WildHerd.pose("float", 1, 50, {}, out)
  local a1 = out.dy
  WildHerd.pose("float", 2, 50, {}, out)
  check(out.dy ~= a1, "...each to its own rhythm")
  lo, hi = 0, 0
  for t = 0, 200 do
    WildHerd.pose("swim", 1, t, {}, out)
    lo, hi = math.min(lo, out.dy), math.max(hi, out.dy)
  end
  check(lo < -1 and hi > 1 and hi <= 2, "swim: bobs gently")
  -- a bird hopping about
  local s, xs, flips, hops, moved = {}, {}, {}, 0, 0
  local c = WildHerd.WANDER
  local last = 0
  for t = 1, 3000 do
    WildHerd.pose("bird", 1, t, s, out)
    check(math.abs(out.dx) <= c.range, "bird: stays near its place") ; if math.abs(out.dx) > c.range then break end
    if out.dy < 0 then hops = hops + 1 end
    if out.dx ~= last then moved = moved + 1 end
    last = out.dx
    flips[out.flip] = true
    xs[math.floor(out.dx + 0.5)] = true
  end
  check(hops > 100, "bird: hops (" .. hops .. " airborne ticks)")
  check(flips[true] and flips[false], "...facing both ways (the way it goes, turning round)")
  local spots = 0
  for _ in pairs(xs) do spots = spots + 1 end
  check(spots >= 8, "...about all over its patch (" .. spots .. " spots)")
  WildHerd.pose("bird", 1, 3000, s, out)
  local x0 = out.dx
  WildHerd.pose("bird", 1, 3000, s, out)
  eq(out.dx, x0, "...not moved again on the same tick (the intro: the clock stands still)")
  local s2 = {}
  for t = 1, 600 do WildHerd.pose("bird", 2, t, s2, out) end
  check(s2.seed ~= s.seed, "two birds on their own paths")
  WildHerd.pose("land", 1, 0, {}, out)
  check(out.flip == false, "land: facing the player, as the leader does")
end

-- ------- caught: they flee the battle screen
do
  for _, kind in ipairs({ "land", "float", "bird", "swim" }) do
    local goneAt = {}
    for k = 1, 4 do
      for age = 0, 200 do
        local out = WildHerd.pose(kind, k, 100, {}, {})
        WildHerd.flee(kind, k, age, k % 2 == 0 and 1 or -1, out)
        check(out.bark == nil, kind .. ": no bark while fleeing") ; if out.bark then break end
        if out.gone then goneAt[k] = age break end
      end
      check(goneAt[k] ~= nil, kind .. ": member " .. k .. " gone off the screen")
    end
    check(goneAt[4] > goneAt[1], kind .. ": one after another, not all at once")
    local o0 = WildHerd.flee(kind, 1, 0, -1, WildHerd.pose(kind, 1, 100, {}, {}))
    local o1 = WildHerd.flee(kind, 1, 20, -1, WildHerd.pose(kind, 1, 100, {}, {}))
    if kind == "land" then
      check(o1.dx < o0.dx - 30 and o1.flip == false, "land: runs off to its side (left), facing that way")
      local r1 = WildHerd.flee(kind, 1, 20, 1, WildHerd.pose(kind, 1, 100, {}, {}))
      check(r1.dx > o0.dx + 30 and r1.flip == true, "land: ...or right, from the right side")
    elseif kind == "swim" then
      check(o1.dy > o0.dy and o1.alpha < 1, "swim: dives, going under")
    else
      check(o1.dy < o0.dy - 10 and o1.alpha < 1, kind .. ": up and away, fading")
    end
  end
end

-- ------- the group lends its leader strength
do
  eq(#WildHerd.boosts(0, {}), 0, "alone: no boost")
  local b = WildHerd.boosts(1, { attack = 20, spAtk = 12 })
  eq(#b, 1, "one member: one stat")
  eq(b[1], "attack", "...its stronger attacking stat")
  eq(WildHerd.boosts(1, { attack = 12, spAtk = 20 })[1], "spAtk", "a special attacker: Sp. Atk")
  eq(WildHerd.boosts(1, nil)[1], "attack", "no stats known: Attack")
  local four = WildHerd.boosts(4, { attack = 20, spAtk = 12 })
  eq(table.concat(four, ","), "attack,defense,spDef,speed", "four members: four stats, one each")
  eq(#WildHerd.boosts(9, {}), WildHerd.MAX - 1, "never more than the group on screen")
  local stages = { attack = 0, defense = 5, spDef = 6, speed = -1 }
  eq(WildHerd.applyBoosts(stages, four), 3, "three went up (one was already at +6)")
  eq(stages.attack, 1, "+1 Attack")
  eq(stages.defense, 6, "+1 Defense, up to the cap")
  eq(stages.spDef, 6, "never past +6")
  eq(stages.speed, 0, "a lowered stat goes up too")
  eq(WildHerd.applyBoosts(nil, four), 0, "no stages: nothing")
  local steps = { { kind = "msg", data = { text = "Go! SWAMPERT!" } } }
  eq(WildHerd.addBoostSteps(steps, "cheer", "rose"), 3, "boost steps added: the wait is step 3")
  eq(#steps, 4, "...three of them")
  eq(steps[1].data.text, "Go! SWAMPERT!", "...after the intro's own steps")
  eq(steps[2].data.text, "cheer", "the cheer line first")
  check(steps[3].kind == "wait" and steps[3].data.wohBoost and steps[3].data.frames == 1,
    "then a short wait, where the stat-up animation plays")
  eq(steps[4].data.text, "rose", "then the line saying it rose")
  eq(WildHerd.addBoostSteps(nil, "a", "b"), nil, "no steps: nothing")
  local SA = { MULTIPLE_PLUS1 = 55 }
  local function argOf(stat, d) return (stat == "attack" and 15 or 99) + d - 1 end
  eq(WildHerd.boostAnimArg({ "attack", "defense" }, SA, argOf), 55, "several stats: the multiple-stats animation")
  eq(WildHerd.boostAnimArg({ "attack" }, SA, argOf), 15, "one: that stat's own")
  eq(WildHerd.boostAnimArg({}, SA, argOf), nil, "none: no animation")
  eq(string.format(WildHerd.CHEER_TEXT, "ZIGZAGOON"), "ZIGZAGOON's group cheers it on!", "the English cheer")
  eq(string.format(WildHerd.ROSE_TEXT, "ZIGZAGOON"), "ZIGZAGOON's power rose!", "the English rise")
end

-- ------- the intro's line
do
  local steps = {
    { kind = "fade", data = {} },
    { kind = "msg", data = { text = "Other" } },
    { kind = "msg", data = { text = "Wild ZIGZAGOON appeared!" } },
  }
  check(WildHerd.patchIntroText(steps, "Wild ZIGZAGOON appeared!", "A wild ZIGZAGOON group appeared!"),
    "the intro's line found")
  eq(steps[3].data.text, "A wild ZIGZAGOON group appeared!", "...and swapped for the group's")
  eq(steps[2].data.text, "Other", "...the other messages left alone")
  check(not WildHerd.patchIntroText(steps, "missing", "x"), "no such line: nothing changed")
  check(not WildHerd.patchIntroText(nil, "a", "b"), "no steps: nothing")
  eq(string.format(WildHerd.TEXT, "ZIGZAGOON"), "A wild ZIGZAGOON group appeared!", "the English line")
end

if failures > 0 then
  io.stderr:write(string.format("\nwild_herd_unit_test: %d failure(s)\n", failures))
  os.exit(1)
end
print("\nwild_herd_unit_test: all passed")
