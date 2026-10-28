extends Node2D
## The playable level scene. Drives one [Simulation] at a fixed 60 ticks/s and renders it.
## Any tap / click / key / gamepad button is the single action: fire.
## The camera can zoom out (mouse wheel or pinch) and be dragged around while a button is held.

const DEATH_PAUSE := 0.7

var sim: Simulation
var view: LevelView
var level: Dictionary
var rev: String                 # revision hash the times of this session belong to
var taps: Array = []            # ticks the button was pressed on in the current attempt
## Ghosts race on the run clock. Each: {"sim", "taps": {tick: true}, "first_tap", "label", "ticks"}.
var ghosts: Array = []
var ghost_armed := false        # true once the player fired and the ghost race is on
var pending_fire := false
var death_timer := 0.0
var finished := false

var camera: CameraRig
var dragging := false

var ui: CanvasLayer
var ghost_button: Button
var time_label: Label
var best_label: Label
var hint_label: Label
var flash: ColorRect
var win_panel: PanelContainer
var win_time: Label
var win_best: Label
var next_button: Button


func _ready() -> void:
	level = GameState.current_level
	if level.is_empty():
		level = GameState.builtin_levels()[0]
	rev = GameState.level_hash(level)
	sim = Simulation.new(level)
	view = LevelView.new()
	add_child(view)
	view.bind(sim)
	_load_ghost()
	camera = CameraRig.new()
	add_child(camera)
	_fit_camera()
	get_viewport().size_changed.connect(_fit_camera)
	_build_ui()


## Levels larger than the screen start zoomed out so they are fully visible; zooming in
## up to the default view stays allowed.
func _fit_camera() -> void:
	var vp := get_viewport_rect().size
	camera.limit_rect = Rect2(Vector2.ZERO, vp).merge(Rect2(view.position + sim.world.position, sim.world.size))
	var fit := minf(1.0, minf(vp.x / sim.size.x, vp.y / sim.size.y))
	camera.zoom_min = minf(CameraRig.ZOOM_MIN, fit)
	camera.zoom = Vector2(fit, fit)
	camera.position = view.position + sim.size * 0.5
	camera.clamp_position()


