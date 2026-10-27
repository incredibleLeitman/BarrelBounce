class_name PlayerNode
extends Node2D
## The ball: a round hero with a face, a motion trail and a death puff.

const TRAIL_LEN := 40
const BODY := Color("#ffd166")
const BODY_DARK := Color("#e0a62e")

var trail: PackedVector2Array = PackedVector2Array()
var facing := 0.0
var visible_body := true
var in_cannon := true
var squash := 0.0
var puffs: Array = []   # [{pos, age}]


func update_from(sim: Simulation) -> void:
	position = sim.pos
	facing = sim.facing()
	in_cannon = sim.mode == Simulation.Mode.IN_CANNON
	visible_body = sim.mode != Simulation.Mode.DEAD
	if sim.mode == Simulation.Mode.FLYING or sim.mode == Simulation.Mode.DASHING:
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


func _process(delta: float) -> void:
	squash = maxf(0.0, squash - delta * 4.0)
	for p in puffs:
		p["age"] += delta
	puffs = puffs.filter(func(p): return p["age"] < 0.6)
	if squash > 0.0 or not puffs.is_empty():
		queue_redraw()


func _draw() -> void:
	# Trail (in local space: subtract our own position).
	for i in range(1, trail.size()):
		var a := float(i) / trail.size()
		draw_line(trail[i - 1] - position, trail[i] - position, Color(BODY, a * 0.5), 2.0 + a * 6.0)
	for p in puffs:
		var k: float = p["age"] / 0.6
		var c: Vector2 = p["pos"] - position
		for j in 6:
			var ang := j * TAU / 6.0
			draw_circle(c + Vector2.from_angle(ang) * k * 60.0, 10.0 * (1.0 - k), Color(UI.BAD, 1.0 - k))
	if not visible_body:
		return
	var r := 15.0
	var s := Vector2(1.0 + squash * 0.35, 1.0 - squash * 0.25)
	draw_set_transform(Vector2.ZERO, facing if not in_cannon else 0.0, s)
	draw_circle(Vector2.ZERO, r + 2.5, Color("#1b2138"))
	draw_circle(Vector2.ZERO, r, BODY)
	draw_circle(Vector2(-4, -5), 5.0, Color(1, 1, 1, 0.35))
	# eyes looking forward
	draw_circle(Vector2(5, -3), 3.2, Color.WHITE)
	draw_circle(Vector2(6, -3), 1.6, Color("#1b2138"))
	draw_circle(Vector2(5, 4), 3.2, Color.WHITE)
	draw_circle(Vector2(6, 4), 1.6, Color("#1b2138"))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
