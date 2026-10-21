# Changelog

## 1.10.1 (2026-10-21)

### Changed

- **Call it out like a trainer.** The Battler button no longer shows "Battling!" / "Following"
  over your partner: you call it out yourself, in a speech bubble over your head, like
  sending a Pokemon into a real battle -- "Go! Mudkip!", "Get 'em, Mudkip!", "That's enough,
  Mudkip!", "Come back, Mudkip!" and more, by its nickname or species name.
- **Battle effects grow with level.** The higher the level of the Pokemon making a move,
  the bigger its effects: from a little over their original size at level 1 to about twice
  it at level 100 (the same as before around level 50).
- **Your Battler runs back to you.** Called back mid-fight (the Battler button or the party
  menu), it now runs back to its place behind you instead of reappearing there at once.

## 1.10.0 (2026-10-20)

### Added

- **Battler button.** Pick a button in the mod options (Battler: Pad -- L or R; Battler: Key --
  E, Q or R; both off to start with) and one press while you walk around switches your partner
  between battling wild Pokemon and following you, with a little label to say which. In
  FireRed / LeafGreen the chosen shoulder button no longer opens Help in the overworld; the
  other one still does.
- **Calling off a fight.** Take your Battler off the job mid-fight (with the Battler button or
  the party menu) and it counts as running away: the wild Pokemon gives a parting cry and a
  lunge at you, then runs off and disappears. No EXP for a fight you left.
- **Jump into your Battler's fight.** Walk into a wild Pokemon your Battler has been fighting
  and the real battle starts with the HP it has left -- and a Pokemon your Battler wore down
  earlier stays worn down, for the next skirmish too.

### Changed

- **Your partner walks at a natural distance.** It now keeps its spacing by how it actually
  looks the way you walk: right behind you walking down (big Pokemon no longer trail two
  tiles back), held back walking up so a big one never covers your head, and beside you
  sideways by how far its head reaches. In both sprite styles, with or without HD sprites.
- **Pokemon are drawn bigger (Species Sizes).** Sizes lean less on real-world heights: mid-size
  Pokemon like Charizard, Tyranitar and Snorlax now stand clearly taller than you (about a
  quarter bigger), small ones grow a little, and the giants keep their size.
- **Kyurem, Zekrom, Reshiram and Koraidon stand taller.** They were drawn smaller than other
  Pokemon their size; they now match Groudon and the like.
- **Calmer wild Pokemon (Wild Reacts).** They only notice you when you run within 2 steps
  of them (4 on a bike), counted in steps so a diagonal is no longer closer than it looks.
  And they react less often: at most half the time, and rarer still the closer they are to
  your lead Pokemon's strength.
- **Bigger battle effects.** Your Battler's attacks now play at a more relaxed pace, so their
  effects are drawn bigger too: the type pieces gathering before a move, the shot flying over,
  the sparks of a hit and the knockout burst are all about three quarters larger.

### Fixed

- **No second battle with a knocked-out Pokemon.** A wild Pokemon your Battler had just
  knocked out could still be walked into while it sank away, starting a fresh battle with it.
  It can no longer be met once it is down.

## 1.9.4 (2026-10-20)

### Added

- **Follower option.** Prefer to walk alone? Switch Follower off in the mod options and your
  partner stays in its Poke Ball. Its Battle and Forage jobs and Pet / Play / Talk wait until
  you switch it back on, and changing your party order still picks who comes out then.

## 1.9.3 (2026-10-19)

### Added

- **Community credits.** A thank-you to the players and the Discord community whose ideas
  shaped the mod, with a running list of who suggested what (COMMUNITY.md, in the package).

### Fixed

- **Smoother on lakes and the sea.** The little wake rings behind swimming Pokemon were rebuilt
  from scratch every frame; they are now reused, cutting about a third of the mod's memory
  churn on water routes (fewer stutters on slower devices).

### Changed

- **Tropius stays on the ground.** It no longer flies past overhead, perches on roofs or swoops
  in to land; wild Tropius walk about like other Pokemon.
- **Calmer Battler fights.** Your partner and the wild Pokemon now take their turns at a steadier
  pace, so each attack and its effect is easy to follow.

## 1.9.2 (2026-10-16)

### Fixed

- **Sweet Scent works with the latest Gen1Recomp.** On the newest engine, using Sweet Scent
  where wild Pokemon answer it could leave you unable to move afterwards. You are free again as
  soon as the scent fades.
- **No more getting stuck after a wild battle fails to open.** Using Sweet Scent in a cave (and
  sometimes just standing in one) could leave you unable to move or open the menu while the
  music played on. A wild Pokemon could wander onto the tile you were standing on and start a
  battle by itself, and if that battle never opened (another mod getting in the way), you were
  held in place for good. Wild Pokemon no longer walk onto you, and a battle that doesn't open is
  dropped within a moment (at most 5 seconds) so you can move again.

## 1.9.0 (2026-10-16)

### Added

- **Livelier Pokemon in the water.** Wild Pokemon on lakes and the sea swim about in short
  runs, a few tiles one way, a pause, then off another way. They bob gently on the surface,
  leave a small ring of wake on each tile they swim off, and every so often dive under and come
  up a few tiles away inside spreading rings. Nothing can bump into one while it is under.

- **Knockout effects for the Battler.** When your partner finishes off a wild Pokemon, the
  final blow shows the type of the move that landed it: a splash of water exploding outward, a
  burst of flame, leaves flung everywhere, a lightning bolt, shards of ice or rock, a dust cloud,
  psychic rings, Fairy sparkles and hearts, and so on for every type, Fairy included when
  National Dex Gen 3 is installed. Each plays the matching battle sound from the game itself
  (Waterfall's splash, Thunderbolt's crack, Charm for Fairy ...) at the game's SFX volume, so
  the options menu's slider applies, down to silent. Some tint the defeated Pokemon as it goes
  down, and a Ghost move makes it fade away instead of sinking.
- **Every Battler hit shows its type.** Ordinary blows spark with a little of their move's type
  (droplets, embers, leaves, sparks ...) on top of the impact: a bigger burst and brighter flash
  when it is super effective, dimmed and grey when it is not very effective, just a grey puff when
  it has no effect, and a star on a critical hit. Each plays the battle's own hit sound for how
  well it landed, at your SFX volume.
- **Battler moves show their type as they are used.** The attacker glows its move's colour as it
  winds up. A move that doesn't make contact (Water Gun, Ember, Confusion ...) gathers a few of
  its type's particles, then flies across to the target as a projectile of its type, landing
  just as the hit does; a contact move (Tackle, Scratch ...) simply lunges, leaving a trail of
  puffs behind it (dust for Normal and Fighting). Which is which comes from the game's own move data.
