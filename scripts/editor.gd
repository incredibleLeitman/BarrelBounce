extends Node2D
## Level editor. Drag cannons and the finish gate around, tweak cannon type / angle /
## behaviours in the inspector, preview the deterministic motion, test play, save.
##
## Selection: tap a cannon to select it. Ctrl / Shift + tap (or the Select mode button on
## touch) toggles cannons in and out of the selection, dragging on empty space in that mode
## draws a selection rectangle. Pressing an already selected cannon never changes the
## selection, it starts a drag of the whole group; the selection only collapses to that one
## cannon when the button is released without having moved. The inspector shows a value when
## every selected cannon agrees on it, leaves it empty otherwise, and applies edits to all.

const GRID := 10.0
const PICK_RADIUS := 40.0
const EDGE_GRAB := 12.0      # distance (level px) from a gate edge that grabs it for resizing
const MIN_GATE := 20.0
const CLICK_SLOP := 6.0      # level px of movement that still counts as a click

enum Drag { NONE, MOVE, LEFT, RIGHT, TOP, BOTTOM, BAND, HANDLE }
const HANDLE_RADIUS := 16.0  # level px within which a path point can be grabbed

var level: Dictionary
var sim: Simulation
var view: LevelView
var dirty := false

var selection: Array[int] = []   # selected cannon indices, last clicked at the end
var finish_selected := false
var dragging := false
var drag_mode: int = Drag.NONE
var drag_offset := Vector2.ZERO
var drag_anchor := Rect2()       # gate rect when a resize drag started
var drag_start := Vector2.ZERO   # level point where the press happened
var drag_moved := false
var drag_positions: Dictionary = {}   # cannon index -> base position when a group drag started
var pressed_cannon := -1         # cannon under the press, for the release-collapses-selection rule
var press_modifier := false      # select mode / Ctrl was active at the press
var press_was_selected := false  # the pressed cannon was already selected before the press
var panning := false             # dragging empty space (or the middle mouse button) moves the camera
var previewing := false
var select_mode := false         # touch-friendly stand-in for holding Ctrl
var path_edit := -1              # behaviour index of the primary cannon whose path is being edited
var behavior_panels: Array = []  # [panel, idle stylebox, active stylebox] per behaviour row
var last_active_step := -1
var handle_index := -1           # control point being dragged in path edit mode
var camera: CameraRig
var grid_button: Button
var select_button: Button

var ui: CanvasLayer
var name_edit: LineEdit
var inspector: PanelContainer
var inspector_box: VBoxContainer
var preview_button: Button
var tick_label: Label
var save_button: Button


func _ready() -> void:
	Online.track("editor_open")
	level = GameState.editor_level
	if level.is_empty():
		level = GameState.new_level()
	level = GameState.normalize_level(level)
	GameState.editor_level = level
	sim = Simulation.new(level)
	view = LevelView.new()
	view.show_hints = true
	view.fit_inset = Rect2(12, 66, 372, 12)   # keep clear of the top bar and the inspector
	add_child(view)
	view.bind(sim)
	camera = CameraRig.new()
	add_child(camera)
	_update_camera_limits()
	get_viewport().size_changed.connect(_update_camera_limits)
	_build_ui()
	_set_selection([0])


func _update_camera_limits() -> void:
	# The view is scaled to fit beside the inspector, so the world bounds scale with it.
	var world := Rect2(view.position + sim.world.position * view.scale.x, sim.world.size * view.scale.x)
	# Merge with the viewport so the default view stays put when the scaled world is smaller than the screen.
	camera.limit_rect = Rect2(Vector2.ZERO, get_viewport_rect().size).merge(world)
	camera.clamp_position()


## The cannon the inspector header talks about: the last one clicked.
func primary() -> int:
	return selection[selection.size() - 1] if not selection.is_empty() else -1


# ---------------------------------------------------------------- UI

