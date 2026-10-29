class_name Backdrop
extends Node2D
## Procedural level backgrounds. Every theme is drawn with primitives so no textures are needed.

const THEMES := {
	"space": {"label": "Space", "swatch": Color("#121c33")},
	"underwater": {"label": "Underwater", "swatch": Color("#0b4f6c")},
	"meadow": {"label": "Meadow", "swatch": Color("#7ec8ff")},
	"sunset": {"label": "Sunset", "swatch": Color("#ff7b54")},
	"cave": {"label": "Cave", "swatch": Color("#2c2230")},
	"battlefield": {"label": "Battlefield", "swatch": Color("#5a4a36")},
}
const THEME_ORDER := ["space", "underwater", "meadow", "sunset", "cave", "battlefield"]

var theme_name := "space":
	set(v):
		theme_name = v if THEMES.has(v) else "space"
		queue_redraw()
var show_bounds := false
## Editor alignment grid: faint 10 px lines (the snap step) with stronger lines every 50 px.
var show_grid := false
## Play area and death bounds of the level being drawn (set by LevelView).
var level_size: Vector2 = Simulation.BASE_SIZE
var world_rect: Rect2 = Simulation.WORLD
var t := 0.0


func _process(delta: float) -> void:
	# Only the animated themes need continuous redraws.
	if theme_name == "underwater" or theme_name == "meadow" or theme_name == "battlefield":
		t += delta
		queue_redraw()


func _draw() -> void:
	match theme_name:
		"underwater": _draw_underwater()
		"meadow": _draw_meadow()
		"sunset": _draw_sunset()
		"cave": _draw_cave()
		"battlefield": _draw_battlefield()
		_: _draw_space()
	if show_grid:
		_draw_grid()
	# Play area outline, visible in every theme.
	draw_rect(Rect2(Vector2.ZERO, level_size), Color(1, 1, 1, 0.08), false, 2.0)
	if show_bounds:
		_draw_dashed_rect(world_rect, Color(UI.BAD, 0.35))


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _bands(top: Color, bottom: Color, y0: float, y1: float, steps: int = 12) -> void:
	var h := (y1 - y0) / steps
	for i in steps:
		draw_rect(Rect2(-4000, y0 + i * h, 8000, h + 1), top.lerp(bottom, float(i) / (steps - 1)))


func _draw_space() -> void:
	draw_rect(Rect2(-4000, -4000, 8000, 8000), UI.BG)
	for i in 8:
		draw_rect(Rect2(-4000, -640.0 + i * 170.0, 8000, 170), Color(UI.BG_DEEP, 0.08 * (8 - i)))
	var rng := _rng(4242)
	for i in 140:
		var p := Vector2(rng.randf_range(-800, 2100), rng.randf_range(-700, 760))
		draw_circle(p, rng.randf_range(1.0, 2.6), Color(1, 1, 1, rng.randf_range(0.15, 0.55)))
	draw_rect(Rect2(-4000, level_size.y, 8000, 4000), Color("#0a1122"))
	draw_rect(Rect2(-4000, level_size.y, 8000, 6), Color("#2b3b63"))


func _draw_underwater() -> void:
	draw_rect(Rect2(-4000, -4000, 8000, 8000), Color("#062a3d"))
	_bands(Color("#1b8fb8"), Color("#062a3d"), -700, 760, 16)
	# Light rays from the surface.
	for i in 6:
		var x := -300.0 + i * 420.0 + sin(t * 0.3 + i) * 30.0
		var pts := PackedVector2Array([Vector2(x, -700), Vector2(x + 90, -700), Vector2(x + 330, 760), Vector2(x + 60, 760)])
		draw_colored_polygon(pts, Color(1, 1, 1, 0.035))
	# Bubbles rising, deterministic per bubble and looping on time.
	var rng := _rng(77)
	for i in 50:
		var speed := rng.randf_range(20, 60)
		var x := rng.randf_range(-600, 1900) + sin(t * 1.3 + i) * 6.0
		var y := 800.0 - fmod(rng.randf_range(0, 1500) + t * speed, 1500.0)
		draw_arc(Vector2(x, y), rng.randf_range(2, 7), 0.0, TAU, 12, Color(1, 1, 1, 0.3), 1.5)
	# Sandy floor with sea plants.
	draw_rect(Rect2(-4000, level_size.y, 8000, 4000), Color("#c9b27c"))
	draw_rect(Rect2(-4000, level_size.y, 8000, 8), Color("#e6d4a2"))
	var prng := _rng(99)
	for i in 30:
		var x := prng.randf_range(-700, 2000)
		var h := prng.randf_range(40, 130)
		var sway := sin(t * 1.5 + i) * 10.0
		draw_line(Vector2(x, level_size.y), Vector2(x + sway, level_size.y - h), Color("#2f8f5b"), 5.0)
		draw_line(Vector2(x + 8, level_size.y), Vector2(x + 8 + sway * 0.6, level_size.y - h * 0.6), Color("#3fae6e"), 4.0)


