class_name UI
extends RefCounted
## Shared look & feel. Everything is built in code so there are no asset files to manage.

const BG := Color("#121c33")
const BG_DEEP := Color("#0c1426")
const PANEL := Color("#1d2a4a")
const PANEL_LIGHT := Color("#2b3b63")
const ACCENT := Color("#ff8a3d")
const ACCENT_2 := Color("#4cc9f0")
const GOOD := Color("#9bd36a")
const BAD := Color("#e5484d")
const TEXT := Color("#f1f3f8")
const MUTED := Color("#9aa5c4")

static var _theme: Theme


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font_size = 20

	t.set_stylebox("normal", "Button", flat(PANEL_LIGHT, 14, 14))
	t.set_stylebox("hover", "Button", flat(PANEL_LIGHT.lightened(0.12), 14, 14))
	t.set_stylebox("pressed", "Button", flat(ACCENT, 14, 14))
	t.set_stylebox("focus", "Button", empty())
	t.set_stylebox("disabled", "Button", flat(PANEL, 14, 14))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", TEXT)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", MUTED)
	t.set_color("font_focus_color", "Button", TEXT)

	for cls in ["OptionButton", "CheckBox", "CheckButton"]:
		t.set_stylebox("normal", cls, flat(PANEL_LIGHT, 10, 10))
		t.set_stylebox("hover", cls, flat(PANEL_LIGHT.lightened(0.12), 10, 10))
		t.set_stylebox("pressed", cls, flat(ACCENT, 10, 10))
		t.set_stylebox("focus", cls, empty())
		t.set_color("font_color", cls, TEXT)
		t.set_color("font_hover_color", cls, TEXT)
		t.set_color("font_pressed_color", cls, TEXT)

	t.set_stylebox("panel", "PanelContainer", flat(PANEL, 18, 16))
	t.set_stylebox("panel", "Panel", flat(PANEL, 18, 16))
	t.set_stylebox("panel", "PopupMenu", flat(PANEL, 10, 8))
	t.set_stylebox("hover", "PopupMenu", flat(PANEL_LIGHT, 8, 6))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)

	t.set_stylebox("normal", "LineEdit", flat(BG_DEEP, 10, 10))
	t.set_stylebox("focus", "LineEdit", flat(BG_DEEP, 10, 10, ACCENT))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("font_placeholder_color", "LineEdit", MUTED)

	t.set_stylebox("up_background", "SpinBox", empty())
	t.set_stylebox("down_background", "SpinBox", empty())
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "ScrollContainer", empty())
	_theme = t
	return t


static func flat(color: Color, radius: int = 12, pad: int = 10, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad * 1.4
	s.content_margin_right = pad * 1.4
	s.content_margin_top = pad
	s.content_margin_bottom = pad
	if border.a > 0.0:
		s.border_color = border
		s.set_border_width_all(2)
	return s


static func empty() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()


static func button(text: String, min_height: float = 56.0, font_size: int = 22) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, min_height)
	b.add_theme_font_size_override("font_size", font_size)
	b.focus_mode = Control.FOCUS_NONE
	return b


static func accent_button(text: String, min_height: float = 64.0, font_size: int = 26) -> Button:
	var b := button(text, min_height, font_size)
	b.add_theme_stylebox_override("normal", flat(ACCENT, 16, 14))
	b.add_theme_stylebox_override("hover", flat(ACCENT.lightened(0.12), 16, 14))
	b.add_theme_stylebox_override("pressed", flat(ACCENT.darkened(0.15), 16, 14))
	b.add_theme_color_override("font_color", Color.WHITE)
	return b


static func small_button(text: String) -> Button:
	return button(text, 44.0, 18)


static func label(text: String, size: int = 20, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func title(text: String, size: int = 64) -> Label:
	var l := label(text, size, TEXT)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 5)
	return l


static func spacer(size: float = 12.0, vertical: bool = true) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, size) if vertical else Vector2(size, 0)
	return c


static func hspacer_expand() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


static func spin(min_v: float, max_v: float, step: float, value: float, suffix: String = "") -> SpinBox:
	var s := SpinBox.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.suffix = suffix
	s.custom_minimum_size = Vector2(120, 40)
	s.get_line_edit().add_theme_font_size_override("font_size", 16)
	return s


## Full-screen UI root with the game theme applied.
static func layer() -> CanvasLayer:
	var canvas := CanvasLayer.new()
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(root)
	return canvas


static func root_of(canvas: CanvasLayer) -> Control:
	return canvas.get_node("Root") as Control


## Transient message at the bottom of the screen.
static func toast(parent: Control, text: String, color: Color = ACCENT_2) -> void:
	var l := label(text, 22, Color.WHITE)
	l.add_theme_stylebox_override("normal", flat(color, 12, 10))
	l.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l.grow_vertical = Control.GROW_DIRECTION_BEGIN
	l.position = Vector2(-l.size.x / 2.0, -90)
	parent.add_child(l)
	l.reset_size()
	l.position = Vector2(parent.size.x / 2.0 - l.size.x / 2.0, parent.size.y - 90.0)
	var tw := l.create_tween()
	tw.tween_interval(1.4)
	tw.tween_property(l, "modulate:a", 0.0, 0.4)
	tw.tween_callback(l.queue_free)
