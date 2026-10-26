-- Japanese (にほんご). Kana only: the Gen 3 cart's Japanese font has no kanji, so this is
-- written the way the original Japanese releases were -- hiragana and katakana, a space
-- between phrases (the font has no 、), full-width ！？。 and ‥ for an ellipsis.
-- Keys are the English text (lib/i18n.lua); "<context>|..." keys for option / choice /
-- menu / party rows. tests/i18n_coverage_unit_test.lua checks every key is here.
return {
  -- options: labels
  ["option|Language"] = "げんご",
  ["option|Show Wild Mons"] = "やせいを みせる",
  ["option|Spawn Amount"] = "でる かず",
  ["option|Flying Mons"] = "とぶ ポケモン",
  ["option|Water Life"] = "みずの いきもの",
  ["option|Local Scenes"] = "ばしょの けしき",
  ["option|Wild Reacts"] = "やせい はんのう",
  ["option|Sprite Style"] = "スプライト",
  ["option|Follower"] = "つれあるき",
  ["option|Battler: Pad"] = "バトラー：パッド",
  ["option|Battler: Key"] = "バトラー：キー",
  ["option|Smooth Follow"] = "なめらか いどう",
  ["option|Type Aura"] = "タイプ オーラ",
  ["option|Classic Enc"] = "ランダム バトル",
  ["option|Silhouette"] = "シルエット",
  ["option|Species Sizes"] = "おおきさ",
  ["option|Portraits"] = "ポートレート",

  -- options: choices
  ["choice|LOW"] = "すくない",
  ["choice|NORMAL"] = "ふつう",
  ["choice|HIGH"] = "おおい",
  ["choice|FULL"] = "すべて",
  ["choice|AMBIENT"] = "けしき",
  ["choice|OFF"] = "オフ",
  ["choice|HGSS"] = "HGSS",
  ["choice|PMD"] = "PMD",
  ["choice|R"] = "R",
  ["choice|L"] = "L",
  ["choice|E (R)"] = "E (R)",
  ["choice|Q (L)"] = "Q (L)",
  ["choice|UNDISCOVERED"] = "みはっけん",
  ["choice|ALL"] = "すべて",
  ["toggle|ON"] = "オン",
  ["toggle|OFF"] = "オフ",

  -- options: descriptions
  ["The language of Wilds of Hoenn's own text: these options, your partner's words, its menus and the labels over it. The game's own text is not changed. Japanese is written in kana, like the original Japanese games."] =
    "Wilds of Hoenn の テキストの げんご： この オプション パートナーの ことば メニュー そして うえに でる ラベル。 ゲームの テキストは かわりません。 にほんごは むかしの にほんの ゲームと おなじく かなで かかれます。",
  ["Spawn visible wild Pokemon in eligible grass/water encounter areas."] =
    "やせいの ポケモンが でる くさむらや みずの うえに その すがたを みせます。",
  ["How many wild Pokemon are out at once, for grass and water each, growing with the size of the area. Low: about half (up to 4). Normal: up to 8. High: about one and a half times (up to 12)."] =
    "いちどに でている やせいの ポケモンの かず。 くさむらと みず それぞれ ばしょの ひろさで ふえます。 すくない： やく はんぶん(4ひきまで)。 ふつう： 8ひきまで。 おおい： やく 1.5ばい(12ひきまで)。",
  ["Flying Pokemon in the sky: birds of the area pass overhead, perch on trees, roofs and signposts, and real sea birds dive for food; wild Flying-type Pokemon swoop down to land (and take off again) instead of rising out of the grass. Full: all of it, with big soft-focus birds flying high overhead. Ambient: the same without the high birds. Off: none of it, wild Pokemon all arrive the usual way."] =
    "そらを とぶ ポケモン： その ばしょの とりポケモンが あたまの うえを とび き や やね や かんばんに とまり うみどりは えさを とりに もぐります。 ひこうタイプの やせいの ポケモンは くさむらから でるかわりに そらから まいおります。 すべて： ぜんぶ たかい そらを とぶ おおきな とりも ふくめて。 けしき： たかい とり いがい。 オフ： なし。",
  ["Life in the water, just for the scenery: small fish of the area (Magikarp, Goldeen, Luvdisc ...) leap out of the water and splash back in, and Wailmer and Wailord surface for a while, blowing a spray, before sinking back under. Out at sea, Finizen porpoise by now and then (once in a while a whole pod comes up to play). Diving, fish swim by under the sea as dark shadows trailing bubbles. Never battled."] =
    "みずの なかの いきもの(けしき だけ)： その ばしょの ちいさな さかなポケモンが みずから はねて ホエルコや ホエルオーが しおを ふきながら うかびあがります。 うみでは ナミイルカが ときどき とびはね たまに むれで あそびに きます。 ダイビング ちゅうは さかなの かげが あわを ひいて およぎます。 たたかう ことは ありません。",
  ["Little moments in a few special places: ghosts drift through Lavender Town, bug Pokemon dangle from the trees of Petalburg Woods where Slakoth naps and Vigoroth dances on the treetops, and a great Tropius rises out of Fortree's trees. Just for the scenery."] =
    "とくべつな ばしょの ちいさな ひとこま： シオンタウンには ゆうれいが ただよい トウカのもりでは むしポケモンが き から ぶらさがり ナマケロが ひるねを して ヤルキモノが こずえで おどります。 ヒワマキシティでは おおきな トロピウスが き の うえに あらわれます。 けしき だけです。",
  ["Run or bike close to wild Pokemon and they react: weaker ones than your lead Pokemon are startled and run off (small birds fly away), stronger ones get angry and chase you (catching you starts the battle). Walking past disturbs nobody. Off: they just wander."] =
    "はしったり じてんしゃで ちかづくと やせいの ポケモンが はんのう します： せんとうの ポケモンより よわい ものは おどろいて にげ(ちいさな とりは とびさり) つよい ものは おこって おいかけて きます(つかまると せんとうに なります)。 あるいて とおれば だいじょうぶ。 オフ： ただ うろうろ します。",
  ["Overworld sprite style for wild Pokemon and your follower. HGSS / PokeMMO draws each species at its own native size (\"True Size\"), anchored at its feet -- a Snorlax is drawn much bigger than a Rattata."] =
    "やせいの ポケモンと パートナーの スプライト。 HGSS / PokeMMO は それぞれの ポケモンを ほんらいの おおきさで あしもとから えがきます： カビゴンは コラッタより ずっと おおきく えがかれます。",
  ["PMDCollab uses the PMD Explorers-style sprites with fully animated walking and idle loops (species without PMD art fall back to HGSS / PokeMMO)."] =
    "PMDCollab は ふしぎのダンジョンふうの スプライトで あるきも たちすがたも すべて うごきます(PMD の え が ない ポケモンは HGSS / PokeMMO に なります)。",
  ["Your partner Pokemon walks behind you. Off: it stays in its Poke Ball (its Battle and Forage jobs and Pet / Play / Talk wait until it is out again). Changing your party order still changes who your partner is."] =
    "パートナーの ポケモンが うしろを ついて あるきます。 オフ： モンスターボールの なかに います(たたかう さがす の やくわりと なでる あそぶ はなす は でてくるまで まちます)。 てもちの じゅんばんを かえると パートナーも かわります。",
  ["A controller shoulder button that switches your partner between Battle and Follow while you walk around -- you call it out like a trainer in battle ('Go! Mudkip!', 'Come back, Mudkip!'). In FireRed / LeafGreen that button then no longer opens Help in the overworld; the other shoulder still does."] =
    "コントローラーの L か R ボタンで あるきながら パートナーを たたかう と ついてくる に きりかえます。 バトルの トレーナーの ように よびかけます(「いけっ！ ミズゴロウ！」「もどれ ミズゴロウ！」)。 ファイアレッド / リーフグリーンでは その ボタンで フィールドの ヘルプは ひらかなく なります。 もう かたほうの ボタンは そのままです。",
  ["The keyboard key that switches your partner between Battle and Follow while you walk around. E and Q are the game's R and L buttons (in FireRed / LeafGreen that one then no longer opens Help in the overworld); R is a free key."] =
    "あるきながら パートナーを たたかう と ついてくる に きりかえる キーボードの キー。 E と Q は ゲームの R と L ボタンです(ファイアレッド / リーフグリーンでは その ボタンで フィールドの ヘルプは ひらかなく なります)。 R は あいている キーです。",
  ["Your partner is always spaced out behind you by its size. On: it glides round when you turn. Off: it snaps straight to its place behind you, step for step like the original games."] =
    "パートナーは いつも おおきさに あわせて うしろに ならびます。 オン： まがる ときに なめらかに まわりこみます。 オフ： むかしの ゲームの ように ひとマスずつ すぐ うしろに つきます。",
  ["Now and then your partner gives off a little puff of its type: embers from a Fire type, droplets from a Water type, leaves, sparks, snow, wisps ... Off: only while you Pet, Play or Talk with it."] =
    "ときどき パートナーから タイプの けむりが ふわっと でます： ほのおタイプは ひのこ みずタイプは しずく ほかにも はっぱ ひばな ゆき おにび‥ オフ： なでる あそぶ はなす の ときだけ。",
  ["Classic Encounters: the original step-based random encounters in grass and water (Surf). Visible wild Pokemon stay active either way. Fishing and Rock Smash are unaffected."] =
    "もとの ゲームの くさむらや なみのりの ランダム エンカウント。 みえる やせいの ポケモンは どちらでも でます。 つりや いわくだきは かわりません。",
  ["Off keeps normal colours. Undiscovered silhouettes species not yet caught in your Pokedex. All silhouettes every visible wild Pokemon."] =
    "オフ： ふつうの いろ。 みはっけん： ずかんで まだ つかまえて いない ポケモンを シルエットに します。 すべて： みえる やせいの ポケモンを ぜんぶ シルエットに します。",
  ["Draw each species at its own size next to you, in either sprite style: small ones knee-high, giants towering over you. Needs the Gen 3 HD Sprites mod (with its Field HD option on); without it every species is drawn at its sheet's size."] =
    "どちらの スプライトでも ポケモンを ほんらいの おおきさで えがきます： ちいさな ものは ひざの たかさ おおきな ものは みあげる ほど。 Gen 3 HD Sprites MOD(Field HD オン)が ひつようです。 ない ときは がぞうの ままの おおきさです。",
  ["Your partner's PMDCollab portrait above its messages when you Pet, Play or Talk with it. Off: the messages show without it."] =
    "なでる あそぶ はなす の とき パートナーの PMDCollab ポートレートを メッセージの うえに だします。 オフ： メッセージだけ。",

  -- the partner's menu
  ["menu|Interact"] = "ふれあう",
  ["menu|Role"] = "やくめ",
  ["menu|Recall"] = "もどす",
  ["menu|Cancel"] = "やめる",
  ["menu|Pet"] = "なでる",
  ["menu|Play"] = "あそぶ",
  ["menu|Talk"] = "はなす",
  ["menu|Back"] = "もどる",
  ["menu|Follow"] = "ついてくる",
  ["menu|Forage"] = "さがす",
  ["menu|Fight"] = "たたかう",
  ["menu|Evolve"] = "しんか",
  ["menu|Learn Move"] = "わざを おぼえる",

  -- the party menu (80 px box; ROLE leaves room for its arrow)
  ["party|ROLE"] = "やくめ",
  ["party|BACK"] = "もどる",
  ["party|FOLLOW"] = "ついてくる",
  ["party|FORAGE"] = "さがす",
  ["party|FIGHT"] = "たたかう",

  -- messages and labels
  ["%s returned to you."] = "%sは もどってきた！",
  ["%s will follow you."] = "%sは ついてくる！",
  ["%s will battle wild Pokemon for you."] = "%sは やせいの ポケモンと たたかう！",
  ["%s will forage for items."] = "%sは どうぐを さがす！",
  ["%s can't do that right now."] = "%sは いまは それが できない。",
  ["%s has nothing to do right now."] = "%sは いま することが ない。",
  ["%s is already doing that."] = "%sは もう そうしている。",
  ["Nothing happened."] = "なにも おきなかった。",
  ["Found %s!"] = "%sを みつけた！",
  ["an item"] = "どうぐ",
  ["+%d EXP"] = "+%d けいけんち",
  ["Lv.%d!"] = "Lv.%d！",
  ["New move ready!"] = "わざを おぼえられる！",
  ["Ready to evolve!"] = "しんか できる！",
  ["POKeMON"] = "ポケモン",

  -- the partner's words (two lines at most; {name} is its name)
  ["{name} can barely keep\nits eyes open..."] = "{name}は いまにも\nめを とじそうだ‥",
  ["{name} is in a bad way\nand looks close to tears."] = "{name}は ぐあいが わるく\nいまにも なきそうだ",
  ["{name} is hurting badly.\nIt needs help soon!"] = "{name}は ひどく いたそうだ\nはやく てあてが ひつようだ！",
  ["{name} is poisoned and\nlooks miserable."] = "{name}は どくを うけて\nつらそうだ",
  ["{name} winces. The poison\nis really bothering it."] = "{name}は かおを しかめた\nどくが とても つらいようだ",
  ["{name} is burned and\nyelping in pain!"] = "{name}は やけどを して\nいたがっている！",
  ["{name} is scorched and\ncan't settle down."] = "{name}は やけどで\nおちつかない ようすだ",
  ["{name} is paralyzed and\ncan hardly move."] = "{name}は まひして\nほとんど うごけない",
  ["{name} twitches. Its body\nwon't listen to it."] = "{name}は ぴくぴく している\nからだが いうことを きかない",
  ["{name} is frozen stiff\nand shivering."] = "{name}は こおりついて\nふるえている",
  ["{name} is encased in ice\nand looks stunned."] = "{name}は こおりづけで\nぼうぜんと している",
  ["{name} is half asleep\nand swaying a little."] = "{name}は ねむそうに\nゆらゆら している",
  ["{name} can barely stay\nawake right now."] = "{name}は いまにも\nねむって しまいそうだ",
  ["{name} is hurt and\nlooks uneasy."] = "{name}は けがを して\nふあんそうだ",
  ["{name} is limping and\nwinces when it moves."] = "{name}は あしを ひきずり\nうごくたびに いたそうだ",
  ["{name} looks a bit\nworried about its wounds."] = "{name}は きずを\nすこし きにしている",
  ["{name} is a little banged\nup and keeping close."] = "{name}は すこし きずついて\nそばを はなれない",
  ["{name} glares at you.\nIt doesn't trust you yet."] = "{name}は にらんでいる\nまだ しんようして いないようだ",
  ["{name} snorts and looks\nreally annoyed."] = "{name}は はなを ならした\nとても いらいら している",
  ["{name} looks down and\nkeeps its distance."] = "{name}は うつむいて\nはなれた ところに いる",
  ["{name} sighs. It seems\na little lonely."] = "{name}は ためいきを ついた\nすこし さびしそうだ",
  ["{name} looks up at you\ncalmly."] = "{name}は おだやかに\nこちらを みあげている",
  ["{name} is watching you,\nwaiting to see what's next."] = "{name}は こちらを みて\nつぎを まっている",
  ["{name} seems to be in\ngood spirits!"] = "{name}は\nごきげんな ようすだ！",
  ["{name} wags along happily,\nglad you're here."] = "{name}は うれしそうだ\nいっしょで たのしいらしい",
  ["{name} is happy, though\na little sore."] = "{name}は たのしそうだが\nすこし いたむようだ",
  ["{name} smiles, but it's\nfavouring a sore spot."] = "{name}は わらっているが\nいたい ところを かばっている",
  ["{name} is overjoyed to\nsee you!"] = "{name}は あえて\nとても うれしそうだ！",
  ["{name} is beaming with\njoy!"] = "{name}は よろこびで\nかがやいている！",
  ["{name} is brimming with\nenergy and bonds!"] = "{name}は げんきと きずなに\nみちあふれている！",
  ["{name} is full of life.\nIt loves you dearly!"] = "{name}は げんき いっぱいだ\nきみが だいすきなようだ！",
  ["{name} is hunched over.\nIt's a bit cramped here."] = "{name}は せなかを まるめた\nここは すこし きゅうくつだ",
  ["{name} shuffles about.\nThis spot is too tight!"] = "{name}は もぞもぞ している\nここは せますぎる！",
  ["{name} eyes the roof.\nIt wants more room."] = "{name}は やねを みあげた\nもっと ひろい ところが いいようだ",
  ["{name} nudges you.\nIt'd like to move on."] = "{name}が きみを つついた\nさきへ すすみたいようだ",
  ["You pet {name}.\nIt leans into your hand!"] = "{name}を なでた！\nてに すりよってきた！",
  ["You stroke {name}.\nIt closes its eyes happily."] = "{name}を なでた\nうれしそうに めを とじた",
  ["You played with {name}!\nIt's having a blast!"] = "{name}と あそんだ！\nとても たのしそうだ！",
  ["You and {name} romp\naround together!"] = "{name}と いっしょに\nはしりまわった！",
  ["You talked with {name}.\nIt listens closely."] = "{name}に はなしかけた\nじっと きいている",
  ["You chat with {name}.\nIt seems to understand."] = "{name}と おしゃべりした\nわかっている みたいだ",
  ["You gently pet {name}.\nIt takes comfort in it."] = "{name}を やさしく なでた\nすこし おちついたようだ",
  ["{name} tries to play,\nbut it's hurting."] = "{name}は あそぼうと したが\nいたくて できない",
  ["You talk softly to\n{name}. It listens."] = "やさしく はなしかけた\n{name}は きいている",
  ["{name} is hurt and\ncan't play."] = "{name}は けがを して\nあそべない",
  ["{name} is sick and\ncan't play."] = "{name}は ぐあいが わるくて\nあそべない",
  ["{name} is paralyzed and\ncan't play."] = "{name}は まひして\nあそべない",
  ["{name} is too cold and\ncan't play."] = "{name}は こおっていて\nあそべない",
  ["{name} is burning and\ncan't play."] = "{name}は やけどで\nあそべない",
  ["{name} is asleep and\ncan't play."] = "{name}は ねむっていて\nあそべない",
  ["{name} feels better now!"] = "{name}は げんきに なった！",
  ["{name} is wary of\nyou..."] = "{name}は きみを\nけいかい している‥",
  ["{name} is curious\nabout you!"] = "{name}は きみに\nきょうみ しんしんだ！",
  ["{name} is starting\nto like you!"] = "{name}は きみを\nすきに なってきた！",
  ["{name} trusts you!"] = "{name}は きみを しんらい している！",
  ["{name} really likes\nyou!"] = "{name}は きみが\nとても すきだ！",
  ["{name} loves you!"] = "{name}は きみが だいすきだ！",
  ["{name} is already as\nhappy as can be!"] = "{name}は もう\nこのうえなく しあわせだ！",
  ["{name} couldn't possibly\nbe any fonder of you!"] = "{name}は きみのことが\nこれいじょう ないほど すきだ！",
  ["{name} isn't in the\nmood right now."] = "{name}は いまは\nそういう きぶんじゃ ない",
  ["{name} looks away.\nGive it a moment."] = "{name}は そっぽを むいた\nすこし まってあげよう",
  ["{name} has had plenty of\nattention for now."] = "{name}は もう\nじゅうぶん かまってもらった",
  ["{name} seems worn out\nfrom all the fuss."] = "{name}は かまわれすぎて\nつかれた ようすだ",
  ["{name} is fed up!\nIt turns its back on you."] = "{name}は うんざりした！\nせなかを むけてしまった",
  ["{name} wants some space.\nTry again later."] = "{name}は ひとりに なりたいようだ\nまた あとで ためそう",
  ["{name} ignores you.\nIt needs some time alone."] = "{name}は しらんぷりだ\nしばらく ひとりに させよう",

  -- the trainer call-outs (one "|" break each, %s = the partner's name)
  ["list:send"] = {
    "いけっ！|%s！", "たのんだぞ|%s！", "ちからを|みせてやれ！", "いってこい|%s！",
    "ゆけっ！|%s！", "でばんだ|%s！", "がんばれ|%s！", "まかせたぞ|%s！",
    "やっつけろ|%s！", "ぜんりょくだ|%s！",
  },
  ["list:recall"] = {
    "もういいぞ|%s！", "もどれ|%s！", "%s よくやった！|もどれ！", "ナイスだ|%s！",
    "ひとやすみだ|%s！", "%s オーケー！|もどれ！", "こっちへ|%s！", "おつかれ|%s！",
    "じゅうぶんだ|%s！", "いいぞ！|もどれ %s！",
  },
}