func _build_ui() -> void:
	ui = UI.layer()
	add_child(ui)
	var root := UI.root_of(ui)

	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 12
	top.offset_right = -12
	top.offset_top = 10
	top.add_theme_constant_override("separation", 8)
	root.add_child(top)

	var back := UI.small_button("  < Back  ")
	back.pressed.connect(_on_back)
	top.add_child(back)

	name_edit = LineEdit.new()
	name_edit.text = str(level.get("name", "My Level"))
	name_edit.placeholder_text = tr("Level name")
	name_edit.custom_minimum_size = Vector2(180, 44)
	name_edit.text_changed.connect(func(t):
		level["name"] = t
		_mark_dirty())
	top.add_child(name_edit)

	var add := UI.small_button("  + Cannon  ")
	add.pressed.connect(_add_cannon)
	top.add_child(add)

	var settings := UI.icon_button("", "gear")
	settings.tooltip_text = tr("Level settings (background)")
	settings.pressed.connect(_show_settings)
	top.add_child(settings)

	var help := UI.icon_button("", "help")
	help.pressed.connect(func(): HelpDialog.show(root))
	top.add_child(help)

	grid_button = UI.icon_button("", "grid")
	grid_button.toggle_mode = true
	grid_button.button_pressed = false
	grid_button.tooltip_text = tr("Show the alignment grid")
	grid_button.toggled.connect(func(on):
		view.backdrop.show_grid = on
		view.backdrop.queue_redraw())
	top.add_child(grid_button)

	select_button = UI.icon_button("", "select")
	select_button.toggle_mode = true
	select_button.tooltip_text = tr("Multi-select: tap cannons to add or remove them, drag a rectangle on empty space. Same as holding Ctrl.")
	select_button.toggled.connect(func(on): select_mode = on)
	top.add_child(select_button)

	top.add_child(UI.hspacer_expand())

	tick_label = UI.label("t = 0.00 s", 16, UI.MUTED)
	tick_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(tick_label)
	preview_button = UI.small_button("  Preview  ")
	preview_button.pressed.connect(_toggle_preview)
	top.add_child(preview_button)

	var test := UI.small_button("  Test  ")
	test.pressed.connect(_test_play)
	top.add_child(test)
	save_button = UI.accent_button("  Save  ", 44, 18)
	save_button.pressed.connect(_save)
	top.add_child(save_button)

	# Inspector (right side)
	inspector = PanelContainer.new()
	inspector.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	inspector.offset_left = -372
	inspector.offset_right = -12
	inspector.offset_top = 66
	inspector.offset_bottom = -12
	root.add_child(inspector)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inspector.add_child(scroll)
	inspector_box = VBoxContainer.new()
	inspector_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector_box.add_theme_constant_override("separation", 8)
	scroll.add_child(inspector_box)

	var hint := UI.label("Drag to move · Ctrl+tap or Select mode for multi-select · drag a gate edge to resize it", 15, UI.MUTED)
	hint.add_theme_stylebox_override("normal", UI.flat(Color(UI.BG_DEEP, 0.75), 10, 6))
	hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.offset_left = 16
	hint.offset_top = -44
	hint.offset_bottom = -12
	root.add_child(hint)


func _clear_inspector() -> void:
	behavior_panels.clear()
	last_active_step = -1
	for c in inspector_box.get_children():
		c.queue_free()


func _rebuild_inspector() -> void:
	_clear_inspector()
	if finish_selected:
		_build_finish_inspector()
	elif not selection.is_empty():
		_build_cannon_inspector()
	else:
		inspector_box.add_child(UI.label("Nothing selected", 20, UI.MUTED))
		inspector_box.add_child(UI.label("Tap a cannon or the finish gate.", 16, UI.MUTED))


func _build_finish_inspector() -> void:
	var f: Dictionary = level["finish"]
	inspector_box.add_child(UI.title("Finish gate", 28))
	inspector_box.add_child(UI.label("Cross it to finish the level.", 15, UI.MUTED))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	inspector_box.add_child(grid)
	for spec in [["w", "Width", 20.0, 600.0], ["h", "Height", 20.0, 720.0]]:
		grid.add_child(UI.label(spec[1], 16, UI.MUTED))
		var s := UI.spin(spec[2], spec[3], 10.0, float(f.get(spec[0], 60.0)), " px")
		var key: String = spec[0]
		s.value_changed.connect(func(v):
			f[key] = v
			_mark_dirty()
			view.refresh())
		grid.add_child(s)


## Selected cannon dictionaries, in selection order.
func _selected_cannons() -> Array:
	var out: Array = []
	for i in selection:
		if i >= 0 and i < level["cannons"].size():
			out.append(level["cannons"][i])
	return out


## The shared value of [param key] across the selection, or null when they differ.
func _common(cannons: Array, key: String, default) -> Variant:
	var first = cannons[0].get(key, default)
	for c in cannons:
		if c.get(key, default) != first:
			return null
	return first


