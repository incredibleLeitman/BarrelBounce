class_name Simulation
extends RefCounted
## The complete, deterministic game model.
##
## Everything that affects the outcome of a run lives here and is driven by an
## integer tick counter. Cannon positions and angles are *pure functions* of
## the tick, the player is integrated with a fixed time step, and there is no
## use of the physics engine, randomness or wall-clock time. Two players who
## press the button on the same ticks get exactly the same run.
##
## The scenes (level, editor, solver) only call [method step] / [method reset]
## and read the public state to draw it.

const TICK_RATE := 60
const DT := 1.0 / TICK_RATE
const GRAVITY := 1500.0
const CATCH_RADIUS := 36.0           # distance at which a cannon sucks the player in
const COOLDOWN_TICKS := 10           # ticks before the cannon that just fired can re-catch
const DOUBLE_JUMP_VEL := -650.0
const BASE_SIZE := Vector2(1280, 720)
## Leaving this rectangle kills the player (and resets the run).
const WORLD := Rect2(-80.0, -640.0, 1440.0, 1440.0)

enum Mode { IN_CANNON, FLYING, FINISHED, DEAD }

## The start cannon is always a plain cannon: a level must never fire without the player's tap.
const START_TYPE := "normal"

## Cannon (barrel) types. "power" is the launch speed in px/s.
const TYPES := {
	"normal": {"label": "Cannon", "power": 950.0, "color": Color("#ff8a3d"), "barrel": 22.0,
		"hint": "Fires the ball along the barrel."},
	"strong": {"label": "Big Bertha", "power": 1400.0, "color": Color("#e5484d"), "barrel": 30.0,
		"hint": "Much more power, much longer flight."},
	"weak": {"label": "Pea Shooter", "power": 620.0, "color": Color("#9bd36a"), "barrel": 14.0,
		"hint": "Short, gentle hops."},
	"dash": {"label": "Blink", "power": 650.0, "teleport": 210.0,
		"color": Color("#4cc9f0"), "barrel": 20.0,
		"hint": "Teleports the ball 210 px along the barrel, then it flies on."},
	"double": {"label": "Hopper", "power": 950.0, "jumps": 1, "color": Color("#f6d55c"), "barrel": 22.0,
		"hint": "Tap again in the air for one extra boost."},
	"bubble": {"label": "Bubble", "power": 820.0, "gravity": 0.35, "color": Color("#c77dff"), "barrel": 22.0,
		"hint": "The ball floats under reduced gravity."},
	"auto": {"label": "Hot Head", "power": 950.0, "auto_fire_ticks": 45, "color": Color("#ff6fb5"), "barrel": 22.0,
		"hint": "Its fuse burns down in 0.75 s and then it fires by itself. Tap earlier if you dare."},
}
const TYPE_ORDER := ["normal", "strong", "weak", "dash", "double", "bubble", "auto"]

const DIAG := 0.7071067811865476
const DIRS := {
	"right": Vector2(1, 0), "left": Vector2(-1, 0), "up": Vector2(0, -1), "down": Vector2(0, 1),
	"up_right": Vector2(DIAG, -DIAG), "up_left": Vector2(-DIAG, -DIAG),
	"down_right": Vector2(DIAG, DIAG), "down_left": Vector2(-DIAG, DIAG),
}
const DIR_ORDER := ["right", "up_right", "up", "up_left", "left", "down_left", "down", "down_right"]

## Behaviour definitions used by the editor UI (key, label, min, max, step, default).
const BEHAVIORS := {
	"rotate": {"label": "Rotate", "params": [["speed", "Speed °/s", -720.0, 720.0, 15.0, 90.0]]},
	"sweep": {"label": "Sweep", "params": [
		["from", "From °", -180.0, 180.0, 5.0, -45.0],
		["to", "To °", -180.0, 180.0, 5.0, 45.0],
		["period", "Period s", 0.2, 20.0, 0.1, 2.0]]},
	"move": {"label": "Move", "params": [
		["range", "Range px", 10.0, 1200.0, 10.0, 150.0],
		["period", "Period s", 0.2, 20.0, 0.1, 2.0]], "dir": true},
	"orbit": {"label": "Orbit", "params": [
		["radius", "Radius px", 10.0, 600.0, 10.0, 120.0],
		["period", "Period s", 0.2, 20.0, 0.1, 3.0]], "clockwise": true},
}
const BEHAVIOR_ORDER := ["rotate", "sweep", "move", "orbit"]

var level: Dictionary
var cannons: Array            # references the level's cannon dictionaries (shared, not copied)
var cannon_states: Array = [] # per cannon: {"pos": Vector2, "angle": float (deg)} for the current tick

