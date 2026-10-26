-- Translations of this mod's own text (the Language option: English, Japanese, Portuguese,
-- Spanish, German; English is the default).
--
-- Keyed by the ENGLISH SOURCE, like the engine's own src/core/Strings.lua: a call site
-- keeps its readable English,
--
--   I18n.t("Found %s!", itemName)
--
-- and a language file (lib/lang/<code>.lua) maps that English to its translation. A line a
-- language has not translated falls back to the English, never to a raw key. The same
-- English with two meanings takes a context: I18n.tc("party", "BATTLE") looks up
-- "party|BATTLE" first.
--
-- Format directives fill in argument order; a translation that needs another order numbers
-- them POSIX-style ("%2$s ... %1$s"). A translation that numbers some directives but not
-- all, or numbers one the English does not have, falls back to the English.
--
-- The game's font is the Gen 3 cart's: Japanese is written in kana (the cart has no kanji,
-- like the original Japanese releases), and the Latin font has the Spanish and German
-- letters but no ã / õ (there was never a Portuguese Gen 3 release), so FONT_FALLBACK maps
-- those to plain a / o when drawn. The language files keep the correct spelling.
local V = ...

local I18n = {}

I18n.LANGUAGES = { "en", "ja", "pt", "es", "de" }
-- the Language option's choices, each shown in its own language
I18n.NAMES = { en = "ENGLISH", ja = "にほんご", pt = "PORTUGUÊS", es = "ESPAÑOL", de = "DEUTSCH" }

-- characters the Gen 3 font has no glyph for -> the nearest it has
I18n.FONT_FALLBACK = { ["ã"] = "a", ["õ"] = "o", ["Ã"] = "A", ["Õ"] = "O" }

local current = "en"
local catalogs = {} -- [code] = table | false (missing)

local function catalog(code)
  if code == "en" then return nil end
  local hit = catalogs[code]
  if hit == nil then
    local ok, t = pcall(V.require, "lang/" .. code)
    hit = (ok and type(t) == "table") and t or false
    catalogs[code] = hit
  end
  return hit or nil
end

--- Sets the language ("en" / "ja" / "pt" / "es" / "de"; anything else -> English).
function I18n.setLanguage(code)
  local known = false
  for _, c in ipairs(I18n.LANGUAGES) do if c == code then known = true end end
  current = known and code or "en"
  return current
end

function I18n.language() return current end

local function fallbackChars(s)
  return (s:gsub("[\xC3][\x83\x95\xA3\xB5]", I18n.FONT_FALLBACK))
end

-- the directives of a format string, in order (%% skipped)
local function directives(s)
  local list = {}
  for spec in s:gmatch("%%([%d%$%-%.]*[sdif])") do list[#list + 1] = spec end
  return list
end

-- A translation's format usable with the English's arguments: plain directives (in order)
-- or ALL numbered within range. nil = fall back to the English.
local function formatOf(english, translated)
  local src, dst = directives(english), directives(translated)
  local numbered = 0
  for _, d in ipairs(dst) do if d:find("%$") then numbered = numbered + 1 end end
  if numbered == 0 then
    return #dst <= #src and translated or nil
  end
  if numbered ~= #dst then return nil end
  for _, d in ipairs(dst) do
    local n = tonumber(d:match("^(%d+)%$"))
    if not n or n < 1 or n > #src then return nil end
  end
  return translated
end

local function fill(fmt, ...)
  local n = select("#", ...)
  if n == 0 then return fmt end
  if not fmt:find("%%%d+%$") then return string.format(fmt, ...) end
  local args = { ... }
  return (fmt:gsub("%%(%d+)%$([%-%.%d]*[sdif])", function(i, spec)
    return string.format("%" .. spec, args[tonumber(i)])
  end))
end

local function lookup(key, english)
  local t = catalog(current)
  if not t then return nil end
  local s = t[key]
  if s == nil and key ~= english then s = t[english] end
  return type(s) == "string" and s or nil
end

--- The text for `english` in the current language, filled with the arguments.
function I18n.t(english, ...)
  local s = lookup(english, english)
  if s then
    local fmt = formatOf(english, s)
    if fmt then return fallbackChars(fill(fmt, ...)) end
  end
  return fill(english, ...)
end

--- The current language's FORMAT for `english` (unfilled), or `english` itself.
function I18n.format(english)
  local s = lookup(english, english)
  return (s and formatOf(english, s)) or english
end

--- I18n.t with a context: "<context>|<english>" is looked up first, then the English.
function I18n.tc(context, english, ...)
  local s = lookup(context .. "|" .. english, english)
  if s then
    local fmt = formatOf(english, s)
    if fmt then return fallbackChars(fill(fmt, ...)) end
  end
  return fill(english, ...)
end

--- A list of English lines (call-out lists, dialogue pools) in the current language: the
--- language's own list for `key` when it has one, else `list` itself.
function I18n.list(key, list)
  local t = catalog(current)
  local own = t and t["list:" .. key]
  if type(own) ~= "table" or #own == 0 then return list end
  local out = {}
  for i, line in ipairs(own) do out[i] = fallbackChars(line) end
  return out
end

-- lower-case accented letters -> the capitals the Gen 3 font has (ã / õ have none: they
-- are drawn as a / o anyway)
local UPPER = {
  ["á"] = "Á", ["à"] = "À", ["â"] = "Â", ["ç"] = "Ç", ["é"] = "É", ["è"] = "È", ["ê"] = "Ê",
  ["ë"] = "Ë", ["í"] = "Í", ["î"] = "Î", ["ï"] = "Ï", ["ó"] = "Ó", ["ò"] = "Ò", ["ô"] = "Ô",
  ["ú"] = "Ú", ["ù"] = "Ù", ["û"] = "Û", ["ñ"] = "Ñ", ["ä"] = "Ä", ["ö"] = "Ö", ["ü"] = "Ü",
  ["ã"] = "A", ["õ"] = "O",
}

--- `s` in capitals, accented letters too ("Vida acuática" -> "VIDA ACUÁTICA"); kana are
--- left as they are, and POKéMON keeps its small é, as the Gen 3 games write it.
function I18n.upper(s)
  s = tostring(s or ""):upper()
  s = s:gsub("[\195][\128-\191]", UPPER)
  return (s:gsub("POKÉMON", "POKéMON"))
end

function I18n._reset() catalogs = {} current = "en" end

return I18n
