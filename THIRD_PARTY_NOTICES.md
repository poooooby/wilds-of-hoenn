# Third-party notices

This mod's own code is MIT-licensed (see `LICENSE`). The art below is not.

## Code adapted from Wilds of Kanto Revival

`lib/json_decode.lua`, `lib/HGSS_scale.lua` (the per-species overworld size table; `lib/PMD_scale.lua` is its PMDCollab twin),
`tools/generate_sprite_atlases.py` and `tools/validate_sprite_atlases.py` are copied or
adapted from
**Wilds of Kanto Revival** (`poooooby/wilds-of-kanto-gen-3`), which is
released under the MIT License:

> Copyright (c) 2026 YoDrehDenSwagAuf
>
> Modifications Copyright (c) 2026 poooooby
>
> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction, including without limitation the rights
> to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions: The above copyright
> notice and this permission notice shall be included in all copies or
> substantial portions of the Software. THE SOFTWARE IS PROVIDED "AS IS",
> WITHOUT WARRANTY OF ANY KIND (the full MIT terms are in `LICENSE`).

## Inspiration

- **TTiN** and **Untamed Tohjo**: the idea of weighting a Forager's finds by its friendship (a fonder
  Pokemon finds better and rarer items) comes from their foraging. No code or assets were copied; the
  Forager here (`lib/forager.lua`, `lib/forage_items.lua`) is this mod's own implementation.

## Overworld sprites

The HGSS / PokeMMO art under `assets/enhanced_overworld/` and
`assets/wilds_generated/` is a read-only copy of **Wilds of Kanto**'s
HGSS / PokeMMO Sprite Style sources (`tools/copy_wilds_assets.py`, run against
a sibling `poooooby/wilds-of-kanto-gen-3` checkout). Originally sourced from
https://www.pokecommunity.com/threads/generation-9-resource-pack-v21-1.527398/
This mod does not modify that art and does not share a runtime dependency with 
Wilds of Kanto Revival -- the two repos may diverge over time. 

- **HGSS / PokeMMO** (raw sources in `assets/enhanced_overworld/followsprites/`
  and `water_sprites/`, baked here into `assets/wilds_generated/true_size18/`):
  a large multi-author gap-filling set credited to numerous
  individual artists in Wilds of Kanto Revival's own
  `THIRD_PARTY_NOTICES.md` (MissingLukey, Kymoyonian, Getsuei-H, and many
  others listed there), plus the Pokemon Tower ghost sprite by
  Nuclear-Blizzard. Full credits list [here](https://docs.google.com/spreadsheets/d/1T-KC-4XDOeFKq0Z6tfN6Sz4JIlpaK7B8A0lbmBg9fNY/edit?usp=sharing).

See Wilds of Kanto Revival's `THIRD_PARTY_NOTICES.md` and `README.md` for
the complete, authoritative credit list for this art.

## PMDCollab sprites

The **PMDCollab** Sprite Style uses the Portraits and the Walk, Idle, Attack and Hurt sprites of
[PMDCollab/SpriteCollab](https://github.com/PMDCollab/SpriteCollab)
(https://sprites.pmdcollab.org/), repacked by `tools/generate_pmd_sprites.py`
into `assets/pmd/` (cropped, padded, cardinal directions only -- no pixels
altered). That art is not committed to this repo and is not covered by this
mod's own licence: all custom graphics not originating from official PMD
games are licensed under
[Attribution-NonCommercial 4.0 International](http://creativecommons.org/licenses/by-nc/4.0/),
and the official-game graphics are (c) Spike Chunsoft / Nintendo / The
Pokemon Company. The per-species artist credits are generated into
`assets/pmd/CREDITS.txt`, which ships with any build that includes the
PMDCollab sheets. **A build containing them (the `-hgss-pmd` release) is therefore
non-commercial only.** The `-hgss` release contains none of this art; this
section applies only to builds that ship `assets/pmd/`.

### Sprites added manually (not yet in the public SpriteCollab repo)

These sprites were added by hand from the PMDCollab Discord before they reached
the public SpriteCollab repository, so their artists are not credited publicly
there yet. They are covered by the same CC BY-NC 4.0 terms as the rest of the
PMDCollab art. Artist handles are as given in each sprite folder's
`credits.txt`. (The generated `assets/pmd/CREDITS.txt` lists the same artists.)

| # | Pokemon | Artist(s) |
|---|---|---|
| 514 | Simisear | butchcats |
| 520 | Tranquill | Pokejavi, POWERCRISTAL |
| 522 | Blitzle | Pokejavi, POWERCRISTAL |
| 558 | Crustle | JaiFain, POWERCRISTAL |
| 564 | Tirtouga | Pokejavi, Soulja |
| 592 | Frillish (male) | Pokejavi, POWERCRISTAL |
| 616 | Shelmet | Pokejavi |
| 626 | Bouffalant | Pokejavi, POWERCRISTAL |
| 741 | Oricorio | baronessfaron |
| 837 | Rolycoly | baroness faron |
| 838 | Carkol | baroness faron |
| 931 | Squawkabilly | Pokejavi, pi |
| 943 | Mabosstiff | Gust, DavKriz |
| 956 | Espathra | rhys |
| 962 | Bombirdier | JaiFain |
| 973 | Flamigo | pi |
| 1008 | Miraidon | Delta L |
| 1014 | Okidogi | JaiFain |

### Portraits added or updated manually

These portraits were added or updated by hand from the PMDCollab Discord before
the change (and its updated credits) reached the public SpriteCollab repository.
They are covered by the same CC BY-NC 4.0 terms. Artist names are the display
names from SpriteCollab's `credit_names.txt` for the Discord accounts listed in
each portrait folder's `credits.txt`. (`assets/pmd/CREDITS.txt` lists the
portrait artists for every species.)

| # | Pokemon | Artist(s) |
|---|---|---|
| 45 | Vileplume | Emmuffin |
| 68 | Machamp | Soulja |
| 107 | Hitmonchan | RibbonDove, G〜 |
| 124 | Jynx | baronessfaron |
| 295 | Exploud | Tainted#3886 |
| 365 | Walrein | Top_Kec |
| 681 | Aegislash | Emmuffin, radpeepo |

## Engine

Built against [Gen1Recomp](https://github.com/bryanthaboi/gen1recomp),
which this mod does not redistribute.