func _build_ui() -> void:
	ui = UI.layer()
	add_child(ui)
	var root := UI.root_of(ui)

	flash = ColorRect.new()
	flash.color = Color(UI.BAD, 0.0)
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(flash)

	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 16
	top.offset_right = -16
	top.offset_top = 12
	top.add_theme_constant_override("separation", 12)
	root.add_child(top)

	var back := UI.small_button("  Exit  ")
	back.pressed.connect(_on_back)
	top.add_child(back)
	var name_label := UI.label(str(level.get("name", "Level")), 22, UI.MUTED)
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(name_label)
	top.add_child(UI.hspacer_expand())

	var times := VBoxContainer.new()
	times.alignment = BoxContainer.ALIGNMENT_CENTER
	time_label = UI.label("0.00 s", 40)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	best_label = UI.label("", 16, UI.MUTED)
	best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	times.add_child(time_label)
	times.add_child(best_label)
	top.add_child(times)
	top.add_child(UI.hspacer_expand())

	var help := UI.icon_button("", "help")
	help.pressed.connect(func(): HelpDialog.show(root))
	top.add_child(help)
	ghost_button = UI.small_button("  Ghost  ")
	ghost_button.toggle_mode = true
	ghost_button.button_pressed = GameState.ghost_enabled()
	ghost_button.tooltip_text = "Show the ghost of the best run"
	ghost_button.toggled.connect(func(on):
		GameState.set_ghost_enabled(on)
		_load_ghost()
		_update_best())
	top.add_child(ghost_button)
	var restart := UI.small_button("  Reset  ")
	restart.pressed.connect(_restart)
	top.add_child(restart)

	hint_label = UI.label("Tap anywhere to fire", 24, UI.MUTED)
	hint_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint_label.offset_bottom = -40
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(hint_label)
	_update_best()

	# Win panel
	win_panel = PanelContainer.new()
	win_panel.visible = false
	win_panel.set_anchors_preset(Control.PRESET_CENTER)
	win_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	win_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(win_panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(420, 0)
	box.add_theme_constant_override("separation", 10)
	win_panel.add_child(box)
	var t := UI.title("Finished!", 44)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	win_time = UI.label("", 34, UI.ACCENT)
	win_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(win_time)
	win_best = UI.label("", 18, UI.MUTED)
	win_best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(win_best)
	box.add_child(UI.spacer(8))
	var again := UI.accent_button("Play again")
	again.pressed.connect(_restart)
	box.add_child(again)
	next_button = UI.button("Next level  >")
	next_button.pressed.connect(_next_level)
	box.add_child(next_button)
	var levels := UI.button("Back")
	levels.pressed.connect(_on_back)
	box.add_child(levels)


func _update_best() -> void:
	var id := str(level.get("id", ""))
	var best := GameState.best_ticks(id, rev)
	var parts: Array = []
	if best >= 0:
		parts.append("best " + Simulation.format_ticks(best))
	var creator := GameState.creator_proof(level)
	if not creator.is_empty() and str(creator.get("player_id", "")) != GameState.player_id():
		parts.append("%s: %s" % [str(creator.get("player", "author")), Simulation.format_ticks(int(creator["ticks"]))])
	if not ghosts.is_empty():
		var names: Array = []
		for g in ghosts:
			names.append(g["label"])
		parts.append("ghost: " + ", ".join(names))
	if not parts.is_empty():
		best_label.text = "  ·  ".join(parts)
	elif GameState.best_is_stale(id, rev):
		best_label.text = "level changed: best time reset"
	else:
		best_label.text = "no time yet"


## Ghosts replay the best runs of this revision: the level creator's proof run (white) and
## your own best (your colour). Each races from the player's first launch.
func _load_ghost() -> void:
	ghosts.clear()
	ghost_armed = false
	if GameState.ghost_enabled():
		var creator := GameState.creator_proof(level)
		var own := GameState.best_entry(str(level.get("id", "")), rev)
		var creator_is_me := not creator.is_empty() and str(creator.get("player_id", "")) == GameState.player_id()
		if not creator.is_empty() and not creator_is_me:
			_add_ghost(creator, str(creator.get("player", "author")), Color.WHITE)
		if not own.is_empty():
			_add_ghost(own, "you", GameState.player_color())
	var binds: Array = []
	for g in ghosts:
		binds.append({"sim": g["sim"], "color": g["color"]})
	view.bind_ghosts(binds)


func _add_ghost(entry: Dictionary, label: String, color: Color) -> void:
	var taps_list: Array = entry.get("taps", [])
	if taps_list.is_empty():
		return
	var tap_set := {}
	var first := 1 << 30
	for t in taps_list:
		tap_set[int(t)] = true
		first = mini(first, int(t))
	ghosts.append({"sim": Simulation.new(level.duplicate(true)), "taps": tap_set, "first_tap": first,
		"label": label, "color": color, "ticks": int(entry.get("ticks", -1))})


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	# Camera controls work in every state, firing only while playing.
	if camera.handle_zoom_input(event):
		return
	if event is InputEventMouseButton:
		if event.pressed:
			dragging = true
			_fire()
		else:
			dragging = false
	elif event is InputEventMouseMotion:
		if dragging and not camera.pinching():
			camera.pan_by(event.relative)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_restart()   # leaving is the Exit button's job; Escape restarts the attempt
			return
		_fire()
	elif event is InputEventJoypadButton and event.pressed:
		_fire()


func _fire() -> void:
	if finished:
		return
	pending_fire = true
	get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- simulation

func _physics_process(delta: float) -> void:
	if finished:
		return
	if sim.mode == Simulation.Mode.DEAD:
		pending_fire = false
		death_timer -= delta
		if death_timer <= 0.0:
			_reset_run()
		return
	if pending_fire:
		taps.append(sim.tick + 1)
	var first_launch := pending_fire and sim.mode == Simulation.Mode.IN_CANNON and sim.run_start_tick < 0
	sim.step(pending_fire)
	pending_fire = false
	# Ghosts race on the run clock: they wait in the start cannon until the player's first
	# launch, then play their own run from their first launch onwards.
	if first_launch and not ghost_armed:
		ghost_armed = true
		for g in ghosts:
			while g["sim"].tick < g["first_tap"] - 1:
				g["sim"].step(false)
	if ghost_armed:
		for g in ghosts:
			g["sim"].step(g["taps"].has(g["sim"].tick + 1))
	for e in sim.events:
		match e:
			"launch":
				view.player_node.kick()
				hint_label.visible = false
				Sfx.play(self, Sfx.pop(), -6.0)
			"teleport":
				view.player_node.blink(sim.teleport_from, sim.pos)
			"jump":
				view.player_node.kick()
				Sfx.play(self, Sfx.pop(), -6.0)
			"catch":
				view.player_node.kick()
			"die":
				_on_die()
			"finish":
				_on_finish()


func _process(_delta: float) -> void:
	view.refresh()
	time_label.text = Simulation.format_ticks(sim.elapsed_ticks())


func _on_die() -> void:
	view.player_node.puff()
	death_timer = DEATH_PAUSE
	Sfx.play(self, Sfx.buzzer(), -4.0)
	flash.color = Color(UI.BAD, 0.35)
	var tw := create_tween()
	tw.tween_property(flash, "color:a", 0.0, DEATH_PAUSE)


func _reset_run() -> void:
	sim.reset()
	taps.clear()
	ghost_armed = false
	for g in ghosts:
		g["sim"].reset()
	view.clear_ghost_trails()
	view.player_node.clear_trail()
	view.refresh()


func _restart() -> void:
	finished = false
	win_panel.visible = false
	pending_fire = false
	_reset_run()


func _on_finish() -> void:
	finished = true
	Sfx.play(self, Sfx.chime(), -4.0)
	var ticks := sim.finish_ticks
	var id := str(level.get("id", ""))
	var new_best := GameState.record_time(id, rev, ticks, taps)
	win_time.text = Simulation.format_ticks(ticks)
	win_best.text = "New best time! Your ghost will race you next time." if new_best else "best " + Simulation.format_ticks(GameState.best_ticks(id, rev))
	var creator := GameState.creator_proof(level)
	if new_best and not creator.is_empty() and str(creator.get("player_id", "")) != GameState.player_id() and ticks < int(creator["ticks"]):
		win_best.text = "New best time, faster than %s!" % str(creator.get("player", "the creator"))
	if new_best:
		_load_ghost()
	_update_best()
	var idx := GameState.builtin_index(id)
	next_button.visible = idx >= 0 and idx + 1 < BuiltinLevels.LEVELS.size()
	win_panel.visible = true
	win_panel.scale = Vector2(0.6, 0.6)
	win_panel.pivot_offset = win_panel.size / 2.0
	var tw := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(win_panel, "scale", Vector2.ONE, 0.35)


func _next_level() -> void:
	var idx := GameState.builtin_index(str(level.get("id", "")))
	var levels := GameState.builtin_levels()
	if idx >= 0 and idx + 1 < levels.size():
		GameState.play_level(levels[idx + 1])


func _on_back() -> void:
	GameState.go(GameState.return_scene)
