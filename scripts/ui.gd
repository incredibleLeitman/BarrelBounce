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
	var th := Theme.new()
	th.default_font_size = 20

	th.set_stylebox("normal", "Button", flat(PANEL_LIGHT, 14, 14))
	th.set_stylebox("hover", "Button", flat(PANEL_LIGHT.lightened(0.12), 14, 14))
	th.set_stylebox("pressed", "Button", flat(ACCENT, 14, 14))
	th.set_stylebox("focus", "Button", empty())
	th.set_stylebox("disabled", "Button", flat(PANEL, 14, 14))
	th.set_color("font_color", "Button", TEXT)
	th.set_color("font_hover_color", "Button", TEXT)
	th.set_color("font_pressed_color", "Button", Color.WHITE)
	th.set_color("font_disabled_color", "Button", MUTED)
	th.set_color("font_focus_color", "Button", TEXT)

	for cls in ["OptionButton", "CheckBox", "CheckButton"]:
		th.set_stylebox("normal", cls, flat(PANEL_LIGHT, 10, 10))
		th.set_stylebox("hover", cls, flat(PANEL_LIGHT.lightened(0.12), 10, 10))
		# A checked box is shown by its check mark, not by an orange fill.
		var checked_style := flat(ACCENT, 10, 10) if cls == "OptionButton" else flat(PANEL_LIGHT, 10, 10)
		th.set_stylebox("pressed", cls, checked_style)
		th.set_stylebox("hover_pressed", cls, flat(PANEL_LIGHT.lightened(0.12), 10, 10))
		th.set_stylebox("focus", cls, empty())
		th.set_color("font_color", cls, TEXT)
		th.set_color("font_hover_color", cls, TEXT)
		th.set_color("font_pressed_color", cls, TEXT)

	th.set_stylebox("panel", "PanelContainer", flat(PANEL, 18, 16))
	th.set_stylebox("panel", "Panel", flat(PANEL, 18, 16))
	th.set_stylebox("panel", "PopupMenu", flat(PANEL, 10, 8))
	th.set_stylebox("hover", "PopupMenu", flat(PANEL_LIGHT, 8, 6))
	th.set_color("font_color", "PopupMenu", TEXT)
	th.set_color("font_hover_color", "PopupMenu", Color.WHITE)

	th.set_stylebox("normal", "LineEdit", flat(BG_DEEP, 10, 10))
	th.set_stylebox("focus", "LineEdit", flat(BG_DEEP, 10, 10, ACCENT))
	th.set_color("font_color", "LineEdit", TEXT)
	th.set_color("caret_color", "LineEdit", ACCENT)
	th.set_color("font_placeholder_color", "LineEdit", MUTED)

	th.set_stylebox("up_background", "SpinBox", empty())
	th.set_stylebox("down_background", "SpinBox", empty())
	th.set_color("font_color", "Label", TEXT)
	th.set_stylebox("panel", "ScrollContainer", empty())
	_theme = th
	return th


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


## Translates a string while keeping the padding spaces some buttons use for width.
static func t(text: String) -> String:
	var core := text.strip_edges()
	if core.is_empty():
		return text
	return text.replace(core, TranslationServer.translate(core))


static func button(text: String, min_height: float = 56.0, font_size: int = 22) -> Button:
	var b := Button.new()
	b.text = t(text)
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


## Button with one of the line icons from assets/icons (24 px, white).
static func icon_button(text: String, icon_name: String, min_height: float = 44.0, font_size: int = 18) -> Button:
	var b := button(text, min_height, font_size)
	b.icon = load("res://assets/icons/%s.svg" % icon_name)
	b.expand_icon = false
	b.add_theme_constant_override("h_separation", 8 if text.strip_edges() != "" else 0)
	return b


## Modal dialog with a title, a message and Yes / No buttons. [param on_yes] runs on confirm.
## Full-screen shade on a layer above everything else; freeing it closes the dialog.
static func _shade(parent: Control) -> ColorRect:
	var canvas := CanvasLayer.new()
	canvas.layer = 100
	# Attach to the scene that owns the parent (its top-most ancestor below the root), so the
	# dialog disappears together with the scene instead of surviving a scene change.
	var owner_scene: Node = parent
	var root := parent.get_tree().root
	while owner_scene.get_parent() != null and owner_scene.get_parent() != root:
		owner_scene = owner_scene.get_parent()
	owner_scene.add_child(canvas)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.theme = theme()
	shade.tree_exited.connect(canvas.queue_free)
	canvas.add_child(shade)
	return shade


static func confirm(parent: Control, title_text: String, message: String, yes_text: String, on_yes: Callable) -> void:
	var shade := _shade(parent)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	shade.add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(420, 0)
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var t := title(title_text, 32)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	var m := label(message, 18, MUTED)
	m.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	m.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(m)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var no := button("Cancel")
	no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	no.pressed.connect(shade.queue_free)
	row.add_child(no)
	var yes := accent_button(yes_text, 56, 22)
	yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	yes.pressed.connect(func():
		shade.queue_free()
		on_yes.call())
	row.add_child(yes)


## Modal panel with a close button; returns the VBox to fill with content.
static func dialog(parent: Control, title_text: String, width: float = 720.0) -> VBoxContainer:
	var shade := _shade(parent)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	shade.add_child(panel)
	var outer := VBoxContainer.new()
	outer.custom_minimum_size = Vector2(width, 0)
	outer.add_theme_constant_override("separation", 10)
	panel.add_child(outer)
	var head := HBoxContainer.new()
	outer.add_child(head)
	head.add_child(title(title_text, 32))
	head.add_child(hspacer_expand())
	var close := small_button("  Close  ")
	close.pressed.connect(shade.queue_free)
	head.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(width, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	scroll.add_child(body)
	# Keep the dialog inside the screen on short displays.
	scroll.custom_minimum_size.y = minf(520.0, parent.size.y - 140.0)
	return body


static func label(text: String, size: int = 20, color: Color = TEXT, autowrap: bool = false) -> Label:
	var l := Label.new()
	l.text = t(text)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if autowrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	s.suffix = t(suffix)
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
