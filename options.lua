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
    default = "pmd",
    choices = {
      { "HGSS / PokeMMO", "pokemmo" },
      { "PMDCollab", "pmd" },
    },
    description = "Overworld sprite style for wild Pokemon and your follower. HGSS / PokeMMO draws each species at its own native size (\"True Size\"), anchored at its feet -- a Snorlax is drawn much bigger than a Rattata. PMDCollab uses the PMD Explorers-style sprites with fully animated walking and idle loops (species without PMD art fall back to HGSS / PokeMMO).",
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
    default = "native",
    choices = {
      { "Native", "native" },
      { "1/4096", "r4096" },
      { "1/2048", "r2048" },
      { "1/1024", "r1024" },
      { "1/500", "r500" },
      { "1/100", "r100" },
      { "1/10", "r10" },
      { "All", "all" },
    },
    description = "Native keeps the real shiny chance the engine already rolled against your trainer id (no reroll). Each rate re-rolls a non-shiny encounter at that chance until it is shiny, keeping the same nature and gender. All always shows a shiny.",
  },
  {
    key = "species_sizes",
    label = "Species Sizes",
    type = "toggle",
    default = true,
    description = "Draw each HGSS / PokeMMO species at its own relative size, the same table Wilds of Kanto Revival uses (a Charizard bigger than a Charmander, a Rattata small). Needs the Gen 3 HD Sprites mod (with its Field HD option on); without it every species is drawn at its sheet's size. PMDCollab sprites keep their own sizes.",
  },
  {
    key = "overworld_size",
    label = "Overworld Size",
    type = "choice",
    default = "100",
    choices = {
      { "100%", "100" },
      { "90%", "90" },
      { "80%", "80" },
      { "75%", "75" },
      { "67%", "67" },
      { "50%", "50" },
    },
    description = "Size of wild Pokemon and your follower in the overworld, on top of Species Sizes. Needs the Gen 3 HD Sprites mod (with its Field HD option on), which draws them at your screen's full resolution so any size keeps every pixel of the art; without it they are always drawn at 100%.",
  },
}
