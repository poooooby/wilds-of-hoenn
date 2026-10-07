-- Everything the follower says in the interaction menu
-- (lib/follower_interaction.lua). Plain data + three small lookups; each line
-- is at most two screen lines (explicit \n -- the dialogue box holds two) and
-- `{name}` is replaced with the Pokemon's name. Variants are picked with an
-- injectable rng so tests are deterministic.
local Dialogue = {}

-- What the Pokemon looks like right now, keyed by lib/mon_mood.lua's reason.
Dialogue.REPORT = {
  fainted = { "{name} can barely keep\nits eyes open..." },
  critical = { "{name} is in a bad way\nand looks close to tears.", "{name} is hurting badly.\nIt needs help soon!" },
  poison = { "{name} is poisoned and\nlooks miserable.", "{name} winces. The poison\nis really bothering it." },
  burn = { "{name} is burned and\nyelping in pain!", "{name} is scorched and\ncan't settle down." },
  paralysis = { "{name} is paralyzed and\ncan hardly move.", "{name} twitches. Its body\nwon't listen to it." },
  freeze = { "{name} is frozen stiff\nand shivering.", "{name} is encased in ice\nand looks stunned." },
  sleep = { "{name} is half asleep\nand swaying a little.", "{name} can barely stay\nawake right now." },
  low = { "{name} is hurt and\nlooks uneasy.", "{name} is limping and\nwinces when it moves." },
  hurt = { "{name} looks a bit\nworried about its wounds.", "{name} is a little banged\nup and keeping close." },
  angry = { "{name} glares at you.\nIt doesn't trust you yet.", "{name} snorts and looks\nreally annoyed." },
  sad = { "{name} looks down and\nkeeps its distance.", "{name} sighs. It seems\na little lonely." },
  normal = { "{name} looks up at you\ncalmly.", "{name} is watching you,\nwaiting to see what's next." },
  happy = { "{name} seems to be in\ngood spirits!", "{name} wags along happily,\nglad you're here." },
  sore = { "{name} is happy, though\na little sore.", "{name} smiles, but it's\nfavouring a sore spot." },
  joyous = { "{name} is overjoyed to\nsee you!", "{name} is beaming with\njoy!" },
  inspired = { "{name} is brimming with\nenergy and bonds!", "{name} is full of life.\nIt loves you dearly!" },
}

-- Results of an action that worked.
Dialogue.ACTION = {
  pet = { "You pet {name}.\nIt leans into your hand!", "You stroke {name}.\nIt closes its eyes happily." },
  play = { "You played with {name}!\nIt's having a blast!", "You and {name} romp\naround together!" },
  talk = { "You talked with {name}.\nIt listens closely.", "You chat with {name}.\nIt seems to understand." },
}

-- A hurting Pokemon appreciates the attention but still shows it
-- (used when the action's face is state-derived rather than a happy one).
Dialogue.ACTION_HURTING = {
  pet = { "You gently pet {name}.\nIt takes comfort in it." },
  play = { "{name} tries to play,\nbut it's hurting." },
  talk = { "You talk softly to\n{name}. It listens." },
}

-- Play turned down because the Pokemon is not up to it, keyed by
-- MonMood.playBlocker's reason.
Dialogue.CANT_PLAY = {
  low = { "{name} is hurt and\ncan't play." },
  poison = { "{name} is sick and\ncan't play." },
  paralysis = { "{name} is paralyzed and\ncan't play." },
  freeze = { "{name} is too cold and\ncan't play." },
  burn = { "{name} is burning and\ncan't play." },
  sleep = { "{name} is asleep and\ncan't play." },
}

-- Petting cured its status condition.
Dialogue.HEALED = { "{name} feels better now!" }

-- Talking: how it feels about you, by friendship as a share of the maximum
-- (255). Ascending: { minimum percent, key, portrait emotion, lines }.
Dialogue.FRIENDSHIP_MAX = 255
Dialogue.TALK_TIERS = {
  { 0, "wary", "Worried", { "{name} is wary of\nyou..." } },
  { 20, "curious", "Surprised", { "{name} is curious\nabout you!" } },
  { 40, "starting", "Happy", { "{name} is starting\nto like you!" } },
  { 60, "trusts", "Determined", { "{name} trusts you!" } },
  { 80, "likes", "Joyous", { "{name} really likes\nyou!" } },
  { 95, "loves", "Inspired", { "{name} loves you!" } },
}

Dialogue.MAXED = { "{name} is already as\nhappy as can be!", "{name} couldn't possibly\nbe any fonder of you!" }

-- Turned down by the limiter.
Dialogue.REFUSAL = {
  cooldown = { "{name} isn't in the\nmood right now.", "{name} looks away.\nGive it a moment." },
  tired = { "{name} has had plenty of\nattention for now.", "{name} seems worn out\nfrom all the fuss." },
}

-- Cut off for spamming.
Dialogue.LOCKED_NOW = { "{name} is fed up!\nIt turns its back on you." }
Dialogue.LOCKED = { "{name} wants some space.\nTry again later.", "{name} ignores you.\nIt needs some time alone." }

local function pick(list, rng)
  rng = rng or math.random
  return list[math.floor(rng() * #list) + 1] or list[1]
end

local function fill(text, name)
  -- plain-text replace (a nickname may contain pattern characters)
  return (text:gsub("{name}", function() return name end))
end

--- The line describing the Pokemon's state (`reason` from MonMood.read).
function Dialogue.report(reason, name, rng)
  local list = Dialogue.REPORT[reason] or Dialogue.REPORT.normal
  return fill(pick(list, rng), name)
end

--- The line after a successful Pet/Play/Talk. `hurting` picks the softer
--- text for a Pokemon whose state-derived face is a pained one.
function Dialogue.action(action, name, hurting, rng)
  local list = (hurting and Dialogue.ACTION_HURTING[action]) or Dialogue.ACTION[action] or Dialogue.ACTION.pet
  return fill(pick(list, rng), name)
end

--- Why it will not play (reason from MonMood.playBlocker).
function Dialogue.cantPlay(reason, name, rng)
  local list = Dialogue.CANT_PLAY[reason] or Dialogue.CANT_PLAY.low
  return fill(pick(list, rng), name)
end

function Dialogue.healed(name, rng)
  return fill(pick(Dialogue.HEALED, rng), name)
end

--- How it feels about you: the line and the portrait emotion matching
--- `friendship` (0..255) as a percentage of the maximum.
function Dialogue.talk(friendship, name, rng)
  local percent = math.max(0, math.min(100, (tonumber(friendship) or 0) * 100 / Dialogue.FRIENDSHIP_MAX))
  local tier = Dialogue.TALK_TIERS[1]
  for _, t in ipairs(Dialogue.TALK_TIERS) do
    if percent >= t[1] then tier = t end
  end
  return fill(pick(tier[4], rng), name), tier[3], tier[2]
end

function Dialogue.maxed(name, rng)
  return fill(pick(Dialogue.MAXED, rng), name)
end

--- Why the limiter said no. kind = "cooldown" | "tired" | "locked_now" | "locked".
function Dialogue.refusal(kind, name, rng)
  local list
  if kind == "locked_now" then list = Dialogue.LOCKED_NOW
  elseif kind == "locked" then list = Dialogue.LOCKED
  else list = Dialogue.REFUSAL[kind] or Dialogue.REFUSAL.cooldown end
  return fill(pick(list, rng), name)
end

return Dialogue