func _build_cannon_inspector() -> void:
	var cannons := _selected_cannons()
	var multi := cannons.size() > 1
	var header := HBoxContainer.new()
	inspector_box.add_child(header)
	if multi:
		header.add_child(UI.title(tr("%d cannons") % cannons.size(), 28))
	else:
		header.add_child(UI.title(tr("Cannon %d") % (primary() + 1), 28))
	header.add_child(UI.hspacer_expand())
	var start := int(level.get("start", 0))
	var has_start := selection.has(start)
	if multi:
		if has_start:
			header.add_child(UI.label("incl. START", 14, UI.GOOD))
	elif primary() == start:
		header.add_child(UI.label("START", 14, UI.GOOD))
	else:
		var mk := UI.small_button(" Make start ")
		mk.pressed.connect(func():
			level["start"] = primary()
			Simulation.enforce_start_type(level)
			_structure_changed())
		header.add_child(mk)
	if multi:
		inspector_box.add_child(UI.label("Values are shown when all selected cannons agree and left empty otherwise. Changes apply to all of them.", 13, UI.MUTED, true))

	# Type (locked for the start cannon: a level must never fire without a tap)
	var type_row := HBoxContainer.new()
	type_row.add_theme_constant_override("separation", 10)
	inspector_box.add_child(type_row)
	type_row.add_child(UI.label("Type", 16, UI.MUTED))
	var type_opt := OptionButton.new()
	type_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	type_opt.custom_minimum_size.y = 40
	type_opt.disabled = has_start and not multi
	var common_type = _common(cannons, "type", "normal")
	# Item ids are TYPE_ORDER indices; the demo only lists the plain cannon.
	for key in GameState.allowed_types():
		type_opt.add_item(tr(Simulation.TYPES[key]["label"]), Simulation.TYPE_ORDER.find(key))
	if common_type == null or type_opt.get_item_index(Simulation.TYPE_ORDER.find(str(common_type))) < 0:
		type_opt.add_item("", 99)
		type_opt.select(type_opt.item_count - 1)
	else:
		type_opt.select(type_opt.get_item_index(Simulation.TYPE_ORDER.find(str(common_type))))
	var hint_text := ""
	if common_type != null:
		hint_text = tr(Simulation.type_info(str(common_type))["hint"])
	if has_start:
		hint_text = tr("The start cannon is always a plain cannon so the level only begins with your tap.")
		if multi:
			hint_text += tr(" It keeps its type when you change the others.")
	var type_hint := UI.label(hint_text, 14, UI.MUTED, true)
	type_opt.item_selected.connect(func(i):
		var id := type_opt.get_item_id(i)
		if id < 0 or id >= Simulation.TYPE_ORDER.size():
			return
		for c in cannons:
			c["type"] = Simulation.TYPE_ORDER[id]
		Simulation.enforce_start_type(level)
		type_hint.text = tr(Simulation.TYPES[Simulation.TYPE_ORDER[id]]["hint"])
		_mark_dirty()
		view.redraw_all())
	type_row.add_child(type_opt)
	inspector_box.add_child(type_hint)
	if not GameState.full_version():
		inspector_box.add_child(UI.label("Six more cannon types and walls are in the full game.", 14, UI.ACCENT_2, true))

	# Angle
	var ang_row := HBoxContainer.new()
	ang_row.add_theme_constant_override("separation", 10)
	inspector_box.add_child(ang_row)
	ang_row.add_child(UI.label("Angle", 16, UI.MUTED))
	var common_angle = _common(cannons, "angle", 0.0)
	var apply_angle := func(v: float):
		for c in cannons:
			c["angle"] = v
		_params_changed()
	var ang := HSlider.new()
	ang.min_value = -180
	ang.max_value = 180
	ang.step = 5
	ang.value = float(common_angle) if common_angle != null else 0.0
	ang.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ang.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ang.custom_minimum_size.y = 40
	ang_row.add_child(ang)
	if common_angle == null:
		# Mixed: an empty field; typing a value applies it to every selected cannon.
		var edit := LineEdit.new()
		edit.placeholder_text = tr("mixed")
		edit.custom_minimum_size = Vector2(100, 40)
		edit.text_submitted.connect(func(t):
			if t.is_valid_float():
				apply_angle.call(clampf(float(t), -180.0, 180.0))
				_rebuild_inspector())
		ang_row.add_child(edit)
		ang.value_changed.connect(func(v):
			apply_angle.call(v)
			edit.text = str(v))
	else:
		var ang_spin := UI.spin(-180, 180, 5, float(common_angle), "°")
		ang_spin.custom_minimum_size.x = 100
		ang_row.add_child(ang_spin)
		ang.value_changed.connect(func(v):
			ang_spin.set_value_no_signal(v)
			apply_angle.call(v))
		ang_spin.value_changed.connect(func(v):
			ang.set_value_no_signal(v)
			apply_angle.call(v))
	inspector_box.add_child(UI.label("0° = right, -90° = up, 90° = down", 13, UI.MUTED))

	# Behaviours
	inspector_box.add_child(UI.spacer(6))
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 8)
	inspector_box.add_child(bh)
	bh.add_child(UI.label("Movement", 20))
	bh.add_child(UI.hspacer_expand())
	var add_opt := OptionButton.new()
	add_opt.custom_minimum_size.y = 40
	add_opt.add_item(tr("+ Add…"), 0)
	for i in Simulation.BEHAVIOR_ORDER.size():
		add_opt.add_item(tr(Simulation.BEHAVIORS[Simulation.BEHAVIOR_ORDER[i]]["label"]), i + 1)
	add_opt.item_selected.connect(func(i):
		if i == 0:
			return
		var kind: String = Simulation.BEHAVIOR_ORDER[i - 1]
		for c in cannons:
			var b := {"type": kind}
			for p in Simulation.BEHAVIORS[kind]["params"]:
				b[p[0]] = p[5]
			if Simulation.BEHAVIORS[kind].has("dir"):
				b["dir"] = "right"
			for flag in ["clockwise", "smooth", "closed"]:
				if Simulation.BEHAVIORS[kind].has(flag):
					b[flag] = true
			if Simulation.BEHAVIORS[kind].has("default_points"):
				b["points"] = Simulation.BEHAVIORS[kind]["default_points"].duplicate(true)
			c["behaviors"].append(b)
		_structure_changed())
	bh.add_child(add_opt)
	# Sequence mode on its own row (the header must stay narrower than the inspector).
	var has_step := false
	for c in cannons:
		for blk in c["behaviors"]:
			if bool(blk.get("seq", false)):
				has_step = true
	if has_step:
		var back_and_forth := str(cannons[0].get("seq_mode", "loop")) == "pingpong"
		var mode_btn := UI.small_button(tr("Sequence: back & forth") if back_and_forth else tr("Sequence: loop"))
		mode_btn.tooltip_text = tr("How the sequence repeats: play it forwards and then backwards, or restart from step 1")
		mode_btn.pressed.connect(func():
			for c in cannons:
				c["seq_mode"] = "loop" if back_and_forth else "pingpong"
			_structure_changed())
		inspector_box.add_child(mode_btn)

	# Behaviour rows are editable for the whole selection only when every cannon has the
	# same list; otherwise the lists cannot be lined up and we offer a reset instead.
	var same_lists := true
	var reference := JSON.stringify(cannons[0]["behaviors"])
	for c in cannons:
		if JSON.stringify(c["behaviors"]) != reference:
			same_lists = false
			break
	if not same_lists:
		inspector_box.add_child(UI.label("The selected cannons move differently, so their movement is not shown. Adding a movement adds it to all of them.", 14, UI.MUTED, true))
		var clear := UI.button("Remove all movement", 40, 16)
		clear.pressed.connect(func():
			for c in cannons:
				c["behaviors"].clear()
			_structure_changed())
		inspector_box.add_child(clear)
	elif cannons[0]["behaviors"].is_empty():
		inspector_box.add_child(UI.label("Static cannon. Add movement to make it tricky.", 14, UI.MUTED))
	else:
		for bi in cannons[0]["behaviors"].size():
			_build_behavior_row(cannons, bi)

	inspector_box.add_child(UI.spacer(10))
	var del := UI.icon_button(tr("Delete cannon") if not multi else tr("Delete %d cannons") % cannons.size(), "trash")
	del.add_theme_color_override("font_color", UI.BAD)
	del.disabled = level["cannons"].size() - cannons.size() < 1
	del.pressed.connect(_delete_selection)
	inspector_box.add_child(del)


