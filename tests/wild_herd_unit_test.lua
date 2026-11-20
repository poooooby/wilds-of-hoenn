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

-- ------- slots: a loose pack left of the leader, on the screen
do
  for n = 1, WildHerd.MAX - 1 do eq(#WildHerd.slots(n), n, n .. " others: " .. n .. " places") end
  eq(#WildHerd.slots(0), 0, "none: no places")
  eq(#WildHerd.slots(9), WildHerd.MAX - 1, "more than fit: the most there are")
  for n = 1, WildHerd.MAX - 1 do
    local s = WildHerd.slots(n)
    local rows = {}
    for i, p in ipairs(s) do
      if i > 1 then check(s[i - 1][2] <= p[2], n .. " others: drawn farthest (highest) first, slot " .. i) end
      -- (the leader stands at x 176 on a 240 px screen; a 64 px pic at SCALE)
      check(p[1] < 0, n .. " others: left of the leader (" .. p[1] .. ")")
      check(176 + p[1] - 32 * WildHerd.SCALE >= 0, n .. " others: on the screen (" .. p[1] .. ")")
      check(p[2] <= 0 and p[2] > -24, n .. " others: about on the leader's ground (" .. p[2] .. ")")
      rows[p[2] < -12 and "back" or "front"] = true
      for j = 1, i - 1 do
        local q = s[j]
        local d = math.sqrt((p[1] - q[1]) ^ 2 + (p[2] - q[2]) ^ 2)
        check(d >= 21, n .. " others: slots " .. j .. " and " .. i .. " not hugging (" .. string.format("%.1f", d) .. " px)")
      end
    end
    if n >= 3 then check(rows.back and rows.front, n .. " others: a huddle, not a line (a back row and a front row)") end
  end
  check(WildHerd.FLIP, "mirrored: they face the leader")
  for n = 1, WildHerd.MAX - 1 do
    local full, near = WildHerd.slots(n), WildHerd.slots(n, true)
    eq(#near, n, n .. " others, compact: as many places")
    for i = 1, n do
      check(near[i][1] < 0 and near[i][1] > full[i][1], n .. " others, compact: still left of the leader, nearer it")
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
