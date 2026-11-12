-- Hand-written ecology for the species that matter (lib/eco_profile.lua lays each entry over
-- the profile it derives from the game's own data, so an entry only lists what it changes).
-- Keyed by NATIONAL dex number. Hoenn first (the Hoenn Pokedex, the species found there);
-- species not listed keep their derived profile. Field meanings: lib/eco_profile.lua.
--
-- Hand-edited: tune freely; tests/eco_profile_unit_test.lua checks every entry is well formed.
local PACK, HERD, SCHOOL, SWARM, POD, HUDDLE = "pack", "herd", "school", "swarm", "pod", "huddle"

return {
  -- ------- Hoenn starters
  [252] = { temper = "calm" }, [253] = { temper = "calm" }, [254] = { temper = "territorial" },
  [255] = { temper = "calm" }, [256] = { temper = "calm" }, [257] = { temper = "territorial" },
  [258] = { temper = "calm" }, [259] = { temper = "calm" }, [260] = { temper = "territorial" },

  -- ------- Route 101-104 regulars
  [261] = { social = PACK, group = { 2, 3 }, diet = "predator", temper = "territorial", prey = { "NORMAL", "BUG" } }, -- Poochyena
  [262] = { social = PACK, group = { 2, 3 }, diet = "predator", temper = "aggressive", prey = { "NORMAL", "BUG", "GRASS" } }, -- Mightyena
  [263] = { diet = "prey", temper = "skittish" },                                         -- Zigzagoon
  [264] = { diet = "prey", temper = "skittish" },                                         -- Linoone
  [265] = { social = HUDDLE, group = { 2, 3 }, diet = "prey", temper = "skittish" },      -- Wurmple
  [266] = { diet = "prey", temper = "calm" }, [268] = { diet = "prey", temper = "calm" }, -- Silcoon, Cascoon
  [267] = { temper = "calm" }, [269] = { temper = "calm", activity = "night" },           -- Beautifly, Dustox
  [270] = { social = HUDDLE, group = { 2, 3 }, diet = "prey", temper = "calm", water = "drifter" }, -- Lotad
  [271] = { temper = "calm", water = "drifter" }, [272] = { temper = "calm", water = "swimmer" },
  [273] = { social = HUDDLE, group = { 2, 3 }, diet = "prey", temper = "skittish" },      -- Seedot
  [274] = { temper = "territorial" }, [275] = { temper = "territorial", activity = "night" },
  [276] = { social = SWARM, group = { 2, 3 }, diet = "predator", temper = "skittish", prey = { "BUG" } }, -- Taillow
  [277] = { diet = "predator", temper = "territorial", prey = { "BUG", "GRASS" } },       -- Swellow
  [278] = { social = SWARM, group = { 2, 3 }, diet = "predator", temper = "skittish", prey = { "WATER" } }, -- Wingull
  [279] = { temper = "calm" },                                                             -- Pelipper
  [280] = { temper = "skittish" }, [281] = { temper = "skittish" }, [282] = { temper = "calm" },
  [283] = { social = SWARM, group = { 2, 3 }, diet = "prey", temper = "skittish", water = "drifter" }, -- Surskit
  [284] = { temper = "calm" },
  [285] = { social = HUDDLE, group = { 2, 3 }, diet = "prey", temper = "calm" },          -- Shroomish
  [286] = { diet = "predator", temper = "territorial", prey = { "BUG", "GRASS", "NORMAL" } }, -- Breloom
  [287] = { temper = "calm" }, [288] = { temper = "territorial" }, [289] = { temper = "calm" }, -- Slakoth line
  [290] = { social = HUDDLE, group = { 2, 3 }, diet = "prey", temper = "skittish" },      -- Nincada
  [291] = { temper = "skittish" }, [292] = { temper = "calm", activity = "night" },
  [293] = { temper = "skittish" }, [294] = { temper = "territorial" }, [295] = { temper = "territorial" },
  [296] = { temper = "territorial" }, [297] = { temper = "territorial" },                 -- Makuhita, Hariyama
  [298] = { social = HUDDLE, group = { 2, 3 }, diet = "prey", temper = "calm" },          -- Azurill
  [299] = { temper = "calm" },                                                             -- Nosepass
  [300] = { diet = "prey", temper = "skittish" }, [301] = { temper = "calm" },            -- Skitty, Delcatty
  [302] = { temper = "territorial", activity = "night" },                                  -- Sableye
  [303] = { temper = "territorial" },                                                      -- Mawile
  [304] = { social = HUDDLE, group = { 2, 3 }, temper = "calm" },                         -- Aron
  [305] = { temper = "territorial" }, [306] = { temper = "aggressive" },
  [307] = { temper = "calm" }, [308] = { temper = "calm" },                               -- Meditite, Medicham
  [309] = { social = PACK, group = { 2, 3 }, diet = "predator", temper = "territorial", prey = { "NORMAL", "BUG" } }, -- Electrike
  [310] = { social = PACK, group = { 2, 3 }, diet = "predator", temper = "aggressive" },  -- Manectric
  [311] = { social = HUDDLE, group = { 2, 2 }, temper = "skittish" },                     -- Plusle
  [312] = { social = HUDDLE, group = { 2, 2 }, temper = "skittish" },                     -- Minun
  [313] = { social = SWARM, group = { 2, 3 }, temper = "calm", activity = "night" },      -- Volbeat
  [314] = { social = SWARM, group = { 2, 3 }, temper = "calm", activity = "night" },      -- Illumise
  [315] = { temper = "calm" },                                                             -- Roselia
  [316] = { temper = "calm" }, [317] = { temper = "calm" },                               -- Gulpin, Swalot
  [318] = { social = SCHOOL, group = { 2, 4 }, diet = "predator", temper = "aggressive", water = "diver" }, -- Carvanha
  [319] = { diet = "predator", temper = "aggressive", water = "diver", prey = { "WATER" } }, -- Sharpedo
  [320] = { social = POD, group = { 2, 3 }, diet = "neutral", temper = "calm", water = "whale" }, -- Wailmer
  [321] = { diet = "neutral", temper = "calm", water = "whale" },                         -- Wailord
  [322] = { social = HERD, group = { 2, 4 }, temper = "calm" },                           -- Numel
  [323] = { temper = "territorial" },                                                      -- Camerupt
  [324] = { temper = "calm" },                                                             -- Torkoal
  [325] = { social = HERD, group = { 2, 3 }, diet = "prey", temper = "skittish" },        -- Spoink
  [326] = { temper = "calm" },
  [327] = { temper = "calm" },                                                             -- Spinda
  [328] = { diet = "predator", temper = "territorial", prey = { "BUG", "NORMAL", "GROUND" } }, -- Trapinch
  [329] = { temper = "territorial" }, [330] = { temper = "territorial" },
  [331] = { temper = "calm" },                                                             -- Cacnea
  [332] = { diet = "predator", temper = "territorial", activity = "night" },              -- Cacturne
  [333] = { social = SWARM, group = { 2, 3 }, temper = "calm" },                          -- Swablu
  [334] = { temper = "calm" },                                                             -- Altaria
  [335] = { diet = "predator", temper = "territorial", rival = { [336] = true } },         -- Zangoose
  [336] = { diet = "predator", temper = "territorial", rival = { [335] = true } },         -- Seviper
  [337] = { temper = "calm", activity = "night" }, [338] = { temper = "calm", activity = "day" }, -- Lunatone, Solrock
  [339] = { social = SCHOOL, group = { 2, 3 }, temper = "skittish", water = "diver" },    -- Barboach
  [340] = { temper = "territorial", water = "diver" },                                     -- Whiscash
  [341] = { diet = "predator", temper = "territorial", prey = { "WATER" } },               -- Corphish
  [342] = { diet = "predator", temper = "aggressive", prey = { "WATER" } },                -- Crawdaunt
  [343] = { social = HUDDLE, group = { 2, 3 }, temper = "calm" },                         -- Baltoy
  [344] = { temper = "calm" },
  [345] = { temper = "calm" }, [346] = { temper = "calm" }, [347] = { temper = "territorial" }, [348] = { temper = "territorial" },
  [349] = { social = SCHOOL, group = { 2, 3 }, diet = "prey", temper = "skittish", water = "leaper" }, -- Feebas
  [350] = { temper = "calm", water = "swimmer" },                                          -- Milotic
  [351] = { temper = "calm" }, [352] = { temper = "skittish" },                           -- Castform, Kecleon
  [353] = { social = SWARM, group = { 2, 3 }, temper = "calm", activity = "night" },      -- Shuppet
  [354] = { temper = "territorial", activity = "night" },                                  -- Banette
  [355] = { temper = "calm", activity = "night" }, [356] = { temper = "territorial", activity = "night" },
  [357] = { temper = "calm" }, [358] = { temper = "calm" },                               -- Tropius, Chimecho
  [359] = { temper = "territorial" },                                                      -- Absol
  [360] = { social = HUDDLE, group = { 2, 3 }, temper = "calm" },                         -- Wynaut
  [361] = { social = HUDDLE, group = { 2, 3 }, temper = "skittish" },                     -- Snorunt
  [362] = { temper = "territorial" },                                                      -- Glalie
  [363] = { social = HUDDLE, group = { 2, 3 }, diet = "prey", temper = "calm" },          -- Spheal
  [364] = { temper = "calm" }, [365] = { temper = "territorial" },
  [366] = { temper = "calm", water = "drifter" },                                          -- Clamperl
  [367] = { diet = "predator", temper = "aggressive", water = "diver", prey = { "WATER" } }, -- Huntail
  [368] = { temper = "calm", water = "diver" },                                            -- Gorebyss
  [369] = { temper = "calm", water = "diver" },                                            -- Relicanth
  [370] = { social = SCHOOL, group = { 2, 4 }, diet = "prey", temper = "skittish", water = "leaper" }, -- Luvdisc
  [371] = { temper = "territorial" }, [372] = { temper = "calm" }, [373] = { temper = "aggressive" }, -- Bagon line
  [374] = { social = HUDDLE, group = { 2, 3 }, temper = "calm" },                         -- Beldum
  [375] = { temper = "calm" }, [376] = { temper = "territorial" },

  -- ------- older species found in Hoenn
  [25]  = { social = HUDDLE, group = { 2, 2 }, diet = "prey", temper = "skittish" },      -- Pikachu
  [41]  = { social = SWARM, group = { 2, 4 }, diet = "predator", temper = "territorial", activity = "night", prey = { "BUG" } }, -- Zubat
  [42]  = { social = SWARM, group = { 2, 3 }, diet = "predator", temper = "aggressive", activity = "night" }, -- Golbat
  [43]  = { social = HUDDLE, group = { 2, 3 }, diet = "prey", temper = "calm", activity = "night" }, -- Oddish
  [72]  = { social = SCHOOL, group = { 2, 3 }, temper = "calm", water = "drifter" },      -- Tentacool
  [73]  = { temper = "territorial", water = "drifter" },                                   -- Tentacruel
  [74]  = { social = HUDDLE, group = { 2, 3 }, temper = "calm" },                         -- Geodude
  [81]  = { social = SWARM, group = { 2, 3 }, temper = "calm" },                          -- Magnemite
  [84]  = { social = HERD, group = { 2, 3 }, diet = "prey", temper = "skittish" },        -- Doduo
  [85]  = { temper = "territorial" },                                                      -- Dodrio
  [111] = { social = HERD, group = { 2, 3 }, temper = "territorial" },                    -- Rhyhorn
  [116] = { social = SCHOOL, group = { 2, 3 }, diet = "prey", temper = "skittish", water = "swimmer" }, -- Horsea
  [118] = { social = SCHOOL, group = { 2, 3 }, diet = "prey", temper = "skittish", water = "leaper" }, -- Goldeen
  [119] = { temper = "territorial", water = "leaper" },                                    -- Seaking
  [120] = { temper = "calm", water = "drifter" }, [121] = { temper = "calm", water = "drifter" }, -- Staryu, Starmie
  [127] = { temper = "aggressive", rival = { [214] = true } },                             -- Pinsir
  [129] = { social = SCHOOL, group = { 2, 4 }, diet = "prey", temper = "skittish", water = "leaper" }, -- Magikarp
  [130] = { diet = "predator", temper = "aggressive", water = "diver", prey = { "WATER" } }, -- Gyarados
  [170] = { social = SCHOOL, group = { 2, 3 }, temper = "calm", water = "drifter", activity = "night" }, -- Chinchou
  [171] = { temper = "calm", water = "drifter", activity = "night" },                     -- Lanturn
  [183] = { social = HUDDLE, group = { 2, 3 }, temper = "calm" },                         -- Marill
  [214] = { temper = "territorial", rival = { [127] = true } },                            -- Heracross
  [222] = { social = HUDDLE, group = { 2, 3 }, temper = "calm", water = "drifter" },      -- Corsola
  [223] = { social = SCHOOL, group = { 2, 4 }, diet = "prey", temper = "skittish", water = "diver" }, -- Remoraid
  [224] = { temper = "territorial", water = "diver" },                                     -- Octillery
  [226] = { social = POD, group = { 2, 2 }, temper = "calm", water = "leaper" },          -- Mantine
  [227] = { diet = "predator", temper = "territorial" },                                   -- Skarmory

  -- ------- National Dex Gen 3 extras with a set character
  [963] = { social = POD, group = { 2, 4 }, temper = "calm", water = "leaper" },          -- Finizen
  [964] = { social = POD, group = { 2, 3 }, temper = "territorial", water = "leaper" },   -- Palafin
}
