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
## Default play area; a level can set its own "width" / "height".
const BASE_SIZE := Vector2(1280, 720)
const MIN_SIZE := Vector2(640, 360)
const MAX_SIZE := Vector2(3840, 2160)
## Margins around the play area beyond which the player dies (lots of headroom above).
const WORLD_MARGIN := Rect2(-80.0, -640.0, 160.0, 720.0)
## The default world rect (kept for callers that have no level at hand).
const WORLD := Rect2(-80.0, -640.0, 1440.0, 1440.0)


static func level_size(level_data: Dictionary) -> Vector2:
	var w := float(level_data.get("width", BASE_SIZE.x))
	var h := float(level_data.get("height", BASE_SIZE.y))
	return Vector2(clampf(w, MIN_SIZE.x, MAX_SIZE.x), clampf(h, MIN_SIZE.y, MAX_SIZE.y))


static func world_rect(level_data: Dictionary) -> Rect2:
	var s := level_size(level_data)
	return Rect2(WORLD_MARGIN.position, s + WORLD_MARGIN.size)

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
	"path": {"label": "Path", "params": [
		["period", "Period s", 0.2, 60.0, 0.1, 4.0]], "smooth": true, "closed": true,
		"default_points": [[160.0, -90.0], [320.0, 0.0]]},
}
const BEHAVIOR_ORDER := ["rotate", "sweep", "move", "orbit", "path"]
const PATH_SAMPLES := 12   # spline samples per segment when a path is smoothed

var level: Dictionary
var size: Vector2 = BASE_SIZE   # play area of this level
var world: Rect2 = WORLD        # death bounds of this level
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
##
## Behaviours marked "seq" are steps of a timeline: they run one after another, each for its
## "duration", the offset reached at the end of a step carries into the next, and the timeline
## loops. Behaviours without "seq" run continuously for the whole time and are summed on top.
static func cannon_state_at(c: Dictionary, t: int) -> Dictionary:
	var time := t * DT
	var p := Vector2(float(c.get("x", 0.0)), float(c.get("y", 0.0)))
	var ang := float(c.get("angle", 0.0))
	var steps: Array = []
	for b in c.get("behaviors", []):
		if bool(b.get("seq", false)):
			steps.append(b)
		else:
			var off := behavior_offset(b, time)
			p += off["pos"]
			ang += off["angle"]
	if not steps.is_empty():
		var total := 0.0
		for b in steps:
			total += step_duration(b)
		if total > 0.0:
			var local := fmod(time, total)
			for b in steps:
				var dur := step_duration(b)
				var off: Dictionary
				if local >= dur:
					off = behavior_offset(b, dur)   # finished: carry its end offset
					local -= dur
				else:
					off = behavior_offset(b, local)  # the active step
					local = -1.0
				p += off["pos"]
				ang += off["angle"]
				if local < 0.0:
					break
	return {"pos": p, "angle": ang}


## Offset one behaviour contributes after running for [param time] seconds.
static func behavior_offset(b: Dictionary, time: float) -> Dictionary:
	var p := Vector2.ZERO
	var ang := 0.0
	match str(b.get("type", "")):
		"rotate":
			ang = float(b.get("speed", 90.0)) * time
		"sweep":
			var period: float = maxf(0.1, float(b.get("period", 2.0)))
			var k := 0.5 - 0.5 * cos(TAU * time / period)
			ang = lerpf(float(b.get("from", -45.0)), float(b.get("to", 45.0)), k)
		"move":
			var d: Vector2 = DIRS.get(str(b.get("dir", "right")), Vector2.RIGHT)
			var period: float = maxf(0.1, float(b.get("period", 2.0)))
			var k := 0.5 - 0.5 * cos(TAU * time / period)
			p = d * float(b.get("range", 150.0)) * k
		"orbit":
			var period: float = maxf(0.1, float(b.get("period", 3.0)))
			var th := TAU * time / period
			if not bool(b.get("clockwise", true)):
				th = -th
			p = Vector2(cos(th), sin(th)) * float(b.get("radius", 120.0))
		"path":
			var period: float = maxf(0.1, float(b.get("period", 4.0)))
			var closed := bool(b.get("closed", true))
			var u := fmod(time / period, 1.0)
			if not closed:
				# Ping-pong along an open path.
				u = 1.0 - absf(2.0 * u - 1.0)
			p = point_along(path_polyline(b), closed, u)
	return {"pos": p, "angle": ang}


## How long a sequential step plays, in seconds.
static func step_duration(b: Dictionary) -> float:
	return maxf(0.0, float(b.get("duration", default_duration(b))))


