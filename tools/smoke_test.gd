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
	_test_paths_and_size()
	_test_sequences()
	await _test_ghost_and_fairness()
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
	GameState.scores.erase(level["id"] + "_ghost")
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
	var rev: String = GameState.level_hash(level)
	check(GameState.best_ticks(level["id"], rev) == sim.finish_ticks, "best time was recorded for this revision")
	check(GameState.best_entry(level["id"], rev)["taps"] == taps, "the winning taps were recorded with the time: %s" % str(taps))
	check(scene.ghosts.size() == 1 and scene.view.ghosts.size() == 1, "ghost is loaded after a best time")
	check(GameState.can_share(level), "a finished level is shareable without re-saving it")
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
	# Ghost race: the ghost only starts with the player's first launch and finishes in its own time.
	scene._restart()
	for i in 120:
		scene._physics_process(1.0 / 60.0)
	check(scene.ghosts[0]["sim"].tick == 0 and not scene.ghost_armed, "ghost waits while the player waits")
	scene.pending_fire = true
	scene._physics_process(1.0 / 60.0)
	check(scene.ghost_armed and scene.ghosts[0]["sim"].mode != Simulation.Mode.IN_CANNON, "ghost launches together with the player")
	var ghost_done := false
	for i in 150:
		if scene.ghosts[0]["sim"].mode == Simulation.Mode.FINISHED:
			ghost_done = scene.ghosts[0]["sim"].finish_ticks == GameState.best_ticks(level["id"], rev)
			break
		scene._physics_process(1.0 / 60.0)
	check(ghost_done, "ghost finishes in the best time")
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
	check(editor.level["cannons"].size() == 2 and editor.primary() == 1, "cannon added and selected")
	# Add an orbit behaviour the way the inspector does.
	editor.level["cannons"][1]["behaviors"].append({"type": "orbit", "radius": 120.0, "period": 3.0, "clockwise": true})
	editor._structure_changed()
	check(editor.view.cannon_nodes.size() == 2, "view rebuilt with two cannon nodes")
	# Preview advances the deterministic clock and the orbiting cannon moves.
	var prev0: Vector2 = editor.sim.cannon_states[1]["pos"]
	editor._toggle_preview()
	for i in 30:
		editor._physics_process(1.0 / 60.0)
	var prev1: Vector2 = editor.sim.cannon_states[1]["pos"]
	check(prev0.distance_to(prev1) > 5.0, "preview animates the orbiting cannon")
	editor._toggle_preview()
	check(editor.sim.tick == 0, "stopping preview rewinds to tick 0")
	# Pick & drag cannon 0 at its position.
	var c0: Dictionary = editor.level["cannons"][0]
	editor._press(Vector2(float(c0["x"]), float(c0["y"])))
	check(editor.primary() == 0 and editor.dragging, "pressing a cannon selects it")
	editor._drag_to(Vector2(333, 444))
	editor._release(Vector2(333, 444))
	check(float(c0["x"]) == 330.0 and float(c0["y"]) == 440.0, "dragging snaps to the 10 px grid")
	# Multi-select: select mode toggles membership, group drag moves everything by the same delta.
	editor.select_mode = true
	var c1: Dictionary = editor.level["cannons"][1]
	# Cannon 1 orbits, so it is picked at its animated position, not at its base.
	var p1: Vector2 = editor.sim.cannon_states[1]["pos"]
	editor._press(p1)
	editor._release(p1)
	check(editor.selection.size() == 2, "select mode adds a second cannon to the selection")
	editor.select_mode = false
	var x0: float = float(c0["x"])
	var x1: float = float(c1["x"])
	editor._press(p1)
	check(editor.selection.size() == 2, "pressing a selected cannon keeps the group")
	editor._drag_to(p1 + Vector2(100, 0))
	editor._release(p1 + Vector2(100, 0))
	check(float(c0["x"]) == x0 + 100.0 and float(c1["x"]) == x1 + 100.0, "group drag moves every selected cannon")
	p1 = editor.sim.cannon_states[1]["pos"]
	editor._press(p1)
	editor._release(p1)
	check(editor.selection.size() == 1 and editor.primary() == 1, "click without moving collapses the selection to that cannon")
	# Rubber band in select mode picks everything inside.
	editor.select_mode = true
	editor._press(Vector2(5, 5))
	editor._drag_to(Vector2(1270, 710))
	editor._release(Vector2(1270, 710))
	check(editor.selection.size() == 2, "rubber band selects both cannons")
	editor.select_mode = false
	# Editing a value with a multi-selection applies it to all selected cannons.
	for c in editor._selected_cannons():
		c["angle"] = -60.0
	check(editor._common(editor._selected_cannons(), "angle", 0.0) == -60.0, "common value is reported when all agree")
	c1["angle"] = -10.0
	check(editor._common(editor._selected_cannons(), "angle", 0.0) == null, "mixed values are reported as null")
	# Path editing on cannon 1 (single selection): add a path, place a point, drag it.
	editor._set_selection([1])
	c1["behaviors"].append({"type": "path", "points": [], "period": 4.0, "smooth": true, "closed": true})
	editor._structure_changed()
	editor.path_edit = c1["behaviors"].size() - 1
	var base1 := Vector2(float(c1["x"]), float(c1["y"]))
	editor._press(base1 + Vector2(203, -97))
	editor._release(base1 + Vector2(203, -97))
	check(c1["behaviors"][editor.path_edit]["points"] == [[200.0, -100.0]], "tapping in path mode adds a snapped point")
	editor._press(base1 + Vector2(200, -100))
	editor._drag_to(base1 + Vector2(300, -100))
	editor._release(base1 + Vector2(300, -100))
	check(c1["behaviors"][editor.path_edit]["points"] == [[300.0, -100.0]], "dragging a point moves it")
	editor._set_selection([1])
	check(editor.path_edit == -1, "changing the selection leaves path mode")
	# In select mode a press on a selected cannon drags the group instead of deselecting it.
	editor._set_selection([0, 1])
	editor.select_mode = true
	var sp: Vector2 = editor.sim.cannon_states[1]["pos"]
	var sx0: float = float(c0["x"])
	editor._press(sp)
	check(editor.selection.size() == 2, "select mode press keeps the selection")
	editor._drag_to(sp + Vector2(50, 0))
	editor._release(sp + Vector2(50, 0))
	check(editor.selection.size() == 2 and float(c0["x"]) == sx0 + 50.0, "select mode drag moves the group")
	sp = editor.sim.cannon_states[1]["pos"]
	editor._press(sp)
	editor._release(sp)
	check(editor.selection.size() == 1 and editor.primary() == 0, "select mode click without moving deselects that cannon")
	editor.select_mode = false
	editor._set_selection([1])
	c1["behaviors"].pop_back()
	editor._structure_changed()
	# Wheel over the inspector must not zoom.
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.position = editor.inspector.get_global_rect().get_center()
	editor._unhandled_input(wheel)
	check(editor.camera.zoom.x == 1.0, "wheel over the inspector does not zoom")
	wheel.position = Vector2(300, 300)
	editor._unhandled_input(wheel)
	check(editor.camera.zoom.x < 1.0, "wheel over the level zooms")
	editor.camera.reset_view()
	# Pick & drag the finish gate.
	var fr: Rect2 = editor.sim.finish_rect()
	editor._press(fr.get_center())
	check(editor.finish_selected, "pressing the gate selects it")
	editor._drag_to(fr.get_center() + Vector2(-100, 0))
	editor._release(fr.get_center() + Vector2(-100, 0))
	check(float(editor.level["finish"]["x"]) == fr.position.x - 100.0, "gate dragged")
	# Camera and grid in the editor.
	editor.camera.zoom_by(0.5, Vector2(400, 300))
	check(is_equal_approx(editor.camera.zoom.x, 0.5), "editor zooms out")
	var before: Vector2 = editor.camera.position
	editor.camera.pan_by(Vector2(-200, 0))
	check(editor.camera.position.x > before.x, "editor pans")
	editor.camera.zoom_by(10.0, Vector2(400, 300))
	check(editor.camera.zoom.x == 1.0, "editor zoom stops at the default view")
	check(not editor.view.backdrop.show_grid, "grid is off by default in the editor")
	editor.grid_button.button_pressed = true
	check(editor.view.backdrop.show_grid, "grid button shows the grid")
	editor.grid_button.button_pressed = false
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
	# Shared codes must carry a proof run; attach the solver's known solution of Hot Heads.
	var proof_ticks := GameState.verify_run(level, [19, 58, 80])
	check(proof_ticks > 0, "solver taps finish Hot Heads in %s" % Simulation.format_ticks(proof_ticks))
	level["verified"] = {"rev": GameState.level_hash(level), "ticks": proof_ticks, "taps": [19, 58, 80], "player": "Solver"}
	var code := GameState.level_to_code(level)
	check(code.begins_with("BB1:") and code.length() < 900, "code is compact: %d chars" % code.length())
	var back := GameState.level_from_code(code + "\n")
	check(not back.is_empty(), "code decodes")
	check(back.get("name") == level["name"] and back["cannons"].size() == level["cannons"].size(), "name and cannons survive the round trip")
	check(back["cannons"][1]["behaviors"][0]["type"] == "move", "behaviours survive the round trip")
	check(back["id"] != level["id"], "imported level gets a fresh id")
	check(GameState.level_from_code("hello").is_empty(), "garbage is rejected")
	check(GameState.level_from_code("BB1:aGVsbG8=").is_empty(), "non-level payload is rejected")