- **Knockouts leave a mark on the ground.** Fire, Water, Ground, Rock, Ice and Grass knockouts
  leave a scorch, a puddle, a small crater, rubble, frost or grass clippings where the wild
  Pokemon stood, fading after a few seconds (never on water).
- **Knocked-out Pokemon can drop their held item.** A quarter of Battler knockouts shake
  loose what the wild Pokemon was holding, rolled exactly as the game rolls a wild Pokemon's
  held item (so most hold nothing, a Pikachu sometimes an Oran Berry and rarely a Light Ball).
  It glints on the ground while the Pokemon goes down, then your partner picks it up: "Found
  ORAN BERRY!" after the EXP, straight into your bag. Nothing drops if it would not fit.
- **Your partner shows its type and milestones.** A Battler that levels up gets a gold ring and
  sparkles rising round it; a partner ready to evolve has sparkles drifting up round it until
  it does. While you Pet, Play or Talk with it, it gives off a little puff of its own type
  (embers, droplets, leaves, sparks, snow, wisps ...; a Normal / Flying type like Pidgey puffs
  Flying).
- **New look for the labels over your partner.** EXP, finds and "New move ready!" / "Ready to
  evolve!" pop up in a white speech bubble pointing down at your Pokemon, just over its head
  (however tall it is) instead of floating high above it; a level-up ("Lv.12!") is rainbow
  letters rising and falling in a wave over a soft glow. (The Game Boy games keep the plain
  label.)
- **Type Aura option** (off by default): your partner gives off that puff of its type now and
  then as it follows you.

### Changed

- **Wild Reacts is less dramatic.** A startled Pokemon runs 1-3 tiles instead of 3-6. A
  stronger one only gets angry when you run right up beside it (within a tile, 2 on a bike), and
  gives up the chase after 2-4 tiles instead of 4-10.

- **Changing your partner's job no longer puts it back in its ball.** Picking a new role for
  the Pokemon already out lets it switch jobs on the spot; the ball only comes out when a
  different Pokemon takes over, or one is recalled or sent out.

- **Angry wild Pokemon chase you out of the grass.** Stepping onto the path no longer shakes off
  a Wild Reacts chaser: it follows you across open ground to catch you (never into the water or
  through a doorway), and when it gives up it walks back to its own grass. One that can't find
  its way back slips away, so none is ever left stranded on the path.

- **Battler health bars look like the battle screen's.** A bright middle stripe between darker
  edges, white where health is gone, turning from green to yellow to red as it drops. They are slightly see-through so they
  hide less of the field, and float just over each Pokemon's head, however tall it is;
  when the two would overlap, your partner's bar glides up to sit above the wild one's.

### Fixed

- **Wild Pokemon in the water can move.** Water spawns never took a single step: the game's
  surfing rules refused every one. They swim now (and a startled one can swim away).
- **PMDCollab partners rest on their feet.** After stopping, a PMDCollab style partner holds
  the first pose of its idle animation for a few seconds. For some species (Charmander, Altaria,
  Noctowl ...) that pose reaches a little lower than how they stand, so they sat a pixel or
  three into the ground; for others (Sawk, Drednaw ...) it stood a little high. The resting pose
  now sits on the ground like the player's feet, easing back as the idle animation starts.

## 1.8.0 (2026-10-15)

### Added

- **Portraits option (on by default).** Off: your partner's messages show without its portrait
  above the text box. Only in the HGSS + PMDCollab build, the one with portraits.
- **Your partner shows how it feels.** While you Pet, Play or Talk with it, a little effect plays
  over its head to match its face: hearts (with sparkles when it adores you), music notes when
  it's happy, sparkles when it trusts you, a "!" when it's curious, a rain cloud when it's sad,
  tears, an anger mark, a sweat drop when it's worried, and for a hurting one its trouble:
  poison bubbles, flames, sparks, snowflakes or sleepy Zs.
- **Smooth Follow option (on by default).** Off: your partner snaps straight to its place behind
  you when you turn, step for step like the original games, instead of gliding round. It keeps
  its distance behind you either way, so a big Pokemon never overlaps you.
- **Shinies sparkle.** A shiny wild Pokemon, and a shiny partner, twinkle every few seconds:
  a few little gold stars pop on its body and fade. Each one keeps its own rhythm.
- **Flying Mons: Full / Ambient / Off.** Full is everything, including the big, soft-focus birds
  flying high overhead; Ambient keeps the passing, perching and diving birds and the swooping
  wild Flying types but leaves the high birds out; Off is none of it. A saved On is Full.
- **Finizen at sea (Water Life).** Out on the sea, a Finizen now and then surfaces with a puff
  from its blowhole and porpoises along in a string of leaps before diving again, like a dolphin.
  Once in a long while a whole pod comes up to play, swimming round in a ring and taking turns to
  leap, then goes back under. Drawn at its own size from either sprite style.
- **Local Scenes (Local Scenes option, on by default).** A few special places get moments of
  their own, just for the scenery. Lavender Town: ghosts (Gastly, sometimes Haunter) fade in
  around town, wander a few steps, through walls and over roofs, dark and see-through, and fade away; answer "No"
  when the girl asks whether you believe in ghosts and, 1 time in 4, a Gengar fades in right
  behind you and stays until she has finished talking. Petalburg Woods: Burmy slides down from
  the leaves on a silk thread and is reeled back up, Silcoon and Cascoon dangle and slowly spin,
  Slakoth naps on the treetops with "z"s floating up, and once in a while Vigoroth leaps in from
  off screen, dances on a treetop and leaps away. Fortree City: once in a while a big Tropius rises
  out of the treetops (its top half showing, the leaves rustling round it), walks a few steps
  across them and sinks back under. The bugs and Slakoth are drawn a little smaller, to fit the trees. PMDCollab art plays the
  real Sleep, Dance and Rotate animations.
- **Life in the water (Water Life option, on by default).** The small fish of the area's fishing
  and Surf Pokemon (Magikarp, Goldeen, Feebas, Luvdisc, Carvanha ...) now and then leap out of
  open water in an arc and splash back in, with ripples and a spray of droplets; PMDCollab ones
  play their own hop. Wailmer and Wailord rise to the surface, lie there or drift a little, blow
  a spout from their blowhole and sink back under. Diving, the sea's fish (any non-legendary fish
  of the National Dex under 2 m) swim by as dark shadows trailing bubbles, curving and wiggling,
  nearer the surface bigger and softer, sometimes in a small school. Just scenery: never battled.
