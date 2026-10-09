"""Where each alternate form's overworld art comes from.

One row per form National Dex Gen 3 registers (tools/form_list.py in that repo):
    (base dex, form name, SpriteCollab form folder or None, HGSS source variant or None)
The runtime key of a form is "%03d-<form>" (lib/form_source.lua), so the
baked sheets are <dex3>-<form>-<normal|shiny>.png.

  * PMD: sprite/<dex4>/<folder>/ in SpriteCollab (None: SpriteCollab has no such
    form, the base species' sheet is drawn). A folder with no Walk/Idle art
    of its own is skipped by the bake the same way.
  * HGSS: the raw grid followsprites/<dex3>-b-n-<variant>.png (and -b-s-) copied from
    Wilds of Kanto Revival (None: there is none, the PMD sheet or the base is drawn).
    A string instead of a number names a file in the Gen 9 follower pack (GEN9_FOLLOWERS
    below; a "Followers shiny" folder beside it holds the shiny sheet), a 4x4 grid in the
    same row order but with 64px cells.
    Variants are matched by eye against the raw grids (Rotom 1-5 = Heat, Wash, Frost,
    Fan, Mow; Kyurem 1 = White, 2 = Black).
A form not listed here simply draws its base species.
"""

FORM_ART = [
    (554, "galar", '0001', "DARUMAKA_2.png"),  # DARUMAKA_GALAR
    (555, "galar_standard", '0002', "DARMANITAN_2.png"),  # DARMANITAN_GALAR_STANDARD
    (562, "galar", '0001', "YAMASK_1.png"),  # YAMASK_GALAR
    (618, "galar", '0001', "STUNFISK_1.png"),  # STUNFISK_GALAR
    (570, "hisui", '0001', "ZORUA_1.png"),  # ZORUA_HISUI
    (571, "hisui", '0001', "ZOROARK_1.png"),  # ZOROARK_HISUI
    (503, "hisui", '0001', "SAMUROTT_1.png"),  # SAMUROTT_HISUI
    (549, "hisui", '0001', "LILLIGANT_1.png"),  # LILLIGANT_HISUI
    (628, "hisui", '0001', "BRAVIARY_1.png"),  # BRAVIARY_HISUI
    (705, "hisui", '0001', "SLIGGOO_1.png"),  # SLIGGOO_HISUI
    (706, "hisui", '0001', "GOODRA_1.png"),  # GOODRA_HISUI
    (713, "hisui", '0001', "AVALUGG_1.png"),  # AVALUGG_HISUI
    (724, "hisui", '0001', "DECIDUEYE_1.png"),  # DECIDUEYE_HISUI
    (413, "sandy", '0001', 1),  # WORMADAM_SANDY
    (413, "trash", '0002', 2),  # WORMADAM_TRASH
    (479, "heat", '0001', 1),  # ROTOM_HEAT
    (479, "wash", '0002', 2),  # ROTOM_WASH
    (479, "frost", '0003', 3),  # ROTOM_FROST
    (479, "fan", '0004', 4),  # ROTOM_FAN
    (479, "mow", '0005', 5),  # ROTOM_MOW
    (741, "pau", '0002', "ORICORIO_2.png"),  # ORICORIO_PAU
    (741, "pom_pom", '0001', "ORICORIO_1.png"),  # ORICORIO_POM_POM
    (741, "sensu", '0003', "ORICORIO_3.png"),  # ORICORIO_SENSU
    (710, "small", '0001', None),  # PUMPKABOO_SMALL
    (710, "large", '0002', None),  # PUMPKABOO_LARGE
    (710, "super", '0003', None),  # PUMPKABOO_SUPER
    (711, "small", '0001', None),  # GOURGEIST_SMALL
    (711, "large", '0002', None),  # GOURGEIST_LARGE
    (711, "super", '0003', None),  # GOURGEIST_SUPER
    (745, "midnight", '0001', "LYCANROC_1.png"),  # LYCANROC_MIDNIGHT
    (745, "dusk", '0002', "LYCANROC_2.png"),  # LYCANROC_DUSK
    (892, "rapid_strike", '0001', "URSHIFU_1.png"),  # URSHIFU_RAPID_STRIKE
    (487, "origin", '0001', 1),  # GIRATINA_ORIGIN
    (483, "origin", '0001', "DIALGA_1.png"),  # DIALGA_ORIGIN
    (484, "origin", '0001', "PALKIA_1.png"),  # PALKIA_ORIGIN
    (492, "sky", '0001', 1),  # SHAYMIN_SKY
    (641, "therian", '0001', "TORNADUS_1.png"),  # TORNADUS_THERIAN
    (642, "therian", '0001', "THUNDURUS_1.png"),  # THUNDURUS_THERIAN
    (645, "therian", '0001', "LANDORUS_1.png"),  # LANDORUS_THERIAN
    (905, "therian", '0001', "ENAMORUS_1.png"),  # ENAMORUS_THERIAN
    (646, "black", '0001', 2),  # KYUREM_BLACK
    (646, "white", '0002', 1),  # KYUREM_WHITE
    (720, "unbound", '0001', "HOOPA_1.png"),  # HOOPA_UNBOUND
    (800, "dusk", '0001', "NECROZMA_1.png"),  # NECROZMA_DUSK
    (800, "dawn", '0002', "NECROZMA_2.png"),  # NECROZMA_DAWN
    (898, "ice", '0001', "CALYREX_1.png"),  # CALYREX_ICE
    (898, "shadow", '0002', "CALYREX_2.png"),  # CALYREX_SHADOW
    (888, "crowned", '0001', "ZACIAN_1.png"),  # ZACIAN_CROWNED
    (889, "crowned", '0001', "ZAMAZENTA_1.png"),  # ZAMAZENTA_CROWNED
    (1017, "wellspring_mask", '0005', "OGERPON_1.png"),  # OGERPON_WELLSPRING_MASK
    (1017, "hearthflame_mask", '0006', "OGERPON_2.png"),  # OGERPON_HEARTHFLAME_MASK
    (1017, "cornerstone_mask", '0007', "OGERPON_3.png"),  # OGERPON_CORNERSTONE_MASK
    (901, "bloodmoon", '0001', "URSALUNA_1.png"),  # URSALUNA_BLOODMOON
    (718, "10", '0001', "ZYGARDE_1.png"),  # ZYGARDE_10
    (718, "complete", '0002', None),  # ZYGARDE_COMPLETE
    (670, "eternal", '0005', "FLOETTE_5.png"),  # FLOETTE_ETERNAL
    (869, "ruby_cream", '0007', "ALCREMIE_7.png"),  # ALCREMIE_RUBY_CREAM
    (869, "matcha_cream", '0014', "ALCREMIE_14.png"),  # ALCREMIE_MATCHA_CREAM
    (869, "mint_cream", '0021', "ALCREMIE_21.png"),  # ALCREMIE_MINT_CREAM
    (869, "lemon_cream", '0028', "ALCREMIE_28.png"),  # ALCREMIE_LEMON_CREAM
    (869, "salted_cream", '0035', "ALCREMIE_35.png"),  # ALCREMIE_SALTED_CREAM
    (869, "ruby_swirl", '0042', "ALCREMIE_42.png"),  # ALCREMIE_RUBY_SWIRL
    (869, "caramel_swirl", '0049', "ALCREMIE_49.png"),  # ALCREMIE_CARAMEL_SWIRL
    (869, "rainbow_swirl", '0056', "ALCREMIE_56.png"),  # ALCREMIE_RAINBOW_SWIRL
    (422, "east", '0001', 1),  # SHELLOS_EAST
    (423, "east", '0001', 1),  # GASTRODON_EAST
    (669, "yellow", '0001', "FLABEBE_1.png"),  # FLABEBE_YELLOW
    (669, "orange", '0002', "FLABEBE_2.png"),  # FLABEBE_ORANGE
    (669, "blue", '0003', "FLABEBE_3.png"),  # FLABEBE_BLUE
    (669, "white", '0004', "FLABEBE_4.png"),  # FLABEBE_WHITE
    (670, "yellow", '0001', "FLOETTE_1.png"),  # FLOETTE_YELLOW
    (670, "orange", '0002', "FLOETTE_2.png"),  # FLOETTE_ORANGE
    (670, "blue", '0003', "FLOETTE_3.png"),  # FLOETTE_BLUE
    (670, "white", '0004', "FLOETTE_4.png"),  # FLOETTE_WHITE
    (671, "yellow", '0001', "FLORGES_1.png"),  # FLORGES_YELLOW
    (671, "orange", '0002', "FLORGES_2.png"),  # FLORGES_ORANGE
    (671, "blue", '0003', "FLORGES_3.png"),  # FLORGES_BLUE
    (671, "white", '0004', "FLORGES_4.png"),  # FLORGES_WHITE
    (550, "white_striped", '0002', "BASCULIN_2.png"),  # BASCULIN_WHITE_STRIPED
    (902, "female", '0000/0000/0002', "BASCULEGION_female.png"),  # BASCULEGION_FEMALE
    # No source draws these apart from the base (SpriteCollab and the Gen 9 pack have one
    # sheet each), so they are listed to say so: they draw the base species' sprite.
    (854, "antique", None, None),  # SINISTEA_ANTIQUE
    (855, "antique", None, None),  # POLTEAGEIST_ANTIQUE
    (1012, "artisan", None, None),  # POLTCHAGEIST_ARTISAN
    (1013, "masterpiece", None, None),  # SINISTCHA_MASTERPIECE
]

# A form folder's shiny sheet lives in <folder>/0001 unless listed here (gender
# variants sit one level deeper: <form>/<shiny>/<gender>).
SHINY_DIR_OVERRIDE = {
    (902, "female"): "0000/0001/0002",  # Basculegion female
}

# Gen 9 follower pack (Essentials-style 4x4 sheets) for forms the Wilds grids lack.
# Override with $GEN9_FOLLOWERS; the shiny sheets are in the folder named "<dir> shiny".
import os as _os
from pathlib import Path as _Path
GEN9_FOLLOWERS = _Path(_os.environ.get("GEN9_FOLLOWERS") or
    _Path(__file__).resolve().parent.parent.parent / "1SpriteReferences" / "Gen 9 Pack"
    / "Graphics" / "Characters" / "Followers")