func _test_paths_and_size() -> void:
	print("path movement and level size")
	var b := {"type": "path", "points": [[200.0, 0.0], [200.0, 100.0]], "period": 4.0, "smooth": false, "closed": true}
	var line := Simulation.path_polyline(b)
	check(line.size() == 3, "straight path keeps its control points")
	check(Simulation.point_along(line, true, 0.0) == Vector2.ZERO, "path starts at the cannon base")
	var quarter := Simulation.point_along(line, true, 0.25)
	check(quarter.y == 0.0 and quarter.x > 0.0, "constant speed: a quarter of the loop is still on the first leg")
	var c := {"x": 100.0, "y": 100.0, "angle": 0.0, "behaviors": [b]}
	var at0: Vector2 = Simulation.cannon_state_at(c, 0)["pos"]
	var at240: Vector2 = Simulation.cannon_state_at(c, 240)["pos"]
	check(at0 == Vector2(100, 100) and at0.distance_to(at240) < 0.01, "closed path returns to the base after one period")
	b["smooth"] = true
	b["points"] = [[200.0, 0.0], [200.0, 100.0], [0.0, 100.0]]
	check(Simulation.path_polyline(b).size() == 4 * Simulation.PATH_SAMPLES, "smooth path is sampled per segment")
	b["closed"] = false
	var p_half: Vector2 = Simulation.cannon_state_at(c, 120)["pos"]
	var p_full: Vector2 = Simulation.cannon_state_at(c, 240)["pos"]
	check(p_half.distance_to(Vector2(100, 100)) > 50.0 and p_full.distance_to(Vector2(100, 100)) < 0.01, "open path ping-pongs back to the base")
	# Level size
	var big := GameState.normalize_level({"width": 2000, "height": 1000, "cannons": [{"x": 10, "y": 10, "angle": 0}]})
	var sim := Simulation.new(big)
	check(sim.size == Vector2(2000, 1000) and sim.world.end.x == 2080.0, "level size and death bounds follow the level")
	sim.mode = Simulation.Mode.FLYING
	sim.pos = Vector2(1900, 500)
	sim.vel = Vector2.ZERO
	sim.step(false)
	check(sim.mode == Simulation.Mode.FLYING, "a point inside the bigger level is alive")
	var tiny := GameState.normalize_level({"width": 100, "cannons": [{"x": 10, "y": 10, "angle": 0}]})
	check(Simulation.level_size(tiny).x == Simulation.MIN_SIZE.x, "sizes are clamped to the minimum")


