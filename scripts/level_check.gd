class_name LevelCheck
extends RefCounted
## Revision hashing and run verification, shared by the game (GameState) and the headless
## verifier (tools/verify_runs.gd). Static and free of scene dependencies on purpose.


## Hash of everything that affects play (not the name, author or background). A best time
## belongs to one revision: edit the level and the old times no longer count.
static func level_hash(level: Dictionary) -> String:
	var core := {
		"cannons": level.get("cannons", []), "finish": level.get("finish", {}),
		"start": level.get("start", 0), "width": level.get("width", Simulation.BASE_SIZE.x),
		"height": level.get("height", Simulation.BASE_SIZE.y),
	}
	# Round-trip through JSON first so ints and floats (0 vs 0.0) hash the same whether the
	# level came from code, from a file or from a code string.
	var canonical = JSON.parse_string(JSON.stringify(core))
	return JSON.stringify(canonical).md5_text().substr(0, 16)


## Replays [param taps] (absolute ticks) on a copy of the level. Returns the finish time in
## ticks, or -1 when the run does not finish within [param max_ticks].
static func verify_run(level: Dictionary, taps: Array, max_ticks: int = 36000) -> int:
	var sim := Simulation.new(level.duplicate(true))
	var tap_set := {}
	for t in taps:
		tap_set[int(t)] = true
	while sim.tick < max_ticks:
		sim.step(tap_set.has(sim.tick + 1))
		if sim.mode == Simulation.Mode.FINISHED:
			return sim.finish_ticks
		if sim.mode == Simulation.Mode.DEAD:
			return -1
	return -1


## Minimal structural normalisation for levels that arrive from outside (server, codes),
## mirroring what GameState.normalize_level does without needing the autoload.
static func normalize(l: Dictionary) -> Dictionary:
	if not l.has("cannons") or typeof(l["cannons"]) != TYPE_ARRAY:
		l["cannons"] = []
	for c in l["cannons"]:
		if not c.has("behaviors") or typeof(c["behaviors"]) != TYPE_ARRAY:
			c["behaviors"] = []
		if not c.has("type"):
			c["type"] = "normal"
	if not l.has("finish"):
		l["finish"] = {"x": 1100.0, "y": 160.0, "w": 60.0, "h": 400.0}
	if not l.has("start"):
		l["start"] = 0
	Simulation.enforce_start_type(l)
	return l
