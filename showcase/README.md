# Showcase reel

A scripted "director" that stages every Wilds of Hoenn feature in the real game and moves
the camera (pans, zooms, following a subject) so you can record trailer footage with your
screen capture. Lives on the `showcase` branch only and never ships in a release ZIP.

## Running it

From the repo root (the repo linked into `../gen1recomp/mods/` by `scripts/bootstrap.sh`,
with the game's ROM imported). PowerShell or cmd:

```powershell
showcase\run.cmd emerald            # the Emerald reel from shot 1
showcase\run.cmd firered            # the FireRed reel
showcase\run.cmd emerald 9          # start at shot 9
showcase\run.cmd emerald everything # start at a shot by name
```

Git Bash: `sh showcase/run.sh emerald ...` (the same arguments). The reel runs at 1x: a
scripted run steps the game once per rendered frame, so the launchers ask the engine to
pace frames and the director pins the cap at 60 fps (left to itself it would follow the
display and run 2.4x on a 144 Hz monitor). The console prints each timed shot's real
seconds so you can check.

A new game starts by itself and jumps straight to the first shot. Your gen1recomp
`options.lua` is backed up first and put back when the window closes (the reel changes Wilds'
options in memory only: PMDCollab sprites, everything on, no Classic encounters).

## Controls

| Key | |
|---|---|
| **Page Down** | roll the staged shot; once it is done, stage the next one |
| **Home** | stage this shot again (a retake); while rolling, cut it short and restage |
| **Page Up** | back to the previous shot |

Each shot is staged first (map, party, Pokemon, camera at its opening frame) and waits for
you, so start recording, then press Page Down. The window title says where you are
(`READY` / `ROLLING` / `DONE`) and the console prints the same; nothing is drawn on the
footage. Wild battles are off for the whole reel, so nothing interrupts a shot.

## Recording tips

- Capture the game window (or its client area) so the title bar stays out of frame. Size
  the window to your target resolution (e.g. 1920x1080) before you start: the reel zooms
  and pans inside whatever size it has.
- Shots with a text box (pet, play, talk, the cramped Gyarados, Gengar) use the game's own
  zoom, so the text box and portrait stay whole; the others glide with a smooth zoom.
- Some moments are random (where a bird perches, which way a fish leaps). If a take is not
  right, press Home and roll it again.

## The shots

**Emerald** (`shots_emerald.lua`): Petalburg City from above with birds on the roofs ·
wild Pokemon rising out of the grass · walking and running with your partner · Pet (portrait,
hearts) · Play (the ball) · the Battle job (a fight, EXP) · three type battles, each Hoenn
starter in the widest open ground of its own type's area against a slightly weaker foe
(Blaziken v Metagross in Fiery Path, Swampert v Aggron on Route 109's beach -- the Aggron is
placed on the sand by hand -- and Sceptile v Hariyama in Petalburg Woods; each landed hit is
capped for the reel so both sides trade attacks instead of a one- or two-hit knockout) · a
level-up (Swampert: the rainbow "Lv.", gold ring and "New move ready!", the player stepping
aside so it shows clear) · the Forage job (a find) · a shiny
partner twinkling · weaker Pokemon fleeing · a stronger one giving chase · Sweet Scent ·
a Taillow swooping in to land · sea life (leaping fish, a diving bird, Wailmer) · a Finizen
pod and a lone Finizen · Petalburg Woods · Fortree's Tropius · under the sea · finale ·
**everything at once** (8 seconds): Route 104's cottage between the sea and the woods, 1.5 s
tight on you and Pikachu, a 3 s zoom out, 3.5 s wide, with every feature set going at once
and the usual per-feature caps lifted (staged by hand for the reel: nothing like it can
happen in the real game).

**FireRed** (`shots_firered.lua`): Pallet Town's birds · a tall partner ducking under a roof
and saying it's cramped · a Pikachu that loves you · Lavender Town's ghosts · the girl who
asks about ghosts, and Gengar · the Safari Zone · finale.

## Adding or changing a shot

A shot is `{ name, stage = function(ctx) ... end, roll = function(ctx) ... end }` in a
`shots_<game>.lua` list. The helpers are in `director.lua` (`ctx.go`, `ctx.party`,
`ctx.spawn`, `ctx.walk`, `ctx.run`, `ctx.tap`, `ctx.wait`, `ctx.waitUntil`, `ctx.clearWild`,
`ctx.hidePeople` ...) and the camera in `camera.lua`:

- `cam:set{ panX, panY | at = {wx, wy}, zoom }`: jump (pan in world px from the player)
- `cam:move{ ..., frames, ease }`: glide (ease `smooth`, `inout`, `out`, `in`, `linear`)
- `cam:track(fn, { zoom, lag })`: follow `fn()` -> world x, y; `cam:still()` stops
- `cam:engineZoom(step)`: the game's own zoom (0 FIT, 1 IN1, -1 OUT1), crisp, UI untouched

Testing without pressing keys: `SHOWCASE_AUTO=<dir>` rolls every shot by itself and saves a
frame every 1.5 s (`SHOWCASE_AUTO_EVERY=<frames>` to change) into `<dir>`;
`SHOWCASE_LAST=<n>` stops after shot n; `SHOWCASE_DEBUG=1` prints a few staging details.