func _test_sequences() -> void:
	print("sequential movement")
	# Move left for 1 s, then move right for 1 s: ends back at the base, never cancels out.
	var c := {"x": 500.0, "y": 300.0, "angle": 0.0, "behaviors": [
		{"type": "move", "dir": "left", "range": 150.0, "period": 2.0, "seq": true, "duration": 1.0},
		{"type": "move", "dir": "right", "range": 150.0, "period": 2.0, "seq": true, "duration": 1.0},
	]}
	var p_half: Vector2 = Simulation.cannon_state_at(c, 60)["pos"]
	var p_mid: Vector2 = Simulation.cannon_state_at(c, 90)["pos"]
	var p_end: Vector2 = Simulation.cannon_state_at(c, 120)["pos"]
	check(is_equal_approx(p_half.x, 350.0), "after step 1 the cannon is 150 px left")
	check(p_mid.x > 350.0 and p_mid.x < 500.0, "step 2 starts where step 1 ended and moves right")
	check(is_equal_approx(p_end.x, 500.0), "the sequence loops back to the base")
	check(Simulation.active_step(c, 30) == 0 and Simulation.active_step(c, 90) == 1, "active step is reported")
	var starts := Simulation.behavior_start_offsets(c)
	check(starts[0]["pos"] == Vector2.ZERO and is_equal_approx(starts[1]["pos"].x, -150.0), "hint start offsets follow the chain")
	# A continuous behaviour on top keeps running during the sequence.
	c["behaviors"].append({"type": "rotate", "speed": 90.0})
	check(is_equal_approx(float(Simulation.cannon_state_at(c, 60)["angle"]), 90.0), "together behaviours are summed on top of the steps")
	check(Simulation.cannon_cycle_ticks(c) == 240, "cycle covers the sequence and the rotation")
	check(Simulation.default_duration({"type": "move", "period": 3.0}) == 1.5, "move steps default to one way")
	# Back-and-forth sequences play the steps in reverse after the last one.
	var pp := {"x": 500.0, "y": 300.0, "angle": 0.0, "seq_mode": "pingpong", "behaviors": [
		{"type": "move", "dir": "left", "range": 150.0, "period": 2.0, "seq": true, "duration": 1.0},
		{"type": "move", "dir": "up", "range": 100.0, "period": 2.0, "seq": true, "duration": 1.0},
	]}
	var e1: Vector2 = Simulation.cannon_state_at(pp, 120)["pos"]
	var e2: Vector2 = Simulation.cannon_state_at(pp, 180)["pos"]
	var e3: Vector2 = Simulation.cannon_state_at(pp, 240)["pos"]
	check(is_equal_approx(e1.x, 350.0) and is_equal_approx(e1.y, 200.0), "end of a pingpong pass is the far corner")
	check(is_equal_approx(e2.x, 350.0) and is_equal_approx(e2.y, 300.0), "then it plays step 2 backwards")
	check(is_equal_approx(e3.x, 500.0) and is_equal_approx(e3.y, 300.0), "and step 1 backwards to the base")
	check(Simulation.active_step(pp, 150) == 1 and Simulation.active_step(pp, 210) == 0, "active step follows the reverse pass")
	check(Simulation.cannon_cycle_ticks(pp) == 240, "pingpong cycle is twice the sequence")