## One behaviour row; edits write to the same slot of every selected cannon.
## Blocks that run together get a shared bracket on the left; steps get a number, a duration
## and the sequence icon. The icon button flips a block between the two.
func _build_behavior_row(cannons: Array, bi: int) -> void:
	var b: Dictionary = cannons[0]["behaviors"][bi]
	var kind := str(b.get("type", "rotate"))
	var spec: Dictionary = Simulation.BEHAVIORS.get(kind, Simulation.BEHAVIORS["rotate"])
	var is_step := bool(b.get("seq", false))
	var set_all := func(key: String, v):
		for c in cannons:
			c["behaviors"][bi][key] = v
	var panel := PanelContainer.new()
	var idle := UI.flat(UI.BG_DEEP, 12, 8)
	if not is_step:
		# Bracket joining the blocks that run together.
		idle.border_width_left = 5
		idle.border_color = Color(UI.ACCENT_2, 0.6)
		idle.corner_radius_top_left = 2
		idle.corner_radius_bottom_left = 2
	var active := UI.flat(UI.BG_DEEP.lightened(0.08), 12, 8, UI.ACCENT)
	panel.add_theme_stylebox_override("panel", idle)
	inspector_box.add_child(panel)
	behavior_panels.append([panel, idle, active])
	var box := VBoxContainer.new()
	panel.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	box.add_child(head)
	var mode := UI.icon_button("", "seq" if is_step else "par", 36, 14)
	mode.tooltip_text = tr("Step %d of the sequence: click to run it together with the others") % _step_number(cannons[0], bi) if is_step else tr("Runs together with the other blocks: click to make it a step in a sequence")
	mode.pressed.connect(func():
		for c in cannons:
			var blk: Dictionary = c["behaviors"][bi]
			blk["seq"] = not is_step
			if not is_step and not blk.has("duration"):
				blk["duration"] = Simulation.default_duration(blk)
			if not c.has("seq_mode"):
				c["seq_mode"] = "pingpong"   # new sequences play back and forth by default
		_structure_changed())
	head.add_child(mode)
	if is_step:
		var badge := UI.label(str(_step_number(cannons[0], bi)), 14, Color("#1b2138"))
		badge.add_theme_stylebox_override("normal", UI.flat(UI.ACCENT_2, 10, 2))
		badge.custom_minimum_size = Vector2(24, 24)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		head.add_child(badge)
	head.add_child(UI.label(spec["label"], 18, UI.ACCENT_2))
	head.add_child(UI.hspacer_expand())
	var up := UI.button("^", 32, 14)
	up.custom_minimum_size.x = 32
	up.disabled = bi == 0
	up.pressed.connect(func(): _move_behavior(cannons, bi, -1))
	head.add_child(up)
	var down := UI.button("v", 32, 14)
	down.custom_minimum_size.x = 32
	down.disabled = bi >= cannons[0]["behaviors"].size() - 1
	down.pressed.connect(func(): _move_behavior(cannons, bi, 1))
	head.add_child(down)
	var rm := UI.button("x", 32, 14)
	rm.custom_minimum_size.x = 32
	rm.pressed.connect(func():
		for c in cannons:
			c["behaviors"].remove_at(bi)
		_structure_changed())
	head.add_child(rm)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 4)
	box.add_child(grid)
	if is_step:
		grid.add_child(UI.label("Duration s", 15, UI.MUTED))
		var dur := UI.spin(0.1, 60.0, 0.1, Simulation.step_duration(b))
		dur.value_changed.connect(func(v):
			set_all.call("duration", v)
			_structure_changed())
		grid.add_child(dur)
	for p in spec["params"]:
		grid.add_child(UI.label(p[1], 15, UI.MUTED))
		var s := UI.spin(p[2], p[3], p[4], float(b.get(p[0], p[5])))
		var key: String = p[0]
		s.value_changed.connect(func(v):
			set_all.call(key, v)
			_params_changed())
		grid.add_child(s)
	if spec.has("dir"):
		grid.add_child(UI.label("Direction", 15, UI.MUTED))
		var opt := OptionButton.new()
		opt.custom_minimum_size.y = 40
		for i in Simulation.DIR_ORDER.size():
			opt.add_item(tr(Simulation.DIR_ORDER[i].replace("_", " ")), i)
			if Simulation.DIR_ORDER[i] == str(b.get("dir", "right")):
				opt.select(i)
		opt.item_selected.connect(func(i):
			set_all.call("dir", Simulation.DIR_ORDER[i])
			_params_changed())
		grid.add_child(opt)
	for flag in [["clockwise", "Clockwise"], ["smooth", "Smooth curve"], ["closed", "Loop around"]]:
		if not spec.has(flag[0]):
			continue
		grid.add_child(UI.label(flag[1], 15, UI.MUTED))
		var cb := CheckBox.new()
		var key: String = flag[0]
		cb.button_pressed = bool(b.get(key, true))
		cb.toggled.connect(func(on):
			set_all.call(key, on)
			_params_changed())
		grid.add_child(cb)
	if kind == "path":
		_build_path_tools(box, cannons, bi)


