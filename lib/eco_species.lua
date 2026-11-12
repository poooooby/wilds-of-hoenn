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
  [27]  = { diet = "prey", temper = "skittish" }, [28] = { temper = "territorial" },      -- Sandshrew, Sandslash
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
  [50]  = { social = HUDDLE, group = { 2, 3 }, temper = "skittish" },                     -- Diglett
  [51]  = { temper = "territorial" },
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
  [79]  = { temper = "calm", water = "swimmer" }, [80] = { temper = "calm", water = "swimmer" }, -- Slowpoke, Slowbro
  [82]  = { temper = "calm" },                                                             -- Magneton
  [83]  = { temper = "territorial" },                                                      -- Farfetch'd
  [86]  = { social = POD, group = { 2, 3 }, temper = "calm", water = "swimmer" },         -- Seel
  [87]  = { temper = "calm", water = "swimmer" },                                          -- Dewgong
  [88]  = { temper = "calm" }, [89] = { temper = "territorial" },                         -- Grimer, Muk
  [90]  = { social = HUDDLE, group = { 2, 3 }, diet = "prey", temper = "calm", water = "drifter" }, -- Shellder
  [91]  = { temper = "territorial", water = "drifter" },                                   -- Cloyster
  [92]  = { social = SWARM, group = { 2, 3 }, temper = "territorial", activity = "night" }, -- Gastly
  [93]  = { temper = "territorial", activity = "night" }, [94] = { temper = "aggressive", activity = "night" },
  [95]  = { temper = "territorial" },                                                      -- Onix
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
  [123] = { diet = "predator", temper = "aggressive", prey = { "BUG" } },                  -- Scyther
  [124] = { temper = "calm" }, [125] = { temper = "territorial" }, [126] = { temper = "territorial" },
  [128] = { social = HERD, group = { 2, 4 }, temper = "aggressive" },                     -- Tauros
  [131] = { social = POD, group = { 2, 2 }, temper = "calm", water = "swimmer" },         -- Lapras
  [132] = { temper = "calm" },                                                             -- Ditto
  [133] = { diet = "prey", temper = "skittish" },                                          -- Eevee
  [138] = { temper = "calm", water = "drifter" }, [140] = { temper = "calm", water = "drifter" }, -- Omanyte, Kabuto
  [143] = { temper = "calm" },                                                             -- Snorlax
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
  [213] = { temper = "calm" },                                                            -- Shuckle
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
  [246] = { temper = "calm" },                                                            -- Larvitar

  -- ------- National Dex Gen 3 extras with a set character
  [963] = { social = POD, group = { 2, 4 }, temper = "calm", water = "leaper" },          -- Finizen
  [964] = { social = POD, group = { 2, 3 }, temper = "territorial", water = "leaper" },   -- Palafin
}