func _draw_meadow() -> void:
	draw_rect(Rect2(-4000, -4000, 8000, 8000), Color("#5fb6ff"))
	_bands(Color("#4aa3f0"), Color("#bfe6ff"), -700, 640, 14)
	# Sun
	draw_circle(Vector2(1100, -60), 90.0, Color(1, 0.95, 0.6, 0.35))
	draw_circle(Vector2(1100, -60), 60.0, Color("#fff1a8"))
	# Clouds drifting slowly.
	var rng := _rng(5)
	for i in 10:
		var base_x := rng.randf_range(-800, 2000)
		var y := rng.randf_range(-600, 260)
		var s := rng.randf_range(0.7, 1.4)
		var x := -800.0 + fmod(base_x + 800.0 + t * 12.0 * s, 2800.0)
		var c := Color(1, 1, 1, 0.9)
		draw_circle(Vector2(x, y), 34 * s, c)
		draw_circle(Vector2(x + 34 * s, y - 14 * s), 42 * s, c)
		draw_circle(Vector2(x + 76 * s, y), 32 * s, c)
		draw_rect(Rect2(x - 10 * s, y, 110 * s, 30 * s), c)
	# Rolling hills and the ground.
	draw_rect(Rect2(-4000, level_size.y, 8000, 4000), Color("#5aa83c"))
	for i in 7:
		var cx := -600.0 + i * 420.0
		draw_circle(Vector2(cx, level_size.y + 100.0), 220.0, Color("#6dbb47"))
	draw_rect(Rect2(-4000, level_size.y, 8000, 10), Color("#7fd255"))


func _draw_sunset() -> void:
	draw_rect(Rect2(-4000, -4000, 8000, 8000), Color("#2b1b3d"))
	_bands(Color("#3a2355"), Color("#ff9a62"), -700, 560, 16)
	_bands(Color("#ff9a62"), Color("#ffd27a"), 560, 720, 4)
	draw_circle(Vector2(640, 560), 120.0, Color("#ffe29a"))
	draw_circle(Vector2(640, 560), 150.0, Color(1, 0.85, 0.5, 0.25))
	# Silhouetted hills in two layers.
	for layer in 2:
		var col := Color("#4d2a5a") if layer == 0 else Color("#2b1b3d")
		var rng := _rng(13 + layer)
		var pts := PackedVector2Array([Vector2(-4000, 800)])
		var x := -4000.0
		while x < 4000.0:
			pts.append(Vector2(x, 620 + layer * 40 + rng.randf_range(-70, 40)))
			x += 180.0
		pts.append(Vector2(4000, 800))
		pts.append(Vector2(4000, 4000))
		pts.append(Vector2(-4000, 4000))
		draw_colored_polygon(pts, col)
	draw_rect(Rect2(-4000, level_size.y, 8000, 4000), Color("#2b1b3d"))
	draw_rect(Rect2(-4000, level_size.y, 8000, 6), Color("#6b3f7a"))


func _draw_cave() -> void:
	draw_rect(Rect2(-4000, -4000, 8000, 8000), Color("#1c1622"))
	_bands(Color("#2c2230"), Color("#1c1622"), -700, 760, 10)
	var rng := _rng(21)
	# Stalactites from the top, stalagmites from the floor.
	for i in 26:
		var x := rng.randf_range(-700, 2000)
		var w := rng.randf_range(20, 60)
		var h := rng.randf_range(60, 220)
		draw_colored_polygon(PackedVector2Array([Vector2(x - w, -700), Vector2(x + w, -700), Vector2(x, -700 + h)]), Color("#3a2d42"))
	for i in 18:
		var x := rng.randf_range(-700, 2000)
		var w := rng.randf_range(20, 50)
		var h := rng.randf_range(40, 140)
		draw_colored_polygon(PackedVector2Array([Vector2(x - w, level_size.y + 2.0), Vector2(x + w, level_size.y + 2.0), Vector2(x, level_size.y + 2.0 - h)]), Color("#3a2d42"))
	# Glowing crystals.
	for i in 16:
		var p := Vector2(rng.randf_range(-600, 1900), rng.randf_range(-500, 700))
		var c := Color("#7fe3ff") if i % 2 == 0 else Color("#c77dff")
		draw_circle(p, 18.0, Color(c, 0.12))
		draw_colored_polygon(PackedVector2Array([p + Vector2(-5, 6), p + Vector2(5, 6), p + Vector2(0, -10)]), Color(c, 0.8))
	draw_rect(Rect2(-4000, level_size.y, 8000, 4000), Color("#120e17"))
	draw_rect(Rect2(-4000, level_size.y, 8000, 6), Color("#4a3a55"))


