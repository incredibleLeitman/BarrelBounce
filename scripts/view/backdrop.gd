class_name Backdrop
extends Node2D
## Procedural background: night sky, stars, a soft ground band and the play-area outline.

var show_bounds := false


func _draw() -> void:
	draw_rect(Rect2(-4000, -4000, 8000, 8000), UI.BG)
	# A soft vertical gradient made from a few translucent bands.
	for i in 8:
		var y := -640.0 + i * 170.0
		draw_rect(Rect2(-4000, y, 8000, 170), Color(UI.BG_DEEP, 0.08 * (8 - i)))
	# Deterministic star field.
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in 140:
		var p := Vector2(rng.randf_range(-800, 2100), rng.randf_range(-700, 760))
		var r := rng.randf_range(1.0, 2.6)
		draw_circle(p, r, Color(1, 1, 1, rng.randf_range(0.15, 0.55)))
	# Ground band below the play area.
	draw_rect(Rect2(-4000, Simulation.BASE_SIZE.y, 8000, 4000), Color("#0a1122"))
	draw_rect(Rect2(-4000, Simulation.BASE_SIZE.y, 8000, 6), Color("#2b3b63"))
	# Play area outline.
	draw_rect(Rect2(Vector2.ZERO, Simulation.BASE_SIZE), Color(1, 1, 1, 0.07), false, 2.0)
	if show_bounds:
		_draw_dashed_rect(Simulation.WORLD, Color(UI.BAD, 0.35))


func _draw_dashed_rect(r: Rect2, color: Color) -> void:
	var pts := [r.position, r.position + Vector2(r.size.x, 0), r.end, r.position + Vector2(0, r.size.y), r.position]
	for i in 4:
		draw_dashed_line(pts[i], pts[i + 1], color, 2.0, 14.0)