## 1-based position of behaviour [param bi] among the cannon's steps.
func _step_number(c: Dictionary, bi: int) -> int:
	var n := 0
	for i in bi + 1:
		if bool(c["behaviors"][i].get("seq", false)):
			n += 1
	return n


func _move_behavior(cannons: Array, bi: int, delta: int) -> void:
	for c in cannons:
		var bs: Array = c["behaviors"]
		var j := bi + delta
		if j < 0 or j >= bs.size():
			return
		var tmp = bs[bi]
		bs[bi] = bs[j]
		bs[j] = tmp
	_structure_changed()


## Preview: highlight the step that is playing on the primary cannon.
func _update_active_step() -> void:
	var idx := -1
	if previewing and primary() >= 0 and selection.size() == 1:
		idx = Simulation.active_step(level["cannons"][primary()], sim.tick)
	if idx == last_active_step:
		return
	last_active_step = idx
	for i in behavior_panels.size():
		var entry: Array = behavior_panels[i]
		if is_instance_valid(entry[0]):
			entry[0].add_theme_stylebox_override("panel", entry[2] if i == idx else entry[1])


## Point editing for a path behaviour (single selection only).
func _build_path_tools(box: VBoxContainer, cannons: Array, bi: int) -> void:
	var b: Dictionary = cannons[0]["behaviors"][bi]
	var count: int = b.get("points", []).size()
	if cannons.size() > 1:
		box.add_child(UI.label(tr("%d points · select a single cannon to edit them") % count, 13, UI.MUTED, true))
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var edit := UI.small_button("  Edit points  ")
	edit.toggle_mode = true
	edit.button_pressed = path_edit == bi
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.toggled.connect(func(on):
		path_edit = bi if on else -1
		_update_cursor(view.world_mouse()))
	row.add_child(edit)
	var undo := UI.small_button("  Undo point  ")
	undo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	undo.disabled = count == 0
	undo.pressed.connect(func():
		b["points"].pop_back()
		_params_changed()
		_rebuild_inspector())
	row.add_child(undo)
	box.add_child(UI.label(tr("%d points") % count, 13, UI.MUTED))
	if path_edit == bi:
		box.add_child(UI.label("Tap in the level to add points, drag a point to move it.", 13, UI.MUTED, true))


## Base position of the primary cannon (path points are relative to it).
func _primary_base() -> Vector2:
	var c: Dictionary = level["cannons"][primary()]
	return Vector2(float(c["x"]), float(c["y"]))


func _path_behavior() -> Dictionary:
	if path_edit < 0 or primary() < 0:
		return {}
	var bs: Array = level["cannons"][primary()]["behaviors"]
	if path_edit >= bs.size() or str(bs[path_edit].get("type", "")) != "path":
		return {}
	return bs[path_edit]


func _hit_handle(p: Vector2) -> int:
	var b := _path_behavior()
	if b.is_empty():
		return -1
	var base := _primary_base()
	var pts: Array = b.get("points", [])
	for i in pts.size():
		if p.distance_to(base + Vector2(float(pts[i][0]), float(pts[i][1]))) <= HANDLE_RADIUS:
			return i
	return -1


# ---------------------------------------------------------------- editing

func _mark_dirty() -> void:
	dirty = true
	save_button.text = tr("  Save •  ")


func _params_changed() -> void:
	_mark_dirty()
	sim.set_tick(sim.tick)
	view.redraw_all()
	view.refresh()


## Cannons/behaviours added or removed: rebuild nodes and the inspector.
func _structure_changed() -> void:
	_mark_dirty()
	sim.reset()
	sim.set_tick(0)
	view.rebuild()
	var kept: Array[int] = []
	for i in selection:
		if i < level["cannons"].size() and not kept.has(i):
			kept.append(i)
	selection = kept
	view.set_selection(selection, finish_selected)
	_rebuild_inspector()


