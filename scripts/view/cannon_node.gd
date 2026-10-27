class_name CannonNode
extends Node2D
## Draws one cannon from its level dictionary and the simulation state of the current tick.

var data: Dictionary
var barrel_angle: float = 0.0   # degrees
var occupied := false
var selected := false
var show_hints := false
var pulse := 0.0


func _init(cannon_data: Dictionary) -> void:
	data = cannon_data


func apply_state(state: Dictionary, is_occupied: bool) -> void:
	position = state["pos"]
	var ang := float(state["angle"])
	if ang != barrel_angle or is_occupied != occupied:
		barrel_angle = ang
		occupied = is_occupied
		queue_redraw()


func _process(delta: float) -> void:
	if occupied or selected or data.get("type", "normal") == "auto":
		pulse += delta
		queue_redraw()


func _draw() -> void:
	var info := Simulation.type_info(str(data.get("type", "normal")))
	var color: Color = info["color"]
	var barrel_w: float = info.get("barrel", 22.0)
	var dark := Color("#1b2138")

	if show_hints:
		_draw_hints()

	if selected:
		draw_circle(Vector2.ZERO, 46.0 + 2.0 * sin(pulse * 6.0), Color(UI.ACCENT_2, 0.25))
		draw_arc(Vector2.ZERO, 46.0 + 2.0 * sin(pulse * 6.0), 0.0, TAU, 48, UI.ACCENT_2, 2.0)
	if occupied:
		draw_circle(Vector2.ZERO, 40.0 + 3.0 * sin(pulse * 8.0), Color(color, 0.18))

	# Barrel
	var rot := deg_to_rad(barrel_angle)
	draw_set_transform(Vector2.ZERO, rot, Vector2.ONE)
	draw_rect(Rect2(-4, -barrel_w / 2.0 - 3, 54, barrel_w + 6), dark)
	draw_rect(Rect2(-4, -barrel_w / 2.0, 52, barrel_w), color.darkened(0.25))
	draw_rect(Rect2(-4, -barrel_w / 2.0, 52, barrel_w * 0.4), color.lightened(0.1))
	# muzzle ring
	draw_rect(Rect2(40, -barrel_w / 2.0 - 4, 10, barrel_w + 8), dark)
	draw_rect(Rect2(41, -barrel_w / 2.0 - 2, 8, barrel_w + 4), color.darkened(0.1))
	if str(data.get("type", "normal")) == "dash":
		for k in 3:
			var x := 6.0 + k * 10.0
			draw_line(Vector2(x, -barrel_w * 0.3), Vector2(x + 5, 0), Color.WHITE, 2.0)
			draw_line(Vector2(x + 5, 0), Vector2(x, barrel_w * 0.3), Color.WHITE, 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Base / hub
	draw_circle(Vector2.ZERO, 27.0, dark)
	draw_circle(Vector2.ZERO, 22.0, color)
	draw_circle(Vector2(-6, -6), 9.0, Color(1, 1, 1, 0.22))
	draw_circle(Vector2.ZERO, 7.0, dark)

	# Type markers
	match str(data.get("type", "normal")):
		"double":
			draw_arc(Vector2.ZERO, 14.0, PI * 0.15, PI * 0.85, 12, Color.WHITE, 3.0)
			draw_arc(Vector2.ZERO, 14.0, PI * 1.15, PI * 1.85, 12, Color.WHITE, 3.0)
		"bubble":
			draw_arc(Vector2.ZERO, 15.0, 0.0, TAU, 24, Color(1, 1, 1, 0.8), 2.0)
			draw_circle(Vector2(-5, -5), 3.0, Color.WHITE)
		"auto":
			var t := fmod(pulse, 0.75) / 0.75
			draw_arc(Vector2.ZERO, 15.0, -PI / 2.0, -PI / 2.0 + TAU * t, 24, Color.WHITE, 3.0)
		"strong":
			draw_arc(Vector2.ZERO, 15.0, 0.0, TAU, 24, Color.WHITE, 3.0)
		"weak":
			draw_circle(Vector2.ZERO, 3.0, Color.WHITE)


func _draw_hints() -> void:
	var base := Vector2(float(data.get("x", 0.0)), float(data.get("y", 0.0))) - position
	var hint := Color(UI.ACCENT_2, 0.35)
	for b in data.get("behaviors", []):
		match str(b.get("type", "")):
			"move":
				var d: Vector2 = Simulation.DIRS.get(str(b.get("dir", "right")), Vector2.RIGHT)
				var r := float(b.get("range", 150.0))
				draw_dashed_line(base, base + d * r, hint, 2.0, 8.0)
				draw_circle(base + d * r, 5.0, hint)
			"orbit":
				draw_arc(base, float(b.get("radius", 120.0)), 0.0, TAU, 48, hint, 2.0)
				draw_circle(base, 4.0, hint)
			"sweep":
				var a0 := deg_to_rad(float(data.get("angle", 0.0)) + float(b.get("from", -45.0)))
				var a1 := deg_to_rad(float(data.get("angle", 0.0)) + float(b.get("to", 45.0)))
				draw_arc(Vector2.ZERO, 62.0, minf(a0, a1), maxf(a0, a1), 24, hint, 3.0)
			"rotate":
				draw_arc(Vector2.ZERO, 62.0, 0.0, TAU, 48, Color(hint, 0.5), 1.5)