func _test_ghost_and_fairness() -> void:
	await get_tree().process_frame
	print("ghost replay, revisions, shareable only when verified")
	var level: Dictionary = GameState.builtin_levels()[1]
	var rev := GameState.level_hash(level)
	# The recorded taps replay to the recorded time: that is what the ghost does and what a
	# leaderboard server would check.
	var entry := GameState.best_entry(level["id"], rev)
	check(not entry.is_empty() and GameState.verify_run(level, entry["taps"]) == int(entry["ticks"]), "verify_run reproduces the best time from its taps")
	check(GameState.verify_run(level, [1]) == -1, "a run that falls off does not verify")
	# Editing the level changes its revision and hides the old best.
	var edited: Dictionary = level.duplicate(true)
	edited["cannons"][1]["angle"] = -35.0
	var rev2 := GameState.level_hash(edited)
	check(rev2 != rev, "gameplay edits change the revision hash")
	check(GameState.best_ticks(level["id"], rev2) == -1 and GameState.best_is_stale(level["id"], rev2), "the old best does not count for the edited level and is reported as stale")
	edited["name"] = "Renamed"
	edited["background"] = "cave"
	check(GameState.level_hash(edited) == rev2, "name and background do not change the revision")
	# A user level is shareable only after a verified run of its current revision.
	var mine := GameState.new_level()
	mine["name"] = "Smoke Share"
	GameState.save_user_level(mine)
	check(not GameState.is_verified(mine), "a fresh level is not verified")
	check(GameState.level_from_code(GameState.level_to_code(mine)).is_empty(), "a code without proof is rejected on import")
	var solved_ticks := GameState.verify_run(mine, [1])
	check(solved_ticks > 0, "the default new level is finished by one tap at tick 1")
	GameState.record_time(mine["id"], GameState.level_hash(mine), solved_ticks, [1])
	GameState.save_user_level(mine)
	check(GameState.is_verified(mine), "saving after a finish attaches the proof")
	var imported := GameState.level_from_code(GameState.level_to_code(mine))
	check(not imported.is_empty() and imported["verified"]["ticks"] == solved_ticks, "a code with a valid proof imports")
	var tampered: Dictionary = mine.duplicate(true)
	tampered["verified"]["ticks"] = 1
	check(GameState.level_from_code(GameState.level_to_code(tampered)).is_empty(), "a code whose proof time was tampered with is rejected")
	# The author's proof run is the receiver's ghost until they have a best of their own.
	# Simulate receiving it from someone else: a different creator id on the proof.
	imported["verified"]["player_id"] = "p_someone_else"
	imported["verified"]["player"] = "Someone"
	imported["author_id"] = "p_someone_else"
	GameState.save_user_level(imported)
	check(GameState.is_verified(imported), "saving an imported level keeps the creator's proof")
	GameState.current_level = imported
	var scene := await _swap_scene(GameState.SCENE_LEVEL)
	check(scene.ghosts.size() == 1 and scene.ghosts[0]["label"] == "Someone", "imported level uses the creator's run as ghost")
	# Beat it yourself: both ghosts race next time.
	GameState.record_time(imported["id"], GameState.level_hash(imported), solved_ticks, [1])
	scene._load_ghost()
	check(scene.ghosts.size() == 2 and scene.ghosts[1]["label"] == "you", "creator ghost and own ghost together")
	GameState.set_ghost_enabled(false)
	scene._load_ghost()
	check(scene.ghosts.is_empty(), "ghosts can be switched off")
	check(GameState.display_name("Whoever", GameState.player_id()) == "You" and GameState.display_name("Someone", "p_x") == "Someone", "own player id shows as You")
	GameState.set_ghost_enabled(true)
	scene.queue_free()
	await get_tree().process_frame
	GameState.delete_user_level(mine["id"])
	GameState.delete_user_level(imported["id"])
	GameState.scores.erase(mine["id"])
