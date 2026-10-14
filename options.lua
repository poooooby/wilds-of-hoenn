-- Mod Manager option schema for wilds_of_hoenn.
-- Labels are limited to 14 characters (tools/validate_option_labels.py).
--
-- v1 is deliberately small -- see docs/ARCHITECTURE.md "What v1
-- deliberately leaves out" for the Wilds-of-Kanto-style options this does
-- not (yet) have: Sprite Fade, Control Mode/Trainer Trail,
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
    key = "spawn_amount",
    label = "Spawn Amount",
    type = "choice",
    default = "normal",
    choices = {
      { "Low", "low" },
      { "Normal", "normal" },
      { "High", "high" },
    },
    description = "How many wild Pokemon are out at once, for grass and water each, growing with the size of the area. Low: about half (up to 4). Normal: up to 8. High: about one and a half times (up to 12).",
  },
  {
    key = "flyers",
    label = "Flying Mons",
    type = "toggle",
    default = true,
    description = "Flying Pokemon in the sky: birds of the area pass overhead, perch on trees, roofs and signposts, and sea birds dive for food. Wild Flying-type Pokemon swoop down to land (and take off again) instead of rising out of the grass. Off: none of it, wild Pokemon all arrive the usual way.",
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
    key = "species_sizes",
    label = "Species Sizes",
    type = "toggle",
    default = true,
    description = "Draw each HGSS / PokeMMO species at its own relative size, the same table Wilds of Kanto Revival uses (a Charizard bigger than a Charmander, a Rattata small). Needs the Gen 3 HD Sprites mod (with its Field HD option on); without it every species is drawn at its sheet's size. PMDCollab sprites keep their own sizes.",
  },
}