var tick: int = 0
var run_start_tick: int = -1  # tick of the first launch, -1 until the player fires
var mode: int = Mode.IN_CANNON
var cannon_index: int = 0
var ticks_in_cannon: int = 0
var pos: Vector2 = Vector2.ZERO
var vel: Vector2 = Vector2.ZERO
## Where the last teleport started (for the blink effect), set together with the "teleport" event.
var teleport_from: Vector2 = Vector2.ZERO
var extra_jumps: int = 0
var gravity_scale: float = 1.0
var cooldown: int = 0
var cooldown_cannon: int = -1
var finish_ticks: int = -1
var launches: int = 0
## Events produced by the last [method step]: "launch", "teleport", "jump", "catch", "finish", "die".
var events: Array = []


func _init(level_data: Dictionary) -> void:
	level = level_data
	if not level.has("cannons"):
		level["cannons"] = []
	cannons = level["cannons"]
	reset()


static func type_info(type_name: String) -> Dictionary:
	return TYPES.get(type_name, TYPES["normal"])


func cannon_type(index: int) -> Dictionary:
	if index < 0 or index >= cannons.size():
		return TYPES["normal"]
	return type_info(str(cannons[index].get("type", "normal")))


## Position and angle of a cannon at tick [param t]. Pure function: same input, same output.
static func cannon_state_at(c: Dictionary, t: int) -> Dictionary:
	var time := t * DT
	var p := Vector2(float(c.get("x", 0.0)), float(c.get("y", 0.0)))
	var ang := float(c.get("angle", 0.0))
	for b in c.get("behaviors", []):
		match str(b.get("type", "")):
			"rotate":
				ang += float(b.get("speed", 90.0)) * time
			"sweep":
				var period: float = maxf(0.1, float(b.get("period", 2.0)))
				var k := 0.5 - 0.5 * cos(TAU * time / period)
				ang += lerpf(float(b.get("from", -45.0)), float(b.get("to", 45.0)), k)
			"move":
				var d: Vector2 = DIRS.get(str(b.get("dir", "right")), Vector2.RIGHT)
				var period: float = maxf(0.1, float(b.get("period", 2.0)))
				var k := 0.5 - 0.5 * cos(TAU * time / period)
				p += d * float(b.get("range", 150.0)) * k
			"orbit":
				var period: float = maxf(0.1, float(b.get("period", 3.0)))
				var th := TAU * time / period
				if not bool(b.get("clockwise", true)):
					th = -th
				p += Vector2(cos(th), sin(th)) * float(b.get("radius", 120.0))
	return {"pos": p, "angle": ang}


## Length in ticks after which a cannon's motion repeats (0 = static).
static func cannon_cycle_ticks(c: Dictionary) -> int:
	var cycle := 0.0
	for b in c.get("behaviors", []):
		var period := 0.0
		match str(b.get("type", "")):
			"rotate":
				var speed := absf(float(b.get("speed", 90.0)))
				period = 360.0 / speed if speed > 0.0 else 0.0
			"sweep", "move", "orbit":
				period = maxf(0.1, float(b.get("period", 2.0)))
		cycle = maxf(cycle, period)
	return int(ceil(cycle * TICK_RATE))


## Forces the start cannon to the plain type so no level can fire without a tap.
static func enforce_start_type(level_data: Dictionary) -> void:
	var cs: Array = level_data.get("cannons", [])
	var start := int(level_data.get("start", 0))
	if start >= 0 and start < cs.size():
		cs[start]["type"] = START_TYPE


## 0..1 fraction of the fuse still left on an auto cannon the ball sits in (1 when idle).
func fuse_left(index: int) -> float:
	var auto_ticks := int(cannon_type(index).get("auto_fire_ticks", 0))
	if auto_ticks <= 0 or mode != Mode.IN_CANNON or cannon_index != index:
		return 1.0
	return clampf(1.0 - float(ticks_in_cannon) / float(auto_ticks), 0.0, 1.0)


func finish_rect() -> Rect2:
	var f: Dictionary = level.get("finish", {"x": 1100.0, "y": 160.0, "w": 60.0, "h": 400.0})
	return Rect2(float(f.get("x", 0.0)), float(f.get("y", 0.0)), float(f.get("w", 60.0)), float(f.get("h", 400.0)))


func reset() -> void:
	tick = 0
	run_start_tick = -1
	mode = Mode.IN_CANNON
	cannon_index = clampi(int(level.get("start", 0)), 0, maxi(0, cannons.size() - 1))
	ticks_in_cannon = 0
	vel = Vector2.ZERO
	teleport_from = Vector2.ZERO
	extra_jumps = 0
	gravity_scale = 1.0
	cooldown = 0
	cooldown_cannon = -1
	finish_ticks = -1
	launches = 0
	events.clear()
	_update_cannons()
	if cannons.is_empty():
		mode = Mode.DEAD
		pos = BASE_SIZE * 0.5
	else:
		pos = cannon_states[cannon_index]["pos"]