- **Visible wild Pokemon under the sea.** Dive maps get their own visible wild Pokemon from the
  underwater table, drawn whole (not cut off at a surface they are far below). A fish among them
  swims in from off screen as a shadow, curving round you, and takes shape on its spot; leaving,
  it fades back to a shadow and swims away. Others fade in and out. Swimming onto one starts the
  battle, as on land.
- **Wild Pokemon react when you run or bike close by (Wild Reacts option, on by default).**
  Ones weaker than your lead Pokemon are startled (a "!" over their head) and run off a few
  tiles; small birds fly away. Stronger ones only mind you up close (2 tiles): they stop, turn
  to you, show an anger mark and give chase, a little faster than you can run: if they catch you, the wild battle starts. Each chase gives up at its own
  distance (4 to 10 tiles), and a bike or leaving the grass gets you away. Evenly matched ones
  carry on as normal, and walking past disturbs nobody.
- **Flying Pokemon in the sky (Flying Mons option, Full by default).** Now and then one of the
  area's birds crosses the top of the screen in a gentle arc: the higher it flies, the bigger,
  faster and more out of focus it looks, since it is closer to the camera. In towns and cities,
  birds from the routes around them perch on roofs, trees and signposts, sit with folded wings
  (turning or hopping now and then), and fly off after a while or when you walk up. Sea birds dive into open water for food with a splash and come back
  up. Wild Flying-type Pokemon swoop in from off screen to land in the grass or on the water
  instead of rising out of it (in the wild a bird only ever lands where you can reach it), and
  take off again after a
  while; their flight always curves around you, and one that appears right next to you (within 3
  tiles) arrives the usual way. Only real fliers count: Flying types taller than 3 m (Gyarados,
  Rayquaza), flightless ones (Doduo, Dodrio, Delibird) and a few whose art does not look like
  flying (Charizard, Hoothoot, Xatu, Emolga and others) stay on the ground. No birds in caves
  or indoors, fewer in rain.
  PMDCollab birds fly with the animation picked for each one: their own hover loop,
  a wing beat (Pidgey, Taillow), a glide (Dragonite), or their walk cycle.
- **Spawn Amount option: Low / Normal / High.** Normal is the same number of wild Pokemon as
  before. Low is about half (up to 4 each in grass and water), High about one and a half times (up
  to 12 each). Lowering it takes effect at once, the farthest Pokemon leaving first.

### Changed

- **Wild Reacts: not every Pokemon minds you.** How likely a wild Pokemon is to run off or chase
  depends on how mismatched it is with your lead: one only a little weaker or stronger reacts
  about a quarter of the time, one far weaker or far stronger always does. One that lets you pass
  leaves you be for a few seconds.
- **Wild Reacts: charging and vanishing.** A stronger wild Pokemon chasing you now charges with
  its Attack animation (PMDCollab style) until it catches you and the battle opens; giving up, it
  walks home again. A weaker one that runs off sometimes (30%) disappears at the end of its run:
  ducking down into the grass with a rustle, or fading into a cave's dark. Birds still fly away.
- **Birds overhead bob with their wingbeats.** The high birds crossing the top of the screen rise
  and fall a little as they fly instead of gliding along a flat line.
- **Birds overhead move with the view.** A bird passing high overhead starts across the top of
  the screen, then drifts with your walking at its own depth instead of sticking to the top edge:
  walk up and it slides down the sky, walk down and it slips away off the top.
- **Only real birds dive into the sea.** A sea Flying type that is no bird (Mantine, for example)
  still flies by but never plunges into the water; Wingull, Pelipper and the other real birds do.
- **A new party leader becomes your follower.** Putting a different Pokemon first in your party
  makes it your follower, like the lead in the original games, even if you had sent another one
  out. You can still pick any Pokemon and job in the party menu; that choice stays until you
  change your leader again. Moving your current partner to the front keeps its job.
- **Species Sizes measured against you.** Each Pokemon is now sized by its real height next to the
  player, who stands for an adult: knee-high ones come up to about half your height, the biggest
  tower over you at a little over twice it. Tiny and giant ones are eased toward a sensible
  smallest and largest size instead of becoming specks or filling the screen, and HGSS and
  PMDCollab sprites of the same Pokemon now come out the same size.
- **Tall partners duck under roof edges.** A big follower walking in front of a house no longer
  has its head cut off by the eave: it dips a little and, if it is still too tall, crouches down
  until it clears the roof (with a little sweat drop by its head while it does), then stands back
  up. Behind a house or a tree it still hides as before. Talk to it while it's crouched and it
  tells you it's cramped and would like to move on, with a worried face.
- **Your partner steps into its ball for the nurse and for cutscenes.** At a Pokemon Center
  counter it goes into its ball while the heal machine runs and comes back out after; it does
  the same during any story scene that moves you or someone else about, and comes back out when
  the scene ends. Just talking to someone leaves it out.
