-- Mod Manager option schema for wilds_of_hoenn.
-- Labels are limited to 14 characters (tools/validate_option_labels.py).
--
-- v1 is deliberately small -- see docs/ARCHITECTURE.md "What v1
-- deliberately leaves out" for the Wilds-of-Kanto-style options this does
-- not (yet) have: Spawn Amount, Sprite Fade, Control Mode/Trainer Trail,
-- Water Mons presentation modes, Idle/Roam/Chase/Hidden toggles. Idle and
-- Roam are the only behaviours; there is no Chase or Hidden in v1.

return {
  {
    key = "enabled",
    label = "Show Wild Mons",
    type = "toggle",
    default = true,
    description = "Spawn visible wild Pokemon in eligible grass/water encounter areas.",
  },
  {
    key = "sprite_style",
    label = "Sprite Style",
    type = "choice",
    default = "followers",
    choices = {
      { "Poke Followers / GSC", "followers" },
      { "HGSS / PokeMMO", "pokemmo" },
    },
    description = "Overworld sprite style for wild Pokemon and your follower. Poke Followers / GSC draws every species at a plain 16x16. HGSS / PokeMMO draws each species at its own native size (\"True Size\"), anchored at its feet -- a Snorlax is drawn much bigger than a Rattata.",
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
      { "Off", "off" },
      { "Undiscovered", "undiscovered" },
      { "All", "all" },
    },
    description = "Off keeps normal colours. Undiscovered silhouettes species not yet caught in your Pokedex. All silhouettes every visible wild Pokemon.",
  },
  {
    key = "shiny_rate",
    label = "Shiny Rate",
    type = "choice",
    default = "vanilla",
    choices = {
      { "Vanilla", "vanilla" },
      { "Boosted", "boosted" },
      { "Off", "off" },
    },
    description = "Vanilla keeps the real 1/8192 shiny chance against your trainer id. Boosted re-rolls a non-shiny encounter until it is shiny, keeping the same nature and gender. Off never shows a shiny.",
  },
  {
    key = "follower",
    label = "Follower",
    type = "toggle",
    default = true,
    description = "Your lead party Pokemon follows you in the overworld.",
  },
}
