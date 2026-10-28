extends Node
## End-to-end smoke test. Runs as a scene so the GameState autoload is present:
##   godot --headless res://tools/smoke_test.tscn
## Plays a built-in level with a known tap sequence, round-trips a level through the
## editor's save path and the level select, and exits non-zero on the first failure.

var failures := 0


func _ready() -> void:
	await get_tree().process_frame
	await _test_play_with_taps()
	await _test_editor_roundtrip()
	await _test_level_select_lists_saved_level()
	_test_level_codes()
	print("SMOKE TEST " + ("PASSED" if failures == 0 else "FAILED (%d)" % failures))
	get_tree().quit(0 if failures == 0 else 1)


func check(cond: bool, what: String) -> void:
	if cond:
		print("  ok   " + what)
	else:
		failures += 1
		print("  FAIL " + what)


func _swap_scene(path: String) -> Node:
	var packed: PackedScene = load(path)
	var scene := packed.instantiate()
	get_tree().root.add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	return scene


func _test_play_with_taps() -> void:
	print("level scene: play 'Catch Me' with taps at ticks 1 and 28")
	var level: Dictionary = GameState.builtin_levels()[1]
	GameState.scores.erase(level["id"])
	GameState.current_level = level
	var scene := await _swap_scene(GameState.SCENE_LEVEL)
	var sim: Simulation = scene.sim
	var taps := [1, 28]
	# Drive the scene's physics step by hand so we control the tick exactly.
	scene.set_physics_process(false)
	scene._reset_run()
	for i in 400:
		if sim.mode == Simulation.Mode.FINISHED or sim.mode == Simulation.Mode.DEAD:
			break
		if taps.has(sim.tick + 1):
			scene.pending_fire = true
		scene._physics_process(1.0 / 60.0)
	check(sim.mode == Simulation.Mode.FINISHED, "ball reached the finish gate")
	check(sim.finish_ticks > 0 and sim.finish_ticks < 120, "finish time looks sane: %s" % Simulation.format_ticks(sim.finish_ticks))
	check(GameState.best_ticks(level["id"]) == sim.finish_ticks, "best time was recorded")
	check(scene.win_panel.visible, "win panel is shown")
	check(scene.next_button.visible, "next level button offered for a built-in level")
	# Replay determinism: a second run with the same taps must give the identical result.
	var sim2 := Simulation.new(level.duplicate(true))
	for i in 400:
		if sim2.mode == Simulation.Mode.FINISHED or sim2.mode == Simulation.Mode.DEAD:
			break
		sim2.step(taps.has(sim2.tick + 1))
	check(sim2.mode == Simulation.Mode.FINISHED and sim2.finish_ticks == sim.finish_ticks, "replay is deterministic")
	# Dying resets the run clock and the tick.
	scene._restart()
	check(sim.tick == 0 and sim.elapsed_ticks() == 0, "restart resets tick and timer to 0")
	# Camera: zooming in beyond the default is refused, zooming out is clamped to the minimum.
	scene.camera.zoom_by(2.0, Vector2(640, 360))
	check(scene.camera.zoom.x == 1.0, "cannot zoom closer than the default view")
	scene.camera.zoom_by(0.01, Vector2(640, 360))
	check(is_equal_approx(scene.camera.zoom.x, CameraRig.ZOOM_MIN), "zoom out stops at the minimum")
	scene.queue_free()
	await get_tree().process_frame

	print("rules: start cannon type, teleport")
	var hot: Dictionary = GameState.normalize_level({"cannons": [{"x": 0, "y": 0, "angle": 0, "type": "auto"}], "start": 0})
	check(hot["cannons"][0]["type"] == "normal", "an auto start cannon is forced to a plain cannon on load")
	var blink := Simulation.new(GameState.normalize_level({"cannons": [
		{"x": 100.0, "y": 600.0, "angle": 0.0, "type": "normal"},
		{"x": 300.0, "y": 300.0, "angle": -90.0, "type": "dash"}], "start": 0}))
	blink.cannon_index = 1   # pretend the ball was caught by the Blink cannon
	blink.step(true)
	check(blink.events.has("teleport") and blink.pos.y < 300.0 - 200.0, "Blink teleports 210 px along the barrel instantly")
	check(blink.teleport_from.y > blink.pos.y, "teleport origin recorded for the effect")


