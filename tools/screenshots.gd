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
	GameState.current_level = GameState.builtin_levels()[6]
	GameState.editor_level = GameState.builtin_levels()[5].duplicate(true)
	GameState.editor_level["background"] = "underwater"
	for shot in SHOTS:
		var scene: Node = (load(shot[1]) as PackedScene).instantiate()
		get_tree().root.add_child(scene)
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