- **Every PMDCollab Pokemon has a shiny look now.** 39 species (Tranquill, Flamigo, Bombirdier,
  Squawkabilly, the Alcremie flavours, Ogerpon's masks and more) had no shiny PMDCollab art, so a
  shiny one looked normal. Their shiny is now made from their HGSS shiny colours, keeping the
  PMDCollab shading. A few others missing one animation's shiny (Archen, Marshadow ...) are filled
  in the same way.
- **Visible wild Pokemon in the Safari Zone.** The Safari Zone (Kanto and Hoenn) fills with
  visible Pokemon like everywhere else; walking onto one starts a real Safari Zone battle, with
  Safari Balls, bait and rocks. With Classic Enc off they are the only encounters there, as on
  any route. Sweet Scent calls them over there too, and a partner on the Battle role leaves them
  alone. Species Modern Spawns brings into the Safari Zone battle just the same.
- **Wild Pokemon arrive instead of popping in.** A new one rises out of the grass while the
  grass rustles (the extra-tall grass of Routes 119 and 120 with its own rustle), surfaces from
  the water inside three rings that spread outward, or fades in on bare ground, over about half a second. When one leaves
  (lowering Spawn Amount, out of reach) it sinks back the same way. A route's first Pokemon,
  ones you battled and map changes stay instant.
- **Sweet Scent calls wild Pokemon to you.** Used outside battle, it no longer starts an instant
  classic battle (it did even with Classic Enc off): 2-3 wild Pokemon come out 1-4 tiles away,
  with hearts floating over them, and wait for you for about a minute before wandering off. A
  battle with one starts with its evasion lowered one stage (75%), like the in-battle move. With
  Show Wild Mons off, Sweet Scent works as in the original game.

### Fixed

- **Birds fly whole.** In HGSS / PokeMMO style, birds in the sky (Wingull, Pelipper,
  Butterfree ...) and ones swooping down onto the water or taking off from it flew with their
  over-the-water sprite, cut off at the waterline. They now fly with their normal sprite, wings
  out, and swim once they are down on the water.
- **PMDCollab Pokemon stand where you do.** Their feet sat a pixel below the player's, and ones
  whose idle is a little bounce (Kakuna, Pikachu, Charmeleon ...) sank into the ground while
  resting, by up to six pixels. They now rest on the ground at the player's feet.
- **Lighter on weaker devices.** Wilds makes about a quarter of the memory churn it did (less
  than 1.7.5 too, even with the new sky and water life): each sprite looks up its size and its
  sheet once instead of several times a frame, birds in the sky reuse what they draw with, and
  your partner's details are checked only when they change.
- **HGSS Pokemon stand on the ground.** HGSS / PokeMMO style Pokemon, wild ones and your
  partner, floated a few pixels above the ground (the empty rows under the feet in their sprite
  frames). Their feet now touch the ground like the player's. PMDCollab Pokemon too: they stood
  a few pixels up, or with a walker's front hooves below the ground; flyers still hover.
- **HGSS partner walks properly.** An HGSS / PokeMMO style partner held one walk frame through
  each whole step and flashed its standing pose between steps: on some (Quilava) a twitchy glide.
  It now steps like the player and NPCs do, a foot forward for half a step then standing, the
  other foot on the next step.
- **No softlock when an egg hatches on the step that meets a wild Pokemon.** Stepping onto one
  on the very step an egg hatched started the battle in the middle of the step, and the hatch
  scene opened over it: the "Nickname?" Yes / No then never answered. The battle now waits until
  the game is free (no hatch, poison or other step event, no message or menu) and starts right
  after, with the same Pokemon -- as the original games never roll a wild encounter on a step
  that hatched an egg. Meanwhile you stay on its tile (a held direction or a ledge no longer
  carries you past it before the battle opens).
- **Your partner rides in its Poke Ball on a bike.** Getting on a bike sends it back into its
  ball, and it comes out again when you get off (its Forage / Battle role pauses meanwhile).
- **A worn-out Battler no longer pops out on a new map.** One resting inside you at 1 HP came
  back out for a moment after every map change or save load before going back in.

## 1.7.5 (2026-10-13)

### Fixed

- **Turning down a new move no longer leaves your partner stuck.** If you closed the Learn Move
  screen without learning the move (or stopped an evolution), "New move ready!" stayed over your
  partner and it kept earning no EXP for good. Closing the screen now turns the offer down: the
  label goes and EXP flows again. A stopped evolution is offered again at the next level-up, as in
  the original games. A partner already stuck is freed the next time you open Learn Move and back out.

## 1.7.4 (2026-10-13)

### Fixed

- **Cutscenes no longer break when you're walked into a wild Pokemon.** A scene that moves your
  character (like Wally's catching lesson) started a battle if it walked you onto one, breaking the
  scene. No wild battle starts while a cutscene runs, and wild Pokemon no longer get in the way of
  the characters a scene moves.
- **Trainers no longer freeze when a wild Pokemon reaches you mid-challenge.** If a trainer had
  spotted you and a wild Pokemon walked into you, a wild battle started and the trainer froze. No
  wild battle starts while a trainer is coming over.
- After either, a wild Pokemon left on your tile doesn't jump you the moment the scene ends: step
  off and back on to battle it.
- **Only one roaming legendary.** On the map where FireRed / LeafGreen's roaming Raikou, Entei or
  Suicune (or Emerald's Latias / Latios) was, several of it could appear at once (a player saw 5
  Suicune). It is one Pokemon: at most one shows up.
- **The roaming legendary keeps its damage.** Battling it from the overworld started it at full
  health again; it now has the HP and status it was left with, and if it has been caught or
  defeated since it appeared, it simply leaves. Your partner's BATTLE role leaves it alone.
- **With Modern Spawns, no second roaming legendary.** Modern Spawns' rare legendary spawns no
  longer place the species that is still roaming. Once you catch it, Modern Spawns stops offering
  it as usual; if you defeat it instead, Modern Spawns can still offer it as a second chance.
- **Wild Pokemon sink into the extra-tall grass of Routes 119 and 120** the way you do, instead of
  showing the short-grass tuft at their feet.
- **Every Pokemon on screen keeps its Gen 3 HD Sprites size.** Wild Pokemon far off screen were
  drawn every frame too, and each used up one of Gen 3 HD Sprites' layers (12): on a busy route
  some Pokemon you could see were left at their small size. Only the ones near the screen are
  drawn now (less work on every device too).
- **Several checks that never worked now do:** the reachable area respects the badges Cut, Rock
  Smash and Strength need; your partner's menu doesn't open during a script; the party menu knows
  when a battle is on; the menu's select sound plays.

### Changed

- **Much smaller downloads, same sprites.** Sprites are now packed as colour numbers plus a small
  colour list, with each Pokemon's normal and shiny sheets sharing one drawing. Every sheet comes
  back pixel for pixel the same as before (checked for every sprite at build time), so quality,
  colours and sizes are unchanged. The HGSS + PMDCollab build drops from about 85 MB to about
  28 MB, and the HGSS Only build from about 11 MB to 3 MB.
- **Sprites load faster.** The packed sprite files are a quarter of the size to unpack, so a fresh
  session's first sprites appear about twice as fast (about 0.65 s instead of 1.5 s for 240 sheets
  in testing).

## 1.7.3 (2026-10-13)

### Changed

- **Water Pokemon fill every lake and sea**, Surf or not, for atmosphere. Before, they only appeared
  up to 4 tiles from a shore you could reach (all water once you had Surf). Land Pokemon still only
  appear where you can walk to, and Surf no longer changes that area: land across the water fills
  in once you are there.

- **No more periodic hitch.** Wilds used to re-check where you can walk every 15 seconds while you
  stood still (about 12 ms on a big route like Route 119). Now it re-checks only when something
  that matters changes: a tree cut, a rock smashed, boulders pushed, or Cut, Rock Smash or
  Strength becoming usable. A boulder puzzle costs a single re-check once you pause, not one per
  push.
- **Much less work every frame.** Keeping wild Pokemon topped up no longer copies the map's whole
  list of spawn spots every tick. On a large route that was about 0.3 ms and 18 MB of garbage a
  second, now practically nothing: fewer garbage-collection stutters, most noticeable on Android
  and other low-power devices.

## 1.7.2 (2026-10-11)

### Added

- **For other mods** (thanks to HimioneGranger, PR #2): `mod.exports.spriteAtlas` (optional memory
  limits: `configure`, `stats`, `release`), `mod.exports.enginePatch` (`cacheModules`) and
  `mod.exports.hdField` (species sizing data), for alternate renderers. Nothing changes unless a mod
  uses them.

### Changed

- **Smoother on weaker devices:** Wilds looks up the game's engine pieces once per session instead of
  on every use. Each lookup went from about 0.7 µs and 78 bytes of garbage to about 0.03 µs and none,
  which means fewer garbage-collection pauses.

## 1.7.1 (2026-10-11)

### Changed

- **Species sizes are gentler** (with Gen 3 HD Sprites), in both sprite styles. The smallest
  Pokemon (Geodude, Joltik, Diglett) are about 11-12 px tall instead of 7-8 px, the biggest
  (Kyurem, Koraidon, Rayquaza) about 40 px instead of 60+, and everything in between moves
  toward the middle. Big Pokemon are still bigger than small ones.
- **PMDCollab Pokemon stand on the ground.** Some PMDCollab sprites float above the spot they
  stand on (Gyarados, Seviper, Drifloon and about 160 more), which looked like hovering on
  land. They now stand on the bottom of their art, like the rest. True flyers (Zubat, Gastly,
  Rayquaza ...) still hover.
- **Swimming Pokemon keep off the bank.** A water Pokemon no longer spawns or swims on the last
  row of water before a bank to its south, where it looked like it was bobbing on the ground.
- **Shiny PMDCollab Pokemon stay shiny when they fight** your Battler. Their attack and hurt
  animations used the normal colours; now they use PMDCollab's shiny art (about 1,010
  species). Archen, Venipede, Dedenne, Necrozma and Marshadow have no shiny fight art upstream,
  so theirs is recoloured with their own shiny palette. The HGSS + PMDCollab download is about
  19 MB bigger for it.

