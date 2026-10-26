-- Mod Manager option schema for wilds_of_hoenn.
-- Labels are limited to 14 characters (tools/validate_option_labels.py).
--
-- Wandering is Idle or Roam; Wild Reacts adds fleeing / chasing when the player runs or
-- bikes close by (lib/wild_reactions.lua). Local Scenes are place-specific ambient moments
-- (lib/local_scenes.lua). Not offered: Sprite Fade, Control Mode /
-- Trainer Trail, Water Mons presentation modes, a Hidden behaviour.

return {
  {
    key = "language",
    label = "Language",
    type = "choice",
    default = "en",
    -- each language's own name (lib/i18n.lua NAMES); never translated
    choices = {
      { "ENGLISH", "en" },
      { "にほんご", "ja" },
      { "PORTUGUÊS", "pt" },
      { "ESPAÑOL", "es" },
      { "DEUTSCH", "de" },
    },
    description = "The language of Wilds of Hoenn's own text: these options, your partner's words, its menus and the labels over it. The game's own text is not changed. Japanese is written in kana, like the original Japanese games.",
  },
  {
    key = "enabled",
    label = "Show Wild Mons",
    type = "toggle",
    default = true,
    description = "Spawn visible wild Pokemon in eligible grass/water encounter areas.",
  },
  {
    key = "spawn_amount",
    label = "Spawn Amount",
    type = "choice",
    default = "normal",
    choices = {
      { "LOW", "low" },
      { "NORMAL", "normal" },
      { "HIGH", "high" },
    },
    description = "How many wild Pokemon are out at once, for grass and water each, growing with the size of the area. Low: about half (up to 4). Normal: up to 8. High: about one and a half times (up to 12).",
  },
  {
    key = "flyers",
    label = "Flying Mons",
    type = "choice",
    default = "full",
    choices = {
      { "FULL", "full" },
      { "AMBIENT", "ambient" },
      { "OFF", "off" },
    },
    description = "Flying Pokemon in the sky: birds of the area pass overhead, perch on trees, roofs and signposts, and real sea birds dive for food; wild Flying-type Pokemon swoop down to land (and take off again) instead of rising out of the grass. Full: all of it, with big soft-focus birds flying high overhead. Ambient: the same without the high birds. Off: none of it, wild Pokemon all arrive the usual way.",
  },
  {
    key = "water_life",
    label = "Water Life",
    type = "toggle",
    default = true,
    description = "Life in the water, just for the scenery: small fish of the area (Magikarp, Goldeen, Luvdisc ...) leap out of the water and splash back in, and Wailmer and Wailord surface for a while, blowing a spray, before sinking back under. Out at sea, Finizen porpoise by now and then (once in a while a whole pod comes up to play). Diving, fish swim by under the sea as dark shadows trailing bubbles. Never battled.",
  },
  {
    key = "local_scenes",
    label = "Local Scenes",
    type = "toggle",
    default = true,
    description = "Little moments in a few special places: ghosts drift through Lavender Town, bug Pokemon dangle from the trees of Petalburg Woods where Slakoth naps and Vigoroth dances on the treetops, and a great Tropius rises out of Fortree's trees. Just for the scenery.",
  },
  {
    key = "wild_reacts",
    label = "Wild Reacts",
    type = "toggle",
    default = true,
    description = "Run or bike close to wild Pokemon and they react: weaker ones than your lead Pokemon are startled and run off (small birds fly away), stronger ones get angry and chase you (catching you starts the battle). Walking past disturbs nobody. Off: they just wander.",
  },
  {
    key = "sprite_style",
    label = "Sprite Style",
    type = "choice",
    default = "pmd",
    choices = {
      { "HGSS", "pokemmo" },
      { "PMD", "pmd" },
    },
    description = "Overworld sprite style for wild Pokemon and your follower. HGSS / PokeMMO draws each species at its own native size (\"True Size\"), anchored at its feet -- a Snorlax is drawn much bigger than a Rattata. PMDCollab uses the PMD Explorers-style sprites with fully animated walking and idle loops (species without PMD art fall back to HGSS / PokeMMO).",
  },
  {
    key = "show_follower",
    label = "Follower",
    type = "toggle",
    default = true,
    description = "Your partner Pokemon walks behind you. Off: it stays in its Poke Ball (its Battle and Forage jobs and Pet / Play / Talk wait until it is out again). Changing your party order still changes who your partner is.",
  },
  {
    key = "role_pad",
    label = "Battler: Pad",
    type = "choice",
    default = "off",
    choices = {
      { "R", "r" },
      { "L", "l" },
      { "OFF", "off" },
    },
    description = "A controller shoulder button that switches your partner between Battle and Follow while you walk around -- you call it out like a trainer in battle ('Go! Mudkip!', 'Come back, Mudkip!'). In FireRed / LeafGreen that button then no longer opens Help in the overworld; the other shoulder still does.",
  },
  {
    key = "role_key",
    label = "Battler: Key",
    type = "choice",
    default = "off",
    choices = {
      { "E (R)", "e" },
      { "Q (L)", "q" },
      { "R", "r" },
      { "OFF", "off" },
    },
    description = "The keyboard key that switches your partner between Battle and Follow while you walk around. E and Q are the game's R and L buttons (in FireRed / LeafGreen that one then no longer opens Help in the overworld); R is a free key.",
  },
  {
    key = "smooth_follow",
    label = "Smooth Follow",
    type = "toggle",
    default = true,
    description = "Your partner is always spaced out behind you by its size. On: it glides round when you turn. Off: it snaps straight to its place behind you, step for step like the original games.",
  },
  {
    key = "type_aura",
    label = "Type Aura",
    type = "toggle",
    default = false,
    description = "Now and then your partner gives off a little puff of its type: embers from a Fire type, droplets from a Water type, leaves, sparks, snow, wisps ... Off: only while you Pet, Play or Talk with it.",
  },
  {
    key = "classic_enc",
    label = "Classic Enc",
    type = "toggle",
    default = true,
    description = "Classic Encounters: the original step-based random encounters in grass and water (Surf). Visible wild Pokemon stay active either way. Fishing and Rock Smash are unaffected.",
  },
  {
    key = "wild_silhouettes",
    label = "Silhouette",
    type = "choice",
    default = "off",
    choices = {
      { "OFF", "off" },
      { "UNDISCOVERED", "undiscovered" },
      { "ALL", "all" },
    },
    description = "Off keeps normal colours. Undiscovered silhouettes species not yet caught in your Pokedex. All silhouettes every visible wild Pokemon.",
  },
  {
    key = "species_sizes",
    label = "Species Sizes",
    type = "toggle",
    default = true,
    description = "Draw each species at its own size next to you, in either sprite style: small ones knee-high, giants towering over you. Needs the Gen 3 HD Sprites mod (with its Field HD option on); without it every species is drawn at its sheet's size.",
  },
  {
    key = "portraits",
    label = "Portraits",
    type = "toggle",
    default = true,
    description = "Your partner's PMDCollab portrait above its messages when you Pet, Play or Talk with it. Off: the messages show without it.",
  },
}