func _draw_grid() -> void:
	var size := level_size
	var minor := Color(1, 1, 1, 0.09)
	var major := Color(1, 1, 1, 0.26)
	# Width -1 is a hairline: always one screen pixel, whatever the zoom or editor scale.
	var x := 0.0
	while x <= size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), major if fmod(x, 50.0) == 0.0 else minor, -1.0)
		x += 10.0
	var y := 0.0
	while y <= size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), major if fmod(y, 50.0) == 0.0 else minor, -1.0)
		y += 10.0


## A wasted battlefield: dusty sky, smoke columns, ruined silhouettes, shell craters, barbed
## wire, sandbags and two knocked-out tanks, one of them still smouldering.
func _draw_battlefield() -> void:
	var ground_y := level_size.y
	var field_y := ground_y - 140.0   # where the churned-up mud field begins
	draw_rect(Rect2(-4000, -4000, 8000, 8000), Color("#3a3328"))
	_bands(Color("#4a4236"), Color("#8c7a5e"), -700, field_y - 60, 14)
	_bands(Color("#8c7a5e"), Color("#a08a66"), field_y - 60, field_y, 3)
	# Pale sun behind haze.
	draw_circle(Vector2(level_size.x * 0.75, 120), 70.0, Color(1, 0.95, 0.8, 0.12))
	draw_circle(Vector2(level_size.x * 0.75, 120), 44.0, Color(1, 0.95, 0.8, 0.35))
	# Ruined buildings and dead trees on the horizon.
	var rng := _rng(1917)
	for i in 14:
		var x := rng.randf_range(-600, level_size.x + 900)
		var w := rng.randf_range(50, 140)
		var h := rng.randf_range(40, 150)
		var col := Color("#5f5343")
		var pts := PackedVector2Array([Vector2(x, field_y), Vector2(x, field_y - h)])
		var steps := int(rng.randf_range(2, 5))
		for k in steps:
			var sx := x + w * (k + 1) / steps
			pts.append(Vector2(sx, field_y - h * rng.randf_range(0.3, 1.0)))
		pts.append(Vector2(x + w, field_y))
		draw_colored_polygon(pts, col)
		# blown-out window holes
		for k in 3:
			var wx := x + rng.randf_range(8, w - 16)
			var wy := field_y - rng.randf_range(15, h - 20)
			if wy < field_y - 12:
				draw_rect(Rect2(wx, wy, 8, 10), Color("#8c7a5e"))
	for i in 9:
		var x := rng.randf_range(-600, level_size.x + 900)
		var h := rng.randf_range(60, 130)
		draw_line(Vector2(x, field_y), Vector2(x + 6, field_y - h), Color("#2e2820"), 5.0)
		draw_line(Vector2(x + 3, field_y - h * 0.6), Vector2(x - 25, field_y - h * 0.85), Color("#2e2820"), 3.0)
		draw_line(Vector2(x + 4, field_y - h * 0.8), Vector2(x + 28, field_y - h * 0.95), Color("#2e2820"), 3.0)
	# Thin smoke columns drifting up from fires behind the horizon.
	for i in 4:
		var x := rng.randf_range(-200, level_size.x + 400)
		for k in 9:
			var age := fmod(t * 0.12 + k * 0.111 + i * 0.3, 1.0)
			var p := Vector2(x + sin(age * 5.0 + i) * 14.0 + age * 90.0, field_y - 10.0 - age * 380.0)
			draw_circle(p, 7.0 + age * 22.0, Color(0.22, 0.2, 0.17, 0.10 * (1.0 - age)))
	# The mud field: a churned strip with shell craters, nearer ones bigger.
	draw_rect(Rect2(-4000, field_y, 8000, 4000), Color("#5a4a36"))
	draw_rect(Rect2(-4000, field_y, 8000, 6), Color("#6f5c44"))
	var craters: Array = []
	for i in 22:
		var depth := rng.randf()   # 0 = far (top of the field), 1 = near (bottom)
		craters.append([rng.randf_range(-600, level_size.x + 900), field_y + 14.0 + depth * (ground_y - field_y - 22.0), 28.0 + depth * 80.0, depth])
	craters.sort_custom(func(a, b): return a[3] < b[3])
	for c in craters:
		_crater(Vector2(c[0], c[1]), c[2])
	# Barbed wire on posts, sandbags.
	var wire_y := field_y + 30.0
	for i in 4:
		var x := rng.randf_range(-400, level_size.x + 600)
		for k in 4:
			var px := x + k * 70.0
			draw_line(Vector2(px, wire_y + 2), Vector2(px + 4, wire_y - 34), Color("#2e2820"), 4.0)
			if k > 0:
				var a := Vector2(px - 66, wire_y - 30)
				var b := Vector2(px + 4, wire_y - 34)
				draw_line(a, b, Color("#2e2820"), 1.5)
				draw_line(a + Vector2(0, 16), b + Vector2(0, 16), Color("#2e2820"), 1.5)
				for j in 6:
					var q := a.lerp(b, (j + 0.5) / 6.0)
					draw_line(q + Vector2(-3, -3), q + Vector2(3, 3), Color("#2e2820"), 1.5)
					draw_line(q + Vector2(-3, 3), q + Vector2(3, -3), Color("#2e2820"), 1.5)
	for i in 3:
		var x := rng.randf_range(-300, level_size.x + 500)
		var sy := field_y + rng.randf_range(40, 90)
		for row in 2:
			for k in 4 - row:
				var bx := x + k * 26.0 + row * 13.0
				var by := sy - 12.0 - row * 13.0
				draw_rect(Rect2(bx, by, 24, 12), Color("#7d6a4c"))
				draw_rect(Rect2(bx, by, 24, 12), Color("#4a3d2c"), false, 1.5)
	# Two knocked-out tanks: a distant silhouette and a close one, still smouldering.
	_tank(Vector2(level_size.x * 0.12, field_y + 40.0), 0.5, false)
	_tank(Vector2(level_size.x * 0.62, ground_y - 14.0), 0.9, true)