## Sensible step length when a behaviour is first made sequential: one way for move and
## sweep (half their period), a full loop for orbit and path, one second for rotate.
static func default_duration(b: Dictionary) -> float:
	var period: float = maxf(0.1, float(b.get("period", 2.0)))
	match str(b.get("type", "")):
		"move", "sweep":
			return period * 0.5
		"orbit", "path":
			return period
	return 1.0


## Per behaviour, the offset (pos, angle) a cannon has accumulated when that behaviour
## starts: zero for continuous ones, the sum of the previous steps' end offsets for steps.
## Used to draw movement hints where they really happen.
static func behavior_start_offsets(c: Dictionary) -> Array:
	var out: Array = []
	var acc_p := Vector2.ZERO
	var acc_a := 0.0
	for b in c.get("behaviors", []):
		if bool(b.get("seq", false)):
			out.append({"pos": acc_p, "angle": acc_a})
			var off := behavior_offset(b, step_duration(b))
			acc_p += off["pos"]
			acc_a += off["angle"]
		else:
			out.append({"pos": Vector2.ZERO, "angle": 0.0})
	return out


## Index (into the cannon's behaviours) of the step playing at tick [param t], or -1.
static func active_step(c: Dictionary, t: int) -> int:
	var total := 0.0
	var bs: Array = c.get("behaviors", [])
	for b in bs:
		if bool(b.get("seq", false)):
			total += step_duration(b)
	if total <= 0.0:
		return -1
	var local := fmod(t * DT, total)
	for i in bs.size():
		if not bool(bs[i].get("seq", false)):
			continue
		var dur := step_duration(bs[i])
		if local < dur:
			return i
		local -= dur
	return -1


## The points a path behaviour visits, relative to the cannon base, starting at the base.
static func path_control_points(b: Dictionary) -> PackedVector2Array:
	var pts := PackedVector2Array([Vector2.ZERO])
	for raw in b.get("points", []):
		if typeof(raw) == TYPE_ARRAY and raw.size() >= 2:
			pts.append(Vector2(float(raw[0]), float(raw[1])))
	return pts


## The path as a dense polyline: the control points, or a Catmull-Rom spline through them.
static func path_polyline(b: Dictionary) -> PackedVector2Array:
	var pts := path_control_points(b)
	if not bool(b.get("smooth", true)) or pts.size() < 3:
		return pts
	var closed := bool(b.get("closed", true))
	var n := pts.size()
	var out := PackedVector2Array()
	var segments := n if closed else n - 1
	for i in segments:
		var p0 := pts[(i - 1 + n) % n] if closed else pts[maxi(i - 1, 0)]
		var p1 := pts[i]
		var p2 := pts[(i + 1) % n]
		var p3 := pts[(i + 2) % n] if closed else pts[mini(i + 2, n - 1)]
		for k in PATH_SAMPLES:
			var t := float(k) / PATH_SAMPLES
			out.append(_catmull_rom(p0, p1, p2, p3, t))
	if not closed:
		out.append(pts[n - 1])
	return out


static func _catmull_rom(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


## Point at fraction [param u] (0..1) of the polyline's length, at constant speed.
static func point_along(pts: PackedVector2Array, closed: bool, u: float) -> Vector2:
	var n := pts.size()
	if n == 0:
		return Vector2.ZERO
	if n == 1:
		return pts[0]
	var segs := n if closed else n - 1
	var total := 0.0
	for i in segs:
		total += pts[i].distance_to(pts[(i + 1) % n])
	if total <= 0.0:
		return pts[0]
	var d := clampf(u, 0.0, 1.0) * total
	for i in segs:
		var a := pts[i]
		var c := pts[(i + 1) % n]
		var len := a.distance_to(c)
		if d <= len or i == segs - 1:
			return a.lerp(c, d / len if len > 0.0 else 0.0)
		d -= len
	return pts[0]


## Length in ticks after which a cannon's motion repeats (0 = static).
static func cannon_cycle_ticks(c: Dictionary) -> int:
	var cycle := 0.0
	var seq_total := 0.0
	for b in c.get("behaviors", []):
		if bool(b.get("seq", false)):
			seq_total += step_duration(b)
			continue
		var period := 0.0
		match str(b.get("type", "")):
			"rotate":
				var speed := absf(float(b.get("speed", 90.0)))
				period = 360.0 / speed if speed > 0.0 else 0.0
			"sweep", "move", "orbit", "path":
				period = maxf(0.1, float(b.get("period", 2.0)))
		cycle = maxf(cycle, period)
	cycle = maxf(cycle, seq_total)
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
	size = level_size(level)
	world = world_rect(level)
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
	if not world.has_point(pos):
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
