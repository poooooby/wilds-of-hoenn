-- Mod Manager option schema for wilds_of_hoenn.
-- Labels are limited to 14 characters (tools/validate_option_labels.py).
--
-- Wandering is Idle or Roam; Wild Reacts adds fleeing / chasing when the player runs or
-- bikes close by (lib/wild_reactions.lua). Local Scenes are place-specific ambient moments
-- (lib/local_scenes.lua). Not offered: Sprite Fade, Control Mode /
-- Trainer Trail, Water Mons presentation modes, a Hidden behaviour.

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
      { "HGSS / PokeMMO", "pokemmo" },
      { "PMDCollab", "pmd" },
    },
    description = "Overworld sprite style for wild Pokemon and your follower. HGSS / PokeMMO draws each species at its own native size (\"True Size\"), anchored at its feet -- a Snorlax is drawn much bigger than a Rattata. PMDCollab uses the PMD Explorers-style sprites with fully animated walking and idle loops (species without PMD art fall back to HGSS / PokeMMO).",
  },
  {
    key = "smooth_follow",
    label = "Smooth Follow",
    type = "toggle",
    default = true,
    description = "Your partner is always spaced out behind you by its size. On: it glides round when you turn. Off: it snaps straight to its place behind you, step for step like the original games.",
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
