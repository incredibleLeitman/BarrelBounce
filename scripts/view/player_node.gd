class_name PlayerNode
extends Node2D
## The ball: a round hero in the player's colour with a face, a motion trail, a blink
## effect for teleports and a red puff when it falls off the world.

const TRAIL_LEN := 40
const DEAD_COLOR := Color("#e5484d")

var body_color := Color("#ffd166")
## A ghost is the translucent replay of the best run: no face, no puffs, a faint trail.
var ghost := false
var trail: PackedVector2Array = PackedVector2Array()
var facing := 0.0
var in_cannon := true
var dead := false
var squash := 0.0
var puffs: Array = []    # [{pos, age}]
var blinks: Array = []   # [{from, to, age}]


func _ready() -> void:
	if not ghost:
		body_color = GameState.player_color()


func update_from(sim: Simulation) -> void:
	position = sim.pos
	facing = sim.facing()
	in_cannon = sim.mode == Simulation.Mode.IN_CANNON
	dead = sim.mode == Simulation.Mode.DEAD
	if sim.mode == Simulation.Mode.FLYING:
		trail.append(sim.pos)
		if trail.size() > TRAIL_LEN:
			trail.remove_at(0)
	elif sim.mode == Simulation.Mode.IN_CANNON:
		if not trail.is_empty():
			trail.remove_at(0)
	queue_redraw()


func clear_trail() -> void:
	trail.clear()
	queue_redraw()


func kick() -> void:
	squash = 1.0


func puff() -> void:
	puffs.append({"pos": position, "age": 0.0})


func blink(from: Vector2, to: Vector2) -> void:
	blinks.append({"from": from, "to": to, "age": 0.0})
	trail.clear()


func _process(delta: float) -> void:
	squash = maxf(0.0, squash - delta * 4.0)
	for p in puffs:
		p["age"] += delta
	for b in blinks:
		b["age"] += delta
	puffs = puffs.filter(func(p): return p["age"] < 0.6)
	blinks = blinks.filter(func(b): return b["age"] < 0.45)
	if squash > 0.0 or not puffs.is_empty() or not blinks.is_empty():
		queue_redraw()


func _draw() -> void:
	if ghost:
		_draw_ghost()
		return
	# Trail (in local space: subtract our own position).
	for i in range(1, trail.size()):
		var a := float(i) / trail.size()
		draw_line(trail[i - 1] - position, trail[i] - position, Color(body_color, a * 0.5), 2.0 + a * 6.0)
	for p in puffs:
		var k: float = p["age"] / 0.6
		var c: Vector2 = p["pos"] - position
		for j in 6:
			var ang := j * TAU / 6.0
			draw_circle(c + Vector2.from_angle(ang) * k * 60.0, 10.0 * (1.0 - k), Color(DEAD_COLOR, 1.0 - k))
	for b in blinks:
		var k: float = b["age"] / 0.45
		var from: Vector2 = b["from"] - position
		var to: Vector2 = b["to"] - position
		# Shrinking ghost where the ball vanished, expanding ring where it reappeared.
		draw_circle(from, 15.0 * (1.0 - k), Color(UI.ACCENT_2, 0.7 * (1.0 - k)))
		draw_arc(from, 15.0 + 30.0 * k, 0.0, TAU, 24, Color(UI.ACCENT_2, 0.6 * (1.0 - k)), 2.0)
		draw_arc(to, 40.0 * (1.0 - k) + 15.0, 0.0, TAU, 24, Color(UI.ACCENT_2, 0.8 * (1.0 - k)), 3.0)
		var n := 8
		for j in n:
			var ang := j * TAU / n
			var d := Vector2.from_angle(ang)
			draw_line(from + d * (18.0 + 40.0 * k), from + d * (26.0 + 40.0 * k), Color(UI.ACCENT_2, 0.6 * (1.0 - k)), 2.0)
	var r := 15.0
	var s := Vector2(1.0 + squash * 0.35, 1.0 - squash * 0.25)
	var col := DEAD_COLOR if dead else body_color
	draw_set_transform(Vector2.ZERO, facing if not in_cannon else 0.0, s)
	draw_circle(Vector2.ZERO, r + 2.5, Color("#1b2138"))
	draw_circle(Vector2.ZERO, r, col)
	draw_circle(Vector2(-4, -5), 5.0, Color(1, 1, 1, 0.35))
	if dead:
		# X eyes
		for e in [Vector2(5, -3), Vector2(5, 4)]:
			draw_line(e + Vector2(-3, -3), e + Vector2(3, 3), Color("#1b2138"), 2.0)
			draw_line(e + Vector2(-3, 3), e + Vector2(3, -3), Color("#1b2138"), 2.0)
	else:
		draw_circle(Vector2(5, -3), 3.2, Color.WHITE)
		draw_circle(Vector2(6, -3), 1.6, Color("#1b2138"))
		draw_circle(Vector2(5, 4), 3.2, Color.WHITE)
		draw_circle(Vector2(6, 4), 1.6, Color("#1b2138"))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_ghost() -> void:
	if dead:
		return
	var c := body_color
	for i in range(1, trail.size()):
		var a := float(i) / trail.size()
		draw_line(trail[i - 1] - position, trail[i] - position, Color(c, a * 0.2), 2.0)
	draw_circle(Vector2.ZERO, 15.0, Color(c, 0.16))
	draw_arc(Vector2.ZERO, 15.0, 0.0, TAU, 24, Color(c, 0.6), 2.0)
	draw_circle(Vector2(-4, -5), 4.0, Color(c, 0.2))
