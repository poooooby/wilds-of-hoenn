-- Portuguese (português, Brazilian). Keys are the English text (lib/i18n.lua);
-- "<context>|..." keys for option / choice / menu / party rows.
-- tests/i18n_coverage_unit_test.lua checks every key is here.
-- Written with its proper spelling: the Gen 3 font has no ã / õ (there was never a
-- Portuguese Gen 3 release), so lib/i18n.lua draws those as a / o (FONT_FALLBACK).
return {
  -- options: labels
  ["option|Language"] = "Idioma",
  ["option|Show Wild Mons"] = "Ver selvagens",
  ["option|Spawn Amount"] = "Quantidade",
  ["option|Flying Mons"] = "Voadores",
  ["option|Water Life"] = "Vida aquática",
  ["option|Local Scenes"] = "Cenas locais",
  ["option|Wild Reacts"] = "Reagir",
  ["option|Sprite Style"] = "Estilo sprite",
  ["option|Follower"] = "Companheiro",
  ["option|Battler: Pad"] = "Luta: controle",
  ["option|Battler: Key"] = "Luta: tecla",
  ["option|Smooth Follow"] = "Seguir suave",
  ["option|Type Aura"] = "Aura de tipo",
  ["option|Classic Enc"] = "Enc. clássicos",
  ["option|Silhouette"] = "Silhueta",
  ["option|Species Sizes"] = "Tamanhos",
  ["option|Portraits"] = "Retratos",

  -- options: choices
  ["choice|LOW"] = "BAIXO",
  ["choice|NORMAL"] = "NORMAL",
  ["choice|HIGH"] = "ALTO",
  ["choice|FULL"] = "COMPLETO",
  ["choice|AMBIENT"] = "AMBIENTE",
  ["choice|OFF"] = "DESLIGADO",
  ["choice|HGSS"] = "HGSS",
  ["choice|PMD"] = "PMD",
  ["choice|R"] = "R",
  ["choice|L"] = "L",
  ["choice|E (R)"] = "E (R)",
  ["choice|Q (L)"] = "Q (L)",
  ["choice|UNDISCOVERED"] = "INÉDITOS",
  ["choice|ALL"] = "TODOS",
  ["toggle|ON"] = "LIGADO",
  ["toggle|OFF"] = "DESLIGADO",

  -- options: descriptions
  ["The language of Wilds of Hoenn's own text: these options, your partner's words, its menus and the labels over it. The game's own text is not changed. Japanese is written in kana, like the original Japanese games."] =
    "O idioma dos textos do Wilds of Hoenn: estas opções, as falas do seu parceiro, os menus dele e as legendas acima dele. Os textos do próprio jogo não mudam. O japonês é escrito em kana, como nos jogos japoneses originais.",
  ["Spawn visible wild Pokemon in eligible grass/water encounter areas."] =
    "Mostra Pokémon selvagens visíveis nas áreas de grama e água onde eles aparecem.",
  ["How many wild Pokemon are out at once, for grass and water each, growing with the size of the area. Low: about half (up to 4). Normal: up to 8. High: about one and a half times (up to 12)."] =
    "Quantos Pokémon selvagens ficam à vista de uma vez, na grama e na água, conforme o tamanho da área. Baixo: cerca da metade (até 4). Normal: até 8. Alto: cerca de uma vez e meia (até 12).",
  ["Flying Pokemon in the sky: birds of the area pass overhead, perch on trees, roofs and signposts, and real sea birds dive for food; wild Flying-type Pokemon swoop down to land (and take off again) instead of rising out of the grass. Full: all of it, with big soft-focus birds flying high overhead. Ambient: the same without the high birds. Off: none of it, wild Pokemon all arrive the usual way."] =
    "Pokémon voadores no céu: as aves da área passam por cima, pousam em árvores, telhados e placas, e as aves marinhas mergulham atrás de comida; Pokémon selvagens do tipo Voador descem do céu para pousar (e decolam de novo) em vez de surgir da grama. Completo: tudo isso, com grandes aves desfocadas voando bem alto. Ambiente: o mesmo sem as aves altas. Desligado: nada disso.",
  ["Life in the water, just for the scenery: small fish of the area (Magikarp, Goldeen, Luvdisc ...) leap out of the water and splash back in, and Wailmer and Wailord surface for a while, blowing a spray, before sinking back under. Out at sea, Finizen porpoise by now and then (once in a while a whole pod comes up to play). Diving, fish swim by under the sea as dark shadows trailing bubbles. Never battled."] =
    "Vida na água, só para enfeitar: os peixinhos da área (Magikarp, Goldeen, Luvdisc...) saltam da água e caem de volta, e Wailmer e Wailord sobem à superfície por um tempo, soltando um jato, antes de afundar. No mar, um Finizen salta de vez em quando (e às vezes um grupo inteiro vem brincar). Mergulhando, os peixes passam sob o mar como sombras escuras com bolhas. Nunca há batalha com eles.",
  ["Little moments in a few special places: ghosts drift through Lavender Town, bug Pokemon dangle from the trees of Petalburg Woods where Slakoth naps and Vigoroth dances on the treetops, and a great Tropius rises out of Fortree's trees. Just for the scenery."] =
    "Pequenos momentos em alguns lugares especiais: fantasmas flutuam por Lavender Town, Pokémon inseto pendem das árvores de Petalburg Woods, onde Slakoth tira um cochilo e Vigoroth dança nas copas, e um grande Tropius surge das árvores de Fortree. Só para enfeitar.",
  ["Run or bike close to wild Pokemon and they react: weaker ones than your lead Pokemon are startled and run off (small birds fly away), stronger ones get angry and chase you (catching you starts the battle). Walking past disturbs nobody. Off: they just wander."] =
    "Passe correndo ou de bicicleta perto de Pokémon selvagens e eles reagem: os mais fracos que o seu primeiro Pokémon se assustam e fogem (as aves pequenas voam para longe), os mais fortes ficam bravos e perseguem você (se alcançarem, a batalha começa). Andando, você não incomoda ninguém. Desligado: eles só passeiam.",
  ["Overworld sprite style for wild Pokemon and your follower. HGSS / PokeMMO draws each species at its own native size (\"True Size\"), anchored at its feet -- a Snorlax is drawn much bigger than a Rattata."] =
    "Estilo dos sprites dos Pokémon selvagens e do seu parceiro. HGSS / PokeMMO desenha cada espécie no seu tamanho real, apoiada nos pés: um Snorlax aparece bem maior que um Rattata.",
  ["PMDCollab uses the PMD Explorers-style sprites with fully animated walking and idle loops (species without PMD art fall back to HGSS / PokeMMO)."] =
    "PMDCollab usa sprites no estilo Mystery Dungeon, com o andar e a espera totalmente animados (espécies sem arte PMD usam HGSS / PokeMMO).",
  ["Your partner Pokemon walks behind you. Off: it stays in its Poke Ball (its Battle and Forage jobs and Pet / Play / Talk wait until it is out again). Changing your party order still changes who your partner is."] =
    "Seu Pokémon parceiro anda atrás de você. Desligado: ele fica na Poké Ball (os papéis de lutar e buscar, e acariciar / brincar / conversar, esperam até ele sair). Mudar a ordem da equipe ainda muda quem é o seu parceiro.",
  ["A controller shoulder button that switches your partner between Battle and Follow while you walk around -- you call it out like a trainer in battle ('Go! Mudkip!', 'Come back, Mudkip!'). In FireRed / LeafGreen that button then no longer opens Help in the overworld; the other shoulder still does."] =
    "Um botão de ombro do controle que alterna o seu parceiro entre lutar e seguir enquanto você anda: você o chama como um treinador em batalha ('Vai, Mudkip!', 'Volta, Mudkip!'). Em FireRed / LeafGreen esse botão deixa de abrir a Ajuda fora de batalha; o outro ainda abre.",
  ["The keyboard key that switches your partner between Battle and Follow while you walk around. E and Q are the game's R and L buttons (in FireRed / LeafGreen that one then no longer opens Help in the overworld); R is a free key."] =
    "A tecla que alterna o seu parceiro entre lutar e seguir enquanto você anda. E e Q são os botões R e L do jogo (em FireRed / LeafGreen esse botão deixa de abrir a Ajuda fora de batalha); R é uma tecla livre.",
  ["Your partner is always spaced out behind you by its size. On: it glides round when you turn. Off: it snaps straight to its place behind you, step for step like the original games."] =
    "Seu parceiro sempre fica atrás de você a uma distância conforme o tamanho. Ligado: ele contorna com suavidade quando você vira. Desligado: ele vai direto para o lugar atrás de você, passo a passo, como nos jogos originais.",
  ["Now and then your partner gives off a little puff of its type: embers from a Fire type, droplets from a Water type, leaves, sparks, snow, wisps ... Off: only while you Pet, Play or Talk with it."] =
    "De vez em quando o seu parceiro solta um sopro do seu tipo: brasas se for do tipo Fogo, gotas se for do tipo Água, folhas, faíscas, neve, fogos-fátuos... Desligado: só quando você acaricia, brinca ou conversa com ele.",
  ["Classic Encounters: the original step-based random encounters in grass and water (Surf). Visible wild Pokemon stay active either way. Fishing and Rock Smash are unaffected."] =
    "Encontros clássicos: os encontros aleatórios originais ao andar pela grama ou usar Surf. Os Pokémon selvagens visíveis continuam ativos de qualquer forma. A pesca e o Rock Smash não mudam.",
  ["Off keeps normal colours. Undiscovered silhouettes species not yet caught in your Pokedex. All silhouettes every visible wild Pokemon."] =
    "Desligado: cores normais. Inéditos: mostra em silhueta as espécies que você ainda não capturou na Pokédex. Todos: mostra em silhueta todos os Pokémon selvagens visíveis.",
  ["Draw each species at its own size next to you, in either sprite style: small ones knee-high, giants towering over you. Needs the Gen 3 HD Sprites mod (with its Field HD option on); without it every species is drawn at its sheet's size."] =
    "Desenha cada espécie no seu tamanho ao seu lado, em qualquer estilo: os pequenos na altura do joelho, os gigantes bem acima de você. Precisa do mod Gen 3 HD Sprites (com a opção Field HD ligada); sem ele cada espécie é desenhada no tamanho da imagem.",
  ["Your partner's PMDCollab portrait above its messages when you Pet, Play or Talk with it. Off: the messages show without it."] =
    "O retrato PMDCollab do seu parceiro acima das mensagens quando você acaricia, brinca ou conversa com ele. Desligado: as mensagens aparecem sem ele.",

  -- the partner's menu
  ["menu|Interact"] = "Interagir",
  ["menu|Role"] = "Papel",
  ["menu|Recall"] = "Recolher",
  ["menu|Cancel"] = "Cancelar",
  ["menu|Pet"] = "Acariciar",
  ["menu|Play"] = "Brincar",
  ["menu|Talk"] = "Conversar",
  ["menu|Back"] = "Voltar",
  ["menu|Follow"] = "Seguir",
  ["menu|Forage"] = "Buscar",
  ["menu|Fight"] = "Lutar",
  ["menu|Evolve"] = "Evoluir",
  ["menu|Learn Move"] = "Aprender golpe",

  -- the party menu (80 px box; ROLE leaves room for its arrow)
  ["party|ROLE"] = "PAPEL",
  ["party|BACK"] = "VOLTAR",
  ["party|FOLLOW"] = "SEGUIR",
  ["party|FORAGE"] = "BUSCAR",
  ["party|FIGHT"] = "LUTAR",

  -- messages and labels
  ["%s returned to you."] = "%s voltou para você.",
  ["%s will follow you."] = "%s vai seguir você.",
  ["%s will battle wild Pokemon for you."] = "%s vai lutar contra Pokémon selvagens por você.",
  ["%s will forage for items."] = "%s vai procurar itens.",
  ["%s can't do that right now."] = "%s não pode fazer isso agora.",
  ["%s has nothing to do right now."] = "%s não tem nada para fazer agora.",
  ["%s is already doing that."] = "%s já está fazendo isso.",
  ["Nothing happened."] = "Nada aconteceu.",
  ["Found %s!"] = "Achou %s!",
  ["an item"] = "um item",
  ["+%d EXP"] = "+%d EXP",
  ["Lv.%d!"] = "Nv.%d!",
  ["New move ready!"] = "Novo golpe!",
  ["Ready to evolve!"] = "Pronto p/ evoluir!",
  ["POKeMON"] = "POKéMON",

  -- the partner's words (two lines at most; {name} is its name)
  ["{name} can barely keep\nits eyes open..."] = "{name} mal consegue\nmanter os olhos abertos...",
  ["{name} is in a bad way\nand looks close to tears."] = "{name} está muito mal\ne parece prestes a chorar.",
  ["{name} is hurting badly.\nIt needs help soon!"] = "{name} está muito ferido.\nPrecisa de ajuda logo!",
  ["{name} is poisoned and\nlooks miserable."] = "{name} está envenenado\ne parece péssimo.",
  ["{name} winces. The poison\nis really bothering it."] = "{name} faz careta. O veneno\nestá incomodando muito.",
  ["{name} is burned and\nyelping in pain!"] = "{name} está queimado\ne gemendo de dor!",
  ["{name} is scorched and\ncan't settle down."] = "{name} está chamuscado\ne não consegue se acalmar.",
  ["{name} is paralyzed and\ncan hardly move."] = "{name} está paralisado\ne mal consegue se mexer.",
  ["{name} twitches. Its body\nwon't listen to it."] = "{name} treme. O corpo\nnão obedece.",
  ["{name} is frozen stiff\nand shivering."] = "{name} está congelado\ne tremendo.",
  ["{name} is encased in ice\nand looks stunned."] = "{name} está preso no gelo\ne parece atordoado.",
  ["{name} is half asleep\nand swaying a little."] = "{name} está meio dormindo\ne balança um pouco.",
  ["{name} can barely stay\nawake right now."] = "{name} mal consegue\nficar acordado agora.",
  ["{name} is hurt and\nlooks uneasy."] = "{name} está ferido\ne parece inquieto.",
  ["{name} is limping and\nwinces when it moves."] = "{name} está mancando e\nfaz careta ao se mexer.",
  ["{name} looks a bit\nworried about its wounds."] = "{name} parece um pouco\npreocupado com os ferimentos.",
  ["{name} is a little banged\nup and keeping close."] = "{name} está meio machucado\ne fica bem pertinho.",
  ["{name} glares at you.\nIt doesn't trust you yet."] = "{name} encara você.\nAinda não confia em você.",
  ["{name} snorts and looks\nreally annoyed."] = "{name} bufa e parece\nbem irritado.",
  ["{name} looks down and\nkeeps its distance."] = "{name} olha para baixo\ne mantém distância.",
  ["{name} sighs. It seems\na little lonely."] = "{name} suspira. Parece\num pouco sozinho.",
  ["{name} looks up at you\ncalmly."] = "{name} olha para você\ncom calma.",
  ["{name} is watching you,\nwaiting to see what's next."] = "{name} observa você,\nesperando o que vem.",
  ["{name} seems to be in\ngood spirits!"] = "{name} parece estar\nde bom humor!",
  ["{name} wags along happily,\nglad you're here."] = "{name} está todo contente,\nfeliz por você estar aqui.",
  ["{name} is happy, though\na little sore."] = "{name} está feliz,\nmas um pouco dolorido.",
  ["{name} smiles, but it's\nfavouring a sore spot."] = "{name} sorri, mas está\npoupando um lugar dolorido.",
  ["{name} is overjoyed to\nsee you!"] = "{name} está radiante\npor ver você!",
  ["{name} is beaming with\njoy!"] = "{name} está\nirradiando alegria!",
  ["{name} is brimming with\nenergy and bonds!"] = "{name} transborda\nenergia e carinho!",
  ["{name} is full of life.\nIt loves you dearly!"] = "{name} está cheio de vida.\nAma muito você!",
  ["{name} is hunched over.\nIt's a bit cramped here."] = "{name} está encolhido.\nAqui está meio apertado.",
  ["{name} shuffles about.\nThis spot is too tight!"] = "{name} não para quieto.\nEste lugar é apertado demais!",
  ["{name} eyes the roof.\nIt wants more room."] = "{name} olha o telhado.\nQuer mais espaço.",
  ["{name} nudges you.\nIt'd like to move on."] = "{name} cutuca você.\nQuer seguir em frente.",
  ["You pet {name}.\nIt leans into your hand!"] = "Você acaricia {name}.\nEle se apoia na sua mão!",
  ["You stroke {name}.\nIt closes its eyes happily."] = "Você afaga {name}.\nEle fecha os olhos, feliz.",
  ["You played with {name}!\nIt's having a blast!"] = "Você brincou com {name}!\nEle está se divertindo muito!",
  ["You and {name} romp\naround together!"] = "Você e {name} correm\ne brincam juntos!",
  ["You talked with {name}.\nIt listens closely."] = "Você conversou com {name}.\nEle escuta com atenção.",
  ["You chat with {name}.\nIt seems to understand."] = "Você bate papo com {name}.\nEle parece entender.",
  ["You gently pet {name}.\nIt takes comfort in it."] = "Você acaricia {name} com\ncuidado. Isso o conforta.",
  ["{name} tries to play,\nbut it's hurting."] = "{name} tenta brincar,\nmas está com dor.",
  ["You talk softly to\n{name}. It listens."] = "Você fala baixinho com\n{name}. Ele escuta.",
  ["{name} is hurt and\ncan't play."] = "{name} está ferido\ne não pode brincar.",
  ["{name} is sick and\ncan't play."] = "{name} está doente\ne não pode brincar.",
  ["{name} is paralyzed and\ncan't play."] = "{name} está paralisado\ne não pode brincar.",
  ["{name} is too cold and\ncan't play."] = "{name} está com frio\ndemais para brincar.",
  ["{name} is burning and\ncan't play."] = "{name} está queimado\ne não pode brincar.",
  ["{name} is asleep and\ncan't play."] = "{name} está dormindo\ne não pode brincar.",
  ["{name} feels better now!"] = "{name} já se sente melhor!",
  ["{name} is wary of\nyou..."] = "{name} desconfia\nde você...",
  ["{name} is curious\nabout you!"] = "{name} está curioso\ncom você!",
  ["{name} is starting\nto like you!"] = "{name} está começando\na gostar de você!",
  ["{name} trusts you!"] = "{name} confia em você!",
  ["{name} really likes\nyou!"] = "{name} gosta muito\nde você!",
  ["{name} loves you!"] = "{name} ama você!",
  ["{name} is already as\nhappy as can be!"] = "{name} já está o mais\nfeliz que pode ser!",
  ["{name} couldn't possibly\nbe any fonder of you!"] = "{name} não poderia\ngostar mais de você!",
  ["{name} isn't in the\nmood right now."] = "{name} não está\nno clima agora.",
  ["{name} looks away.\nGive it a moment."] = "{name} desvia o olhar.\nDê um tempo a ele.",
  ["{name} has had plenty of\nattention for now."] = "{name} já recebeu\natenção suficiente.",
  ["{name} seems worn out\nfrom all the fuss."] = "{name} parece cansado\nde tanta agitação.",
  ["{name} is fed up!\nIt turns its back on you."] = "{name} se cansou!\nVirou as costas para você.",
  ["{name} wants some space.\nTry again later."] = "{name} quer espaço.\nTente de novo mais tarde.",
  ["{name} ignores you.\nIt needs some time alone."] = "{name} ignora você.\nPrecisa ficar sozinho.",

  -- the trainer call-outs (one "|" break each, %s = the partner's name)
  ["list:send"] = {
    "Vai,|%s!", "Pega eles,|%s!", "Mostra do que|você é capaz!", "Agora,|%s!",
    "Com tudo,|%s!", "Sua vez,|%s!", "Vamos lá,|%s!", "É com você,|%s!",
    "Derruba eles,|%s!", "Dá o seu melhor,|%s!",
  },
  ["list:recall"] = {
    "Já chega,|%s!", "Volta,|%s!", "Muito bem, %s!|Volta!", "Bom trabalho,|%s!",
    "Descansa,|%s!", "Certo, %s!|Volta!", "Aqui comigo,|%s!", "Mandou bem,|%s!",
    "Pode parar,|%s!", "Isso aí!|Volta, %s!",
  },
}
