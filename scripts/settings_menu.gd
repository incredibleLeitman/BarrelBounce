extends Node2D
## Player profile: pick a ball colour and roll a random name. Kept deliberately simple;
## it is the identity that shared highscores and level authorship will use later.

var backdrop: Backdrop
var ui: CanvasLayer
var name_label: Label
var preview: PlayerNode
var color_hex: String
var player_name: String
var swatches: Array = []


func _ready() -> void:
	backdrop = Backdrop.new()
	add_child(backdrop)
	color_hex = str(GameState.profile.get("color", GameState.PLAYER_COLORS[0]))
	player_name = GameState.player_name()
	_build_ui()


func _build_ui() -> void:
	ui = UI.layer()
	add_child(ui)
	var root := UI.root_of(ui)

	var back := UI.small_button("  < Menu  ")
	back.position = Vector2(20, 20)
	back.pressed.connect(_save_and_leave)
	root.add_child(back)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.custom_minimum_size = Vector2(560, 0)
	box.add_theme_constant_override("separation", 16)
	root.add_child(box)

	var t := UI.title("Player", 48)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)

	# Live preview of the ball in the chosen colour.
	var preview_holder := Control.new()
	preview_holder.custom_minimum_size = Vector2(0, 90)
	box.add_child(preview_holder)
	preview = PlayerNode.new()
	preview.position = Vector2(280, 45)
	preview.scale = Vector2(2.2, 2.2)
	preview_holder.add_child(preview)
	preview.body_color = Color(color_hex)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 12)
	box.add_child(name_row)
	name_label = UI.label(player_name, 30)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_row.add_child(name_label)
	var roll := UI.button("Random name", 48, 18)
	roll.pressed.connect(func():
		player_name = GameState.random_name()
		name_label.text = player_name)
	name_row.add_child(roll)

	box.add_child(UI.label("Ball colour", 18, UI.MUTED))
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 10)
	box.add_child(grid)
	for hex in GameState.PLAYER_COLORS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(58, 58)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_stylebox_override("normal", UI.flat(Color(hex), 14, 0))
		b.add_theme_stylebox_override("hover", UI.flat(Color(hex).lightened(0.15), 14, 0))
		b.add_theme_stylebox_override("pressed", UI.flat(Color(hex), 14, 0, Color.WHITE))
		b.toggle_mode = true
		b.button_pressed = hex == color_hex
		var chosen: String = hex
		b.pressed.connect(func(): _pick_color(chosen))
		grid.add_child(b)
		swatches.append(b)

	box.add_child(UI.label("Language", 18, UI.MUTED))
	var flags := HBoxContainer.new()
	flags.add_theme_constant_override("separation", 10)
	box.add_child(flags)
	for lang in GameState.LANGUAGES:
		var fb := Button.new()
		fb.icon = load("res://assets/icons/flag_%s.svg" % lang)
		fb.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fb.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		fb.custom_minimum_size = Vector2(72, 52)
		fb.focus_mode = Control.FOCUS_NONE
		fb.toggle_mode = true
		fb.button_pressed = lang == GameState.language()
		fb.add_theme_stylebox_override("pressed", UI.flat(UI.PANEL_LIGHT, 14, 8, Color.WHITE))
		var chosen: String = lang
		fb.pressed.connect(func():
			GameState.set_profile(player_name, color_hex)
			GameState.set_language(chosen)
			GameState.go(GameState.SCENE_SETTINGS))   # rebuild this scene in the new language
		flags.add_child(fb)

	var ghost := CheckButton.new()
	ghost.text = tr("Show the ghost of the best run while playing")
	ghost.button_pressed = GameState.ghost_enabled()
	ghost.add_theme_font_size_override("font_size", 18)
	ghost.toggled.connect(func(on): GameState.set_ghost_enabled(on))
	box.add_child(ghost)
	box.add_child(UI.spacer(8))
	var done := UI.accent_button("Done")
	done.pressed.connect(_save_and_leave)
	box.add_child(done)


func _pick_color(hex: String) -> void:
	color_hex = hex
	preview.body_color = Color(hex)
	preview.queue_redraw()
	for i in swatches.size():
		swatches[i].button_pressed = GameState.PLAYER_COLORS[i] == hex


func _save_and_leave() -> void:
	GameState.set_profile(player_name, color_hex)
	GameState.go(GameState.SCENE_MENU)
