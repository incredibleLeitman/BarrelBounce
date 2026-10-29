class_name CannonNode
extends Node2D
## Draws one cannon from its level dictionary and the simulation state of the current tick.

var data: Dictionary
var barrel_angle: float = 0.0   # degrees
var occupied := false
var selected := false
var show_hints := false
var pulse := 0.0
var fuse := 1.0           # 0..1, fraction of the fuse left (auto cannons only)
## Which cannon of its type this is (0, 1, 2, ...). Movement hints get a darker shade per step
## so neighbouring cannons of the same type can be told apart.
var shade_index := 0
const SHADE_STEPS := 4
var spark_rng := RandomNumberGenerator.new()


func _init(cannon_data: Dictionary) -> void:
	data = cannon_data


func apply_state(state: Dictionary, is_occupied: bool, fuse_left: float = 1.0) -> void:
	var moved: bool = position != state["pos"]
	position = state["pos"]
	var ang := float(state["angle"])
	# Hints are drawn relative to the node, so a cannon that moves must redraw them or they
	# would ride along with it instead of staying at the stored base position.
	if ang != barrel_angle or is_occupied != occupied or fuse_left != fuse or (moved and show_hints):
		barrel_angle = ang
		occupied = is_occupied
		fuse = fuse_left
		queue_redraw()


func _process(delta: float) -> void:
	if occupied or selected:
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
			_draw_fuse()
		"strong":
			draw_arc(Vector2.ZERO, 15.0, 0.0, TAU, 24, Color.WHITE, 3.0)
		"weak":
			draw_circle(Vector2.ZERO, 3.0, Color.WHITE)


## A fuse ring that burns down clockwise from the top; it fires when nothing is left.
## While it burns, sparks fly off the burning end.
func _draw_fuse() -> void:
	var start := -PI / 2.0
	var end := start + TAU * fuse
	draw_arc(Vector2.ZERO, 15.0, start, start + TAU, 24, Color(1, 1, 1, 0.2), 3.0)
	if fuse > 0.0:
		draw_arc(Vector2.ZERO, 15.0, start, end, 24, Color.WHITE, 3.0)
	if occupied and fuse < 1.0 and fuse > 0.0:
		var tip := Vector2.from_angle(end) * 15.0
		draw_circle(tip, 4.0, Color("#fff1a8"))
		# Sparks: purely visual, re-rolled every frame.
		spark_rng.seed = int(pulse * 60.0)
		for i in 7:
			var dir := Vector2.from_angle(spark_rng.randf_range(0.0, TAU))
			var spark_len := spark_rng.randf_range(6.0, 18.0)
			var col := Color("#ffd166") if i % 2 == 0 else Color("#ff8a3d")
			draw_line(tip + dir * 3.0, tip + dir * spark_len, Color(col, spark_rng.randf_range(0.4, 1.0)), 1.5)
			draw_circle(tip + dir * spark_len, 1.5, Color(col, 0.9))


## Colour of this cannon's movement hints: the pulsing selection colour when selected,
## otherwise a lighter tint of the type colour, one step darker per cannon of the same type.
func hint_color() -> Color:
	if selected:
		return Color(UI.ACCENT_2, 0.6 + 0.35 * sin(pulse * 6.0))
	var type_color: Color = Simulation.type_info(str(data.get("type", "normal")))["color"]
	var tint := type_color.lightened(0.55).darkened(0.24 * (shade_index % SHADE_STEPS))
	return Color(tint, 0.6)


func _draw_hints() -> void:
	var origin := Vector2(float(data.get("x", 0.0)), float(data.get("y", 0.0))) - position
	var hint := hint_color()
	var w := 3.0 if selected else 2.0
	var starts := Simulation.behavior_start_offsets(data)
	var behaviors: Array = data.get("behaviors", [])
	var step_no := 0
	for bi in behaviors.size():
		var b: Dictionary = behaviors[bi]
		# Steps start where the previous step ended; continuous behaviours start at the base.
		var base: Vector2 = origin + starts[bi]["pos"]
		var angle_base: float = float(data.get("angle", 0.0)) + float(starts[bi]["angle"])
		var is_step := bool(b.get("seq", false))
		if is_step:
			step_no += 1
			if selected:
				# Small numbered marker at the start of each step.
				draw_circle(base, 9.0, Color("#1b2138"))
				draw_circle(base, 7.0, hint)
				draw_string(ThemeDB.fallback_font, base + Vector2(-4, 4), str(step_no), HORIZONTAL_ALIGNMENT_CENTER, -1, 11, Color("#1b2138"))
		match str(b.get("type", "")):
			"move":
				var d: Vector2 = Simulation.DIRS.get(str(b.get("dir", "right")), Vector2.RIGHT)
				var r := float(b.get("range", 150.0))
				draw_dashed_line(base, base + d * r, hint, w, 8.0)
				draw_circle(base + d * r, 5.0, hint)
			"orbit":
				draw_arc(base, float(b.get("radius", 120.0)), 0.0, TAU, 48, hint, w)
				draw_circle(base, 4.0, hint)
			"sweep":
				var a0 := deg_to_rad(angle_base + float(b.get("from", -45.0)))
				var a1 := deg_to_rad(angle_base + float(b.get("to", 45.0)))
				draw_arc(Vector2.ZERO, 62.0, minf(a0, a1), maxf(a0, a1), 24, hint, w + 1.0)
			"rotate":
				draw_arc(Vector2.ZERO, 62.0, 0.0, TAU, 48, hint, w)
			"path":
				var line := Simulation.path_polyline(b)
				var closed := bool(b.get("closed", true))
				for i in range(1, line.size()):
					draw_line(base + line[i - 1], base + line[i], hint, w)
				if closed and line.size() > 1:
					draw_line(base + line[line.size() - 1], base + line[0], hint, w)
				# Control point handles, bigger when selected so they can be grabbed.
				var ctrl := Simulation.path_control_points(b)
				for i in range(1, ctrl.size()):
					draw_circle(base + ctrl[i], 7.0 if selected else 4.0, hint)
					if selected:
						draw_circle(base + ctrl[i], 4.0, Color("#1b2138"))
				draw_circle(base, 4.0, hint)
