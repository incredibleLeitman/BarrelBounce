class_name WallsNode
extends Node2D
## Draws a level's walls (solid blocks the ball bounces off) in a style that fits the
## background theme: riveted plates in space, planks in the meadow, bricks or stone elsewhere.

const STYLES := {
	"space":       {"fill": Color("#3a4766"), "edge": Color("#8ea2cc"), "line": Color("#27324d"), "pattern": "plates"},
	"underwater":  {"fill": Color("#2f6f72"), "edge": Color("#9be0d6"), "line": Color("#1f4e52"), "pattern": "stone"},
	"meadow":      {"fill": Color("#a8743f"), "edge": Color("#5a3a1a"), "line": Color("#7d5429"), "pattern": "planks"},
	"sunset":      {"fill": Color("#c98a5a"), "edge": Color("#6e3f23"), "line": Color("#9c6540"), "pattern": "bricks"},
	"cave":        {"fill": Color("#4a3c4f"), "edge": Color("#9a8aa0"), "line": Color("#342a38"), "pattern": "stone"},
	"battlefield": {"fill": Color("#8a7652"), "edge": Color("#4a3d2c"), "line": Color("#6a5a3e"), "pattern": "bricks"},
}

var walls: Array[Rect2] = []
var theme_name := "space"
var selected := -1


func set_walls(rects: Array[Rect2], theme: String) -> void:
	if rects != walls or theme != theme_name:
		walls = rects.duplicate()
		theme_name = theme
		queue_redraw()


func _draw() -> void:
	var st: Dictionary = STYLES.get(theme_name, STYLES["space"])
	for i in walls.size():
		var r: Rect2 = walls[i]
		draw_rect(r, st["fill"])
		match str(st["pattern"]):
			"plates": _plates(r, st)
			"planks": _planks(r, st)
			"stone": _stone(r, st, i)
			_: _bricks(r, st)
		draw_rect(r, st["edge"], false, 3.0)
		if i == selected:
			draw_rect(r.grow(6), UI.ACCENT_2, false, 2.0)


func _plates(r: Rect2, st: Dictionary) -> void:
	var cell := 40.0
	var x := r.position.x + cell
	while x < r.end.x - 1.0:
		draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), st["line"], 2.0)
		x += cell
	var y := r.position.y + cell
	while y < r.end.y - 1.0:
		draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), st["line"], 2.0)
		y += cell
	# rivets in every corner of every plate
	var px := r.position.x + 6.0
	while px < r.end.x - 4.0:
		var py := r.position.y + 6.0
		while py < r.end.y - 4.0:
			draw_circle(Vector2(px, py), 2.2, st["edge"])
			py += cell
		px += cell


func _planks(r: Rect2, st: Dictionary) -> void:
	var y := r.position.y + 16.0
	while y < r.end.y - 2.0:
		draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), st["line"], 2.0)
		y += 16.0
	var x := r.position.x + 70.0
	while x < r.end.x - 2.0:
		draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), st["line"], 1.5)
		x += 70.0


func _bricks(r: Rect2, st: Dictionary) -> void:
	var bh := 20.0
	var bw := 44.0
	var row := 0
	var y := r.position.y + bh
	while y < r.end.y - 1.0:
		draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), st["line"], 2.0)
		y += bh
	y = r.position.y
	while y < r.end.y:
		var x := r.position.x + (bw * 0.5 if row % 2 == 1 else bw)
		while x < r.end.x - 1.0:
			draw_line(Vector2(x, y), Vector2(x, minf(y + bh, r.end.y)), st["line"], 2.0)
			x += bw
		y += bh
		row += 1


func _stone(r: Rect2, st: Dictionary, seed_index: int) -> void:
	# Irregular blocks: brick rows whose joints wander a little, seeded per wall.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 + seed_index * 31
	var y := r.position.y
	var row := 0
	while y < r.end.y:
		var h := minf(rng.randf_range(18.0, 30.0), r.end.y - y)
		if y > r.position.y:
			draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), st["line"], 2.0)
		var x := r.position.x + rng.randf_range(10.0, 40.0) + (18.0 if row % 2 == 1 else 0.0)
		while x < r.end.x - 4.0:
			draw_line(Vector2(x, y), Vector2(x, y + h), st["line"], 2.0)
			x += rng.randf_range(30.0, 60.0)
		y += h
		row += 1
