class_name CameraRig
extends Camera2D
## Zoom-out-and-back camera shared by the level and the editor.
## Mouse wheel, two-finger pinch and trackpad magnify zoom around the pointer; the owning
## scene decides when a drag pans and calls [method pan_by]. Zooming in closer than the
## default view is not allowed, and panning is clamped so the world never leaves the screen.

const ZOOM_MIN := 0.4
const ZOOM_MAX := 1.0
const ZOOM_STEP := 1.12

## Screen-space rectangle the camera may not leave (set by the owner, usually the world bounds).
var limit_rect := Rect2()
var touches: Dictionary = {}       # finger index -> screen position
var pinch_last_dist := 0.0


func _ready() -> void:
	reset_view()
	get_viewport().size_changed.connect(reset_view)


func reset_view() -> void:
	zoom = Vector2.ONE
	position = get_viewport_rect().size * 0.5
	clamp_position()


## True while two fingers are down (the owner should not treat the motion as a drag).
func pinching() -> bool:
	return touches.size() >= 2


## Handles wheel, touch tracking, pinch and magnify. Returns true when the event was a zoom.
func handle_zoom_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_by(ZOOM_STEP, event.position)
			return true
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_by(1.0 / ZOOM_STEP, event.position)
			return true
	elif event is InputEventScreenTouch:
		if event.pressed:
			touches[event.index] = event.position
		else:
			touches.erase(event.index)
		if touches.size() == 2:
			pinch_last_dist = _pinch_distance()
	elif event is InputEventScreenDrag:
		if touches.has(event.index):
			touches[event.index] = event.position
		if touches.size() == 2:
			var d := _pinch_distance()
			if pinch_last_dist > 0.0:
				zoom_by(d / pinch_last_dist, _pinch_center())
			pinch_last_dist = d
			return true
	elif event is InputEventMagnifyGesture:
		if touches.size() < 2:
			zoom_by(event.factor, event.position)
		return true
	return false


func pan_by(screen_delta: Vector2) -> void:
	position -= screen_delta / zoom.x
	clamp_position()


## Zooms around a screen point so what is under the finger / cursor stays put.
func zoom_by(factor: float, screen_point: Vector2) -> void:
	var old_zoom := zoom.x
	var new_zoom := clampf(old_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	if is_equal_approx(new_zoom, old_zoom):
		return
	var vp_center := get_viewport_rect().size * 0.5
	var world_before := position + (screen_point - vp_center) / old_zoom
	zoom = Vector2(new_zoom, new_zoom)
	position = world_before - (screen_point - vp_center) / new_zoom
	clamp_position()


func clamp_position() -> void:
	if limit_rect.size == Vector2.ZERO:
		return
	var half := get_viewport_rect().size * 0.5 / zoom.x
	var lo := limit_rect.position + half
	var hi := limit_rect.end - half
	position.x = clampf(position.x, minf(lo.x, hi.x), maxf(lo.x, hi.x))
	position.y = clampf(position.y, minf(lo.y, hi.y), maxf(lo.y, hi.y))


func _pinch_distance() -> float:
	var pts := touches.values()
	return (pts[0] as Vector2).distance_to(pts[1] as Vector2)


func _pinch_center() -> Vector2:
	var pts := touches.values()
	return ((pts[0] as Vector2) + (pts[1] as Vector2)) * 0.5
