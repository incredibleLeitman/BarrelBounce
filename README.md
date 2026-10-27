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
| `dash` | Blink | straight line at 2800 px/s ignoring gravity for 9 ticks, then normal flight |
| `double` | Hopper | one extra mid-air boost on a second tap |
| `bubble` | Bubble | 35 % gravity during the flight |
| `auto` | Hot Head | fires on its own after 45 ticks, tap earlier if you want |

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
  "start": 0
}
```

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

## Ideas for later

Barrel types: sticky (holds the ball until a second tap, lets you wait out a pattern),
bouncer (walls / bumpers the ball ricochets off), magnet (bends the trajectory toward it),
one-shot (disappears after use, forces a route), portal pairs, gravity flipper,
timed gate (finish only open during part of the cycle), wind zones, moving hazards.
Also: ghost replays from tap ticks, online leaderboards verified by replaying the taps,
level sharing by code, daily level.
