-- Spanish (español). Keys are the English text (lib/i18n.lua); "<context>|..." keys for
-- option / choice / menu / party rows. tests/i18n_coverage_unit_test.lua checks every
-- key is here. Wording follows the official Spanish releases (Pokémon, Poké Ball,
-- Pokédex, Nv. for the level).
return {
  -- options: labels
  ["option|Language"] = "Idioma",
  ["option|Show Wild Mons"] = "Ver salvajes",
  ["option|Spawn Amount"] = "Cantidad",
  ["option|Flying Mons"] = "Voladores",
  ["option|Water Life"] = "Vida acuática",
  ["option|Local Scenes"] = "Escenas",
  ["option|Wild Reacts"] = "Reacciones",
  ["option|Sprite Style"] = "Estilo sprite",
  ["option|Follower"] = "Acompañante",
  ["option|Battler: Pad"] = "Lucha: mando",
  ["option|Battler: Key"] = "Lucha: tecla",
  ["option|Smooth Follow"] = "Seguir suave",
  ["option|Type Aura"] = "Aura de tipo",
  ["option|Classic Enc"] = "Enc. clásicos",
  ["option|Silhouette"] = "Silueta",
  ["option|Species Sizes"] = "Tamaños",
  ["option|Portraits"] = "Retratos",

  -- options: choices
  ["choice|LOW"] = "BAJO",
  ["choice|NORMAL"] = "NORMAL",
  ["choice|HIGH"] = "ALTO",
  ["choice|FULL"] = "COMPLETO",
  ["choice|AMBIENT"] = "AMBIENTE",
  ["choice|OFF"] = "NO",
  ["choice|HGSS"] = "HGSS",
  ["choice|PMD"] = "PMD",
  ["choice|R"] = "R",
  ["choice|L"] = "L",
  ["choice|E (R)"] = "E (R)",
  ["choice|Q (L)"] = "Q (L)",
  ["choice|UNDISCOVERED"] = "SIN CAPTURAR",
  ["choice|ALL"] = "TODOS",
  ["toggle|ON"] = "SÍ",
  ["toggle|OFF"] = "NO",

  -- options: descriptions
  ["The language of Wilds of Hoenn's own text: these options, your partner's words, its menus and the labels over it. The game's own text is not changed. Japanese is written in kana, like the original Japanese games."] =
    "El idioma de los textos de Wilds of Hoenn: estas opciones, las palabras de tu compañero, sus menús y los rótulos sobre él. Los textos del juego no cambian. El japonés se escribe en kana, como en los juegos japoneses originales.",
  ["Spawn visible wild Pokemon in eligible grass/water encounter areas."] =
    "Muestra Pokémon salvajes visibles en las zonas de hierba y agua donde aparecen.",
  ["How many wild Pokemon are out at once, for grass and water each, growing with the size of the area. Low: about half (up to 4). Normal: up to 8. High: about one and a half times (up to 12)."] =
    "Cuántos Pokémon salvajes hay a la vez, en hierba y en agua, según el tamaño de la zona. Bajo: más o menos la mitad (hasta 4). Normal: hasta 8. Alto: una vez y media (hasta 12).",
  ["Flying Pokemon in the sky: birds of the area pass overhead, perch on trees, roofs and signposts, and real sea birds dive for food; wild Flying-type Pokemon swoop down to land (and take off again) instead of rising out of the grass. Full: all of it, with big soft-focus birds flying high overhead. Ambient: the same without the high birds. Off: none of it, wild Pokemon all arrive the usual way."] =
    "Pokémon voladores en el cielo: las aves de la zona pasan por encima, se posan en árboles, tejados y carteles, y las aves marinas se lanzan al agua a pescar; los Pokémon salvajes de tipo Volador bajan del cielo (y vuelven a despegar) en vez de salir de la hierba. Completo: todo, con grandes aves desenfocadas volando muy alto. Ambiente: lo mismo sin las aves altas. No: nada de esto.",
  ["Life in the water, just for the scenery: small fish of the area (Magikarp, Goldeen, Luvdisc ...) leap out of the water and splash back in, and Wailmer and Wailord surface for a while, blowing a spray, before sinking back under. Out at sea, Finizen porpoise by now and then (once in a while a whole pod comes up to play). Diving, fish swim by under the sea as dark shadows trailing bubbles. Never battled."] =
    "Vida en el agua, solo de ambiente: los peces de la zona (Magikarp, Goldeen, Luvdisc...) saltan fuera del agua y vuelven a caer, y Wailmer y Wailord salen a la superficie un rato, echando un chorro, antes de hundirse. En el mar, algún Finizen salta de vez en cuando (y a veces llega todo un grupo a jugar). Buceando, los peces pasan bajo el mar como sombras oscuras con burbujas. Nunca se lucha con ellos.",
  ["Little moments in a few special places: ghosts drift through Lavender Town, bug Pokemon dangle from the trees of Petalburg Woods where Slakoth naps and Vigoroth dances on the treetops, and a great Tropius rises out of Fortree's trees. Just for the scenery."] =
    "Pequeños momentos en algunos lugares especiales: fantasmas que flotan por Pueblo Lavanda, Pokémon bicho colgando de los árboles del Bosque Petalia, donde Slakoth duerme la siesta y Vigoroth baila en las copas, y un gran Tropius que surge de los árboles de Arborada. Solo de ambiente.",
  ["Run or bike close to wild Pokemon and they react: weaker ones than your lead Pokemon are startled and run off (small birds fly away), stronger ones get angry and chase you (catching you starts the battle). Walking past disturbs nobody. Off: they just wander."] =
    "Si pasas corriendo o en bici cerca de Pokémon salvajes, reaccionan: los más débiles que tu primer Pokémon se asustan y huyen (las aves pequeñas salen volando) y los más fuertes se enfadan y te persiguen (si te alcanzan, empieza el combate). Andando no molestas a nadie. No: solo deambulan.",
  ["Overworld sprite style for wild Pokemon and your follower. HGSS / PokeMMO draws each species at its own native size (\"True Size\"), anchored at its feet -- a Snorlax is drawn much bigger than a Rattata."] =
    "Estilo de los sprites de los Pokémon salvajes y de tu compañero. HGSS / PokeMMO dibuja cada especie a su tamaño real, apoyada en sus pies: un Snorlax se ve mucho más grande que un Rattata.",
  ["PMDCollab uses the PMD Explorers-style sprites with fully animated walking and idle loops (species without PMD art fall back to HGSS / PokeMMO)."] =
    "PMDCollab usa sprites al estilo de Mundo Misterioso, con el andar y la espera totalmente animados (las especies sin arte PMD usan HGSS / PokeMMO).",
  ["Your partner Pokemon walks behind you. Off: it stays in its Poke Ball (its Battle and Forage jobs and Pet / Play / Talk wait until it is out again). Changing your party order still changes who your partner is."] =
    "Tu Pokémon compañero camina detrás de ti. No: se queda en su Poké Ball (sus papeles de luchar y buscar, y acariciar / jugar / hablar, esperan a que salga). Cambiar el orden del equipo sigue cambiando quién es tu compañero.",
  ["A controller shoulder button that switches your partner between Battle and Follow while you walk around -- you call it out like a trainer in battle ('Go! Mudkip!', 'Come back, Mudkip!'). In FireRed / LeafGreen that button then no longer opens Help in the overworld; the other shoulder still does."] =
    "Un gatillo del mando que cambia a tu compañero entre luchar y seguirte mientras caminas: lo llamas como un entrenador en combate ('¡Adelante, Mudkip!', '¡Vuelve, Mudkip!'). En Rojo Fuego / Verde Hoja ese botón ya no abre la Ayuda fuera de combate; el otro sí.",
  ["The keyboard key that switches your partner between Battle and Follow while you walk around. E and Q are the game's R and L buttons (in FireRed / LeafGreen that one then no longer opens Help in the overworld); R is a free key."] =
    "La tecla que cambia a tu compañero entre luchar y seguirte mientras caminas. E y Q son los botones R y L del juego (en Rojo Fuego / Verde Hoja ese botón ya no abre la Ayuda fuera de combate); R es una tecla libre.",
  ["Your partner is always spaced out behind you by its size. On: it glides round when you turn. Off: it snaps straight to its place behind you, step for step like the original games."] =
    "Tu compañero siempre va detrás de ti a una distancia según su tamaño. Sí: gira con suavidad al cambiar de dirección. No: se coloca directamente detrás de ti, paso a paso, como en los juegos originales.",
  ["Now and then your partner gives off a little puff of its type: embers from a Fire type, droplets from a Water type, leaves, sparks, snow, wisps ... Off: only while you Pet, Play or Talk with it."] =
    "De vez en cuando tu compañero suelta un soplo de su tipo: ascuas si es de tipo Fuego, gotas si es de tipo Agua, hojas, chispas, nieve, fuegos fatuos... No: solo al acariciarlo, jugar o hablar con él.",
  ["Classic Encounters: the original step-based random encounters in grass and water (Surf). Visible wild Pokemon stay active either way. Fishing and Rock Smash are unaffected."] =
    "Encuentros clásicos: los encuentros aleatorios originales al andar por la hierba o al hacer Surf. Los Pokémon salvajes visibles siguen activos igualmente. La pesca y Golpe Roca no cambian.",
  ["Off keeps normal colours. Undiscovered silhouettes species not yet caught in your Pokedex. All silhouettes every visible wild Pokemon."] =
    "No: colores normales. Sin capturar: muestra en silueta las especies que aún no has capturado en la Pokédex. Todos: muestra en silueta a todos los Pokémon salvajes visibles.",
  ["Draw each species at its own size next to you, in either sprite style: small ones knee-high, giants towering over you. Needs the Gen 3 HD Sprites mod (with its Field HD option on); without it every species is drawn at its sheet's size."] =
    "Dibuja cada especie a su tamaño junto a ti, en cualquier estilo: los pequeños a la altura de la rodilla, los gigantes muy por encima de ti. Necesita el mod Gen 3 HD Sprites (con su opción Field HD activada); sin él cada especie se dibuja al tamaño de su imagen.",
  ["Your partner's PMDCollab portrait above its messages when you Pet, Play or Talk with it. Off: the messages show without it."] =
    "El retrato PMDCollab de tu compañero sobre sus mensajes al acariciarlo, jugar o hablar con él. No: los mensajes salen sin él.",

  -- the partner's menu
  ["menu|Interact"] = "Interactuar",
  ["menu|Role"] = "Papel",
  ["menu|Recall"] = "Retirar",
  ["menu|Cancel"] = "Salir",
  ["menu|Pet"] = "Acariciar",
  ["menu|Play"] = "Jugar",
  ["menu|Talk"] = "Hablar",
  ["menu|Back"] = "Atrás",
  ["menu|Follow"] = "Seguir",
  ["menu|Forage"] = "Buscar",
  ["menu|Fight"] = "Luchar",
  ["menu|Evolve"] = "Evolucionar",
  ["menu|Learn Move"] = "Aprender mov.",

  -- the party menu (80 px box; ROLE leaves room for its arrow)
  ["party|ROLE"] = "ROL",
  ["party|BACK"] = "ATRÁS",
  ["party|FOLLOW"] = "SEGUIR",
  ["party|FORAGE"] = "BUSCAR",
  ["party|FIGHT"] = "LUCHAR",

  -- messages and labels
  ["%s returned to you."] = "%s ha vuelto contigo.",
  ["%s will follow you."] = "%s te seguirá.",
  ["%s will battle wild Pokemon for you."] = "%s luchará contra los Pokémon salvajes por ti.",
  ["%s will forage for items."] = "%s buscará objetos.",
  ["%s can't do that right now."] = "%s no puede hacer eso ahora.",
  ["%s has nothing to do right now."] = "%s no tiene nada que hacer ahora.",
  ["%s is already doing that."] = "%s ya está haciendo eso.",
  ["Nothing happened."] = "No ha pasado nada.",
  ["Found %s!"] = "¡Encontró %s!",
  ["an item"] = "un objeto",
  ["+%d EXP"] = "+%d EXP",
  ["Lv.%d!"] = "¡Nv.%d!",
  ["New move ready!"] = "¡Nuevo movimiento!",
  ["Ready to evolve!"] = "¡Listo para evolucionar!",
  ["POKeMON"] = "POKéMON",

  -- the partner's words (two lines at most; {name} is its name)
  ["{name} can barely keep\nits eyes open..."] = "A {name} casi se le\ncierran los ojos...",
  ["{name} is in a bad way\nand looks close to tears."] = "{name} está muy mal\ny parece a punto de llorar.",
  ["{name} is hurting badly.\nIt needs help soon!"] = "A {name} le duele mucho.\n¡Necesita ayuda pronto!",
  ["{name} is poisoned and\nlooks miserable."] = "{name} está envenenado\ny se le ve fatal.",
  ["{name} winces. The poison\nis really bothering it."] = "{name} hace una mueca.\nEl veneno le molesta mucho.",
  ["{name} is burned and\nyelping in pain!"] = "¡{name} está quemado\ny se queja de dolor!",
  ["{name} is scorched and\ncan't settle down."] = "{name} está chamuscado\ny no consigue calmarse.",
  ["{name} is paralyzed and\ncan hardly move."] = "{name} está paralizado\ny apenas puede moverse.",
  ["{name} twitches. Its body\nwon't listen to it."] = "{name} se estremece.\nSu cuerpo no le obedece.",
  ["{name} is frozen stiff\nand shivering."] = "{name} está congelado\ny tiembla.",
  ["{name} is encased in ice\nand looks stunned."] = "{name} está atrapado en hielo\ny parece aturdido.",
  ["{name} is half asleep\nand swaying a little."] = "{name} está medio dormido\ny se balancea un poco.",
  ["{name} can barely stay\nawake right now."] = "A {name} le cuesta\nmantenerse despierto.",
  ["{name} is hurt and\nlooks uneasy."] = "{name} está herido\ny parece inquieto.",
  ["{name} is limping and\nwinces when it moves."] = "{name} cojea y hace\nmuecas al moverse.",
  ["{name} looks a bit\nworried about its wounds."] = "{name} parece algo\npreocupado por sus heridas.",
  ["{name} is a little banged\nup and keeping close."] = "{name} está algo magullado\ny no se aparta de ti.",
  ["{name} glares at you.\nIt doesn't trust you yet."] = "{name} te fulmina con la\nmirada. Aún no se fía de ti.",
  ["{name} snorts and looks\nreally annoyed."] = "{name} resopla y parece\nmuy molesto.",
  ["{name} looks down and\nkeeps its distance."] = "{name} mira al suelo\ny guarda las distancias.",
  ["{name} sighs. It seems\na little lonely."] = "{name} suspira. Parece\nun poco solo.",
  ["{name} looks up at you\ncalmly."] = "{name} te mira\ncon calma.",
  ["{name} is watching you,\nwaiting to see what's next."] = "{name} te observa,\nesperando lo que viene.",
  ["{name} seems to be in\ngood spirits!"] = "¡{name} parece estar\nde buen humor!",
  ["{name} wags along happily,\nglad you're here."] = "{name} va muy contento,\nfeliz de que estés aquí.",
  ["{name} is happy, though\na little sore."] = "{name} está contento,\naunque algo dolorido.",
  ["{name} smiles, but it's\nfavouring a sore spot."] = "{name} sonríe, pero protege\nuna zona dolorida.",
  ["{name} is overjoyed to\nsee you!"] = "¡{name} está encantado\nde verte!",
  ["{name} is beaming with\njoy!"] = "¡{name} irradia\nalegría!",
  ["{name} is brimming with\nenergy and bonds!"] = "¡{name} rebosa\nenergía y cariño!",
  ["{name} is full of life.\nIt loves you dearly!"] = "{name} está lleno de vida.\n¡Te quiere muchísimo!",
  ["{name} is hunched over.\nIt's a bit cramped here."] = "{name} está encogido.\nAquí está algo apretado.",
  ["{name} shuffles about.\nThis spot is too tight!"] = "{name} no para quieto.\n¡Aquí no cabe!",
  ["{name} eyes the roof.\nIt wants more room."] = "{name} mira el tejado.\nQuiere más espacio.",
  ["{name} nudges you.\nIt'd like to move on."] = "{name} te da un empujón.\nQuiere seguir adelante.",
  ["You pet {name}.\nIt leans into your hand!"] = "Acaricias a {name}.\n¡Se apoya en tu mano!",
  ["You stroke {name}.\nIt closes its eyes happily."] = "Acaricias a {name}.\nCierra los ojos, feliz.",
  ["You played with {name}!\nIt's having a blast!"] = "¡Has jugado con {name}!\n¡Se lo está pasando genial!",
  ["You and {name} romp\naround together!"] = "¡{name} y tú\nretozáis juntos!",
  ["You talked with {name}.\nIt listens closely."] = "Hablas con {name}.\nTe escucha con atención.",
  ["You chat with {name}.\nIt seems to understand."] = "Charlas con {name}.\nParece que te entiende.",
  ["You gently pet {name}.\nIt takes comfort in it."] = "Acaricias con cuidado a\n{name}. Eso le reconforta.",
  ["{name} tries to play,\nbut it's hurting."] = "{name} intenta jugar,\npero le duele.",
  ["You talk softly to\n{name}. It listens."] = "Hablas en voz baja a\n{name}. Te escucha.",
  ["{name} is hurt and\ncan't play."] = "{name} está herido\ny no puede jugar.",
  ["{name} is sick and\ncan't play."] = "{name} está enfermo\ny no puede jugar.",
  ["{name} is paralyzed and\ncan't play."] = "{name} está paralizado\ny no puede jugar.",
  ["{name} is too cold and\ncan't play."] = "{name} tiene demasiado\nfrío para jugar.",
  ["{name} is burning and\ncan't play."] = "{name} está quemado\ny no puede jugar.",
  ["{name} is asleep and\ncan't play."] = "{name} está dormido\ny no puede jugar.",
  ["{name} feels better now!"] = "¡{name} ya se encuentra mejor!",
  ["{name} is wary of\nyou..."] = "{name} desconfía\nde ti...",
  ["{name} is curious\nabout you!"] = "¡{name} siente\ncuriosidad por ti!",
  ["{name} is starting\nto like you!"] = "¡{name} empieza\na apreciarte!",
  ["{name} trusts you!"] = "¡{name} confía en ti!",
  ["{name} really likes\nyou!"] = "¡{name} te aprecia\nmucho!",
  ["{name} loves you!"] = "¡{name} te adora!",
  ["{name} is already as\nhappy as can be!"] = "¡{name} ya no podría\nser más feliz!",
  ["{name} couldn't possibly\nbe any fonder of you!"] = "¡{name} no podría\nquererte más!",
  ["{name} isn't in the\nmood right now."] = "{name} no está de\nhumor ahora mismo.",
  ["{name} looks away.\nGive it a moment."] = "{name} aparta la mirada.\nDale un momento.",
  ["{name} has had plenty of\nattention for now."] = "{name} ya ha tenido\nbastante atención.",
  ["{name} seems worn out\nfrom all the fuss."] = "{name} parece agotado\nde tanto jaleo.",
  ["{name} is fed up!\nIt turns its back on you."] = "¡{name} está harto!\nTe da la espalda.",
  ["{name} wants some space.\nTry again later."] = "{name} quiere espacio.\nInténtalo más tarde.",
  ["{name} ignores you.\nIt needs some time alone."] = "{name} te ignora.\nNecesita estar solo.",

  -- the trainer call-outs (one "|" break each, %s = the partner's name)
  ["list:send"] = {
    "¡Adelante,|%s!", "¡A por ellos,|%s!", "¡Demuestra lo|que vales!", "¡Vamos,|%s!",
    "¡Ve a por todas,|%s!", "¡Te toca,|%s!", "¡Ánimo,|%s!", "¡Es tu turno,|%s!",
    "¡Derrótalos,|%s!", "¡Dalo todo,|%s!",
  },
  ["list:recall"] = {
    "¡Ya basta,|%s!", "¡Vuelve,|%s!", "¡Bien hecho, %s!|¡Vuelve!", "¡Buen trabajo,|%s!",
    "¡Descansa,|%s!", "¡Vale, %s!|¡Vuelve!", "¡Conmigo,|%s!", "¡Muy bien,|%s!",
    "¡Suficiente,|%s!", "¡Genial!|¡Vuelve, %s!",
  },
}
