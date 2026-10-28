class_name FinishNode
extends Node2D
## The finish gate: a calm outline with rings that pulse inwards, and a checkered flag on top.

var rect := Rect2(1100, 160, 60, 400)
var selected := false
var t := 0.0


func set_rect(r: Rect2) -> void:
	if r != rect:
		rect = r
		queue_redraw()


func _process(delta: float) -> void:
	t += delta
	queue_redraw()


func _draw() -> void:
	draw_rect(rect, Color(UI.GOOD, 0.12))
	# Rings travelling from the border towards the centre, fading as they go.
	var half := minf(rect.size.x, rect.size.y) * 0.5
	for k in 3:
		var phase := fmod(t * 0.6 + k / 3.0, 1.0)
		var inset := phase * half
		var inner := rect.grow(-inset)
		if inner.size.x > 2.0 and inner.size.y > 2.0:
			draw_rect(inner, Color(UI.GOOD, 0.55 * (1.0 - phase)), false, 2.0)
	draw_rect(rect, Color(UI.GOOD, 0.9), false, 3.0)
	# Flag pole and checkered flag at the top-left corner.
	var pole_top := rect.position + Vector2(0, -48)
	draw_line(rect.position, pole_top, Color("#dfe6f5"), 4.0)
	var sq := 8.0
	for i in 5:
		for j in 3:
			var c := Color.WHITE if (i + j) % 2 == 0 else Color("#1b2138")
			var wave := sin(t * 6.0 + i * 0.7) * 2.0
			draw_rect(Rect2(pole_top + Vector2(2 + i * sq, j * sq + wave), Vector2(sq, sq)), c)
	if selected:
		draw_rect(rect.grow(6), UI.ACCENT_2, false, 2.0)