func _crater(c: Vector2, rw: float) -> void:
	var rh := rw * 0.38
	# rim (lighter), bowl (darker), shadow inside
	draw_set_transform(c, 0.0, Vector2(1.0, rh / rw))
	draw_circle(Vector2.ZERO, rw + 8.0, Color("#6f5c44"))
	draw_circle(Vector2.ZERO, rw, Color("#3f3326"))
	draw_circle(Vector2(0, 4), rw * 0.7, Color("#2c231a"))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _tank(base: Vector2, s: float, smoke: bool) -> void:
	var dark := Color("#2a2a22")
	var body := Color("#4b5236") if smoke else Color("#3b3f2c")
	var light := Color("#5d654a") if smoke else Color("#474c38")
	draw_set_transform(base, 0.0, Vector2(s, s))
	# tracks: a sunken, bent track on the right side
	draw_rect(Rect2(-120, -40, 230, 44), dark)
	for i in 6:
		draw_circle(Vector2(-100 + i * 42, -18), 14.0, Color("#3a3a30"))
		draw_circle(Vector2(-100 + i * 42, -18), 6.0, dark)
	draw_line(Vector2(110, -36), Vector2(150, -4), dark, 10.0)   # thrown track
	# hull, tilted into a crater
	draw_set_transform(base, deg_to_rad(-6.0), Vector2(s, s))
	draw_colored_polygon(PackedVector2Array([Vector2(-130, -42), Vector2(120, -42), Vector2(100, -78), Vector2(-110, -78)]), body)
	draw_colored_polygon(PackedVector2Array([Vector2(-110, -78), Vector2(100, -78), Vector2(90, -86), Vector2(-100, -86)]), light)
	# turret, blown slightly off its ring
	draw_set_transform(base + Vector2(10, -84) * s, deg_to_rad(-14.0), Vector2(s, s))
	draw_colored_polygon(PackedVector2Array([Vector2(-55, 0), Vector2(55, 0), Vector2(40, -34), Vector2(-40, -34)]), body)
	draw_rect(Rect2(-18, -46, 36, 12), light)   # hatch, open
	# barrel, bent upwards at the end
	draw_line(Vector2(50, -18), Vector2(150, -24), dark, 9.0)
	draw_line(Vector2(150, -24), Vector2(178, -48), dark, 8.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# blackened hole in the hull
	draw_circle(base + Vector2(-40, -62) * s, 14.0 * s, Color("#161612"))
	draw_circle(base + Vector2(-40, -62) * s, 20.0 * s, Color("#161612", 0.4))
	if smoke:
		for k in 8:
			var age := fmod(t * 0.2 + k * 0.125, 1.0)
			var p := base + Vector2(-40 + sin(age * 5.0 + k) * 14.0 + age * 50.0, -70 - age * 240.0) * s
			draw_circle(p, (6.0 + age * 26.0) * s, Color(0.18, 0.17, 0.15, 0.22 * (1.0 - age)))
		# embers
		var e := _rng(int(t * 8.0))
		for k in 5:
			var p := base + Vector2(-40 + e.randf_range(-12, 12), -62 + e.randf_range(-10, 10)) * s
			draw_circle(p, 2.0, Color("#ff8a3d", e.randf_range(0.5, 1.0)))


func _draw_dashed_rect(r: Rect2, color: Color) -> void:
	var pts := [r.position, r.position + Vector2(r.size.x, 0), r.end, r.position + Vector2(0, r.size.y), r.position]
	for i in 4:
		draw_dashed_line(pts[i], pts[i + 1], color, 2.0, 14.0)
