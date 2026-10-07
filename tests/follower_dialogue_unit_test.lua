-- Run: lua tests/follower_dialogue_unit_test.lua
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

local Dialogue = assert(loadfile("lib/follower_dialogue.lua"))(nil)

-- every reason lib/mon_mood.lua can produce has a report
local REASONS = { "fainted", "critical", "poison", "burn", "paralysis", "freeze", "sleep", "low",
  "hurt", "angry", "sad", "normal", "happy", "sore", "joyous", "inspired" }
for _, reason in ipairs(REASONS) do
  check(type(Dialogue.REPORT[reason]) == "table" and #Dialogue.REPORT[reason] > 0, "a report exists for '" .. reason .. "'")
end

-- fixed rng -> the first variant
local first = function() return 0 end
eq(Dialogue.report("happy", "BLAZE", first), "BLAZE seems to be in\ngood spirits!", "report fills the name")
check(Dialogue.report("nonsense", "BLAZE", first):find("BLAZE", 1, true), "an unknown reason falls back to the normal report")

-- the name is substituted literally (no pattern surprises)
local weird = Dialogue.report("normal", "50%+[A]%1", first)
check(weird:find("50%+[A]%1", 1, true) ~= nil, "a nickname with pattern characters survives untouched")

-- the dialogue box holds two lines, so every line of every text is
-- at most two lines of at most 32 characters even with a 10 letter name
local function lintAll(label, list)
  for i, text in ipairs(list) do
    local filled = text:gsub("{name}", "ABCDEFGHIJ")
    local lines = 0
    for line in (filled .. "\n"):gmatch("(.-)\n") do
      lines = lines + 1
      check(#line <= 32, string.format("%s[%d] line '%s' fits (%d chars)", label, i, line, #line))
    end
    check(lines <= 2, string.format("%s[%d] is at most 2 lines (%d)", label, i, lines))
    check(not filled:find("{", 1, true), string.format("%s[%d] has no unresolved placeholder", label, i))
  end
end
for reason, list in pairs(Dialogue.REPORT) do lintAll("REPORT." .. reason, list) end
for action, list in pairs(Dialogue.ACTION) do lintAll("ACTION." .. action, list) end
for action, list in pairs(Dialogue.ACTION_HURTING) do lintAll("HURTING." .. action, list) end
for kind, list in pairs(Dialogue.REFUSAL) do lintAll("REFUSAL." .. kind, list) end
lintAll("MAXED", Dialogue.MAXED)
lintAll("LOCKED_NOW", Dialogue.LOCKED_NOW)
lintAll("LOCKED", Dialogue.LOCKED)

-- actions
check(Dialogue.action("pet", "BLAZE", false, first):find("pet", 1, true), "Pet text mentions petting")
check(Dialogue.action("play", "BLAZE", false, first):find("played", 1, true), "Play text mentions playing")
check(Dialogue.action("talk", "BLAZE", false, first):find("talked", 1, true), "Talk text mentions talking")
check(Dialogue.action("pet", "BLAZE", true, first) ~= Dialogue.action("pet", "BLAZE", false, first), "a hurting mon gets the softer text")
check(Dialogue.action("dance", "BLAZE", false, first):find("BLAZE", 1, true), "an unknown action still produces a line")

-- refusals
for _, kind in ipairs({ "cooldown", "tired", "locked_now", "locked" }) do
  check(Dialogue.refusal(kind, "BLAZE", first):find("BLAZE", 1, true), "refusal '" .. kind .. "' names the Pokemon")
end
check(Dialogue.refusal("locked_now", "X", first) ~= Dialogue.refusal("locked", "X", first), "being cut off differs from still being locked")
check(Dialogue.maxed("BLAZE", first):find("BLAZE", 1, true), "maxed text names the Pokemon")

-- variants are chosen by the rng
local last = function() return 0.999 end
check(Dialogue.report("joyous", "B", first) ~= Dialogue.report("joyous", "B", last), "different rng values pick different variants")

-- ------- Play turned down: why, one line per blocker, always "can't play"
for reason, word in pairs({ low = "hurt", poison = "sick", paralysis = "paralyzed", freeze = "too cold",
    burn = "burning", sleep = "asleep" }) do
  local text = Dialogue.cantPlay(reason, "BLAZE", first)
  check(text:find("BLAZE", 1, true) and text:find(word, 1, true) and text:find("can't play", 1, true),
    "cantPlay(" .. reason .. "): '" .. word .. " ... can't play'")
  check(select(2, text:gsub(string.char(10), "")) <= 1, "cantPlay(" .. reason .. ") fits the two-line box")
end
check(Dialogue.cantPlay("???", "B", first):find("can't play", 1, true), "an unknown reason still refuses politely")

-- ------- Petting cured it
eq(Dialogue.healed("BLAZE", first), "BLAZE feels better now!", "the cure line")

-- ------- Talk: friendship as a share of the maximum (255), with the portrait to match
local function talk(f) local text, emotion, key = Dialogue.talk(f, "BLAZE", first) return text, emotion, key end
local cases = {
  { 0, "wary", "Worried", "wary of" }, { 50, "wary", "Worried", "wary of" },        -- 19.6%
  { 51, "curious", "Surprised", "curious about you" },                                  -- 20%
  { 101, "curious", "Surprised", "curious about you" },                                 -- 39.6%
  { 102, "starting", "Happy", "starting to like you" },                                 -- 40%
  { 152, "starting", "Happy", "starting to like you" },                                 -- 59.6%
  { 153, "trusts", "Determined", "trusts you" },                                        -- 60%
  { 203, "trusts", "Determined", "trusts you" },                                        -- 79.6%
  { 204, "likes", "Joyous", "really likes you" },                                       -- 80%
  { 241, "likes", "Joyous", "really likes you" },                                       -- 94.5%
  { 243, "loves", "Inspired", "loves you" },                                            -- 95.3%
  { 255, "loves", "Inspired", "loves you" },
}
for _, c in ipairs(cases) do
  local text, emotion, key = talk(c[1])
  eq(key, c[2], "friendship " .. c[1] .. " is the '" .. c[2] .. "' tier")
  eq(emotion, c[3], "...with the " .. c[3] .. " portrait")
  check((text:gsub(string.char(10), " ")):find(c[4], 1, true), "...saying '" .. c[4] .. "'")
end
check(talk(0):find("BLAZE", 1, true), "talk names the Pokemon")
eq(select(3, talk(-5)), "wary", "a nonsense low friendship is the lowest tier")
eq(select(3, talk(9999)), "loves", "...and a huge one the highest")
eq(select(3, talk(nil)), "wary", "...and none at all the lowest")

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("follower_dialogue_unit_test: all passed")