### Removed

- **The Overworld Size option.** With Gen 3 HD Sprites, each species is drawn at its hand-tuned
  size (Species Sizes), so a global percentage on top was redundant. A saved Overworld Size
  setting is simply ignored, and sprites are drawn at 100%.

## 1.7.0 (2026-10-10)

### Added

- **Shiny chains** (needs [Modern Spawns](https://github.com/poooooby/g1r_modern_spawns)).
  Win or catch the same species again and again and the chain grows:
  - It turns up more often wherever it lives: 1 in 8 encounters at a chain of 2, every encounter
    from 9. This covers visible spawns and Classic Encounters alike.
  - It's more likely to be shiny: about 1 in 82 at a chain of 100.
  - It has better stats: 1 / 2 / 3 perfect stats from a chain of 10 / 25 / 40.
  - Wins by your Battler companion count too.
  - Running from it or blacking out ends the chain, and another species starts a new one.
  - Switch it off with Modern Spawns' **SHINY CHAINS** option (default ON). A chain in progress is
    kept for when it's back on.

  Modern Spawns keeps the count; Wilds makes the shiny, keeping its nature and gender. Inspired by
  TTiN and Untamed Tohjo, used with permission.

- **Zygarde 100% (Complete Forme) has its own HGSS / PokeMMO sprite**, normal and shiny, on
  land and swimming. It's baked from pokeemerald-expansion's follower sprite and palettes,
  enlarged to the same size as Zygarde 50%, with or without Gen 3 HD Sprites. Before, it fell
  back to PMDCollab or base Zygarde art.

### Changed

- **The SHINY RATE option is gone, replaced by shiny chains.** Without Modern Spawns, wild
  Pokemon keep the game's own shiny odds. A saved SHINY RATE setting is simply ignored.
- **Water Pokemon appear near the shore without Surf.** Before, water spawns only appeared on
  water you could surf to, so lakes and the sea stayed empty until you had Surf. Now water up to
  4 tiles out from any shore you can reach has visible water Pokemon too. A Battler swims out to
  fight them when they're in range, using its swimming sprite.

## 1.6.2 (2026-10-10)

Includes everything from 1.6.2-beta.1 (below).

### Added

- **PMDCollab Pokemon swim.** PMDCollab has no water art, so water Pokemon used to stand on the
  water in full. Now they sit in it like the HGSS swim sprites: the body ends in a curved bowl of
  pale foam that follows the width of each frame (narrow from the front, wide from the side). Each
  species shows as much of itself as its HGSS swim sprite does (about 75-90%); species without
  HGSS swim art show 80%.
  - **While you Surf, a PMDCollab companion swims along behind you** instead of shrinking into
    you.
  - **Swimmers sit a little lower in the water** for the RSE perspective: PMDCollab swimmers
    (the bowl's bottom is 2 px below the tile) and the HGSS / PokeMMO swim sprites alike
    (4 px lower, `Config.SWIM_DROP`).
- **Water reflections and ripples for wild Pokemon and your companion, in both sprite styles.**
  The game reflects the player and every NPC on ponds, puddles and ice, and the player leaves a
  ripple on pond water. Now our Pokemon get the same:
  - **Reflections** are mirrored below the sprite and shown only on reflective tiles. On RSE
    water they have the game's wobble, and they stay under bridges and shore tiles.
  - **Our art has no reflection palette, so reflections are blended toward a pale blue**
    (`Config.REFLECTION_TINT`, `REFLECTION_MIX`), to match the paler look of the game's own.
  - **With Gen 3 HD Sprites, reflections are drawn at window resolution too.** They're exactly
    the size and place of the plain ones (this needs Gen 3 HD Sprites 0.2.0 or newer; older
    versions draw them the plain way).
  - **Ripples:** each step onto pond water or a puddle leaves the game's own ripple.
  - **True flyers and floaters stay whole over water.** This covers species like Zubat, Gastly,
    Koffing and Rayquaza. Winged walkers such as Charizard and Pidgeot sit in the water.
  - **The flyer list can be edited by hand** in `lib/pmd_water.lua`. It was seeded by
    `tools/generate_pmd_water.py`.
  - **The cut and foam are worked out when the art is baked.** The bowl is stored as
    `waterline` and `bowl` in `index.json`. The few rows inside it are a tiny band sheet drawn
    over the cut. The art itself isn't copied, so the ZIP stays about the same size.

### Changed

- **The Battler fights water spawns reliably.** Before, it only walked on land. It never fought
  anything while you surfed, and a water spawn only counted if a land tile touched it. It also
  ignored wild Pokemon that were mid-step, which water spawns often are.
  - It now swims out to water spawns, both from the shore and while you surf, and is drawn
    swimming while it's on the water (both styles).
  - It picks up a wild Pokemon mid-step and plans for the tile it's stepping onto. That Pokemon
    finishes its step instead of freezing between tiles.

- **Foraging reworked: every trip finds something, and friendship matters.** The Forager no
  longer makes idle trips or digs up nothing. Every 1-3 minutes of walking it catches a scent:
  it stops and perks up, a glint appears on the ground 3-5 tiles away, it dashes over, digs and
  always comes back with an item (it only sets out when the find will fit in your bag).
  - The fonder it is, the sooner it finds things (about every 2.3 min at low friendship, 1.5 min
    at max) and the more eager its tell and dash.
  - Finds come in four rarity tiers. Rare finds (Ultra Balls, dear healing items, evolution
    stones and National Dex Gen 3's evolution items) need friendship 130; the rarest (top
    revives, the 3000-price evolution items) need 200; above that, higher friendship tilts the
    odds further toward them. A rare find cries twice, bounces and keeps its label up longer.
    The friendship idea is inspired by TTiN and Untamed Tohjo (credited in the README and
    THIRD_PARTY_NOTICES.md).
  - Confirmed against the real mod loader: with National Dex Gen 3 installed, all 36 of its
    evolution items are in the Forager's pool (rare / very rare by price).

### Fixes

- **The follower no longer appears on the door, over the building, when you come out.** Leaving
  a building, a cave or taking stairs, the game places the follower in the doorway while you are
  walked out, so it was drawn on the door (a big sprite well over the roof). It now stays out of
  sight in the doorway and fades in as it steps out behind you. Walking across a route border,
  Fly, a fall and loading a save are unchanged.

## 1.6.2-beta.1 (2026-10-09)

### Added

- **Species Sizes** (with the Gen 3 HD Sprites mod): each HGSS / PokeMMO species is drawn
  at its own relative size, the per-species table from Wilds of Kanto Revival (0.67x to
  1.2x of the sheet, a form sized like its base species). It multiplies with Overworld
  Size, applies to wild Pokemon, water Pokemon and the follower, and is on by default; it
  does nothing without the library. A large follower is spaced out from the player by
  its drawn width, not the sheet's.
- **`lib/HGSS_scale.lua` and `lib/PMD_scale.lua`**: the per-species size tables, one per
  sprite style, edited by hand. A dex number sizes a
  species and its forms; a form key like `479-heat` sizes one form. A PMD sheet now scales
  about its baked ground point, so shrinking one keeps it standing on its tile.
  `PMD_scale.lua` is sized so each PMD sprite is as big as its HGSS one (mean of height and
  area), with a pixel-density floor from 0.49 (small) to 0.8 (big) so a large Pokemon is not
  shrunk into a tiny, too-fine sprite (`tools/generate_pmd_scale.py`).

### Fixes

- **PMDCollab sprites and portraits for Pokemon #1-99 were missing** in 1.6.0 and 1.6.1 (they
  drew as HGSS, with no portrait). The form update wrote the PMD index with zero-padded keys
  ("006") that the game never looked up; #100 and up happened to match. The bake now keys base
  species by plain dex number, and the validator and a unit test check it.
- A small follower facing down could stay stuck off to one side after walking left or right,
  until you turned a different way. Its offset now always eases back to the centre.
- A wide PMD follower (a long-tailed Tyranitar) trailed nearly two tiles behind when you walked
  left or right: only 60% of its overhang is kept behind you there now
  (`PMD_FOLLOWER_SIDE_OVERHANG`, like the down factor).

## 1.6.1 (2026-10-09)

### Added

- A Battler that levels up now asks you to finish the job. It cannot learn moves or
  evolve mid-walk, so "New move ready!" and "Ready to evolve!" float over its head
  (alternating when both apply) until you face it, press A and pick **Learn Move**
  or **Evolve** from the menu, which opens the game's own move relearner (listing
  only the moves it skipped) or evolution scene (you can stop it). Remembered per
  Pokemon in the save; it stops asking when the move is known or the evolution is
  no longer possible. It is kept per Pokemon in the save, so it survives a battle,
  leaving the area, recalling the Pokemon, swapping it out, the PC and a reload,
  and a request to evolve stays until the Pokemon evolves. A Pokemon holding an
  Everstone never asks to evolve (the request returns if the stone comes off), and
  while a move or evolution is waiting the Battler earns no more EXP, so no level
  (and no move) is skipped.

## 1.6.0 (2026-10-08)

### Added

- Alternate forms draw their own art. With National Dex Gen 3 installed, a form in
  your party or a wild spawn (Wormadam-Sandy, Rotom-Heat, Galarian / Hisuian forms,
  Flabebe colours ...) is looked up by its form (`%03d-<form>`, e.g. `479-heat`)
  instead of its base species' dex number. PMDCollab has 68 form sheets and 64
  form portraits (a form without its own portrait shows its base species') and HGSS has 73 (from the Wilds grids and the Gen 9
  follower pack). A form with no art of its own draws its base species: Pumpkaboo /
  Gourgeist sizes, Zygarde Complete, Antique Sinistea / Polteageist, Artisan
  Poltchageist, Masterpiece Sinistcha (no different sprite exists for them), and a few
  PMD forms. See `tools/form_art_map.py`.

## 1.5.0 (2026-10-08)

### Fixes

- A shiny Pokemon's follower is now shiny too (it was always drawn in normal
  colours). It uses the same real shiny check as the overworld spawns, on the
  Pokemon's own personality and trainer ids, and rebuilds when you swap to or
  from a shiny.

