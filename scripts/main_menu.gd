extends Node2D
## Main menu: Start (-> level select), Level editor, Player settings, How to play, Exit.
## A self-playing demo sits left of the buttons and lobs the ball over the title into a gate on
## the right. The demo is drawn on a layer above the UI so the ball is never hidden by it; the
## backdrop stays below the UI.

## Not a playable level, so it may use a Big Bertha as its start cannon: a plain cannon could
## not throw the ball across the whole menu.
const DEMO_LEVEL := {
	"id": "menu_demo", "name": "Menu", "author": "BarrelBounce", "background": "space",
	"cannons": [{"x": 170.0, "y": 560.0, "angle": -64.0, "type": "strong", "behaviors": []}],
	"finish": {"x": 1010.0, "y": 150.0, "w": 60.0, "h": 480.0},
	"start": 0,
}

var view: LevelView
var sim: Simulation
var backdrop: Backdrop
var demo_timer := 0.0
var ui: CanvasLayer


func _ready() -> void:
	sim = Simulation.new(DEMO_LEVEL.duplicate(true))
	# Backdrop below the UI, in the same place the demo view will be.
	backdrop = Backdrop.new()
	add_child(backdrop)
	_place_backdrop()
	get_viewport().size_changed.connect(_place_backdrop)
	_build_ui()
	# The demo itself above the UI.
	var demo_layer := CanvasLayer.new()
	demo_layer.layer = 2
	add_child(demo_layer)
	view = LevelView.new()
	demo_layer.add_child(view)
	view.bind(sim)
	view.backdrop.visible = false


func _place_backdrop() -> void:
	backdrop.position = ((get_viewport_rect().size - Simulation.BASE_SIZE) * 0.5).floor()


func _build_ui() -> void:
	ui = UI.layer()
	add_child(ui)
	var root := UI.root_of(ui)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 12)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(box)

	var t := UI.title("BarrelBounce", 84)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_color", UI.ACCENT)
	box.add_child(t)
	var sub := UI.label("one button · one ball · many barrels", 22, UI.MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	box.add_child(UI.spacer(20))

	var start := UI.accent_button("Start", 72, 30)
	start.custom_minimum_size = Vector2(320, 72)
	start.pressed.connect(func(): GameState.go(GameState.SCENE_SELECT))
	box.add_child(start)

	var editor := UI.icon_button("Level editor", "pen", 56, 22)
	editor.pressed.connect(func():
		GameState.editor_level = GameState.new_level()
		GameState.go(GameState.SCENE_EDITOR))
	box.add_child(editor)

	var settings := UI.icon_button("Player: " + GameState.player_name(), "user", 56, 22)
	settings.pressed.connect(func(): GameState.go(GameState.SCENE_SETTINGS))
	box.add_child(settings)

	var help := UI.icon_button("How to play", "help", 56, 22)
	help.pressed.connect(func(): HelpDialog.show(root))
	box.add_child(help)

	# Browsers do not let a page close itself, so the web build has no Exit button.
	if not OS.has_feature("web"):
		var quit := UI.icon_button("Exit", "exit", 56, 22)
		quit.pressed.connect(func():
			UI.confirm(root, "Exit BarrelBounce?", "Your levels and best times are saved.", "Exit", func(): get_tree().quit()))
		box.add_child(quit)

	# Title bob
	var tw := create_tween().set_loops()
	tw.tween_property(t, "position:y", t.position.y - 6.0, 1.2).set_trans(Tween.TRANS_SINE)
	tw.tween_property(t, "position:y", t.position.y + 6.0, 1.2).set_trans(Tween.TRANS_SINE)


func _physics_process(delta: float) -> void:
	# Self-playing demo: fire after a short pause, rest a moment after each landing.
	demo_timer += delta
	var fire := false
	if sim.mode == Simulation.Mode.IN_CANNON and sim.ticks_in_cannon > 70:
		fire = true
	if sim.mode == Simulation.Mode.DEAD or sim.mode == Simulation.Mode.FINISHED:
		if demo_timer > 1.2:
			sim.reset()
			view.player_node.clear_trail()
			demo_timer = 0.0
		return
	demo_timer = 0.0 if sim.mode != Simulation.Mode.IN_CANNON else demo_timer
	sim.step(fire)


func _process(_delta: float) -> void:
	view.refresh()