func _set_selection(indices: Array, finish := false) -> void:
	path_edit = -1
	selection.clear()
	for i in indices:
		selection.append(int(i))
	finish_selected = finish and indices.is_empty()
	view.set_selection(selection, finish_selected)
	_rebuild_inspector()


func _toggle_in_selection(i: int) -> void:
	var s := selection.duplicate()
	if s.has(i):
		s.erase(i)
	else:
		s.append(i)
	_set_selection(s)


func _select_all() -> void:
	var all: Array[int] = []
	for i in level["cannons"].size():
		all.append(i)
	_set_selection(all)


func _add_cannon() -> void:
	var c := {"x": sim.size.x * 0.5, "y": sim.size.y * 0.55, "angle": -45.0, "type": "normal", "behaviors": []}
	level["cannons"].append(c)
	selection = [level["cannons"].size() - 1]
	finish_selected = false
	_structure_changed()


func _delete_selection() -> void:
	var doomed := selection.duplicate()
	doomed.sort()
	doomed.reverse()
	if level["cannons"].size() - doomed.size() < 1:
		return
	var start := int(level.get("start", 0))
	for i in doomed:
		level["cannons"].remove_at(i)
		if i < start:
			start -= 1
		elif i == start:
			start = 0
	level["start"] = clampi(start, 0, level["cannons"].size() - 1)
	Simulation.enforce_start_type(level)
	selection = []
	_structure_changed()


func _modifier_held() -> bool:
	return select_mode or Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_META)


## True when a screen point is over the inspector or the top bar.
func _over_ui(screen_point: Vector2) -> bool:
	return inspector.get_global_rect().has_point(screen_point) or screen_point.y < 66.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and _over_ui(event.position):
		# Wheel over the inspector scrolls or edits values there; it must never zoom the level.
		if not event.pressed:
			_release(view.world_mouse())
		return
	if event is InputEventMouseMotion and not dragging and not panning and _over_ui(event.position):
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		return
	if camera.handle_zoom_input(event):
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE or event.button_index == MOUSE_BUTTON_RIGHT:
			panning = event.pressed
			return
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		if event.pressed:
			_press(view.world_mouse())
		else:
			_release(view.world_mouse())
	elif event is InputEventMouseMotion:
		if camera.pinching():
			return
		if dragging:
			_drag_to(view.world_mouse())
		elif panning:
			camera.pan_by(event.relative)
		else:
			_update_cursor(view.world_mouse())
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if path_edit >= 0:
				path_edit = -1
				_rebuild_inspector()
			else:
				_on_back()
		elif event.keycode == KEY_DELETE:
			if path_edit >= 0:
				var b := _path_behavior()
				if not b.is_empty() and not b["points"].is_empty():
					b["points"].pop_back()
					_params_changed()
					_rebuild_inspector()
			else:
				_delete_selection()
		elif event.keycode == KEY_A and (event.ctrl_pressed or event.meta_pressed):
			_select_all()


func _exit_tree() -> void:
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)


# ---------------------------------------------------------------- picking & dragging

func _hit_cannon(p: Vector2) -> int:
	var best := -1
	var best_d := PICK_RADIUS * PICK_RADIUS
	for i in sim.cannon_states.size():
		var d: float = p.distance_squared_to(sim.cannon_states[i]["pos"])
		if d < best_d:
			best_d = d
			best = i
	return best


func _hit_gate(p: Vector2) -> int:
	var r := sim.finish_rect()
	if not r.grow(EDGE_GRAB).has_point(p):
		return Drag.NONE
	# Edges win over the interior so even a thin gate can be resized.
	var dl := absf(p.x - r.position.x)
	var dr := absf(p.x - r.end.x)
	var dt := absf(p.y - r.position.y)
	var db := absf(p.y - r.end.y)
	var m := minf(minf(dl, dr), minf(dt, db))
	if m <= EDGE_GRAB:
		if m == dl: return Drag.LEFT
		if m == dr: return Drag.RIGHT
		if m == dt: return Drag.TOP
		return Drag.BOTTOM
	return Drag.MOVE


func _update_cursor(p: Vector2) -> void:
	var shape := Input.CURSOR_ARROW
	if dragging:
		shape = _cursor_for(drag_mode)
	elif path_edit >= 0:
		shape = Input.CURSOR_MOVE if _hit_handle(p) >= 0 else Input.CURSOR_CROSS
	elif _hit_cannon(p) >= 0:
		shape = Input.CURSOR_MOVE
	else:
		shape = _cursor_for(_hit_gate(p))
	Input.set_default_cursor_shape(shape)


func _cursor_for(mode: int) -> Input.CursorShape:
	match mode:
		Drag.MOVE: return Input.CURSOR_MOVE
		Drag.LEFT, Drag.RIGHT: return Input.CURSOR_HSIZE
		Drag.TOP, Drag.BOTTOM: return Input.CURSOR_VSIZE
		Drag.BAND: return Input.CURSOR_CROSS
		Drag.HANDLE: return Input.CURSOR_MOVE
	return Input.CURSOR_ARROW


