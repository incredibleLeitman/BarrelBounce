extends SceneTree
## Headless verifier for the online API. Reads the JSON the server's "pending" action returns,
## replays every run and every published level's proof with the game's own simulation, and
## writes the verdicts for the "resolve" action.
##
##   godot --headless -s tools/verify_runs.gd -- pending.json results.json
##
## A run is verified when its taps finish the level in exactly the claimed ticks on the
## claimed revision. A level is verified when its proof run does the same. Rejections carry
## a short reason code the game turns into a message for the author:
##   bad_data       the level JSON is unreadable or has no proof run
##   rev_mismatch   the level content differs from the one the proof run was made on
##   no_finish      replaying the taps does not reach the finish gate
##   time_mismatch  the taps finish the level, but not in the claimed time
##   unknown_level  (runs only) the level is not built-in and not published

## Loaded at run time (not preloaded) so that a project that was not imported yet, where
## class names do not resolve, makes this script exit with an error instead of idling.
var LevelsScript: GDScript
var CheckScript: GDScript


func _init() -> void:
	LevelsScript = load("res://levels/builtin_levels.gd")
	CheckScript = load("res://scripts/level_check.gd")
	if LevelsScript == null or CheckScript == null or not CheckScript.can_instantiate():
		printerr("game scripts failed to load; run `godot --headless --import` first")
		quit(3)
		return
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("usage: -- pending.json results.json")
		quit(2)
		return
	var f := FileAccess.open(args[0], FileAccess.READ)
	if f == null:
		printerr("cannot read " + args[0])
		quit(2)
		return
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		printerr("pending.json is not a JSON object")
		quit(2)
		return

	var levels_by_id := {}
	for l in LevelsScript.LEVELS:
		levels_by_id[str(l["id"])] = l.duplicate(true)
	var extra: Dictionary = data.get("level_data", {})
	for id in extra.keys():
		if typeof(extra[id]) == TYPE_DICTIONARY:
			levels_by_id[str(id)] = CheckScript.normalize(extra[id])

	var results := {"runs": [], "levels": []}
	var verified := 0
	var rejected := 0

	for l in data.get("levels", []):
		var level = l.get("data")
		var reason := "bad_data"
		if typeof(level) == TYPE_DICTIONARY:
			level = CheckScript.normalize(level)
			var v = level.get("verified")
			if typeof(v) == TYPE_DICTIONARY and typeof(v.get("taps")) == TYPE_ARRAY:
				var rev: String = CheckScript.level_hash(level)
				if str(v.get("rev", "")) != rev or str(l.get("rev", "")) != rev:
					reason = "rev_mismatch"
				else:
					var ticks: int = CheckScript.verify_run(level, v["taps"])
					if ticks <= 0:
						reason = "no_finish"
					elif ticks != int(v.get("ticks", -2)):
						reason = "time_mismatch"
					else:
						reason = ""
						levels_by_id[str(l["id"])] = level
		var status := "verified" if reason == "" else "rejected"
		results["levels"].append({"id": str(l.get("id", "")), "status": status, "reason": reason})
		if status == "verified": verified += 1
		else: rejected += 1
		print("level %-24s %s %s" % [str(l.get("id", "")), status, reason])

	for r in data.get("runs", []):
		var reason := "bad_data"
		var level = levels_by_id.get(str(r.get("level_id", "")))
		if typeof(level) != TYPE_DICTIONARY:
			reason = "unknown_level"
		elif typeof(r.get("taps")) == TYPE_ARRAY:
			if CheckScript.level_hash(level) != str(r.get("rev", "")):
				reason = "rev_mismatch"
			else:
				var ticks: int = CheckScript.verify_run(level, r["taps"])
				if ticks <= 0:
					reason = "no_finish"
				elif ticks != int(r.get("ticks", -2)):
					reason = "time_mismatch"
				else:
					reason = ""
		var status := "verified" if reason == "" else "rejected"
		results["runs"].append({"id": int(r.get("id", 0)), "status": status, "reason": reason})
		if status == "verified": verified += 1
		else: rejected += 1
		print("run %6d on %-24s %s %s" % [int(r.get("id", 0)), str(r.get("level_id", "")), status, reason])

	var out := FileAccess.open(args[1], FileAccess.WRITE)
	out.store_string(JSON.stringify(results))
	print("verified %d, rejected %d" % [verified, rejected])
	quit(0)
