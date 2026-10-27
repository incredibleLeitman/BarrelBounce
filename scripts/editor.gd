extends Node2D
## Level editor. Drag cannons and the finish gate around, tweak cannon type / angle /
## behaviours in the inspector, preview the deterministic motion, test play, save.

const GRID := 10.0
const PICK_RADIUS := 40.0

var level: Dictionary
var sim: Simulation
var view: LevelView
var dirty := false

var selected := -1          # cannon index, -1 = none
var finish_selected := false
var dragging := false
var drag_offset := Vector2.ZERO
var previewing := false

var ui: CanvasLayer
var name_edit: LineEdit
var inspector: PanelContainer
var inspector_box: VBoxContainer
var preview_button: Button
var tick_label: Label
var save_button: Button


func _ready() -> void:
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
	_build_ui()
	_select_cannon(0)


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

	var back := UI.small_button("  ◀  ")
	back.pressed.connect(_on_back)
	top.add_child(back)

	name_edit = LineEdit.new()
	name_edit.text = str(level.get("name", "My Level"))
	name_edit.placeholder_text = "Level name"
	name_edit.custom_minimum_size = Vector2(220, 44)
	name_edit.text_changed.connect(func(t):
		level["name"] = t
		_mark_dirty())
	top.add_child(name_edit)

	var add := UI.small_button("  + Cannon  ")
	add.pressed.connect(_add_cannon)
	top.add_child(add)

	top.add_child(UI.hspacer_expand())

	tick_label = UI.label("t = 0.00 s", 16, UI.MUTED)
	tick_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(tick_label)
	preview_button = UI.small_button("  ▶ Preview  ")
	preview_button.pressed.connect(_toggle_preview)
	top.add_child(preview_button)

	var test := UI.small_button("  Test ▶  ")
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

	var hint := UI.label("Drag things to move them · tap a cannon or the gate to edit it", 15, UI.MUTED)
	hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.offset_left = 16
	hint.offset_top = -40
	hint.offset_bottom = -12
	root.add_child(hint)


func _clear_inspector() -> void:
	for c in inspector_box.get_children():
		c.queue_free()


func _rebuild_inspector() -> void:
	_clear_inspector()
	if finish_selected:
		_build_finish_inspector()
	elif selected >= 0 and selected < level["cannons"].size():
		_build_cannon_inspector(level["cannons"][selected])
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