func _press(p: Vector2) -> void:
	drag_start = p
	drag_moved = false
	pressed_cannon = -1
	var modifier := _modifier_held()
	if path_edit >= 0 and not _path_behavior().is_empty():
		var b := _path_behavior()
		handle_index = _hit_handle(p)
		if handle_index < 0:
			var rel := (p - _primary_base()).snapped(Vector2(GRID, GRID))
			b["points"].append([rel.x, rel.y])
			handle_index = b["points"].size() - 1
			_rebuild_inspector()
		dragging = true
		drag_mode = Drag.HANDLE
		_params_changed()
		_update_cursor(p)
		return
	# Cannons are picked at their *current* (animated) position.
	var hit := _hit_cannon(p)
	if hit >= 0:
		pressed_cannon = hit
		press_modifier = modifier
		press_was_selected = selection.has(hit) and not finish_selected
		if modifier:
			# Select mode: an unselected cannon joins the selection right away; an already
			# selected one leaves it only on a click without movement (see _release), so a
			# press can always start a drag of the group.
			if not press_was_selected:
				_toggle_in_selection(hit)
		elif not press_was_selected:
			_set_selection([hit])
		# Group drag: remember where every selected cannon started.
		dragging = true
		drag_mode = Drag.MOVE
		drag_positions.clear()
		for i in selection:
			var c: Dictionary = level["cannons"][i]
			drag_positions[i] = Vector2(float(c["x"]), float(c["y"]))
		drag_offset = drag_positions[hit] - sim.cannon_states[hit]["pos"]
		_update_cursor(p)
		return
	var gate := _hit_gate(p)
	if gate != Drag.NONE and not modifier:
		_set_selection([], true)
		dragging = true
		drag_mode = gate
		drag_anchor = sim.finish_rect()
		drag_offset = drag_anchor.position - p
		_update_cursor(p)
		return
	if modifier:
		# Rubber band on empty space.
		dragging = true
		drag_mode = Drag.BAND
		view.set_band(Rect2(p, Vector2.ZERO))
		_update_cursor(p)
		return
	# Empty space: clear the selection and let the drag pan the camera.
	_set_selection([])
	panning = true


func _release(p: Vector2) -> void:
	if drag_mode == Drag.BAND:
		var band := Rect2(drag_start, p - drag_start).abs()
		var picked: Array[int] = selection.duplicate()
		for i in sim.cannon_states.size():
			if band.has_point(sim.cannon_states[i]["pos"]) and not picked.has(i):
				picked.append(i)
		view.set_band(Rect2())
		_set_selection(picked)
	elif drag_mode == Drag.MOVE and pressed_cannon >= 0 and not drag_moved:
		if press_modifier and press_was_selected:
			# Click (no drag) on a selected cannon in select mode: remove it from the selection.
			_toggle_in_selection(pressed_cannon)
		elif not press_modifier and selection.size() > 1:
			# A plain click on one of several selected cannons, without moving: select just that one.
			_set_selection([pressed_cannon])
	dragging = false
	panning = false
	drag_mode = Drag.NONE
	pressed_cannon = -1
	_update_cursor(p)


func _drag_to(p: Vector2) -> void:
	if p.distance_to(drag_start) > CLICK_SLOP:
		drag_moved = true
	if drag_mode == Drag.BAND:
		view.set_band(Rect2(drag_start, p - drag_start).abs())
		return
	if drag_mode == Drag.HANDLE:
		var b := _path_behavior()
		if not b.is_empty() and handle_index >= 0 and handle_index < b["points"].size():
			var rel := (p - _primary_base()).snapped(Vector2(GRID, GRID))
			b["points"][handle_index] = [rel.x, rel.y]
			_params_changed()
		return
	var snapped_p := p.snapped(Vector2(GRID, GRID))
	if finish_selected:
		var f: Dictionary = level["finish"]
		var a := drag_anchor
		match drag_mode:
			Drag.MOVE:
				var target := (p + drag_offset).snapped(Vector2(GRID, GRID))
				f["x"] = clampf(target.x, 0.0, sim.size.x - a.size.x)
				f["y"] = clampf(target.y, 0.0, sim.size.y - a.size.y)
			Drag.LEFT:
				var x := clampf(snapped_p.x, 0.0, a.end.x - MIN_GATE)
				f["x"] = x
				f["w"] = a.end.x - x
			Drag.RIGHT:
				f["w"] = clampf(snapped_p.x, a.position.x + MIN_GATE, sim.size.x) - a.position.x
			Drag.TOP:
				var y := clampf(snapped_p.y, 0.0, a.end.y - MIN_GATE)
				f["y"] = y
				f["h"] = a.end.y - y
			Drag.BOTTOM:
				f["h"] = clampf(snapped_p.y, a.position.y + MIN_GATE, sim.size.y) - a.position.y
		if drag_mode != Drag.MOVE:
			_rebuild_inspector()   # keep the width / height spin boxes in sync
	elif not selection.is_empty() and pressed_cannon >= 0:
		# Move the whole group by the grabbed cannon's snapped displacement.
		var target := (p + drag_offset).snapped(Vector2(GRID, GRID))
		var delta: Vector2 = target - drag_positions[pressed_cannon]
		for i in selection:
			if not drag_positions.has(i):
				continue
			var c: Dictionary = level["cannons"][i]
			var np: Vector2 = drag_positions[i] + delta
			c["x"] = clampf(np.x, 0.0, sim.size.x)
			c["y"] = clampf(np.y, 0.0, sim.size.y)
	_mark_dirty()
	sim.set_tick(sim.tick)
	view.refresh()
	view.redraw_all()


