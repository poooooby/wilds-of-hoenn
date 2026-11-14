-- Hand-written ecology for the species that matter (lib/eco_profile.lua lays each entry over
-- the profile it derives from the game's own data, so an entry only lists what it changes).
-- Keyed by NATIONAL dex number. Hoenn first (the Hoenn Pokedex, the species found there), then
-- Kanto and Johto, then every later generation (National Dex Gen 3 brings them all to the field):
-- every species 1-1025 but the legendaries, mythicals, Ultra Beasts and Paradox Pokemon, which
-- keep their derived profile (alone, unbothered). Field meanings: lib/eco_profile.lua.
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
  [287] = { temper = "placid" }, [288] = { temper = "territorial" }, [289] = { temper = "placid" }, -- Slakoth line
  [290] = { social = HUDDLE, group = { 2, 3 }, diet = "prey", temper = "skittish", burrower = true }, -- Nincada
  [291] = { temper = "skittish" }, [292] = { temper = "calm", activity = "night" },
  [293] = { temper = "skittish" }, [294] = { temper = "territorial" }, [295] = { temper = "territorial" },
  [296] = { temper = "territorial" }, [297] = { temper = "territorial" },                 -- Makuhita, Hariyama
  [298] = { social = HUDDLE, group = { 2, 3 }, diet = "prey", temper = "calm" },          -- Azurill
  [299] = { temper = "calm" },                                                             -- Nosepass
  [300] = { diet = "prey", temper = "skittish" }, [301] = { temper = "calm" },            -- Skitty, Delcatty
  [302] = { temper = "territorial", activity = "night", rival = { [303] = true } },         -- Sableye (vs Mawile: Granite Cave)
  [303] = { temper = "territorial", rival = { [302] = true } },                            -- Mawile
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
  [319] = { diet = "predator", temper = "aggressive", water = "diver", prey = { "WATER" },
            rival = { [320] = true, [321] = true } },                                    -- Sharpedo (vs the whales)
  [320] = { social = POD, group = { 2, 3 }, diet = "neutral", temper = "placid", water = "whale",
            rival = { [319] = true } },                                                  -- Wailmer
  [321] = { diet = "neutral", temper = "placid", water = "whale", rival = { [319] = true } }, -- Wailord
  [322] = { social = HERD, group = { 2, 4 }, temper = "calm" },                           -- Numel
  [323] = { temper = "territorial" },                                                      -- Camerupt
  [324] = { temper = "calm" },                                                             -- Torkoal
  [325] = { social = HERD, group = { 2, 3 }, diet = "prey", temper = "skittish" },        -- Spoink
  [326] = { temper = "calm" },
  [327] = { temper = "calm" },                                                             -- Spinda
  [328] = { diet = "predator", temper = "territorial", prey = { "BUG", "NORMAL", "GROUND" }, burrower = true }, -- Trapinch
  [329] = { temper = "territorial" }, [330] = { temper = "territorial" },
  [331] = { temper = "calm" },                                                             -- Cacnea
  [332] = { diet = "predator", temper = "territorial", activity = "night" },              -- Cacturne
  [333] = { social = SWARM, group = { 2, 3 }, temper = "calm" },                          -- Swablu
  [334] = { temper = "calm" },                                                             -- Altaria
  [335] = { diet = "predator", temper = "territorial", rival = { [336] = true } },         -- Zangoose
  [336] = { diet = "predator", temper = "territorial", rival = { [335] = true } },         -- Seviper
  [337] = { temper = "calm", activity = "night", rival = { [338] = true } },               -- Lunatone (vs Solrock: moon and sun)
  [338] = { temper = "calm", activity = "day", rival = { [337] = true } },                 -- Solrock
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
  [357] = { temper = "placid" }, [358] = { temper = "calm" },                               -- Tropius, Chimecho
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
  [127] = { temper = "aggressive", rival = { [214] = true, [123] = true } },              -- Pinsir (vs Heracross, Scyther)
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

  -- ------- Kanto (FireRed / LeafGreen): the species not already listed above
  [1]   = { temper = "calm" }, [2] = { temper = "calm" }, [3] = { temper = "territorial" },
  [4]   = { temper = "calm" }, [5] = { temper = "territorial" }, [6] = { temper = "aggressive" },
  [7]   = { temper = "calm" }, [8] = { temper = "calm" }, [9] = { temper = "territorial" },
  [10]  = { social = HUDDLE, group = { 2, 3 }, diet = "prey", temper = "skittish" },      -- Caterpie
  [11]  = { diet = "prey", temper = "calm" },                                              -- Metapod
  [12]  = { social = SWARM, group = { 2, 3 }, temper = "calm" },                          -- Butterfree
  [13]  = { social = HUDDLE, group = { 2, 3 }, diet = "prey", temper = "skittish" },      -- Weedle
  [14]  = { diet = "prey", temper = "calm" },                                              -- Kakuna
  [15]  = { social = SWARM, group = { 2, 3 }, temper = "aggressive" },                    -- Beedrill
  [16]  = { social = SWARM, group = { 2, 3 }, diet = "predator", temper = "skittish", prey = { "BUG" } }, -- Pidgey
  [17]  = { diet = "predator", temper = "territorial", prey = { "BUG", "NORMAL" } },       -- Pidgeotto
  [18]  = { diet = "predator", temper = "territorial" },                                   -- Pidgeot
  [19]  = { social = SWARM, group = { 2, 3 }, diet = "prey", temper = "skittish" },       -- Rattata
  [20]  = { temper = "territorial", activity = "night" },                                  -- Raticate
  [21]  = { social = SWARM, group = { 2, 3 }, diet = "predator", temper = "aggressive", prey = { "BUG" } }, -- Spearow
  [22]  = { diet = "predator", temper = "aggressive" },                                    -- Fearow
  [23]  = { diet = "predator", temper = "territorial", prey = { "NORMAL" } },              -- Ekans
  [24]  = { diet = "predator", temper = "aggressive" },                                    -- Arbok
  [27]  = { diet = "prey", temper = "skittish", burrower = true }, [28] = { temper = "territorial", burrower = true }, -- Sandshrew, Sandslash
  [29]  = { social = HUDDLE, group = { 2, 3 }, diet = "prey", temper = "skittish" },      -- Nidoran F
  [32]  = { social = HUDDLE, group = { 2, 3 }, diet = "prey", temper = "skittish" },      -- Nidoran M
  [30]  = { temper = "territorial" }, [33] = { temper = "territorial" },
  [31]  = { temper = "territorial" }, [34] = { temper = "aggressive" },
  [35]  = { social = HUDDLE, group = { 2, 3 }, temper = "skittish", activity = "night" }, -- Clefairy
  [37]  = { diet = "prey", temper = "skittish" }, [38] = { temper = "calm" },             -- Vulpix, Ninetales
  [39]  = { temper = "calm" }, [40] = { temper = "calm" },                                -- Jigglypuff line
  [44]  = { temper = "calm" }, [45] = { temper = "calm" },
  [46]  = { social = HUDDLE, group = { 2, 3 }, diet = "prey", temper = "calm" },          -- Paras
  [47]  = { temper = "calm" },
  [48]  = { social = SWARM, group = { 2, 3 }, temper = "calm", activity = "night" },      -- Venonat
  [49]  = { temper = "calm", activity = "night" },                                         -- Venomoth
  [50]  = { social = HUDDLE, group = { 2, 3 }, temper = "skittish", burrower = true },     -- Diglett
  [51]  = { temper = "territorial", burrower = true },                                     -- Dugtrio
  [52]  = { diet = "predator", temper = "skittish", activity = "night", prey = { "NORMAL", "BUG" } }, -- Meowth
  [53]  = { diet = "predator", temper = "territorial", activity = "night" },              -- Persian
  [54]  = { temper = "calm", water = "swimmer" }, [55] = { temper = "calm", water = "swimmer" }, -- Psyduck, Golduck
  [56]  = { social = PACK, group = { 2, 3 }, temper = "aggressive" },                     -- Mankey
  [57]  = { temper = "aggressive" },                                                       -- Primeape
  [58]  = { social = PACK, group = { 2, 3 }, diet = "predator", temper = "territorial", prey = { "NORMAL" } }, -- Growlithe
  [59]  = { diet = "predator", temper = "territorial" },                                   -- Arcanine
  [60]  = { social = SCHOOL, group = { 2, 3 }, diet = "prey", temper = "skittish", water = "swimmer" }, -- Poliwag
  [61]  = { temper = "calm", water = "swimmer" }, [62] = { temper = "territorial" },
  [63]  = { temper = "skittish" }, [64] = { temper = "skittish" }, [65] = { temper = "calm" }, -- Abra line
  [66]  = { social = PACK, group = { 2, 3 }, temper = "territorial" },                    -- Machop
  [67]  = { temper = "territorial" }, [68] = { temper = "territorial" },
  [69]  = { social = HUDDLE, group = { 2, 3 }, diet = "predator", temper = "calm", prey = { "BUG" } }, -- Bellsprout
  [70]  = { diet = "predator", temper = "calm", prey = { "BUG" } }, [71] = { diet = "predator", temper = "territorial", prey = { "BUG" } },
  [75]  = { temper = "calm" }, [76] = { temper = "territorial" },                         -- Graveler, Golem
  [77]  = { social = HERD, group = { 2, 3 }, temper = "skittish" },                       -- Ponyta
  [78]  = { social = HERD, group = { 2, 3 }, temper = "territorial" },                    -- Rapidash
  [79]  = { temper = "placid", water = "swimmer" }, [80] = { temper = "placid", water = "swimmer" }, -- Slowpoke, Slowbro
  [82]  = { temper = "calm" },                                                             -- Magneton
  [83]  = { temper = "territorial" },                                                      -- Farfetch'd
  [86]  = { social = POD, group = { 2, 3 }, temper = "calm", water = "swimmer" },         -- Seel
  [87]  = { temper = "calm", water = "swimmer" },                                          -- Dewgong
  [88]  = { temper = "calm" }, [89] = { temper = "territorial" },                         -- Grimer, Muk
  [90]  = { social = HUDDLE, group = { 2, 3 }, diet = "prey", temper = "calm", water = "drifter" }, -- Shellder
  [91]  = { temper = "territorial", water = "drifter" },                                   -- Cloyster
  [92]  = { social = SWARM, group = { 2, 3 }, temper = "territorial", activity = "night" }, -- Gastly
  [93]  = { temper = "territorial", activity = "night" }, [94] = { temper = "aggressive", activity = "night" },
  [95]  = { temper = "territorial", burrower = true },                                     -- Onix
  [96]  = { temper = "calm", activity = "night" }, [97] = { temper = "territorial", activity = "night" }, -- Drowzee, Hypno
  [98]  = { social = HUDDLE, group = { 2, 3 }, diet = "predator", temper = "territorial", prey = { "WATER" } }, -- Krabby
  [99]  = { diet = "predator", temper = "aggressive", prey = { "WATER" } },               -- Kingler
  [100] = { temper = "territorial" }, [101] = { temper = "aggressive" },                  -- Voltorb, Electrode
  [102] = { social = HUDDLE, group = { 3, 4 }, diet = "prey", temper = "calm" },          -- Exeggcute
  [103] = { temper = "calm" },
  [104] = { temper = "skittish" }, [105] = { temper = "territorial" },                    -- Cubone, Marowak
  [106] = { temper = "territorial" }, [107] = { temper = "territorial" },
  [108] = { temper = "calm" },                                                             -- Lickitung
  [109] = { social = SWARM, group = { 2, 3 }, temper = "calm" },                          -- Koffing
  [110] = { temper = "calm" }, [112] = { temper = "aggressive" },
  [113] = { temper = "skittish" },                                                         -- Chansey
  [114] = { temper = "calm" },
  [115] = { temper = "aggressive" },                                                       -- Kangaskhan
  [117] = { temper = "territorial", water = "swimmer" },                                   -- Seadra
  [122] = { temper = "calm" },
  [123] = { diet = "predator", temper = "aggressive", prey = { "BUG" }, rival = { [127] = true } }, -- Scyther (vs Pinsir)
  [124] = { temper = "calm" }, [125] = { temper = "territorial" }, [126] = { temper = "territorial" },
  [128] = { social = HERD, group = { 2, 4 }, temper = "aggressive" },                     -- Tauros
  [131] = { social = POD, group = { 2, 2 }, temper = "placid", water = "swimmer" },         -- Lapras
  [132] = { temper = "calm" },                                                             -- Ditto
  [133] = { diet = "prey", temper = "skittish" },                                          -- Eevee
  [138] = { temper = "calm", water = "drifter" }, [140] = { temper = "calm", water = "drifter" }, -- Omanyte, Kabuto
  [143] = { temper = "placid" },                                                             -- Snorlax
  [147] = { temper = "calm", water = "swimmer" }, [148] = { temper = "calm", water = "swimmer" }, -- Dratini, Dragonair

  -- ------- Johto species of the Sevii Islands
  [161] = { social = HUDDLE, group = { 2, 3 }, diet = "prey", temper = "skittish" },     -- Sentret
  [162] = { temper = "skittish" },
  [163] = { diet = "predator", temper = "calm", activity = "night", prey = { "NORMAL", "BUG" } }, -- Hoothoot
  [164] = { diet = "predator", temper = "territorial", activity = "night" },              -- Noctowl
  [165] = { social = SWARM, group = { 2, 3 }, temper = "calm" },                         -- Ledyba
  [167] = { diet = "predator", temper = "territorial", activity = "night", prey = { "BUG" } }, -- Spinarak
  [177] = { temper = "skittish" },                                                        -- Natu
  [179] = { social = HERD, group = { 2, 3 }, temper = "calm" },                          -- Mareep
  [187] = { social = SWARM, group = { 2, 3 }, temper = "skittish" },                     -- Hoppip
  [190] = { temper = "skittish" },                                                        -- Aipom
  [193] = { temper = "skittish" },                                                        -- Yanma
  [194] = { social = HUDDLE, group = { 2, 3 }, temper = "calm", water = "swimmer" },      -- Wooper
  [198] = { social = SWARM, group = { 2, 3 }, diet = "predator", temper = "territorial", activity = "night" }, -- Murkrow
  [200] = { temper = "territorial", activity = "night" },                                 -- Misdreavus
  [204] = { temper = "calm" },                                                            -- Pineco
  [206] = { temper = "skittish" },                                                        -- Dunsparce
  [207] = { diet = "predator", temper = "territorial", prey = { "BUG" } },                -- Gligar
  [209] = { temper = "territorial" },                                                     -- Snubbull
  [211] = { social = SCHOOL, group = { 2, 3 }, temper = "territorial", water = "diver" }, -- Qwilfish
  [213] = { temper = "placid" },                                                            -- Shuckle
  [215] = { diet = "predator", temper = "aggressive", activity = "night" },               -- Sneasel
  [216] = { diet = "prey", temper = "skittish" },                                         -- Teddiursa
  [217] = { temper = "aggressive" },                                                      -- Ursaring
  [218] = { temper = "calm" },                                                            -- Slugma
  [220] = { social = HERD, group = { 2, 3 }, temper = "calm" },                          -- Swinub
  [228] = { social = PACK, group = { 2, 3 }, diet = "predator", temper = "territorial", activity = "night" }, -- Houndour
  [229] = { diet = "predator", temper = "aggressive", activity = "night" },               -- Houndoom
  [231] = { social = HERD, group = { 2, 3 }, temper = "calm" },                          -- Phanpy
  [232] = { temper = "territorial" },                                                     -- Donphan
  [234] = { social = HERD, group = { 2, 3 }, temper = "skittish" },                      -- Stantler
  [241] = { social = HERD, group = { 2, 3 }, temper = "calm" },                          -- Miltank
  [246] = { temper = "calm", burrower = true },                                           -- Larvitar

  -- ------- Gen 1-3: the rest
  [26]  = { diet = "neutral", temper = "calm" },                                           -- Raichu
  [36]  = { temper = "calm", activity = "night" },                                         -- Clefable
  [134] = { temper = "calm", water = "swimmer" },                                          -- Vaporeon
  [135] = { diet = "neutral", temper = "territorial" },                                    -- Jolteon
  [136] = { diet = "neutral", temper = "calm" },                                           -- Flareon
  [137] = { temper = "calm" },                                                             -- Porygon
  [139] = { diet = "predator", temper = "territorial", water = "drifter", prey = { "WATER" } }, -- Omastar
  [141] = { diet = "predator", temper = "territorial", water = "swimmer", prey = { "WATER" } }, -- Kabutops
  [142] = { diet = "predator", temper = "aggressive" },                                    -- Aerodactyl
  [149] = { temper = "calm" },                                                             -- Dragonite
  [152] = { temper = "calm" }, [153] = { temper = "calm" }, [154] = { temper = "territorial" },
  -- (Cyndaquil line: neutral -- the derived Field + Fire rule would make the shy starter a hunter)
  [155] = { diet = "neutral", temper = "calm" }, [156] = { diet = "neutral", temper = "calm" },
  [157] = { diet = "neutral", temper = "territorial" },
  [158] = { temper = "calm" }, [159] = { temper = "calm" }, [160] = { temper = "territorial" },
  [166] = { temper = "calm", activity = "night" },                                         -- Ledian
  [168] = { diet = "predator", temper = "territorial", activity = "night", prey = { "BUG" } }, -- Ariados
  [169] = { diet = "predator", temper = "territorial", activity = "night" },              -- Crobat
  [172] = { social = HUDDLE, group = { 2, 3 }, diet = "prey", temper = "skittish" },      -- Pichu
  [173] = { social = HUDDLE, group = { 2, 3 }, temper = "skittish", activity = "night" }, -- Cleffa
  [174] = { temper = "skittish" }, [175] = { temper = "skittish" }, [176] = { temper = "calm" }, -- Igglybuff, Togepi, Togetic
  [178] = { temper = "placid" },                                                           -- Xatu
  [180] = { diet = "neutral", temper = "calm" },                                           -- Flaaffy
  [181] = { diet = "neutral", temper = "calm" },                                           -- Ampharos
  [182] = { social = HUDDLE, group = { 2, 3 }, temper = "calm" },                         -- Bellossom
  [184] = { temper = "calm", water = "swimmer" },                                          -- Azumarill
  [185] = { temper = "calm" },                                                             -- Sudowoodo
  [186] = { temper = "calm", water = "swimmer" },                                          -- Politoed
  [188] = { social = SWARM, group = { 2, 3 }, temper = "skittish" },                     -- Skiploom
  [189] = { social = SWARM, group = { 2, 3 }, temper = "calm" },                         -- Jumpluff
  [191] = { social = HUDDLE, group = { 2, 3 }, diet = "prey", temper = "skittish" },     -- Sunkern
  [192] = { temper = "calm" },                                                            -- Sunflora
  [195] = { temper = "calm", water = "swimmer" },                                         -- Quagsire
  [196] = { temper = "calm", activity = "day" },                                          -- Espeon
  [197] = { temper = "territorial" },                                                     -- Umbreon
  [199] = { temper = "calm", water = "swimmer" },                                         -- Slowking
  [201] = { social = SWARM, group = { 2, 3 }, temper = "calm" },                         -- Unown
  [202] = { temper = "placid" },                                                            -- Wobbuffet
  [203] = { temper = "territorial" },                                                     -- Girafarig
  [205] = { temper = "territorial" },                                                     -- Forretress
  [208] = { temper = "territorial", burrower = true },                                    -- Steelix
  [210] = { temper = "calm" },                                                            -- Granbull
  [212] = { diet = "predator", temper = "territorial", prey = { "BUG" } },                -- Scizor
  [219] = { temper = "calm" },                                                            -- Magcargo
  [221] = { social = HERD, group = { 2, 3 }, temper = "territorial" },                   -- Piloswine
  [225] = { temper = "calm" },                                                            -- Delibird
  [230] = { temper = "territorial", water = "diver" },                                    -- Kingdra
  [233] = { temper = "calm" },                                                            -- Porygon2
  [235] = { temper = "calm" },                                                            -- Smeargle
  [236] = { temper = "territorial" }, [237] = { temper = "territorial" },                -- Tyrogue, Hitmontop
  [238] = { temper = "skittish" }, [239] = { temper = "calm" }, [240] = { temper = "calm" }, -- Smoochum, Elekid, Magby
  [242] = { temper = "calm" },                                                            -- Blissey
  [247] = { temper = "territorial" },                                                     -- Pupitar
  [248] = { temper = "aggressive" },                                                      -- Tyranitar

  -- ------- Gen 4 (Sinnoh)
  [387] = { temper = "calm" }, [388] = { temper = "calm" }, [389] = { temper = "territorial" }, -- Turtwig line
  [390] = { temper = "calm" }, [391] = { temper = "calm" }, [392] = { temper = "territorial" }, -- Chimchar line
  [393] = { temper = "calm" }, [394] = { temper = "calm" }, [395] = { temper = "territorial" }, -- Piplup line
  [396] = { social = SWARM, group = { 2, 4 }, diet = "predator", temper = "skittish", prey = { "BUG" } }, -- Starly
  [397] = { social = SWARM, group = { 2, 3 }, diet = "predator", temper = "territorial", prey = { "BUG" } }, -- Staravia
  [398] = { diet = "predator", temper = "aggressive" },                                    -- Staraptor
  [399] = { social = HUDDLE, group = { 2, 3 }, diet = "prey", temper = "calm" },          -- Bidoof
  [400] = { temper = "calm", water = "swimmer" },                                          -- Bibarel
  [401] = { social = HUDDLE, group = { 2, 3 }, diet = "prey", temper = "skittish", activity = "night" }, -- Kricketot
  [402] = { temper = "calm", activity = "night" },                                         -- Kricketune
  [403] = { social = PACK, group = { 2, 3 }, diet = "predator", temper = "territorial", prey = { "NORMAL", "BUG" } }, -- Shinx
  [404] = { social = PACK, group = { 2, 3 }, diet = "predator", temper = "territorial", prey = { "NORMAL", "BUG" } }, -- Luxio
  [405] = { diet = "predator", temper = "territorial" },                                   -- Luxray
  [406] = { social = HUDDLE, group = { 2, 3 }, temper = "skittish" },                     -- Budew
  [407] = { temper = "territorial" },                                                      -- Roserade
  [408] = { temper = "territorial" }, [409] = { temper = "aggressive" },                  -- Cranidos, Rampardos
  [410] = { social = HERD, group = { 2, 3 }, temper = "calm" },                           -- Shieldon
  [411] = { social = HERD, group = { 2, 3 }, temper = "calm" },                           -- Bastiodon
  [412] = { social = HUDDLE, group = { 2, 3 }, diet = "prey", temper = "calm" },          -- Burmy
  [413] = { temper = "calm" }, [414] = { temper = "calm", activity = "night" },           -- Wormadam, Mothim
  [415] = { social = SWARM, group = { 2, 4 }, diet = "prey", temper = "calm" },           -- Combee
  [416] = { temper = "territorial" },                                                      -- Vespiquen
  [417] = { social = HUDDLE, group = { 2, 2 }, diet = "prey", temper = "skittish" },      -- Pachirisu
  [418] = { diet = "predator", temper = "calm", water = "swimmer", prey = { "WATER" } },  -- Buizel
  [419] = { diet = "predator", temper = "calm", water = "swimmer", prey = { "WATER" } },  -- Floatzel
  [420] = { social = HUDDLE, group = { 2, 3 }, diet = "prey", temper = "skittish" },      -- Cherubi
  [421] = { temper = "calm" },                                                             -- Cherrim
  [422] = { social = HUDDLE, group = { 2, 3 }, diet = "prey", temper = "calm", water = "drifter" }, -- Shellos
  [423] = { temper = "calm", water = "drifter" },                                          -- Gastrodon
  [424] = { social = PACK, group = { 2, 3 }, temper = "calm" },                           -- Ambipom
  [425] = { temper = "calm" },                                                             -- Drifloon
  [426] = { social = SWARM, group = { 2, 3 }, temper = "calm" },                          -- Drifblim
  [427] = { diet = "prey", temper = "skittish" }, [428] = { temper = "skittish" },        -- Buneary, Lopunny
  [429] = { temper = "territorial" },                                                      -- Mismagius
  [430] = { diet = "predator", temper = "territorial" },                                   -- Honchkrow
  [431] = { diet = "predator", temper = "calm", prey = { "BUG" } },                        -- Glameow
  [432] = { diet = "predator", temper = "territorial" },                                   -- Purugly
  [433] = { temper = "skittish" },                                                         -- Chingling
  [434] = { diet = "predator", temper = "territorial", prey = { "BUG" } },                 -- Stunky
  [435] = { diet = "predator", temper = "territorial" },                                   -- Skuntank
  [436] = { temper = "calm" }, [437] = { temper = "calm" },                               -- Bronzor, Bronzong
  [438] = { temper = "skittish" }, [439] = { temper = "skittish" }, [440] = { temper = "skittish" }, -- Bonsly, Mime Jr., Happiny
  [441] = { social = SWARM, group = { 2, 3 }, temper = "calm" },                          -- Chatot
  [442] = { temper = "territorial" },                                                      -- Spiritomb
  [443] = { diet = "predator", temper = "territorial" },                                   -- Gible
  [444] = { diet = "predator", temper = "territorial" },                                   -- Gabite
  [445] = { diet = "predator", temper = "aggressive" },                                    -- Garchomp
  [446] = { temper = "calm" },                                                             -- Munchlax
  [447] = { temper = "calm" }, [448] = { temper = "territorial" },                        -- Riolu, Lucario
  [449] = { social = HERD, group = { 2, 3 }, temper = "calm" },                           -- Hippopotas
  [450] = { temper = "territorial" },                                                      -- Hippowdon
  [451] = { diet = "predator", temper = "territorial", burrower = true },                  -- Skorupi
  [452] = { diet = "predator", temper = "aggressive" },                                    -- Drapion
  [453] = { temper = "territorial" }, [454] = { temper = "territorial" },                 -- Croagunk, Toxicroak
  [455] = { diet = "predator", temper = "calm", prey = { "BUG" } },                        -- Carnivine
  [456] = { social = SCHOOL, group = { 2, 4 }, diet = "prey", temper = "skittish", water = "leaper" }, -- Finneon
  [457] = { temper = "calm", water = "diver" },                                            -- Lumineon
  [458] = { social = POD, group = { 2, 3 }, temper = "skittish", water = "leaper" },      -- Mantyke
  [459] = { temper = "calm" }, [460] = { temper = "calm" },                               -- Snover, Abomasnow
  [461] = { social = PACK, group = { 2, 4 }, diet = "predator", temper = "aggressive" },  -- Weavile
  [462] = { temper = "calm" }, [463] = { temper = "calm" },                               -- Magnezone, Lickilicky
  [464] = { temper = "aggressive" }, [465] = { temper = "calm" },                         -- Rhyperior, Tangrowth
  [466] = { temper = "territorial" }, [467] = { temper = "territorial" },                 -- Electivire, Magmortar
  [468] = { temper = "calm" },                                                             -- Togekiss
  [469] = { diet = "predator", temper = "territorial", prey = { "BUG" } },                 -- Yanmega
  [470] = { temper = "calm" }, [471] = { temper = "calm" },                               -- Leafeon, Glaceon
  [472] = { diet = "predator", temper = "territorial", activity = "night", prey = { "BUG", "NORMAL" } }, -- Gliscor
  [473] = { social = HERD, group = { 2, 3 }, temper = "territorial" },                    -- Mamoswine
  [474] = { temper = "calm" },                                                             -- Porygon-Z
  [475] = { temper = "territorial" }, [476] = { temper = "calm" },                        -- Gallade, Probopass
  [477] = { temper = "territorial" }, [478] = { temper = "territorial" },                 -- Dusknoir, Froslass
  [479] = { temper = "calm" },                                                             -- Rotom

  -- ------- Gen 5 (Unova)
  [495] = { temper = "calm" }, [496] = { temper = "calm" }, [497] = { temper = "territorial" }, -- Snivy line
  [498] = { temper = "calm" }, [499] = { temper = "calm" }, [500] = { temper = "territorial" }, -- Tepig line
  [501] = { temper = "calm" }, [502] = { temper = "calm" }, [503] = { temper = "territorial" }, -- Oshawott line
  [504] = { social = HUDDLE, group = { 2, 3 }, diet = "prey", temper = "skittish" },      -- Patrat
  [505] = { temper = "calm" },                                                             -- Watchog
  [506] = { social = PACK, group = { 2, 3 }, temper = "calm" },                           -- Lillipup
  [507] = { social = PACK, group = { 2, 3 }, temper = "territorial" },                    -- Herdier
  [508] = { temper = "territorial" },                                                      -- Stoutland
  [509] = { diet = "predator", temper = "skittish", prey = { "NORMAL", "BUG" } },         -- Purrloin
  [510] = { diet = "predator", temper = "territorial" },                                   -- Liepard
  [511] = { social = PACK, group = { 2, 3 }, temper = "calm" },                           -- Pansage
  [513] = { social = PACK, group = { 2, 3 }, temper = "calm" },                           -- Pansear
  [515] = { social = PACK, group = { 2, 3 }, temper = "calm" },                           -- Panpour
  [512] = { temper = "territorial" }, [514] = { temper = "territorial" }, [516] = { temper = "territorial" }, -- Simisage, Simisear, Simipour
  [517] = { temper = "skittish", activity = "night" },                                     -- Munna
  [518] = { temper = "calm", activity = "night" },                                         -- Musharna
  [519] = { social = SWARM, group = { 2, 4 }, diet = "prey", temper = "skittish" },       -- Pidove
  [520] = { temper = "calm" }, [521] = { temper = "territorial" },                        -- Tranquill, Unfezant
  [522] = { social = HERD, group = { 2, 3 }, diet = "prey", temper = "skittish" },        -- Blitzle
  [523] = { social = HERD, group = { 2, 3 }, temper = "territorial" },                    -- Zebstrika
  [524] = { social = HUDDLE, group = { 2, 3 }, temper = "calm" },                         -- Roggenrola
  [525] = { temper = "calm" }, [526] = { temper = "territorial" },                        -- Boldore, Gigalith
  [527] = { social = SWARM, group = { 2, 4 }, temper = "skittish", activity = "night" },  -- Woobat
  [528] = { temper = "calm", activity = "night" },                                         -- Swoobat
  [529] = { temper = "calm", burrower = true },                                            -- Drilbur
  [530] = { temper = "territorial", burrower = true },                                     -- Excadrill
  [531] = { temper = "skittish" },                                                         -- Audino
  [532] = { social = PACK, group = { 2, 3 }, temper = "territorial" },                    -- Timburr
  [533] = { temper = "territorial" }, [534] = { temper = "territorial" },                 -- Gurdurr, Conkeldurr
  [535] = { social = SCHOOL, group = { 2, 3 }, diet = "prey", temper = "skittish", water = "swimmer" }, -- Tympole
  [536] = { temper = "calm", water = "swimmer" }, [537] = { temper = "territorial", water = "swimmer" }, -- Palpitoad, Seismitoad
  [538] = { temper = "territorial" }, [539] = { temper = "territorial" },                 -- Throh, Sawk
  [540] = { social = HUDDLE, group = { 2, 3 }, diet = "prey", temper = "skittish" },      -- Sewaddle
  [541] = { diet = "prey", temper = "calm" }, [542] = { temper = "calm" },                -- Swadloon, Leavanny
  [543] = { diet = "predator", temper = "territorial", prey = { "BUG" } },                -- Venipede
  [544] = { temper = "calm" },                                                             -- Whirlipede
  [545] = { diet = "predator", temper = "aggressive", prey = { "BUG", "GRASS" } },        -- Scolipede
  [546] = { social = SWARM, group = { 2, 3 }, temper = "skittish" },                      -- Cottonee
  [547] = { temper = "calm" },                                                             -- Whimsicott
  [548] = { social = HUDDLE, group = { 2, 3 }, temper = "skittish" },                     -- Petilil
  [549] = { temper = "calm" },                                                             -- Lilligant
  [550] = { social = SCHOOL, group = { 2, 3 }, diet = "predator", temper = "aggressive", water = "diver", prey = { "WATER" } }, -- Basculin
  [551] = { diet = "predator", temper = "calm", activity = "any", burrower = true, prey = { "NORMAL", "BUG", "GROUND" } }, -- Sandile
  [552] = { diet = "predator", temper = "territorial", activity = "any", burrower = true }, -- Krokorok
  [553] = { diet = "predator", temper = "aggressive", activity = "any" },                  -- Krookodile
  [554] = { temper = "calm" }, [555] = { temper = "territorial" },                        -- Darumaka, Darmanitan
  [556] = { temper = "calm" },                                                             -- Maractus
  [557] = { social = HUDDLE, group = { 2, 3 }, diet = "prey", temper = "skittish" },      -- Dwebble
  [558] = { temper = "territorial" },                                                      -- Crustle
  [559] = { diet = "neutral", temper = "territorial", activity = "any" },                  -- Scraggy
  [560] = { social = PACK, group = { 2, 3 }, diet = "neutral", temper = "aggressive", activity = "any" }, -- Scrafty
  [561] = { temper = "territorial" },                                                      -- Sigilyph
  [562] = { temper = "calm" }, [563] = { temper = "territorial" },                        -- Yamask, Cofagrigus
  [564] = { temper = "calm", water = "swimmer" }, [565] = { temper = "territorial", water = "swimmer" }, -- Tirtouga, Carracosta
  [566] = { temper = "calm" }, [567] = { temper = "territorial" },                        -- Archen, Archeops
  [568] = { social = HUDDLE, group = { 2, 3 }, temper = "calm" },                         -- Trubbish
  [569] = { temper = "territorial" },                                                      -- Garbodor
  [570] = { diet = "neutral", temper = "skittish" },                                       -- Zorua
  [571] = { diet = "predator", temper = "territorial" },                                   -- Zoroark
  [572] = { social = HUDDLE, group = { 2, 3 }, diet = "prey", temper = "skittish" },      -- Minccino
  [573] = { temper = "calm" },                                                             -- Cinccino
  [574] = { temper = "calm" }, [575] = { temper = "calm" }, [576] = { temper = "calm" },  -- Gothita line
  [577] = { social = HUDDLE, group = { 2, 3 }, temper = "skittish" },                     -- Solosis
  [578] = { temper = "calm" }, [579] = { temper = "calm" },                               -- Duosion, Reuniclus
  [580] = { social = SWARM, group = { 2, 3 }, temper = "skittish", water = "swimmer" },    -- Ducklett
  [581] = { temper = "calm", water = "swimmer" },                                          -- Swanna
  [582] = { social = HUDDLE, group = { 2, 3 }, temper = "skittish" },                     -- Vanillite
  [583] = { temper = "calm" }, [584] = { temper = "calm" },                               -- Vanillish, Vanilluxe
  [585] = { social = HERD, group = { 2, 3 }, diet = "prey", temper = "skittish" },        -- Deerling
  [586] = { social = HERD, group = { 2, 3 }, temper = "territorial" },                    -- Sawsbuck
  [587] = { diet = "prey", temper = "skittish" },                                          -- Emolga
  [588] = { temper = "territorial", rival = { [616] = true } },                            -- Karrablast (vs Shelmet)
  [589] = { temper = "territorial" },                                                      -- Escavalier
  [590] = { social = HUDDLE, group = { 2, 3 }, temper = "calm" },                         -- Foongus
  [591] = { temper = "calm" },                                                             -- Amoonguss
  [592] = { temper = "calm", water = "drifter" },                                          -- Frillish
  [593] = { temper = "territorial", water = "drifter" },                                   -- Jellicent
  [594] = { diet = "neutral", temper = "calm", water = "drifter" },                        -- Alomomola
  [595] = { social = HUDDLE, group = { 2, 3 }, diet = "prey", temper = "skittish" },      -- Joltik
  [596] = { diet = "predator", temper = "territorial", prey = { "BUG" } },                -- Galvantula
  [597] = { social = HUDDLE, group = { 2, 3 }, temper = "calm" },                         -- Ferroseed
  [598] = { temper = "territorial" },                                                      -- Ferrothorn
  [599] = { social = SWARM, group = { 2, 3 }, temper = "calm" },                          -- Klink
  [600] = { temper = "calm" }, [601] = { temper = "territorial" },                        -- Klang, Klinklang
  [602] = { social = SWARM, group = { 2, 4 }, diet = "prey", temper = "skittish" },       -- Tynamo
  [603] = { diet = "predator", temper = "territorial", water = "diver" },                  -- Eelektrik
  [604] = { diet = "predator", temper = "aggressive", water = "diver" },                   -- Eelektross
  [605] = { temper = "calm" }, [606] = { temper = "calm" },                               -- Elgyem, Beheeyem
  [607] = { social = SWARM, group = { 2, 3 }, temper = "calm" },                          -- Litwick
  [608] = { temper = "territorial" }, [609] = { temper = "territorial" },                 -- Lampent, Chandelure
  [610] = { temper = "calm" }, [611] = { temper = "territorial" }, [612] = { temper = "territorial" }, -- Axew line
  [613] = { social = HUDDLE, group = { 2, 3 }, diet = "prey", temper = "skittish" },      -- Cubchoo
  [614] = { diet = "predator", temper = "territorial", prey = { "WATER" } },              -- Beartic
  [615] = { temper = "calm" },                                                             -- Cryogonal
  [616] = { temper = "skittish", rival = { [588] = true } },                               -- Shelmet (vs Karrablast)
  [617] = { temper = "calm" },                                                             -- Accelgor
  [618] = { temper = "calm" },                                                             -- Stunfisk
  [619] = { temper = "calm" }, [620] = { temper = "territorial" },                        -- Mienfoo, Mienshao
  [621] = { temper = "territorial" },                                                      -- Druddigon
  [622] = { temper = "calm" }, [623] = { temper = "calm" },                               -- Golett, Golurk
  [624] = { social = PACK, group = { 2, 3 }, diet = "predator", temper = "territorial" }, -- Pawniard
  [625] = { diet = "predator", temper = "territorial" },                                   -- Bisharp
  [626] = { social = HERD, group = { 2, 3 }, temper = "aggressive" },                     -- Bouffalant
  [627] = { diet = "predator", temper = "territorial", prey = { "BUG", "NORMAL" } },       -- Rufflet
  [628] = { diet = "predator", temper = "territorial" },                                   -- Braviary
  [629] = { diet = "neutral", temper = "calm", activity = "any" },                         -- Vullaby
  [630] = { diet = "predator", temper = "territorial", activity = "any" },                 -- Mandibuzz
  [631] = { diet = "predator", temper = "territorial", prey = { "BUG" }, rival = { [632] = true } }, -- Heatmor (vs Durant)
  [632] = { social = SWARM, group = { 2, 4 }, temper = "territorial", rival = { [631] = true } }, -- Durant
  [633] = { temper = "calm" }, [634] = { temper = "territorial" }, [635] = { temper = "aggressive" }, -- Deino line
  [636] = { temper = "calm" }, [637] = { temper = "territorial" },                        -- Larvesta, Volcarona

  -- ------- Gen 6 (Kalos)
  [650] = { temper = "calm" }, [651] = { temper = "calm" }, [652] = { temper = "territorial" },
  [653] = { temper = "calm" }, [654] = { temper = "calm" }, [655] = { temper = "territorial" },
  [656] = { temper = "calm" }, [657] = { temper = "calm" }, [658] = { temper = "territorial" },
  [659] = { diet = "prey", temper = "skittish", burrower = true },                         -- Bunnelby
  [660] = { temper = "territorial", burrower = true },                                      -- Diggersby
  [661] = { social = SWARM, group = { 2, 3 }, diet = "predator", temper = "skittish", prey = { "BUG" } }, -- Fletchling
  [662] = { diet = "predator", temper = "territorial", prey = { "BUG", "NORMAL" } },        -- Fletchinder
  [663] = { diet = "predator", temper = "territorial" },                                    -- Talonflame
  [664] = { social = HUDDLE, group = { 2, 3 }, diet = "prey", temper = "skittish" },       -- Scatterbug
  [665] = { diet = "prey", temper = "calm" },                                               -- Spewpa
  [666] = { social = SWARM, group = { 2, 3 }, temper = "calm" },                           -- Vivillon
  [667] = { social = PACK, group = { 2, 3 }, diet = "predator", temper = "territorial", prey = { "NORMAL" } }, -- Litleo
  [668] = { social = PACK, group = { 2, 3 }, diet = "predator", temper = "territorial" },  -- Pyroar
  [669] = { social = HUDDLE, group = { 2, 3 }, diet = "prey", temper = "skittish" },       -- Flabebe
  [670] = { temper = "calm" }, [671] = { temper = "calm" },                                -- Floette, Florges
  [672] = { social = HERD, group = { 2, 3 }, temper = "calm" },                            -- Skiddo
  [673] = { social = HERD, group = { 2, 3 }, temper = "calm" },                            -- Gogoat
  [674] = { diet = "neutral", temper = "territorial" },                                     -- Pancham
  [675] = { diet = "neutral", temper = "territorial" },                                     -- Pangoro
  [676] = { temper = "calm" },                                                              -- Furfrou
  [677] = { temper = "skittish" }, [678] = { temper = "calm" },                            -- Espurr, Meowstic
  [679] = { temper = "calm" }, [680] = { temper = "territorial" }, [681] = { temper = "territorial" }, -- Honedge line
  [682] = { temper = "calm" }, [683] = { temper = "calm" },                                -- Spritzee, Aromatisse
  [684] = { temper = "calm" }, [685] = { temper = "calm" },                                -- Swirlix, Slurpuff
  [686] = { temper = "calm" },                                                              -- Inkay
  [687] = { diet = "predator", temper = "territorial" },                                    -- Malamar
  [688] = { social = HUDDLE, group = { 2, 3 }, temper = "calm", water = "drifter" },       -- Binacle
  [689] = { temper = "territorial", water = "drifter" },                                    -- Barbaracle
  [690] = { diet = "prey", temper = "skittish", water = "drifter" },                       -- Skrelp
  [691] = { temper = "territorial" },                                                       -- Dragalge
  [692] = { diet = "predator", temper = "calm", prey = { "WATER", "BUG" } },               -- Clauncher
  [693] = { diet = "predator", temper = "territorial", prey = { "WATER" } },               -- Clawitzer
  [694] = { diet = "prey", temper = "skittish", activity = "day" },                        -- Helioptile
  [695] = { temper = "calm", activity = "day" },                                            -- Heliolisk
  [696] = { temper = "territorial" },                                                       -- Tyrunt
  [697] = { diet = "predator", temper = "aggressive" },                                     -- Tyrantrum
  [698] = { social = HERD, group = { 2, 3 }, temper = "calm" },                            -- Amaura
  [699] = { social = HERD, group = { 2, 3 }, temper = "calm" },                            -- Aurorus
  [700] = { temper = "calm" },                                                              -- Sylveon
  [701] = { temper = "territorial" },                                                       -- Hawlucha
  [702] = { social = HUDDLE, group = { 2, 2 }, diet = "prey", temper = "skittish" },       -- Dedenne
  [703] = { social = HUDDLE, group = { 2, 3 }, temper = "calm" },                          -- Carbink
  [704] = { diet = "prey", temper = "skittish" },                                           -- Goomy
  [705] = { temper = "calm" }, [706] = { temper = "calm" },                                -- Sliggoo, Goodra
  [707] = { temper = "calm" },                                                              -- Klefki
  [708] = { temper = "calm" }, [709] = { temper = "territorial" },                         -- Phantump, Trevenant
  [710] = { social = HUDDLE, group = { 2, 3 }, temper = "calm" },                          -- Pumpkaboo
  [711] = { temper = "territorial" },                                                       -- Gourgeist
  [712] = { social = HUDDLE, group = { 2, 3 }, temper = "calm" },                          -- Bergmite
  [713] = { temper = "calm" },                                                              -- Avalugg
  [714] = { social = SWARM, group = { 2, 3 }, temper = "calm", activity = "night" },       -- Noibat
  [715] = { diet = "predator", temper = "territorial", activity = "night" },               -- Noivern

  -- ------- Gen 7 (Alola)
  [722] = { temper = "calm" }, [723] = { temper = "calm" }, [724] = { temper = "territorial" },
  [725] = { temper = "calm" }, [726] = { temper = "calm" }, [727] = { temper = "territorial" },
  [728] = { temper = "calm" }, [729] = { temper = "calm" }, [730] = { temper = "territorial" },
  [731] = { social = SWARM, group = { 2, 3 }, diet = "predator", temper = "skittish", prey = { "BUG" } }, -- Pikipek
  [732] = { diet = "predator", temper = "calm", prey = { "BUG" } },                        -- Trumbeak
  [733] = { diet = "predator", temper = "territorial", prey = { "BUG" } },                 -- Toucannon
  [734] = { diet = "predator", temper = "territorial", activity = "day", prey = { "NORMAL", "BUG" } }, -- Yungoos
  [735] = { diet = "predator", temper = "territorial", activity = "day", prey = { "NORMAL", "BUG" } }, -- Gumshoos
  [736] = { social = HUDDLE, group = { 2, 3 }, diet = "prey", temper = "skittish" },       -- Grubbin
  [737] = { diet = "prey", temper = "calm" },                                               -- Charjabug
  [738] = { temper = "territorial" },                                                       -- Vikavolt
  [739] = { temper = "territorial" }, [740] = { temper = "territorial" },                  -- Crabrawler, Crabominable
  [741] = { temper = "calm" },                                                              -- Oricorio
  [742] = { social = SWARM, group = { 2, 3 }, diet = "prey", temper = "skittish" },        -- Cutiefly
  [743] = { temper = "calm" },                                                              -- Ribombee
  [744] = { social = PACK, group = { 2, 3 }, temper = "calm" },                            -- Rockruff
  [745] = { social = PACK, group = { 2, 3 }, diet = "predator", temper = "territorial", prey = { "NORMAL", "BUG" } }, -- Lycanroc
  [746] = { social = SCHOOL, group = { 2, 4 }, diet = "prey", temper = "skittish", water = "leaper" }, -- Wishiwashi
  [747] = { diet = "predator", temper = "territorial", water = "drifter", prey = { "WATER" } }, -- Mareanie
  [748] = { diet = "predator", temper = "territorial", water = "drifter", prey = { "WATER" } }, -- Toxapex
  [749] = { social = HERD, group = { 2, 3 }, temper = "calm" },                            -- Mudbray
  [750] = { social = HERD, group = { 2, 3 }, temper = "territorial" },                     -- Mudsdale
  [751] = { diet = "prey", temper = "skittish" },                                           -- Dewpider
  [752] = { diet = "predator", temper = "territorial", prey = { "BUG", "WATER" } },        -- Araquanid
  [753] = { temper = "skittish" }, [754] = { temper = "territorial" },                     -- Fomantis, Lurantis
  [755] = { social = HUDDLE, group = { 2, 3 }, temper = "calm", activity = "night" },      -- Morelull
  [756] = { temper = "calm", activity = "night" },                                          -- Shiinotic
  [757] = { social = PACK, group = { 2, 3 }, diet = "predator", temper = "territorial", prey = { "BUG" } }, -- Salandit
  [758] = { diet = "predator", temper = "territorial" },                                    -- Salazzle
  [759] = { temper = "calm" },                                                              -- Stufful
  [760] = { temper = "aggressive" },                                                        -- Bewear
  [761] = { diet = "prey", temper = "skittish" },                                           -- Bounsweet
  [762] = { temper = "calm" }, [763] = { temper = "territorial" },                         -- Steenee, Tsareena
  [764] = { temper = "calm" },                                                              -- Comfey
  [765] = { temper = "placid" },                                                            -- Oranguru
  [766] = { social = PACK, group = { 2, 4 }, temper = "territorial" },                     -- Passimian
  [767] = { social = SWARM, group = { 2, 3 }, diet = "prey", temper = "skittish" },        -- Wimpod
  [768] = { temper = "territorial" },                                                       -- Golisopod
  [769] = { temper = "calm", activity = "any" },                                            -- Sandygast
  [770] = { temper = "territorial", activity = "any" },                                     -- Palossand
  [771] = { social = HUDDLE, group = { 2, 3 }, temper = "placid", water = "drifter" },     -- Pyukumuku
  [774] = { temper = "calm" },                                                              -- Minior
  [775] = { temper = "placid" },                                                            -- Komala
  [776] = { temper = "territorial" },                                                       -- Turtonator
  [777] = { social = HUDDLE, group = { 2, 2 }, temper = "calm" },                          -- Togedemaru
  [778] = { temper = "skittish" },                                                          -- Mimikyu
  [779] = { social = "solo", temper = "territorial" },                                    -- Bruxish (a lone triggerfish)
  [780] = { temper = "calm" },                                                              -- Drampa
  [781] = { temper = "territorial" },                                                       -- Dhelmise
  [782] = { temper = "territorial" }, [783] = { temper = "territorial" }, [784] = { temper = "territorial" }, -- Jangmo-o line

  -- ------- Gen 8 (Galar, Hisui)
  [810] = { temper = "calm" }, [811] = { temper = "calm" }, [812] = { temper = "territorial" }, -- Grookey line
  [813] = { temper = "calm" }, [814] = { temper = "calm" }, [815] = { temper = "territorial" }, -- Scorbunny line
  [816] = { temper = "calm" }, [817] = { temper = "calm" }, [818] = { temper = "territorial" }, -- Sobble line
  [819] = { social = HUDDLE, group = { 2, 3 }, diet = "prey", temper = "skittish" },      -- Skwovet
  [820] = { temper = "calm" },                                                             -- Greedent
  [821] = { social = SWARM, group = { 2, 3 }, diet = "predator", temper = "territorial", prey = { "BUG" } }, -- Rookidee (brave, takes on anyone)
  [822] = { diet = "predator", temper = "territorial", prey = { "BUG", "NORMAL" } },       -- Corvisquire
  [823] = { diet = "predator", temper = "territorial", rival = { [959] = true } },         -- Corviknight (vs Tinkaton)
  [824] = { social = HUDDLE, group = { 2, 3 }, diet = "prey", temper = "skittish" },      -- Blipbug
  [825] = { diet = "prey", temper = "calm" }, [826] = { temper = "calm" },                -- Dottler, Orbeetle
  [827] = { diet = "prey", temper = "skittish" },                                          -- Nickit
  [828] = { diet = "predator", temper = "territorial", prey = { "NORMAL", "BUG" } },       -- Thievul
  [829] = { social = HUDDLE, group = { 2, 3 }, diet = "prey", temper = "calm" },          -- Gossifleur
  [830] = { temper = "calm" },                                                             -- Eldegoss
  [831] = { social = HERD, group = { 2, 4 }, diet = "prey", temper = "skittish" },        -- Wooloo
  [832] = { social = HERD, group = { 2, 3 }, temper = "calm" },                           -- Dubwool
  [833] = { diet = "predator", temper = "territorial", water = "swimmer", prey = { "WATER" } }, -- Chewtle
  [834] = { diet = "predator", temper = "aggressive", water = "swimmer", prey = { "WATER", "ROCK" } }, -- Drednaw
  [835] = { social = PACK, group = { 2, 3 }, temper = "calm" },                           -- Yamper
  [836] = { social = PACK, group = { 2, 3 }, diet = "predator", temper = "territorial", prey = { "NORMAL" } }, -- Boltund
  [837] = { social = HUDDLE, group = { 2, 3 }, temper = "calm" },                         -- Rolycoly
  [838] = { temper = "calm" }, [839] = { temper = "territorial" },                        -- Carkol, Coalossal
  [840] = { social = HUDDLE, group = { 2, 3 }, diet = "prey", temper = "skittish" },      -- Applin
  [841] = { temper = "calm" }, [842] = { temper = "calm" },                               -- Flapple, Appletun
  [843] = { temper = "calm", burrower = true },                                            -- Silicobra
  [844] = { temper = "territorial" },                                                      -- Sandaconda
  [845] = { diet = "predator", temper = "calm", water = "swimmer", prey = { "WATER" } },   -- Cramorant
  [846] = { social = SCHOOL, group = { 2, 4 }, diet = "predator", temper = "territorial", water = "diver", prey = { "WATER" } }, -- Arrokuda
  [847] = { diet = "predator", temper = "aggressive", water = "diver", prey = { "WATER" } }, -- Barraskewda
  [848] = { temper = "skittish" }, [849] = { temper = "territorial" },                    -- Toxel, Toxtricity
  [850] = { diet = "predator", temper = "territorial", prey = { "BUG" } },                 -- Sizzlipede
  [851] = { diet = "predator", temper = "aggressive" },                                    -- Centiskorch
  [852] = { temper = "territorial", water = "swimmer" },                                   -- Clobbopus
  [853] = { diet = "predator", temper = "territorial", water = "swimmer", prey = { "WATER" } }, -- Grapploct
  [854] = { temper = "calm" }, [855] = { temper = "calm" },                               -- Sinistea, Polteageist
  [856] = { temper = "skittish" }, [857] = { temper = "territorial" }, [858] = { temper = "territorial" }, -- Hatenna line
  [859] = { temper = "skittish" }, [860] = { temper = "territorial" }, [861] = { temper = "territorial" }, -- Impidimp line
  [862] = { diet = "predator", temper = "aggressive" },                                    -- Obstagoon
  [863] = { temper = "territorial" },                                                      -- Perrserker
  [864] = { temper = "territorial", water = "drifter" },                                   -- Cursola
  [865] = { temper = "territorial" }, [866] = { temper = "calm" },                        -- Sirfetch'd, Mr. Rime
  [867] = { temper = "territorial" },                                                      -- Runerigus
  [868] = { temper = "skittish" }, [869] = { temper = "calm" },                           -- Milcery, Alcremie
  [870] = { temper = "territorial" },                                                      -- Falinks
  [871] = { social = HUDDLE, group = { 2, 3 }, temper = "calm", water = "drifter" },      -- Pincurchin
  [872] = { social = HUDDLE, group = { 2, 3 }, diet = "prey", temper = "skittish" },      -- Snom
  [873] = { temper = "calm", activity = "night" },                                         -- Frosmoth
  [874] = { temper = "placid" },                                                             -- Stonjourner
  [875] = { social = HUDDLE, group = { 2, 3 }, diet = "predator", temper = "calm", water = "swimmer", prey = { "WATER" } }, -- Eiscue
  [876] = { temper = "calm" },                                                             -- Indeedee
  [877] = { diet = "prey", temper = "skittish", activity = "any" },                        -- Morpeko
  [878] = { social = HERD, group = { 2, 3 }, temper = "calm" },                           -- Cufant
  [879] = { social = HERD, group = { 2, 3 }, temper = "territorial" },                    -- Copperajah
  [880] = { temper = "territorial" }, [881] = { temper = "calm" },                        -- Dracozolt, Arctozolt
  [882] = { diet = "predator", temper = "territorial", water = "swimmer" },               -- Dracovish
  [883] = { temper = "calm", water = "swimmer" },                                          -- Arctovish
  [884] = { temper = "calm" },                                                             -- Duraludon
  [885] = { social = SWARM, group = { 2, 3 }, temper = "skittish" },                      -- Dreepy
  [886] = { temper = "territorial" }, [887] = { temper = "territorial" },                 -- Drakloak, Dragapult
  [899] = { social = HERD, group = { 2, 3 }, temper = "calm" },                           -- Wyrdeer
  [900] = { temper = "aggressive" },                                                       -- Kleavor
  [901] = { temper = "territorial" },                                                      -- Ursaluna
  [902] = { diet = "predator", temper = "territorial", water = "diver", activity = "any", prey = { "WATER" } }, -- Basculegion
  [903] = { diet = "predator", temper = "aggressive" },                                    -- Sneasler
  [904] = { temper = "aggressive", water = "diver", activity = "any" },                    -- Overqwil

  -- ------- Gen 9 (Paldea)
  [906] = { temper = "calm" }, [907] = { temper = "calm" }, [908] = { temper = "territorial" },
  [909] = { temper = "calm" }, [910] = { temper = "calm" }, [911] = { temper = "territorial" },
  [912] = { temper = "calm" }, [913] = { temper = "calm" }, [914] = { temper = "territorial" },
  [915] = { social = HERD, group = { 2, 3 }, diet = "prey", temper = "skittish" },        -- Lechonk
  [916] = { temper = "calm" },                                                             -- Oinkologne
  [917] = { diet = "predator", temper = "skittish", prey = { "BUG" } },                   -- Tarountula
  [918] = { diet = "predator", temper = "territorial", prey = { "BUG" } },                -- Spidops
  [919] = { diet = "prey", temper = "skittish", activity = "night" },                     -- Nymble
  [920] = { diet = "predator", temper = "territorial", prey = { "BUG" } },                -- Lokix
  [921] = { social = HUDDLE, group = { 2, 3 }, diet = "prey", temper = "skittish" },      -- Pawmi
  [922] = { temper = "calm" }, [923] = { temper = "territorial" },                        -- Pawmo, Pawmot
  [924] = { social = HUDDLE, group = { 2, 3 }, diet = "prey", temper = "skittish" },      -- Tandemaus
  [925] = { temper = "calm" },                                                             -- Maushold
  [926] = { diet = "prey", temper = "calm" }, [927] = { temper = "territorial" },         -- Fidough, Dachsbun
  [928] = { social = HUDDLE, group = { 2, 3 }, diet = "prey", temper = "skittish" },      -- Smoliv
  [929] = { temper = "calm" }, [930] = { temper = "calm" },                               -- Dolliv, Arboliva
  [931] = { social = SWARM, group = { 2, 4 }, temper = "territorial" },                   -- Squawkabilly
  [932] = { social = HUDDLE, group = { 2, 3 }, temper = "calm" },                         -- Nacli
  [933] = { temper = "calm" }, [934] = { temper = "calm" },                               -- Naclstack, Garganacl
  [935] = { temper = "calm" }, [936] = { temper = "territorial" }, [937] = { temper = "territorial" }, -- Charcadet line
  [938] = { diet = "prey", temper = "skittish" },                                          -- Tadbulb
  [939] = { temper = "calm" },                                                             -- Bellibolt
  [940] = { social = SWARM, group = { 2, 3 }, diet = "predator", temper = "skittish", prey = { "WATER" } }, -- Wattrel
  [941] = { diet = "predator", temper = "territorial", prey = { "WATER" } },               -- Kilowattrel
  [942] = { social = PACK, group = { 2, 3 }, diet = "predator", temper = "territorial", prey = { "NORMAL" } }, -- Maschiff
  [943] = { diet = "predator", temper = "territorial" },                                   -- Mabosstiff
  [944] = { social = HUDDLE, group = { 2, 3 }, diet = "prey", temper = "skittish" },      -- Shroodle
  [945] = { temper = "calm" },                                                             -- Grafaiai
  [946] = { social = SWARM, group = { 2, 3 }, temper = "calm", activity = "any" },        -- Bramblin
  [947] = { temper = "territorial", activity = "any" },                                    -- Brambleghast
  [948] = { social = HUDDLE, group = { 2, 3 }, diet = "prey", temper = "skittish" },      -- Toedscool
  [949] = { social = HUDDLE, group = { 2, 3 }, temper = "territorial" },                  -- Toedscruel
  [950] = { diet = "predator", temper = "territorial" },                                   -- Klawf
  [951] = { diet = "prey", temper = "skittish" }, [952] = { temper = "territorial" },     -- Capsakid, Scovillain
  [953] = { diet = "prey", temper = "calm" }, [954] = { temper = "calm" },                -- Rellor, Rabsca
  [955] = { social = SWARM, group = { 2, 3 }, diet = "prey", temper = "skittish" },       -- Flittle
  [956] = { temper = "calm" },                                                             -- Espathra
  [957] = { temper = "calm" }, [958] = { temper = "territorial" },                         -- Tinkatink, Tinkatuff
  [959] = { temper = "territorial", rival = { [823] = true } },                            -- Tinkaton (smashes Corviknight)
  [960] = { social = HUDDLE, group = { 2, 3 }, diet = "prey", temper = "skittish", burrower = true }, -- Wiglett
  [961] = { temper = "territorial", burrower = true },                                     -- Wugtrio
  [962] = { diet = "predator", temper = "territorial", activity = "day" },                -- Bombirdier
  [965] = { temper = "territorial" }, [966] = { temper = "territorial" },                 -- Varoom, Revavroom
  [967] = { social = HERD, group = { 2, 3 }, temper = "calm" },                           -- Cyclizar
  [968] = { temper = "calm", burrower = true },                                            -- Orthworm
  [969] = { social = HUDDLE, group = { 2, 3 }, temper = "calm" },                         -- Glimmet
  [970] = { temper = "territorial" },                                                      -- Glimmora
  [971] = { temper = "calm" }, [972] = { temper = "calm" },                               -- Greavard, Houndstone
  [973] = { social = SWARM, group = { 2, 4 }, temper = "calm" },                          -- Flamigo
  [974] = { social = HERD, group = { 2, 3 }, temper = "calm" },                           -- Cetoddle
  [975] = { temper = "calm" },                                                             -- Cetitan
  [976] = { diet = "predator", temper = "territorial", water = "diver", prey = { "WATER" } }, -- Veluza
  [977] = { diet = "predator", temper = "calm", water = "diver", prey = { "WATER" } },    -- Dondozo
  [978] = { social = SCHOOL, group = { 2, 3 }, temper = "skittish", water = "swimmer" },  -- Tatsugiri
  [979] = { temper = "aggressive" },                                                       -- Annihilape
  [980] = { temper = "calm", water = "swimmer" },                                          -- Clodsire
  [981] = { social = HERD, group = { 2, 3 }, temper = "calm" },                           -- Farigiraf
  [982] = { temper = "calm" },                                                             -- Dudunsparce
  [983] = { temper = "territorial" },                                                      -- Kingambit
  [996] = { temper = "calm" }, [997] = { temper = "territorial" }, [998] = { temper = "aggressive" }, -- Frigibax line
  [999] = { temper = "skittish" }, [1000] = { temper = "calm" },                          -- Gimmighoul, Gholdengo
  [1011] = { temper = "calm" },                                                            -- Dipplin
  [1012] = { social = HUDDLE, group = { 2, 3 }, temper = "skittish" },                    -- Poltchageist
  [1013] = { temper = "calm" },                                                            -- Sinistcha
  [1018] = { temper = "territorial" },                                                     -- Archaludon
  [1019] = { temper = "calm" },                                                            -- Hydrapple

  -- ------- National Dex Gen 3 extras with a set character
  [963] = { social = POD, group = { 2, 4 }, temper = "calm", water = "leaper" },          -- Finizen
  [964] = { social = POD, group = { 2, 3 }, temper = "territorial", water = "leaper" },   -- Palafin
}