func _test_editor_roundtrip() -> void:
	print("editor scene: add cannon, behaviour, drag, save")
	GameState.editor_level = GameState.new_level()
	GameState.editor_level["name"] = "Smoke Test Level"
	var editor := await _swap_scene(GameState.SCENE_EDITOR)
	check(editor.level["cannons"].size() == 1, "new level starts with one cannon")
	editor._add_cannon()
	check(editor.level["cannons"].size() == 2 and editor.selected == 1, "cannon added and selected")
	# Add an orbit behaviour the way the inspector does.
	editor.level["cannons"][1]["behaviors"].append({"type": "orbit", "radius": 120.0, "period": 3.0, "clockwise": true})
	editor._structure_changed()
	check(editor.view.cannon_nodes.size() == 2, "view rebuilt with two cannon nodes")
	# Preview advances the deterministic clock and the orbiting cannon moves.
	var p0: Vector2 = editor.sim.cannon_states[1]["pos"]
	editor._toggle_preview()
	for i in 30:
		editor._physics_process(1.0 / 60.0)
	var p1: Vector2 = editor.sim.cannon_states[1]["pos"]
	check(p0.distance_to(p1) > 5.0, "preview animates the orbiting cannon")
	editor._toggle_preview()
	check(editor.sim.tick == 0, "stopping preview rewinds to tick 0")
	# Pick & drag cannon 0 at its position.
	var c0: Dictionary = editor.level["cannons"][0]
	editor._pick(Vector2(float(c0["x"]), float(c0["y"])))
	check(editor.selected == 0 and editor.dragging, "picking a cannon selects it")
	editor._drag_to(Vector2(333, 444))
	check(float(c0["x"]) == 330.0 and float(c0["y"]) == 440.0, "dragging snaps to the 10 px grid")
	# Pick & drag the finish gate.
	var fr: Rect2 = editor.sim.finish_rect()
	editor._pick(fr.get_center())
	check(editor.finish_selected, "picking the gate selects it")
	editor._drag_to(fr.get_center() + Vector2(-100, 0))
	check(float(editor.level["finish"]["x"]) == fr.position.x - 100.0, "gate dragged")
	# Camera and grid in the editor.
	editor.camera.zoom_by(0.5, Vector2(400, 300))
	check(is_equal_approx(editor.camera.zoom.x, 0.5), "editor zooms out")
	var before: Vector2 = editor.camera.position
	editor.camera.pan_by(Vector2(-200, 0))
	check(editor.camera.position.x > before.x, "editor pans")
	editor.camera.zoom_by(10.0, Vector2(400, 300))
	check(editor.camera.zoom.x == 1.0, "editor zoom stops at the default view")
	check(editor.view.backdrop.show_grid, "grid is on by default in the editor")
	editor.grid_button.button_pressed = false
	check(not editor.view.backdrop.show_grid, "grid button hides the grid")
	editor._save()
	var saved := GameState.user_levels()
	var found := false
	for l in saved:
		if l["name"] == "Smoke Test Level":
			found = true
			check(l["cannons"].size() == 2, "saved level keeps both cannons")
			check(l["cannons"][1]["behaviors"][0]["type"] == "orbit", "saved level keeps the behaviour")
	check(found, "saved level is listed among user levels")
	check(not editor.dirty, "save clears the dirty flag")
	editor.queue_free()
	await get_tree().process_frame


func _test_level_select_lists_saved_level() -> void:
	print("level select: lists saved level, then delete it")
	var select := await _swap_scene(GameState.SCENE_SELECT)
	select.tab = select.Tab.MINE
	select._refresh()
	await get_tree().process_frame
	var rows: int = select.list.get_child_count()
	check(rows >= 1, "my levels tab shows %d row(s)" % rows)
	for l in GameState.user_levels():
		if l["name"] == "Smoke Test Level":
			GameState.delete_user_level(l["id"])
	var still := false
	for l in GameState.user_levels():
		if l["name"] == "Smoke Test Level":
			still = true
	check(not still, "level deleted again")
	select.queue_free()
	await get_tree().process_frame


func _test_level_codes() -> void:
	print("level codes: round trip and validation")
	var level: Dictionary = GameState.builtin_levels()[6]
	var code := GameState.level_to_code(level)
	check(code.begins_with("BB1:") and code.length() < 900, "code is compact: %d chars" % code.length())
	var back := GameState.level_from_code(code + "\n")
	check(not back.is_empty(), "code decodes")
	check(back.get("name") == level["name"] and back["cannons"].size() == level["cannons"].size(), "name and cannons survive the round trip")
	check(back["cannons"][1]["behaviors"][0]["type"] == "move", "behaviours survive the round trip")
	check(back["id"] != level["id"], "imported level gets a fresh id")
	check(GameState.level_from_code("hello").is_empty(), "garbage is rejected")
	check(GameState.level_from_code("BB1:aGVsbG8=").is_empty(), "non-level payload is rejected")