# ---------------------------------------------------------------- level settings

func _show_settings() -> void:
	var body := UI.dialog(UI.root_of(ui), "Level settings", 640)
	body.add_child(UI.label("Size", 20))
	body.add_child(UI.label("The play area in pixels. Bigger levels start zoomed out so they fit on the screen.", 13, UI.MUTED, true))
	var size_row := HBoxContainer.new()
	size_row.add_theme_constant_override("separation", 10)
	body.add_child(size_row)
	for spec in [["width", "Width", Simulation.MIN_SIZE.x, Simulation.MAX_SIZE.x, sim.size.x],
			["height", "Height", Simulation.MIN_SIZE.y, Simulation.MAX_SIZE.y, sim.size.y]]:
		size_row.add_child(UI.label(spec[1], 16, UI.MUTED))
		var spin := UI.spin(spec[2], spec[3], 10.0, spec[4], " px")
		var key: String = spec[0]
		spin.value_changed.connect(func(v):
			level[key] = v
			_size_changed())
		size_row.add_child(spin)
	body.add_child(UI.spacer(6))
	body.add_child(UI.label("Background", 20))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	body.add_child(grid)
	var buttons: Array = []
	for key in Backdrop.THEME_ORDER:
		var info: Dictionary = Backdrop.THEMES[key]
		var b := Button.new()
		b.text = tr(info["label"])
		b.custom_minimum_size = Vector2(190, 70)
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.button_pressed = key == str(level.get("background", "space"))
		var col: Color = info["swatch"]
		b.add_theme_stylebox_override("normal", UI.flat(col, 14, 10))
		b.add_theme_stylebox_override("hover", UI.flat(col.lightened(0.1), 14, 10))
		b.add_theme_stylebox_override("pressed", UI.flat(col, 14, 10, Color.WHITE))
		b.add_theme_color_override("font_color", Color.WHITE if col.get_luminance() < 0.5 else Color("#1b2138"))
		b.add_theme_color_override("font_pressed_color", Color.WHITE if col.get_luminance() < 0.5 else Color("#1b2138"))
		var chosen: String = key
		b.pressed.connect(func():
			level["background"] = chosen
			for other in buttons:
				other.button_pressed = other == b
			_mark_dirty()
			view.refresh())
		grid.add_child(b)
		buttons.append(b)


# ---------------------------------------------------------------- preview / play / save

func _toggle_preview() -> void:
	previewing = not previewing
	preview_button.text = tr("  Stop  ") if previewing else "  Preview  "
	if not previewing:
		sim.set_tick(0)
		view.refresh()


func _physics_process(_delta: float) -> void:
	if previewing:
		sim.set_tick(sim.tick + 1)
		view.refresh()
	_update_active_step()
	tick_label.text = tr("t = %.2f s") % (sim.tick / float(Simulation.TICK_RATE))


func _test_play() -> void:
	GameState.editor_level = level
	GameState.play_level(level, GameState.SCENE_EDITOR)


func _save() -> void:
	if GameState.is_builtin(level):
		level["id"] = GameState.new_level_id()
		level["author"] = GameState.player_name()
	if GameState.save_user_level(level):
		dirty = false
		save_button.text = tr("  Save  ")
		var id := str(level["id"])
		var rev := GameState.level_hash(level)
		if GameState.best_is_stale(id, rev):
			UI.toast(UI.root_of(ui), tr("Saved “%s”. The level changed, so its best time was reset. Finish it to share it.") % str(level.get("name", "")), UI.ACCENT)
		elif not GameState.is_verified(level):
			UI.toast(UI.root_of(ui), tr("Saved “%s”. Finish it once (Test) to make it shareable.") % str(level.get("name", "")), UI.GOOD)
		else:
			UI.toast(UI.root_of(ui), tr("Saved “%s”") % str(level.get("name", "")), UI.GOOD)
	else:
		UI.toast(UI.root_of(ui), "Could not save level", UI.BAD)


func _on_back() -> void:
	if dirty:
		_save()
	GameState.editor_level = {}
	GameState.go(GameState.SCENE_SELECT)


## The play area was resized: keep everything inside it and refit the view.
func _size_changed() -> void:
	sim.reset()
	for c in level["cannons"]:
		c["x"] = clampf(float(c["x"]), 0.0, sim.size.x)
		c["y"] = clampf(float(c["y"]), 0.0, sim.size.y)
	var f: Dictionary = level["finish"]
	f["w"] = clampf(float(f.get("w", 60.0)), MIN_GATE, sim.size.x)
	f["h"] = clampf(float(f.get("h", 400.0)), MIN_GATE, sim.size.y)
	f["x"] = clampf(float(f.get("x", 0.0)), 0.0, sim.size.x - float(f["w"]))
	f["y"] = clampf(float(f.get("y", 0.0)), 0.0, sim.size.y - float(f["h"]))
	_mark_dirty()
	view.rebuild()
	_update_camera_limits()
	camera.reset_view()
	view.set_selection(selection, finish_selected)