func _build_cannon_inspector(c: Dictionary) -> void:
	var header := HBoxContainer.new()
	inspector_box.add_child(header)
	header.add_child(UI.title("Cannon %d" % (selected + 1), 28))
	header.add_child(UI.hspacer_expand())
	if selected == int(level.get("start", 0)):
		header.add_child(UI.label("START", 14, UI.GOOD))
	else:
		var mk := UI.small_button(" Make start ")
		mk.pressed.connect(func():
			level["start"] = selected
			_structure_changed())
		header.add_child(mk)

	# Type
	var type_row := HBoxContainer.new()
	type_row.add_theme_constant_override("separation", 10)
	inspector_box.add_child(type_row)
	type_row.add_child(UI.label("Type", 16, UI.MUTED))
	var type_opt := OptionButton.new()
	type_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	type_opt.custom_minimum_size.y = 40
	for i in Simulation.TYPE_ORDER.size():
		var key: String = Simulation.TYPE_ORDER[i]
		type_opt.add_item(Simulation.TYPES[key]["label"], i)
		if key == str(c.get("type", "normal")):
			type_opt.select(i)
	var type_hint := UI.label(Simulation.type_info(str(c.get("type", "normal")))["hint"], 14, UI.MUTED)
	type_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	type_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	type_opt.item_selected.connect(func(i):
		c["type"] = Simulation.TYPE_ORDER[i]
		type_hint.text = Simulation.TYPES[c["type"]]["hint"]
		_mark_dirty()
		view.redraw_all())
	type_row.add_child(type_opt)
	inspector_box.add_child(type_hint)

	# Angle
	var ang_row := HBoxContainer.new()
	ang_row.add_theme_constant_override("separation", 10)
	inspector_box.add_child(ang_row)
	ang_row.add_child(UI.label("Angle", 16, UI.MUTED))
	var ang := HSlider.new()
	ang.min_value = -180
	ang.max_value = 180
	ang.step = 5
	ang.value = float(c.get("angle", 0.0))
	ang.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ang.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ang.custom_minimum_size.y = 40
	ang_row.add_child(ang)
	var ang_spin := UI.spin(-180, 180, 5, float(c.get("angle", 0.0)), "°")
	ang_spin.custom_minimum_size.x = 100
	ang_row.add_child(ang_spin)
	ang.value_changed.connect(func(v):
		c["angle"] = v
		ang_spin.set_value_no_signal(v)
		_params_changed())
	ang_spin.value_changed.connect(func(v):
		c["angle"] = v
		ang.set_value_no_signal(v)
		_params_changed())
	inspector_box.add_child(UI.label("0° = right, -90° = up, 90° = down", 13, UI.MUTED))

	# Behaviours
	inspector_box.add_child(UI.spacer(6))
	var bh := HBoxContainer.new()
	inspector_box.add_child(bh)
	bh.add_child(UI.label("Movement", 20))
	bh.add_child(UI.hspacer_expand())
	var add_opt := OptionButton.new()
	add_opt.custom_minimum_size.y = 40
	add_opt.add_item("+ Add…", 0)
	for i in Simulation.BEHAVIOR_ORDER.size():
		add_opt.add_item(Simulation.BEHAVIORS[Simulation.BEHAVIOR_ORDER[i]]["label"], i + 1)
	add_opt.item_selected.connect(func(i):
		if i == 0:
			return
		var kind: String = Simulation.BEHAVIOR_ORDER[i - 1]
		var b := {"type": kind}
		for p in Simulation.BEHAVIORS[kind]["params"]:
			b[p[0]] = p[5]
		if Simulation.BEHAVIORS[kind].has("dir"):
			b["dir"] = "right"
		if Simulation.BEHAVIORS[kind].has("clockwise"):
			b["clockwise"] = true
		c["behaviors"].append(b)
		_structure_changed())
	bh.add_child(add_opt)

	if c["behaviors"].is_empty():
		inspector_box.add_child(UI.label("Static cannon. Add movement to make it tricky.", 14, UI.MUTED))
	for bi in c["behaviors"].size():
		_build_behavior_row(c, bi)

	inspector_box.add_child(UI.spacer(10))
	var del := UI.button("Delete cannon", 44, 18)
	del.add_theme_color_override("font_color", UI.BAD)
	del.disabled = level["cannons"].size() <= 1
	del.pressed.connect(func():
		level["cannons"].remove_at(selected)
		if int(level.get("start", 0)) >= level["cannons"].size():
			level["start"] = 0
		selected = -1
		_structure_changed())
	inspector_box.add_child(del)


func _build_behavior_row(c: Dictionary, bi: int) -> void:
	var b: Dictionary = c["behaviors"][bi]
	var kind := str(b.get("type", "rotate"))
	var spec: Dictionary = Simulation.BEHAVIORS.get(kind, Simulation.BEHAVIORS["rotate"])
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UI.flat(UI.BG_DEEP, 12, 8))
	inspector_box.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	head.add_child(UI.label(spec["label"], 18, UI.ACCENT_2))
	head.add_child(UI.hspacer_expand())
	var rm := UI.small_button(" ✕ ")
	rm.pressed.connect(func():
		c["behaviors"].remove_at(bi)
		_structure_changed())
	head.add_child(rm)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 4)
	box.add_child(grid)
	for p in spec["params"]:
		grid.add_child(UI.label(p[1], 15, UI.MUTED))
		var s := UI.spin(p[2], p[3], p[4], float(b.get(p[0], p[5])))
		var key: String = p[0]
		s.value_changed.connect(func(v):
			b[key] = v
			_params_changed())
		grid.add_child(s)
	if spec.has("dir"):
		grid.add_child(UI.label("Direction", 15, UI.MUTED))
		var opt := OptionButton.new()
		opt.custom_minimum_size.y = 40
		for i in Simulation.DIR_ORDER.size():
			opt.add_item(Simulation.DIR_ORDER[i].replace("_", " "), i)
			if Simulation.DIR_ORDER[i] == str(b.get("dir", "right")):
				opt.select(i)
		opt.item_selected.connect(func(i):
			b["dir"] = Simulation.DIR_ORDER[i]
			_params_changed())
		grid.add_child(opt)
	if spec.has("clockwise"):
		grid.add_child(UI.label("Clockwise", 15, UI.MUTED))
		var cb := CheckBox.new()
		cb.button_pressed = bool(b.get("clockwise", true))
		cb.toggled.connect(func(on):
			b["clockwise"] = on
			_params_changed())
		grid.add_child(cb)


