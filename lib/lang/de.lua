-- German (Deutsch). Keys are the English text (lib/i18n.lua); "<context>|..." keys for
-- option / choice / menu / party rows. tests/i18n_coverage_unit_test.lua checks every
-- key is here. Wording and names follow the official German releases (Pokédex,
-- Pokéball, EP, Hydropi, Lavandia, Blütenburgwald, Baumhausen ...).
return {
  -- options: labels
  ["option|Language"] = "Sprache",
  ["option|Show Wild Mons"] = "Wilde Pokémon",
  ["option|Spawn Amount"] = "Anzahl",
  ["option|Flying Mons"] = "Flug-Pokémon",
  ["option|Water Life"] = "Wasserleben",
  ["option|Local Scenes"] = "Ortsszenen",
  ["option|Wild Reacts"] = "Reaktionen",
  ["option|Sprite Style"] = "Sprite-Stil",
  ["option|Follower"] = "Begleiter",
  ["option|Battler: Pad"] = "Kämpfer: Pad",
  ["option|Battler: Key"] = "Kämpfer: Taste",
  ["option|Smooth Follow"] = "Weich folgen",
  ["option|Type Aura"] = "Typ-Aura",
  ["option|Classic Enc"] = "Zufallskämpfe",
  ["option|Silhouette"] = "Silhouette",
  ["option|Species Sizes"] = "Größen",
  ["option|Portraits"] = "Porträts",

  -- options: choices
  ["choice|LOW"] = "NIEDRIG",
  ["choice|NORMAL"] = "NORMAL",
  ["choice|HIGH"] = "HOCH",
  ["choice|FULL"] = "VOLL",
  ["choice|AMBIENT"] = "UMGEBUNG",
  ["choice|OFF"] = "AUS",
  ["choice|HGSS"] = "HGSS",
  ["choice|PMD"] = "PMD",
  ["choice|R"] = "R",
  ["choice|L"] = "L",
  ["choice|E (R)"] = "E (R)",
  ["choice|Q (L)"] = "Q (L)",
  ["choice|UNDISCOVERED"] = "UNENTDECKT",
  ["choice|ALL"] = "ALLE",
  ["toggle|ON"] = "AN",
  ["toggle|OFF"] = "AUS",

  -- options: descriptions
  ["The language of Wilds of Hoenn's own text: these options, your partner's words, its menus and the labels over it. The game's own text is not changed. Japanese is written in kana, like the original Japanese games."] =
    "Die Sprache der eigenen Texte von Wilds of Hoenn: diese Optionen, die Worte deines Partners, seine Menüs und die Schilder über ihm. Die Texte des Spiels selbst bleiben unverändert. Japanisch steht in Kana, wie in den japanischen Originalspielen.",
  ["Spawn visible wild Pokemon in eligible grass/water encounter areas."] =
    "Zeigt wilde Pokémon sichtbar in den Gras- und Wassergebieten, in denen sie vorkommen.",
  ["How many wild Pokemon are out at once, for grass and water each, growing with the size of the area. Low: about half (up to 4). Normal: up to 8. High: about one and a half times (up to 12)."] =
    "Wie viele wilde Pokémon gleichzeitig unterwegs sind, im Gras und im Wasser, je nach Größe des Gebiets. Niedrig: etwa die Hälfte (bis zu 4). Normal: bis zu 8. Hoch: etwa anderthalbmal so viele (bis zu 12).",
  ["Flying Pokemon in the sky: birds of the area pass overhead, perch on trees, roofs and signposts, and real sea birds dive for food; wild Flying-type Pokemon swoop down to land (and take off again) instead of rising out of the grass. Full: all of it, with big soft-focus birds flying high overhead. Ambient: the same without the high birds. Off: none of it, wild Pokemon all arrive the usual way."] =
    "Fliegende Pokémon am Himmel: Vögel der Gegend ziehen vorbei, sitzen auf Bäumen, Dächern und Schildern, und echte Seevögel tauchen nach Futter; wilde Pokémon vom Typ Flug landen aus der Luft (und fliegen wieder auf), statt aus dem Gras aufzutauchen. Voll: alles, auch große unscharfe Vögel hoch oben. Umgebung: dasselbe ohne die hohen Vögel. Aus: nichts davon.",
  ["Life in the water, just for the scenery: small fish of the area (Magikarp, Goldeen, Luvdisc ...) leap out of the water and splash back in, and Wailmer and Wailord surface for a while, blowing a spray, before sinking back under. Out at sea, Finizen porpoise by now and then (once in a while a whole pod comes up to play). Diving, fish swim by under the sea as dark shadows trailing bubbles. Never battled."] =
    "Leben im Wasser, nur zur Kulisse: kleine Fische der Gegend (Karpador, Goldini, Liebiskus ...) springen aus dem Wasser und platschen zurück, und Wailmer und Wailord tauchen eine Weile auf und blasen eine Fontäne, bevor sie wieder abtauchen. Auf dem Meer springt ab und zu ein Normifin (manchmal kommt eine ganze Schule zum Spielen). Beim Tauchen ziehen Fische als dunkle Schatten mit Blasen vorbei. Kein Kampf.",
  ["Little moments in a few special places: ghosts drift through Lavender Town, bug Pokemon dangle from the trees of Petalburg Woods where Slakoth naps and Vigoroth dances on the treetops, and a great Tropius rises out of Fortree's trees. Just for the scenery."] =
    "Kleine Momente an besonderen Orten: Geister schweben durch Lavandia, Käfer-Pokémon hängen von den Bäumen im Blütenburgwald, wo Bummelz ein Nickerchen macht und Muntier auf den Baumkronen tanzt, und ein großes Tropius steigt aus den Bäumen von Baumhausen. Nur zur Kulisse.",
  ["Run or bike close to wild Pokemon and they react: weaker ones than your lead Pokemon are startled and run off (small birds fly away), stronger ones get angry and chase you (catching you starts the battle). Walking past disturbs nobody. Off: they just wander."] =
    "Renne oder fahre nah an wilden Pokémon vorbei, und sie reagieren: schwächere als dein erstes Pokémon erschrecken und laufen weg (kleine Vögel fliegen davon), stärkere werden wütend und jagen dich (holen sie dich ein, beginnt der Kampf). Wer geht, stört niemanden. Aus: sie streifen nur umher.",
  ["Overworld sprite style for wild Pokemon and your follower. HGSS / PokeMMO draws each species at its own native size (\"True Size\"), anchored at its feet -- a Snorlax is drawn much bigger than a Rattata."] =
    "Sprite-Stil für wilde Pokémon und deinen Begleiter. HGSS / PokeMMO zeichnet jede Art in ihrer echten Größe, an den Füßen verankert: ein Relaxo ist viel größer als ein Rattfratz.",
  ["PMDCollab uses the PMD Explorers-style sprites with fully animated walking and idle loops (species without PMD art fall back to HGSS / PokeMMO)."] =
    "PMDCollab nutzt Sprites im Stil von Mystery Dungeon, mit voll animiertem Laufen und Stehen (Arten ohne PMD-Grafik nutzen HGSS / PokeMMO).",
  ["Your partner Pokemon walks behind you. Off: it stays in its Poke Ball (its Battle and Forage jobs and Pet / Play / Talk wait until it is out again). Changing your party order still changes who your partner is."] =
    "Dein Partner-Pokémon läuft hinter dir her. Aus: es bleibt in seinem Pokéball (Kämpfen und Suchen sowie Streicheln / Spielen / Reden warten, bis es wieder draußen ist). Eine neue Team-Reihenfolge wechselt weiterhin deinen Partner.",
  ["A controller shoulder button that switches your partner between Battle and Follow while you walk around -- you call it out like a trainer in battle ('Go! Mudkip!', 'Come back, Mudkip!'). In FireRed / LeafGreen that button then no longer opens Help in the overworld; the other shoulder still does."] =
    "Eine Schultertaste des Controllers, die deinen Partner beim Laufen zwischen Kämpfen und Folgen wechselt: du rufst ihn wie ein Trainer im Kampf ('Los, Hydropi!', 'Zurück, Hydropi!'). In Feuerrot / Blattgrün öffnet diese Taste dann außerhalb von Kämpfen keine Hilfe mehr; die andere schon.",
  ["The keyboard key that switches your partner between Battle and Follow while you walk around. E and Q are the game's R and L buttons (in FireRed / LeafGreen that one then no longer opens Help in the overworld); R is a free key."] =
    "Die Taste, die deinen Partner beim Laufen zwischen Kämpfen und Folgen wechselt. E und Q sind die R- und L-Tasten des Spiels (in Feuerrot / Blattgrün öffnet diese Taste dann außerhalb von Kämpfen keine Hilfe mehr); R ist eine freie Taste.",
  ["Your partner is always spaced out behind you by its size. On: it glides round when you turn. Off: it snaps straight to its place behind you, step for step like the original games."] =
    "Dein Partner hält immer einen Abstand hinter dir, passend zu seiner Größe. An: er gleitet in Kurven sanft herum. Aus: er springt direkt an seinen Platz hinter dir, Schritt für Schritt wie in den Originalspielen.",
  ["Now and then your partner gives off a little puff of its type: embers from a Fire type, droplets from a Water type, leaves, sparks, snow, wisps ... Off: only while you Pet, Play or Talk with it."] =
    "Ab und zu gibt dein Partner einen kleinen Hauch seines Typs ab: Funken bei Typ Feuer, Tropfen bei Typ Wasser, Blätter, Blitze, Schnee, Irrlichter ... Aus: nur beim Streicheln, Spielen oder Reden.",
  ["Classic Encounters: the original step-based random encounters in grass and water (Surf). Visible wild Pokemon stay active either way. Fishing and Rock Smash are unaffected."] =
    "Zufallskämpfe: die originalen zufälligen Begegnungen beim Laufen im Gras und beim Surfen. Sichtbare wilde Pokémon bleiben so oder so aktiv. Angeln und Zertrümmerer sind nicht betroffen.",
  ["Off keeps normal colours. Undiscovered silhouettes species not yet caught in your Pokedex. All silhouettes every visible wild Pokemon."] =
    "Aus: normale Farben. Unentdeckt: Arten, die du im Pokédex noch nicht gefangen hast, als Silhouette. Alle: jedes sichtbare wilde Pokémon als Silhouette.",
  ["Draw each species at its own size next to you, in either sprite style: small ones knee-high, giants towering over you. Needs the Gen 3 HD Sprites mod (with its Field HD option on); without it every species is drawn at its sheet's size."] =
    "Zeichnet jede Art neben dir in ihrer eigenen Größe, in beiden Stilen: kleine reichen bis zum Knie, Riesen überragen dich. Braucht die Mod Gen 3 HD Sprites (mit eingeschalteter Field HD-Option); ohne sie wird jede Art in der Größe ihres Bildes gezeichnet.",
  ["Your partner's PMDCollab portrait above its messages when you Pet, Play or Talk with it. Off: the messages show without it."] =
    "Das PMDCollab-Porträt deines Partners über seinen Nachrichten beim Streicheln, Spielen oder Reden. Aus: die Nachrichten erscheinen ohne Porträt.",

  -- the partner's menu
  ["menu|Interact"] = "Interagieren",
  ["menu|Role"] = "Rolle",
  ["menu|Recall"] = "Zurückrufen",
  ["menu|Cancel"] = "Abbrechen",
  ["menu|Pet"] = "Streicheln",
  ["menu|Play"] = "Spielen",
  ["menu|Talk"] = "Reden",
  ["menu|Back"] = "Zurück",
  ["menu|Follow"] = "Folgen",
  ["menu|Forage"] = "Suchen",
  ["menu|Fight"] = "Kämpfen",
  ["menu|Evolve"] = "Entwickeln",
  ["menu|Learn Move"] = "Attacke lernen",

  -- the party menu (80 px box; ROLE leaves room for its arrow)
  ["party|ROLE"] = "ROLLE",
  ["party|BACK"] = "ZURÜCK",
  ["party|FOLLOW"] = "FOLGEN",
  ["party|FORAGE"] = "SUCHEN",
  ["party|FIGHT"] = "KÄMPFEN",

  -- messages and labels
  ["%s returned to you."] = "%s ist zu dir zurückgekehrt.",
  ["%s will follow you."] = "%s folgt dir.",
  ["%s will battle wild Pokemon for you."] = "%s kämpft für dich gegen wilde Pokémon.",
  ["%s will forage for items."] = "%s sucht nach Items.",
  ["%s can't do that right now."] = "%s kann das gerade nicht.",
  ["%s has nothing to do right now."] = "%s hat gerade nichts zu tun.",
  ["%s is already doing that."] = "%s macht das schon.",
  ["Nothing happened."] = "Nichts ist passiert.",
  ["Found %s!"] = "%s gefunden!",
  ["an item"] = "ein Item",
  ["+%d EXP"] = "+%d EP",
  ["Lv.%d!"] = "Lv.%d!",
  ["New move ready!"] = "Neue Attacke!",
  ["Ready to evolve!"] = "Bereit zur Entwicklung!",
  ["POKeMON"] = "POKéMON",

  -- the partner's words (two lines at most; {name} is its name)
  ["{name} can barely keep\nits eyes open..."] = "{name} kann kaum noch\ndie Augen offen halten ...",
  ["{name} is in a bad way\nand looks close to tears."] = "{name} geht es schlecht,\nes ist den Tränen nahe.",
  ["{name} is hurting badly.\nIt needs help soon!"] = "{name} hat starke Schmerzen.\nEs braucht bald Hilfe!",
  ["{name} is poisoned and\nlooks miserable."] = "{name} ist vergiftet\nund sieht elend aus.",
  ["{name} winces. The poison\nis really bothering it."] = "{name} zuckt zusammen.\nDas Gift setzt ihm zu.",
  ["{name} is burned and\nyelping in pain!"] = "{name} hat Verbrennungen\nund jault vor Schmerz!",
  ["{name} is scorched and\ncan't settle down."] = "{name} ist versengt\nund kommt nicht zur Ruhe.",
  ["{name} is paralyzed and\ncan hardly move."] = "{name} ist paralysiert\nund kann sich kaum rühren.",
  ["{name} twitches. Its body\nwon't listen to it."] = "{name} zuckt. Sein Körper\ngehorcht ihm nicht.",
  ["{name} is frozen stiff\nand shivering."] = "{name} ist steif gefroren\nund zittert.",
  ["{name} is encased in ice\nand looks stunned."] = "{name} steckt im Eis\nund wirkt benommen.",
  ["{name} is half asleep\nand swaying a little."] = "{name} ist im Halbschlaf\nund schwankt ein wenig.",
  ["{name} can barely stay\nawake right now."] = "{name} kann sich gerade\nkaum wach halten.",
  ["{name} is hurt and\nlooks uneasy."] = "{name} ist verletzt\nund wirkt unruhig.",
  ["{name} is limping and\nwinces when it moves."] = "{name} humpelt und zuckt\nbei jeder Bewegung.",
  ["{name} looks a bit\nworried about its wounds."] = "{name} sorgt sich etwas\num seine Wunden.",
  ["{name} is a little banged\nup and keeping close."] = "{name} ist etwas lädiert\nund bleibt dicht bei dir.",
  ["{name} glares at you.\nIt doesn't trust you yet."] = "{name} funkelt dich an.\nEs traut dir noch nicht.",
  ["{name} snorts and looks\nreally annoyed."] = "{name} schnaubt und wirkt\nrichtig genervt.",
  ["{name} looks down and\nkeeps its distance."] = "{name} schaut zu Boden\nund hält Abstand.",
  ["{name} sighs. It seems\na little lonely."] = "{name} seufzt. Es wirkt\nein wenig einsam.",
  ["{name} looks up at you\ncalmly."] = "{name} schaut ruhig\nzu dir auf.",
  ["{name} is watching you,\nwaiting to see what's next."] = "{name} beobachtet dich\nund wartet, was kommt.",
  ["{name} seems to be in\ngood spirits!"] = "{name} scheint\nguter Laune zu sein!",
  ["{name} wags along happily,\nglad you're here."] = "{name} ist ganz fröhlich,\nfroh, dass du da bist.",
  ["{name} is happy, though\na little sore."] = "{name} ist fröhlich,\naber etwas wund.",
  ["{name} smiles, but it's\nfavouring a sore spot."] = "{name} lächelt, schont aber\neine wunde Stelle.",
  ["{name} is overjoyed to\nsee you!"] = "{name} freut sich riesig,\ndich zu sehen!",
  ["{name} is beaming with\njoy!"] = "{name} strahlt\nvor Freude!",
  ["{name} is brimming with\nenergy and bonds!"] = "{name} sprüht vor\nEnergie und Zuneigung!",
  ["{name} is full of life.\nIt loves you dearly!"] = "{name} ist voller Leben.\nEs hat dich sehr lieb!",
  ["{name} is hunched over.\nIt's a bit cramped here."] = "{name} ist ganz geduckt.\nHier ist es etwas eng.",
  ["{name} shuffles about.\nThis spot is too tight!"] = "{name} rutscht hin und her.\nHier ist es zu eng!",
  ["{name} eyes the roof.\nIt wants more room."] = "{name} beäugt das Dach.\nEs will mehr Platz.",
  ["{name} nudges you.\nIt'd like to move on."] = "{name} stupst dich an.\nEs will weiter.",
  ["You pet {name}.\nIt leans into your hand!"] = "Du streichelst {name}.\nEs schmiegt sich an!",
  ["You stroke {name}.\nIt closes its eyes happily."] = "Du streichelst {name}.\nEs schließt glücklich die Augen.",
  ["You played with {name}!\nIt's having a blast!"] = "Du spielst mit {name}!\nEs hat riesigen Spaß!",
  ["You and {name} romp\naround together!"] = "Du und {name} tollt\nzusammen herum!",
  ["You talked with {name}.\nIt listens closely."] = "Du redest mit {name}.\nEs hört genau zu.",
  ["You chat with {name}.\nIt seems to understand."] = "Du plauderst mit {name}.\nEs scheint zu verstehen.",
  ["You gently pet {name}.\nIt takes comfort in it."] = "Du streichelst {name} sanft.\nDas tröstet es.",
  ["{name} tries to play,\nbut it's hurting."] = "{name} will spielen,\naber es hat Schmerzen.",
  ["You talk softly to\n{name}. It listens."] = "Du sprichst leise mit\n{name}. Es hört zu.",
  ["{name} is hurt and\ncan't play."] = "{name} ist verletzt\nund kann nicht spielen.",
  ["{name} is sick and\ncan't play."] = "{name} ist krank\nund kann nicht spielen.",
  ["{name} is paralyzed and\ncan't play."] = "{name} ist paralysiert\nund kann nicht spielen.",
  ["{name} is too cold and\ncan't play."] = "{name} ist zu kalt\nzum Spielen.",
  ["{name} is burning and\ncan't play."] = "{name} brennt\nund kann nicht spielen.",
  ["{name} is asleep and\ncan't play."] = "{name} schläft\nund kann nicht spielen.",
  ["{name} feels better now!"] = "{name} geht es jetzt besser!",
  ["{name} is wary of\nyou..."] = "{name} ist misstrauisch\ndir gegenüber ...",
  ["{name} is curious\nabout you!"] = "{name} ist neugierig\nauf dich!",
  ["{name} is starting\nto like you!"] = "{name} fängt an,\ndich zu mögen!",
  ["{name} trusts you!"] = "{name} vertraut dir!",
  ["{name} really likes\nyou!"] = "{name} mag dich\nwirklich gern!",
  ["{name} loves you!"] = "{name} liebt dich!",
  ["{name} is already as\nhappy as can be!"] = "{name} könnte gar nicht\nglücklicher sein!",
  ["{name} couldn't possibly\nbe any fonder of you!"] = "{name} könnte dich gar\nnicht mehr lieb haben!",
  ["{name} isn't in the\nmood right now."] = "{name} ist gerade\nnicht in Stimmung.",
  ["{name} looks away.\nGive it a moment."] = "{name} schaut weg.\nGib ihm einen Moment.",
  ["{name} has had plenty of\nattention for now."] = "{name} hatte erst mal\ngenug Aufmerksamkeit.",
  ["{name} seems worn out\nfrom all the fuss."] = "{name} wirkt erschöpft\nvon dem ganzen Trubel.",
  ["{name} is fed up!\nIt turns its back on you."] = "{name} hat genug!\nEs dreht dir den Rücken zu.",
  ["{name} wants some space.\nTry again later."] = "{name} braucht Abstand.\nVersuch es später noch mal.",
  ["{name} ignores you.\nIt needs some time alone."] = "{name} ignoriert dich.\nEs will allein sein.",

  -- the trainer call-outs (one "|" break each, %s = the partner's name)
  ["list:send"] = {
    "Los,|%s!", "Schnapp sie dir,|%s!", "Zeig, was du|drauf hast!", "Auf geht's,|%s!",
    "Gib alles,|%s!", "Du bist dran,|%s!", "Vorwärts,|%s!", "Dein Auftritt,|%s!",
    "Mach sie fertig,|%s!", "Volle Kraft,|%s!",
  },
  ["list:recall"] = {
    "Das reicht,|%s!", "Zurück,|%s!", "%s, gut gemacht!|Zurück!", "Prima,|%s!",
    "Ruh dich aus,|%s!", "%s, okay!|Zurück!", "Zu mir,|%s!", "Gut gemacht,|%s!",
    "Genug jetzt,|%s!", "Super!|Zurück, %s!",
  },
}