## 1.4.0 (2026-10-08)

### New

- Talk to your Pokemon (face it, press A) and the menu is now Interact
  (Pet / Play / Talk), Role (Follow / Forage / Fight) and Recall, each sub menu
  with a Back row (B goes back too). Recall shrinks it back into you;
  it stays inside until you pick a job for it again, from this menu or from the
  party menu's ROLE row.
- The party menu now has a single ROLE row (with a right arrow) that opens a sub
  menu: Follow / Forage / Fight / Back (B goes back too). It replaces the three
  Follow / Battle / Forage rows, and always fits the box, so the one-row
  COMPANION fallback is gone.
- Changing the companion (another Pokemon, another job, or a recall) is now a
  scene: after you close the menu, you raise a Poke Ball in one hand, the old
  companion shrinks into you, then you raise it again and the new one grows
  out and cries. (`lib/follower_swap.lua`, `Config.SWAP`)

### Fixes

- The "+EXP" / "Found X!" label is no longer cut off on Android (and other
  window scalings): it is drawn once into a tiny canvas and drawn like a
  sprite, instead of being clipped with a scissor rectangle.
- The same label was also cut off on FireRed / LeafGreen (its text was drawn
  too high for that game's small font); it now sits inside its box on both.
- The follower's grass: a big follower is drawn away from its own tile, so the
  grass tuft over that tile cut across its body. The grass now goes on the grass
  tiles under its real feet, snapped to the tile grid. A companion inside the
  player has no grass.

## 1.3.0 (2026-10-07)

### Fixes

- PMDCollab: fixed walking sprites flicking to their Idle pose between steps
  (Treecko) and Grovyle looking like it was floating. The game reports
  "not moving" for a tick or two between chained steps, which dropped the
  sprite to Idle and restarted its walk; the Walk animation now keeps playing
  for a few ticks after movement stops (`Config.PMD_WALK_LINGER`).

## 1.2.2 (2026-10-07)

### Changes

- PMDCollab art update: 20 more species now have PMD sprites (997 of 1025;
  the rest still fall back to HGSS / PokeMMO), including 18 hand-added ones
  credited in `THIRD_PARTY_NOTICES.md`. Seven species (Vileplume, Machamp,
  Hitmonchan, Jynx, Exploud, Walrein, Aegislash) gained their full set of 16
  portrait emotions.
- `assets/pmd/CREDITS.txt` now also credits the portrait artists, and the
  hand-added sprites' artists.
- (HGSS Only build: no change from 1.2.1.)

## 1.2.1 (2026-10-07)

### Changes

- The Forager now heads out every 5-15 seconds of walking (was every 1-2.5 s).
- The Forager only cries when it actually finds something; a dig that turns
  up nothing is silent.

### Features

- Follower interactions fleshed out: **Play** +3, **Pet** +2, **Talk** +1
  friendship. A Pokemon that is hurt (under 25% HP) or has a status
  condition **refuses to play** and says why ("is sick and can't play").
  **Pet** has a 25% chance to cure a status condition ("feels better
  now!"). **Talk** reports how fond of you it is as a share of maximum
  friendship (wary, curious, starting to like you, trusts you, really likes
  you, loves you) with a matching portrait.

## 1.2.0 (2026-10-07)

### Features

- **Companion roles** (Scarlet / Violet style). Open the party menu, pick ANY
  party Pokemon and choose **Follow**, **Battle** or **Forage**: it becomes
  the one out in the overworld with that job. The **Follower** option is
  gone (a companion is always out; the party lead follows until you choose).
  - **Battle**: it stays near you and, when everything is still, charges
    any wild overworld Pokemon within 3 tiles of you for a short fight using
    its REAL moves, stats, damage and PP, with health bars over both, a hit
    effect and attack / hurt animations (PMD: the species' own Attack and
    Hurt sheets; HGSS: a rapid idle). A defeated wild Pokemon cries and sinks
    into the ground; the Battler earns a small share of the EXP. It is never
    knocked out: at 1 HP (or out of attacks) it runs back, cries and shrinks
    into you and stays inside until it is healed.
  - **Forage**: while you are walking, outside on a route or in a cave (never
    in a building, town, city, the Safari Zone or on the water), it roams 5-10
    tiles around you on open ground and runs back to your side; every 10-30
    seconds of walking it goes foraging: it cries to alert you, digs, has a 20%
    chance to turn up an item for your bag ("Found Potion!"), then runs back
    quickly. The timer carries across map changes. Finds: healing and status items, Poke
    Balls, berries, evolution stones and the extra evolution items National
    Dex Gen 3 adds, cheap TMs. Never HMs, key items, Master Balls, Rare
    Candy or high-level TMs.
- The PMDCollab build bakes two more animations per species (Attack, Hurt).

## 1.1.1 (2026-10-07)

### Fixes

- HGSS / PokeMMO sprites now draw in a release ZIP. Their sheets ship only
  inside the sprite atlas there, and the art lookup only looked for loose
  files, so switching to the HGSS style (and the whole HGSS Only build, and
  PMD builds' ~48 species without PMD art) drew nothing.

## 1.1.0 (2026-10-06)

### Features

- Follower interaction scenes: **Play** has you throw a ball (the engine's
  arms-up pose) that the follower runs to, spins around and brings back;
  **Pet** plays a quick Idle then its cry; **Talk** plays its cry three times.
  Each runs before the result message and portrait, with the field locked.
  Works in both Sprite Styles; tuned through `Config.ACTIONS`.

## 1.0.1 (2026-10-06)

### Fixes

- PMDCollab: large sprites are no longer scaled up (the baked true-size
  scale is ignored; `Config.PMD_TRUE_SIZE` turns it back on).
- PMDCollab follower: tighter spacing while walking down (tall sprites like
  Rayquaza trailed too far above the player).
- PMDCollab follower: the offset slides at a capped speed when the player
  changes direction, so large sprites glide instead of snapping.

## 1.0.0 (2026-10-06)

Two builds per release: **HGSS Only** (small, for low-power devices) and
**HGSS + PMDCollab** (animated walk/idle, portraits, follower
interaction; its art is CC BY-NC, non-commercial only).

Visible wild Pokemon and the party follower have been confirmed working
in a real game session. FireRed / LeafGreen support, the surf recall and
the rest of `docs/MANUAL_TEST.md` are not yet play-tested.

### Features

- Visible wild Pokemon in grass and water for Ruby, Sapphire and Emerald,
  generated via the engine's own `rollSweetScent` (ability bias,
  Synchronize/Cute Charm, roamers, Emerald outbreaks, Ruby/Sapphire IVs
  all included; nothing about wild generation is reimplemented).
- Modern Spawns integration (soft, no dependency): when the `modern_spawns`
  mod is installed and active, each visible spawn takes the species Modern
  Spawns generated for the slot the engine rolled (plus its LEGENDARIES
  roll). Level, personality and the rest of the engine's roll are kept.
  See `lib/modern_spawns_bridge.lua`.
- Idle flap: floating/flying species (those in the baked `levitates` pack, used as a species reference only -- never drawn) slowly play their walk frames while standing still, for wild spawns and the party follower.
- Water art (swimming/levitates) is baked shrunk to match each species' land size (`tools/generate_true_size_18frame.py`, same perceived-size idea as Wilds of Kanto Revival). Re-run the generator with `--kind swimming,levitates --force` after a fresh asset copy.
- PMDCollab Sprite Style (third option): fully animated Walk and Idle loops from SpriteCollab, timed by each species' AnimData.xml frame durations, for wild spawns and the party follower. Baked by `tools/generate_pmd_sprites.py` (needs a sibling `../SpriteCollab` checkout; output `assets/pmd/` is gitignored and packed into the release atlas). Species without PMD art fall back to HGSS / PokeMMO. See `THIRD_PARTY_NOTICES.md` for the licence (CC BY-NC).
- Portrait system (`lib/portrait_ui.lua`): a 40x40 PMDCollab portrait (all 16 standard emotions; a species missing one falls back along a chain ending at Normal) whose face follows the Pokemon's real state (`lib/mon_mood.lua`: fainted / critical HP / status condition / low HP / friendship tier) drawn above the left of the dialogue box while a message is open, via a new `Message.draw` hook in `lib/engine_patch.lua`. Baked by `tools/generate_pmd_sprites.py` into `assets/pmd/portraits/` + `portraits.json` (1025 species, shiny sheets where SpriteCollab has them). Exposed as `mod.exports.portraitUI` (`say`, `show`, `setEmotion`, `clear`); the follower interaction menu is the first user.
- Follower interaction: face your follower and press A. It tells you how it is (portrait + words from its real HP, status and friendship), then offers Pet / Play / Talk / Cancel. Pet uses the engine's own massage friendship event; Play and Talk give a small flat gain. Rate-limited (`Config.INTERACT`): per-action cooldowns, a budget per 10 minutes, and an escalating lock-out (5 min, doubling to 1 h) for button-mashing; the state lives in `mod.storage` so reloading a save or rewinding does not reset it, and a set-back clock does not skip a cooldown.
- Reachable-only spawns (`lib/reachability.lua`): wild Pokemon appear only where the player can actually get to from where they stand -- a flood fill built on the engine's own `Collision.canEnter` (walls, elevation, one-way ledge hops), so sealed cave chambers, fenced-off ground and waterways cut off from the player never spawn anything. Water counts only once Surf is usable (or while surfing); Cut trees, smashable rocks and boulders block until their move is usable; NPCs and item balls do not. Re-measured on map entry, when the player ends up outside the area, and every 15 s (so learning Surf or cutting a tree opens new ground). `Config.REACHABLE_SPAWNS` turns it off.
- `scripts/build-mod.py` now bakes PMDCollab itself: when a SpriteCollab checkout is found (`$SPRITECOLLAB`, else `../SpriteCollab`) it runs `tools/generate_pmd_sprites.py` (only missing sheets; `--rebake-pmd` rewrites all, `--no-pmd` skips), then packs the Walk, Idle and portrait sheets into the release atlas (`pmd_walk`, `pmd_idle`, `pmd_portraits`) and fails the build if an atlas family is missing. 977 species (every Gen 1-3 species included); the 9 that ship an Idle animation but no Walk (Stunfisk, Aromatisse, Toucannon, Dachsbun, Grafaiai, Iron Treads, Ting-Lu, Gouging Fire, Raging Bolt) use their Idle frames, capped at 10 ticks each, as the walk loop. The remaining 48 have no sprite folder upstream and keep the HGSS / PokeMMO art.
- Poke Followers / GSC and the Pokewilds extension are removed (Kanto-only): `tools/copy_wilds_assets.py` no longer copies them, the atlas has no `poke_followers` family, the release has none of their art, and the Sprite Style option is HGSS / PokeMMO or PMDCollab. A saved "Poke Followers / GSC" setting falls back to the new default, PMDCollab (species without PMD art use HGSS / PokeMMO).
- Shiny portraits are no longer baked (a shiny Pokemon talks with its normal face): about half of the portrait art and ~12 MB off the release. `--shiny-portraits` on `tools/generate_pmd_sprites.py` brings them back.
- Fixed: walking straight through a wild Pokemon (holding a direction, e.g. in a cave) did not start a battle -- only stopping on it did. Contact is now the engine's `world.stepped` event, so arriving on its tile always counts.
- Two release builds from one command (`python3 scripts/build-mod.py`, or `--variant hgss|pmd`): `wilds-of-hoenn-v<ver>-hgss.zip` (HGSS / PokeMMO art only) and `wilds-of-hoenn-v<ver>-hgss-pmd.zip` (HGSS / PokeMMO + PMDCollab). Same code and mod id; the mod hides the PMDCollab Sprite Style, and defaults to HGSS / PokeMMO, when no PMD art is installed (`Config.hasPmdArt`). Only the `-pmd` build carries the CC BY-NC PMDCollab art.
- PMDCollab follower while surfing: PMD has no swim art, so the follower shrinks into the player like a Poke Ball recall and grows back out once it is on land (`Config.PMD_RECALL_TICKS`, `PMD_RECALL_LIFT`). It stays in until the follower itself is off the water, and cannot be talked to while inside. HGSS / PokeMMO still uses its swim art.
- FireRed and LeafGreen are supported alongside Ruby, Sapphire and Emerald: the boot gate accepts both Gen 3 layouts (`EnginePatch.layoutName()`), FRLG spawns roll the personality the FRLG encounter rules leave out (so the sprite's shiny/gender is the Pokemon you fight), and Safari Zone maps (both families) spawn nothing so the engine's own Safari battles are untouched. Verified against the real engine's FireRed and LeafGreen boots; not yet play-tested in game.
- Idle and Roam behaviours.
- Contact with a visible wild Pokemon starts a battle with that exact
  mon (species, level, personality, IVs, roamer-ness).
- Gen 3 shiny check against the live trainer id, with an optional
  Boosted re-roll that keeps nature and gender (SHINY RATE option).
- Silhouette option (Off / Undiscovered / All).
- Optional party follower, via the engine's public `world.follower.spawn`
  hook.
- Classic Enc toggle for the original step-based random encounters
  (fishing and Rock Smash are unaffected either way).
- Sprite Style option: HGSS / PokeMMO or PMDCollab (Wilds of Kanto's Poke
  Followers / GSC style is Kanto-only and not part of this mod). HGSS /
  PokeMMO is "True Size" -- each species drawn at its own native frame
  size, anchored at its feet, the same way Gen 3's own native overworld
  sprites anchor a variable-size OAM shape to a 16px cell). Switching
  takes effect immediately on already-spawned wild Pokemon and the
  follower, not just new ones.
- Overworld art is a read-only copy of Wilds of Kanto Revival's sprite
  sheets (`tools/copy_wilds_assets.py`), both styles, covering national
  dex 1-1025 -- not capped at Gen 3's native 386, since a National Dex
  expansion mod (`national_dex_gen3`) can put later species in a real
  save. Shipped as a baked atlas, not 1000+ individual files (see
  "Sprite atlas" below).
- Sprite atlas (`lib/sprite_atlas.lua`, `tools/generate_sprite_atlases.py`,
  default in `scripts/build-mod.py`): packs the ~3900 per-species sheets
  into a handful of shard PNGs + JSON indexes at release time, served
  under their original paths. A repo checkout (or `--no-atlas` build)
  keeps the real per-file sheets and never touches the atlas; it exists
  purely so the release ZIP and the GitHub history don't carry thousands
  of individual PNGs.

### Known gaps (tracked for a later version)

- No Chase or Hidden behaviours.
- No Spawn Amount / density option (fixed curve).
- No Dive/underwater map support.
- Safari Zone and Battle Pike/Pyramid are left fully vanilla (no visible
  spawns there).
