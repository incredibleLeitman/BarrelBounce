extends Node
## Captures a PNG of every scene into user://screenshots/ (needs a real or virtual display):
##   xvfb-run -s "-screen 0 1280x720x24" godot --path . res://tools/screenshots.tscn

const SHOTS := [
	["main_menu", "res://scenes/main_menu.tscn"],
	["level_select", "res://scenes/level_select.tscn"],
	["level", "res://scenes/level.tscn"],
	["editor", "res://scenes/editor.tscn"],
	["settings", "res://scenes/settings.tscn"],
]


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute("user://screenshots")
	await get_tree().process_frame
	GameState.current_level = GameState.builtin_levels()[1]
	# Editor shot: several cannons of the same type with movement, close together, one selected.
	GameState.editor_level = GameState.normalize_level({
		"name": "Pattern colours", "background": "underwater",
		"cannons": [
			{"x": 160.0, "y": 560.0, "angle": -45.0, "type": "normal", "behaviors": []},
			{"x": 520.0, "y": 360.0, "angle": -60.0, "type": "normal", "behaviors": [{"type": "orbit", "radius": 110.0, "period": 4.0}]},
			{"x": 640.0, "y": 420.0, "angle": -30.0, "type": "normal", "behaviors": [{"type": "move", "dir": "right", "range": 250.0, "period": 2.0}, {"type": "sweep", "from": -40.0, "to": 40.0, "period": 2.0}]},
			{"x": 760.0, "y": 300.0, "angle": -90.0, "type": "normal", "behaviors": [
				{"type": "move", "dir": "up", "range": 120.0, "period": 2.0, "seq": true, "duration": 1.0},
				{"type": "move", "dir": "right", "range": 180.0, "period": 2.0, "seq": true, "duration": 1.0},
				{"type": "path", "points": [[150.0, -120.0], [330.0, -60.0], [280.0, 120.0]], "period": 5.0, "smooth": true, "closed": true, "seq": true, "duration": 5.0},
				{"type": "rotate", "speed": 45.0}]},
			{"x": 900.0, "y": 500.0, "angle": 180.0, "type": "weak", "behaviors": [{"type": "rotate", "speed": 90.0}, {"type": "move", "dir": "up", "range": 200.0, "period": 3.0}]},
		],
		"finish": {"x": 1150.0, "y": 100.0, "w": 60.0, "h": 500.0}, "start": 0})
	for shot in SHOTS:
		var scene: Node = (load(shot[1]) as PackedScene).instantiate()
		get_tree().root.add_child(scene)
		if shot[0] == "main_menu":
			# Catch the demo ball mid-flight, above the title.
			for i in 130:
				scene._physics_process(1.0 / 60.0)
		if shot[0] == "editor":
			scene._set_selection([3])
			scene._toggle_preview()
			for i in 80:
				scene._physics_process(1.0 / 60.0)
		if shot[0] == "level":
			# Let the ball fly a bit so the trail shows up.
			for i in 30:
				await get_tree().physics_frame
			scene.pending_fire = true
			for i in 25:
				await get_tree().physics_frame
		else:
			for i in 20:
				await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := "user://screenshots/%s.png" % shot[0]
		img.save_png(path)
		print("saved ", ProjectSettings.globalize_path(path))
		scene.queue_free()
		await get_tree().process_frame
	get_tree().quit()