# ---------------------------------------------------------------- editing

func _mark_dirty() -> void:
	dirty = true
	save_button.text = "  Save •  "


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
	if selected >= level["cannons"].size():
		selected = -1
	view.set_selection(selected, finish_selected)
	_rebuild_inspector()


func _select_cannon(i: int) -> void:
	selected = i
	finish_selected = false
	view.set_selection(selected, false)
	_rebuild_inspector()


func _select_finish() -> void:
	selected = -1
	finish_selected = true
	view.set_selection(-1, true)
	_rebuild_inspector()


func _add_cannon() -> void:
	var c := {"x": 640.0, "y": 400.0, "angle": -45.0, "type": "normal", "behaviors": []}
	level["cannons"].append(c)
	selected = level["cannons"].size() - 1
	finish_selected = false
	_structure_changed()
	view.set_selection(selected, false)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		if event.pressed:
			_pick(view.world_mouse())
		else:
			dragging = false
	elif event is InputEventMouseMotion and dragging:
		_drag_to(view.world_mouse())
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_on_back()
		elif event.keycode == KEY_DELETE and selected >= 0 and level["cannons"].size() > 1:
			level["cannons"].remove_at(selected)
			selected = -1
			_structure_changed()


func _pick(p: Vector2) -> void:
	# Cannons are picked at their *current* (animated) position.
	var best := -1
	var best_d := PICK_RADIUS * PICK_RADIUS
	for i in sim.cannon_states.size():
		var d: float = p.distance_squared_to(sim.cannon_states[i]["pos"])
		if d < best_d:
			best_d = d
			best = i
	if best >= 0:
		_select_cannon(best)
		dragging = true
		var c: Dictionary = level["cannons"][best]
		drag_offset = Vector2(float(c["x"]), float(c["y"])) - sim.cannon_states[best]["pos"]
		return
	if sim.finish_rect().grow(10).has_point(p):
		_select_finish()
		dragging = true
		drag_offset = sim.finish_rect().position - p
		return
	selected = -1
	finish_selected = false
	dragging = false
	view.set_selection(-1, false)
	_rebuild_inspector()


func _drag_to(p: Vector2) -> void:
	var target := (p + drag_offset).snapped(Vector2(GRID, GRID))
	if finish_selected:
		var f: Dictionary = level["finish"]
		f["x"] = clampf(target.x, 0.0, Simulation.BASE_SIZE.x - float(f.get("w", 60.0)))
		f["y"] = clampf(target.y, 0.0, Simulation.BASE_SIZE.y - float(f.get("h", 400.0)))
	elif selected >= 0:
		var c: Dictionary = level["cannons"][selected]
		c["x"] = clampf(target.x, 0.0, Simulation.BASE_SIZE.x)
		c["y"] = clampf(target.y, 0.0, Simulation.BASE_SIZE.y)
	_mark_dirty()
	sim.set_tick(sim.tick)
	view.refresh()
	view.redraw_all()


# ---------------------------------------------------------------- preview / play / save

func _toggle_preview() -> void:
	previewing = not previewing
	preview_button.text = "  ■ Stop  " if previewing else "  ▶ Preview  "
	if not previewing:
		sim.set_tick(0)
		view.refresh()


func _physics_process(_delta: float) -> void:
	if previewing:
		sim.set_tick(sim.tick + 1)
		view.refresh()
	tick_label.text = "t = %.2f s" % (sim.tick / float(Simulation.TICK_RATE))


func _test_play() -> void:
	GameState.editor_level = level
	GameState.play_level(level, GameState.SCENE_EDITOR)


func _save() -> void:
	if GameState.is_builtin(level):
		level["id"] = GameState.new_level_id()
		level["author"] = "You"
	if GameState.save_user_level(level):
		dirty = false
		save_button.text = "  Save  "
		UI.toast(UI.root_of(ui), "Saved “%s”" % str(level.get("name", "")), UI.GOOD)
	else:
		UI.toast(UI.root_of(ui), "Could not save level", UI.BAD)


func _on_back() -> void:
	if dirty:
		_save()
	GameState.editor_level = {}
	GameState.go(GameState.SCENE_SELECT)
