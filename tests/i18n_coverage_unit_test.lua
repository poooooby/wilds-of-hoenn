-- Run: lua tests/i18n_coverage_unit_test.lua
-- lib/i18n.lua and the language files (lib/lang/*.lua): every English text the mod
-- translates (tests/i18n_keys.lua) is in every language, fills the same way, fits where
-- it is drawn, and uses only characters the Gen 3 font has.
package.path = "./?.lua;./?/init.lua;" .. package.path

local failures = 0
local function check(cond, msg)
  if not cond then
    failures = failures + 1
    io.stderr:write("FAIL: " .. tostring(msg) .. "\n")
  end
end
local function eq(a, b, msg)
  check(a == b, string.format("%s (got %s expected %s)", msg, tostring(a), tostring(b)))
end

-- ------------------------------------------------------------------ lib/i18n.lua
local catalogs = {
  ["lang/ja"] = { ["Found %s!"] = "%sを みつけた！", ["menu|Back"] = "もどる", ["Back"] = "x",
    ["%s's %s"] = "%2$s de %1$s", ["bad %s"] = "%s %s", ["mixed %s %s"] = "%1$s %s",
    ["list:send"] = { "いけっ！|%s！" } },
  ["lang/pt"] = { ["No"] = "Não", ["list:send"] = { "Não|%s!" } },
}
local V = { require = function(name) return catalogs[name] or error("no " .. name) end }
local I18n = assert(loadfile("lib/i18n.lua"))(V)
eq(I18n.language(), "en", "English by default")
eq(I18n.t("Found %s!", "ORAN BERRY"), "Found ORAN BERRY!", "English: the source, filled")
eq(I18n.setLanguage("xx"), "en", "an unknown language is English")
I18n.setLanguage("ja")
eq(I18n.t("Found %s!", "ORAN BERRY"), "ORAN BERRYを みつけた！", "a translation, filled")
eq(I18n.t("Not translated %d", 5), "Not translated 5", "an untranslated line falls back to the English")
eq(I18n.tc("menu", "Back"), "もどる", "a context key")
eq(I18n.tc("party", "Back"), "x", "a context without its own key: the plain one")
eq(I18n.t("%s's %s", "PIKACHU", "ATTACK"), "ATTACK de PIKACHU", "numbered directives reorder")
eq(I18n.t("bad %s", "A", "B"), "bad A", "more directives than the English: English")
eq(I18n.t("mixed %s %s", "A", "B"), "mixed A B", "some numbered, some not: English")
eq(I18n.format("Found %s!"), "%sを みつけた！", "format: the translated, unfilled")
eq(I18n.list("send", { "Go!|%s!" })[1], "いけっ！|%s！", "a language's own list")
eq(I18n.list("recall", { "Back|%s!" })[1], "Back|%s!", "no list of its own: the English")
I18n.setLanguage("pt")
eq(I18n.t("No"), "Nao", "ã (no glyph in the Gen 3 font) is drawn as a")
eq(I18n.list("send", {})[1], "Nao|%s!", "...in lists too")
eq(I18n.upper("Vida acuática"), "VIDA ACUÁTICA", "upper: accented letters too")
eq(I18n.upper("Wilde Pokémon"), "WILDE POKéMON", "upper: POKéMON keeps its small é, as Gen 3 writes it")
eq(I18n.upper("Reações"), "REAÇOES", "upper: õ has no capital in the font: O")
eq(I18n.upper("やせいを みせる"), "やせいを みせる", "upper: kana untouched")
I18n.setLanguage("en")

-- ------------------------------------------------------------ the language files
local K = dofile("tests/i18n_keys.lua")
local keys, lists = K.keys, K.lists

-- the Gen 3 font: printable ASCII, the Latin letters it has, kana, the full-width
-- symbols Japanese uses (src/ui/game3/frlg_font.lua, the charmap), and the arrows
local allowed = {}
for c = 32, 126 do allowed[string.char(c)] = true end
allowed[string.char(10)] = true -- the line break
local function allow(s) for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do allowed[ch] = true end end
allow("ÀÁÂÇÈÉÊËÌÎÏÒÓÔŒÙÚÛÑßàáâçèéêëìîïòóôœùúûñºª¿¡ÍíäöüÄÖÜ…“”‘’▶◀")
allow("あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよらりるれろわをんぁぃぅぇぉゃゅょがぎぐげござじずぜぞだぢづでどばびぶべぼぱぴぷぺぽっ")
allow("アイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワヲンァィゥェォャュョガギグゲゴザジズゼゾダヂヅデドバビブベボパピプペポッ")
allow("　！？。ー‥『』「」♂♀円：０１２３４５６７８９")
allow("ãõÃÕ") -- drawn as a / o (I18n.FONT_FALLBACK)

local KANA = "[\227][\128-\191][\128-\191]"
-- width in "Latin letters": a kana / full-width glyph is about 1.75 of one
local function width(s)
  local w = 0
  for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    w = w + ((#ch == 3 and ch:find("^" .. KANA)) and 1.75 or 1)
  end
  return w
end
local function count(s, pat) local _, n = s:gsub(pat, "") return n end
local function directives(s) local t = {} for d in s:gmatch("%%[%d%$]*[sdif]") do t[#t + 1] = d:gsub("%d+%$", "") end return table.concat(t, ",") end

local SKIP_CHARS = { ["option|Language"] = false }
for _, code in ipairs({ "ja", "pt", "es", "de" }) do
  local t = assert(loadfile("lib/lang/" .. code .. ".lua"))()
  local missing, extra = {}, {}
  for k in pairs(keys) do if t[k] == nil then missing[#missing + 1] = k end end
  for k in pairs(t) do if keys[k] == nil and not k:find("^list:") then extra[#extra + 1] = k end end
  check(#missing == 0, code .. ": every key translated (missing: " .. table.concat(missing, " / ") .. ")")
  check(#extra == 0, code .. ": no stale keys (" .. table.concat(extra, " / ") .. ")")
  for k, v in pairs(t) do
    if type(v) == "string" then
      local english = k:gsub("^%w+|", "")
      -- every character drawable
      for ch in v:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        check(allowed[ch], ("%s: %q has %q, which the Gen 3 font cannot draw"):format(code, k, ch))
      end
      -- the same fill-ins
      eq(directives(v):gsub("%%", ""), directives(english):gsub("%%", ""), code .. ": same %s / %d as the English: " .. k)
      eq(count(v, "{name}"), count(english, "{name}"), code .. ": {name} kept: " .. k)
      check(count(v, "\n") <= 1, code .. ": two lines at most: " .. k)
      -- where it is drawn
      local kind = keys[k] or ""
      if kind == "option label" or kind == "choice label" then
        check(width(v) <= 14, ("%s: %q fits the 14-letter option width (%.1f)"):format(code, v, width(v)))
      end
      if k == "party|ROLE" then
        check(width(v) <= 6, ("%s: the ROLE row %q leaves room for its arrow"):format(code, v))
      end
      if k:find("^party|") then
        check(width(v) <= 11, ("%s: party row %q fits the 80 px box"):format(code, v))
      end
      if kind == "dialogue" then
        for line in (v .. "\n"):gmatch("(.-)\n") do
          local w = width((line:gsub("{name}", "WWWWWWWWWW")))
          check(w <= 38, ("%s: dialogue line fits the box (%.1f): %q"):format(code, w, line))
        end
      end
    end
  end
  for _, name in ipairs({ "send", "recall" }) do
    local list = t["list:" .. name]
    check(type(list) == "table" and #list >= 8, code .. ": a " .. name .. " list of 8+ call-outs")
    for i, line in ipairs(list or {}) do
      eq(count(line, "|"), 1, code .. ": one break in " .. name .. " " .. i)
      check(count(line, "%%s") <= 1, code .. ": at most one name in " .. name .. " " .. i)
      check(i == 1 or line ~= list[i - 1], code .. ": " .. name .. " " .. i .. " differs from the one before")
      for ch in line:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        check(allowed[ch], ("%s: %s %d has %q, which the Gen 3 font cannot draw"):format(code, name, i, ch))
      end
    end
  end
end

-- the English option labels / choices too (the Language row's names included)
for k, kind in pairs(keys) do
  if kind == "option label" or kind == "choice label" then
    check(width((k:gsub("^%w+|", ""))) <= 14, "English " .. k .. " fits")
  end
end
check(lists.send and #lists.send >= 8, "the English lists were collected")

print("")
if failures > 0 then
  io.stderr:write(failures .. " failure(s)\n")
  os.exit(1)
end
print("i18n_coverage_unit_test: all passed")
