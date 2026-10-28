class_name Backdrop
extends Node2D
## Procedural level backgrounds. Every theme is drawn with primitives so no textures are needed.

const THEMES := {
	"space": {"label": "Space", "swatch": Color("#121c33")},
	"underwater": {"label": "Underwater", "swatch": Color("#0b4f6c")},
	"meadow": {"label": "Meadow", "swatch": Color("#7ec8ff")},
	"sunset": {"label": "Sunset", "swatch": Color("#ff7b54")},
	"cave": {"label": "Cave", "swatch": Color("#2c2230")},
}
const THEME_ORDER := ["space", "underwater", "meadow", "sunset", "cave"]

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
	if theme_name == "underwater" or theme_name == "meadow":
		t += delta
		queue_redraw()


func _draw() -> void:
	match theme_name:
		"underwater": _draw_underwater()
		"meadow": _draw_meadow()
		"sunset": _draw_sunset()
		"cave": _draw_cave()
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


func _draw_dashed_rect(r: Rect2, color: Color) -> void:
	var pts := [r.position, r.position + Vector2(r.size.x, 0), r.end, r.position + Vector2(0, r.size.y), r.position]
	for i in 4:
		draw_dashed_line(pts[i], pts[i + 1], color, 2.0, 14.0)
