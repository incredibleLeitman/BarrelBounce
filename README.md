# BarrelBounce

One button. One ball. Many barrels.

You sit in a cannon. Tap anywhere (or click, or press any key / gamepad button) and the
cannon fires you in whatever direction it currently points. Land in another cannon and it
sucks you in so you can fire again. Cross the finish gate and your time is saved as a
high score. Fall off the world and you restart from the first cannon with the clock reset.

Cannons can't be aimed. They rotate, sweep, slide and orbit on fixed, deterministic
patterns, so the only skill is *timing*. Every start and every reset begins at tick 0, so
each level plays out exactly the same for every player.

Made with **Godot 4.3** (GL Compatibility renderer, works on mobile, desktop and web).

## Scenes

| Scene | File | What it does |
|---|---|---|
| Main menu | `scenes/main_menu.tscn` | Start, Level editor, Quit. A self-playing demo runs in the background. |
| Level select | `scenes/level_select.tscn` | Tabs: *My levels*, *Built-in*, *Community* (placeholder). Play / Edit / Remix / Delete, best times. |
| Level | `scenes/level.tscn` | The game. One input = fire. Timer, best time, win panel, next level. |
| Editor | `scenes/editor.tscn` | Drag cannons and the finish gate, set type / angle / movement, preview the motion, test play, save. |

All UI is built in code (`scripts/ui.gd`) and all graphics are drawn procedurally, so
there are no art assets to maintain yet. Replace freely.

## How it is built

```
scripts/
  simulation.gd        the whole game model: deterministic, tick based, no physics engine
  game_state.gd        autoload: scene navigation, level files, high scores
  ui.gd                theme + widget helpers
  level.gd             game scene (drives a Simulation at 60 ticks/s)
  main_menu.gd / level_select.gd / editor.gd
  view/                rendering only: LevelView, CannonNode, PlayerNode, FinishNode, Backdrop
levels/builtin_levels.gd   the shipped levels (same dictionary format as saved JSON)
tools/solve_levels.gd      headless brute-force solver, proves every built-in level is beatable
```

### Determinism

`Simulation` owns an integer `tick`. Cannon position and angle are pure functions of the
tick (`Simulation.cannon_state_at`), the ball is integrated with a fixed `DT = 1/60`,
and there is no randomness, no wall clock and no physics engine. `reset()` puts the tick
back to 0. Input is sampled once per tick as a single boolean ("was the button pressed").
That makes runs replayable from a list of tap ticks, which is exactly what the solver and
a future ghost / replay / leaderboard-verification feature need.

### Cannon types

| type | name | effect |
|---|---|---|
| `normal` | Cannon | launch speed 950 px/s |
| `strong` | Big Bertha | 1400 px/s |
| `weak` | Pea Shooter | 620 px/s |
| `dash` | Blink | teleports the ball 210 px along the barrel, then it flies on at 650 px/s |
| `double` | Hopper | one extra mid-air boost on a second tap |
| `bubble` | Bubble | 35 % gravity during the flight |
| `auto` | Hot Head | a fuse burns down for 45 ticks, then it fires on its own; tap earlier if you want |

The **start cannon is always a plain cannon**: a level must never fire without the player's
tap. The editor locks the type of the start cannon and loading a level enforces it.

### Movement behaviours (combine as many as you like per cannon)

| type | parameters | motion |
|---|---|---|
| `rotate` | `speed` °/s | continuous rotation |
| `sweep` | `from`, `to` °, `period` s | ping-pong between two angles (relative to the base angle) |
| `move` | `dir` (8 directions), `range` px, `period` s | ping-pong along a line |
| `orbit` | `radius` px, `period` s, `clockwise` | circle around the base position |

### Level format