## Jump to an arbitrary tick without touching the player (used by the editor preview).
func set_tick(t: int) -> void:
	tick = maxi(0, t)
	_update_cannons()
	if mode == Mode.IN_CANNON and not cannons.is_empty():
		cannon_index = clampi(cannon_index, 0, cannons.size() - 1)
		pos = cannon_states[cannon_index]["pos"]


func _update_cannons() -> void:
	cannon_states.resize(cannons.size())
	for i in cannons.size():
		cannon_states[i] = cannon_state_at(cannons[i], tick)


## Advance one tick. [param fire] is true when the button was pressed since the last step.
func step(fire: bool) -> void:
	events.clear()
	if mode == Mode.FINISHED or mode == Mode.DEAD:
		return
	tick += 1
	_update_cannons()
	match mode:
		Mode.IN_CANNON:
			ticks_in_cannon += 1
			pos = cannon_states[cannon_index]["pos"]
			var auto_ticks := int(cannon_type(cannon_index).get("auto_fire_ticks", 0))
			if fire or (auto_ticks > 0 and ticks_in_cannon >= auto_ticks):
				_launch()
		Mode.FLYING:
			if fire and extra_jumps > 0:
				extra_jumps -= 1
				vel.y = DOUBLE_JUMP_VEL
				events.append("jump")
			vel.y += GRAVITY * gravity_scale * DT
			pos += vel * DT
			if cooldown > 0:
				cooldown -= 1
			_check_catch()
			if mode == Mode.FLYING:
				_check_finish()
			if mode == Mode.FLYING:
				_check_death()


func _launch() -> void:
	var state: Dictionary = cannon_states[cannon_index]
	var info := cannon_type(cannon_index)
	var dir := Vector2.from_angle(deg_to_rad(float(state["angle"])))
	if run_start_tick < 0:
		run_start_tick = tick
	launches += 1
	cooldown = COOLDOWN_TICKS
	cooldown_cannon = cannon_index
	extra_jumps = int(info.get("jumps", 0))
	gravity_scale = float(info.get("gravity", 1.0))
	pos = state["pos"] + dir * 24.0
	mode = Mode.FLYING
	vel = dir * float(info["power"])
	events.append("launch")
	if info.has("teleport"):
		# Blink: the ball vanishes at the muzzle and reappears further along the barrel line.
		teleport_from = pos
		pos += dir * float(info["teleport"])
		events.append("teleport")


func _check_catch() -> void:
	var r2 := CATCH_RADIUS * CATCH_RADIUS
	for i in cannons.size():
		if i == cooldown_cannon and cooldown > 0:
			continue
		var cpos: Vector2 = cannon_states[i]["pos"]
		if pos.distance_squared_to(cpos) <= r2:
			mode = Mode.IN_CANNON
			cannon_index = i
			ticks_in_cannon = 0
			vel = Vector2.ZERO
			extra_jumps = 0
			gravity_scale = 1.0
			pos = cpos
			events.append("catch")
			return


func _check_finish() -> void:
	if finish_rect().has_point(pos):
		mode = Mode.FINISHED
		finish_ticks = tick - run_start_tick
		events.append("finish")


func _check_death() -> void:
	if not WORLD.has_point(pos):
		mode = Mode.DEAD
		events.append("die")


## Ticks on the run clock (starts with the first launch, frozen when finished).
func elapsed_ticks() -> int:
	if run_start_tick < 0:
		return 0
	if mode == Mode.FINISHED:
		return finish_ticks
	return tick - run_start_tick


## Direction the ball is facing, in radians (for drawing).
func facing() -> float:
	if mode == Mode.IN_CANNON and cannon_index < cannon_states.size():
		return deg_to_rad(float(cannon_states[cannon_index]["angle"]))
	if vel.length_squared() > 1.0:
		return vel.angle()
	return 0.0


## Deep copy of the dynamic state (level data is shared). Used by the solver.
func clone() -> Simulation:
	var s := Simulation.new(level)
	s.tick = tick
	s.run_start_tick = run_start_tick
	s.mode = mode
	s.cannon_index = cannon_index
	s.ticks_in_cannon = ticks_in_cannon
	s.pos = pos
	s.vel = vel
	s.teleport_from = teleport_from
	s.extra_jumps = extra_jumps
	s.gravity_scale = gravity_scale
	s.cooldown = cooldown
	s.cooldown_cannon = cooldown_cannon
	s.finish_ticks = finish_ticks
	s.launches = launches
	s.cannon_states = cannon_states.duplicate()
	return s


static func format_ticks(ticks: int) -> String:
	if ticks < 0:
		return "--.--"
	return "%.2f s" % (ticks / float(TICK_RATE))
