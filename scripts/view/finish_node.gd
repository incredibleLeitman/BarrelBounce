class_name FinishNode
extends Node2D
## The finish zone: a glowing gate with a checkered flag on top.

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
	var glow := 0.18 + 0.06 * sin(t * 3.0)
	draw_rect(rect, Color(UI.GOOD, glow))
	draw_rect(rect, Color(UI.GOOD, 0.9), false, 3.0)
	# Horizontal stripes inside the gate
	var y := rect.position.y + 12.0 + fmod(t * 40.0, 24.0)
	while y < rect.end.y - 4.0:
		draw_line(Vector2(rect.position.x + 4, y), Vector2(rect.end.x - 4, y), Color(UI.GOOD, 0.25), 2.0)
		y += 24.0
	# Flag pole and checkered flag at the top-left corner
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