Saved levels are JSON in `user://levels/<id>.json` (on Windows:
`%APPDATA%\Godot\app_userdata\BarrelBounce\levels\`). Scores live in `user://scores.json`.

```json
{
  "format": 1, "id": "user_1730000000_0042", "name": "My Level", "author": "You",
  "cannons": [
    {"x": 160, "y": 560, "angle": -45, "type": "normal", "behaviors": []},
    {"x": 640, "y": 300, "angle": -30, "type": "double",
     "behaviors": [{"type": "orbit", "radius": 120, "period": 3, "clockwise": true}]}
  ],
  "finish": {"x": 1100, "y": 160, "w": 60, "h": 400},
  "start": 0,
  "background": "space"
}
```

`background` is one of `space`, `underwater`, `meadow`, `sunset`, `cave` (all drawn
procedurally in `scripts/view/backdrop.gd`; pick one under *Settings* in the editor).

### Player profile

*Player* on the main menu lets you pick a ball colour and roll a random name. It is stored
in `user://profile.json` and used as the author of levels you create. It is the identity a
future shared leaderboard would use.

### Where your files live

`user://` is Godot's per-app data folder:

| platform | folder |
|---|---|
| Windows | `%APPDATA%\Godot\app_userdata\BarrelBounce\` |
| Linux | `~/.local/share/godot/app_userdata/BarrelBounce/` |
| macOS | `~/Library/Application Support/Godot/app_userdata/BarrelBounce/` |
| Android | app-private storage (`/data/data/com.donkeycat.barrelbounce/files/`), not reachable without root |
| Web | a virtual file system persisted in the browser's IndexedDB; clearing site data deletes it |

Inside: `levels/<id>.json`, `scores.json`, `profile.json`.

### Sharing levels with a code

Every level of yours has a **Share** button in level select that shows a code like
`BB1:eJyrVkrOz...` (the level JSON, deflate-compressed and base64-encoded, a few hundred
characters). Send it any way you like; the receiver pastes it under **Import code** and the
level lands in their *My levels* with the original author's name and a fresh id. The
`BB1:` prefix versions the format so later versions can still read old codes.

Coordinates are in the 1280x720 play area (y down). Angles: 0° = right, -90° = up.
Leaving the rectangle `Simulation.WORLD` (a bit larger than the screen) kills the ball.

## Running

Open the folder in Godot 4.3 and press Play. Headless checks:

```
godot --headless --import                            # build the script class cache (once)
godot --headless -s tools/solve_levels.gd -- 60      # solve every built-in level (60 s budget each)
godot --headless -s tools/solve_levels.gd -- 60 3    # only level index 3
godot --headless res://tools/smoke_test.tscn         # play a level, round-trip the editor, list levels
xvfb-run godot --path . res://tools/screenshots.tscn # PNG of every scene into user://screenshots/
```

## Testing on an Android phone

`export_presets.cfg` ships an **Android** preset (debug APK, arm64 + armv7, landscape,
immersive). One-time setup on your PC, all in the Godot editor:

1. *Editor → Manage Export Templates…* → Download and install the 4.3 templates.
2. Install [Android Studio](https://developer.android.com/studio) (or just the command-line
   SDK) and a JDK 17. In the SDK Manager install *Android SDK Platform 34*,
   *Build-Tools 34.0.0*, *Command-line Tools* and *NDK 23.2.8568313*.
3. *Editor → Editor Settings → Export → Android*: set *Java SDK Path* and *Android SDK
   Path* (for example `C:\Users\<you>\AppData\Local\Android\Sdk`). Godot 4.3 creates the
   debug keystore by itself, so the keystore fields can stay empty.
4. Enable *USB debugging* on the phone (Developer options) and plug it in.

Then *Project → Export… → Android → Export Project* writes `export/BarrelBounce.apk`, or
use the **one-click deploy** button (Android icon in the editor's top-right toolbar) to
install and start it on the connected phone directly. `export/` is git-ignored.

To publish later, change `package/unique_name` in the preset to your own reverse-domain
id, switch to a release keystore and bump `version/code`.

## Playing in the browser (WebAssembly)

`export_presets.cfg` also has a **Web** preset (thread support off, so it runs on plain static
hosting without cross-origin-isolation headers). The workflow in `.github/workflows/web.yml`
exports it with Godot 4.7.2 on every push to `main` (and `claude/**` branches), runs the smoke
test and the level solver, and deploys the result to **GitHub Pages**:

    https://incredibleleitman.github.io/BarrelBounce/

One-time: in the repository go to *Settings → Pages* and set *Source* to **GitHub Actions**
(the workflow tries to enable this itself; if it fails the first time, flip the setting and
re-run the workflow). Open the link on your phone, it plays with touch exactly like the
Android build.

Locally: *Project → Export… → Web → Export Project*, then serve `export/web/` with any static
server (the editor's *Remote Debug → Run in Browser* button does that for you). Opening
`index.html` directly from disk does not work, browsers block WASM over `file://`.

## Ideas for later

Barrel types: sticky (holds the ball until a second tap, lets you wait out a pattern),
bouncer (walls / bumpers the ball ricochets off), magnet (bends the trajectory toward it),
one-shot (disappears after use, forces a route), portal pairs, gravity flipper,
timed gate (finish only open during part of the cycle), wind zones, moving hazards.
Also: ghost replays from tap ticks, online leaderboards verified by replaying the taps,
level sharing by code, daily level.
