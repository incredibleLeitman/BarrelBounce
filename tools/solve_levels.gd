extends SceneTree
## Headless brute-force solver: proves every built-in level is beatable and reports the
## fastest tap sequence it finds. Because the simulation is deterministic this doubles as a
## regression test for the physics.
##
## Run from the project folder:
##   godot --headless --import            (once, builds the script class cache)
##   godot --headless -s tools/solve_levels.gd [max_seconds] [level_index]

const SimulationScript := preload("res://scripts/simulation.gd")
const LevelsScript := preload("res://levels/builtin_levels.gd")

const MAX_TICKS := 1800          # give up on runs longer than 30 s
const WAIT_STEP := 2             # granularity (ticks) for "wait, then fire"
const FLIGHT_CAP := 420          # longest flight we simulate before declaring it lost


func _init() -> void:
	var all_ok := true
	var max_seconds := 30.0
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		max_seconds = float(args[0])
	var only := -1   # optional second arg: only solve the level with this (0-based) index
	if args.size() > 1:
		only = int(args[1])
	for li in LevelsScript.LEVELS.size():
		if only >= 0 and li != only:
			continue
		var level: Dictionary = LevelsScript.LEVELS[li]
		var t0 := Time.get_ticks_msec()
		var res := solve(level.duplicate(true), max_seconds)
		var secs := (Time.get_ticks_msec() - t0) / 1000.0
		if res.is_empty():
			all_ok = false
			print("FAIL  %-18s  not solved (%.1fs search)" % [level["name"], secs])
		else:
			print("ok    %-18s  %s  taps@ticks=%s  (%.1fs search)" % [
				level["name"], SimulationScript.format_ticks(res["ticks"]), str(res["taps"]), secs])
	print("ALL SOLVABLE" if all_ok else "SOME LEVELS UNSOLVABLE")
	quit(0 if all_ok else 1)


## Breadth-first search over (cannon, tick) states. Returns {} or {"ticks", "taps"}.
func solve(level: Dictionary, max_seconds: float) -> Dictionary:
	var start = SimulationScript.new(level)
	var deadline := Time.get_ticks_msec() + int(max_seconds * 1000.0)
	var visited := {}
	var queue: Array = [{"sim": start, "taps": []}]
	var best := {}
	var qi := 0
	# Waiting matters whenever *anything* in the level moves, not just the cannon we sit in.
	var level_cycle := 0
	for c in level["cannons"]:
		level_cycle = maxi(level_cycle, SimulationScript.cannon_cycle_ticks(c))
	while qi < queue.size():
		if Time.get_ticks_msec() > deadline:
			break
		var item: Dictionary = queue[qi]
		qi += 1
		var sim = item["sim"]
		if not best.is_empty() and sim.tick >= best["ticks"] + maxi(0, sim.run_start_tick):
			continue
		var c: Dictionary = level["cannons"][sim.cannon_index]
		var info = sim.cannon_type(sim.cannon_index)
		var max_wait := mini(level_cycle, 600)
		if info.has("auto_fire_ticks"):
			max_wait = mini(max_wait, int(info["auto_fire_ticks"]) - sim.ticks_in_cannon)
		var wait := 0
		while wait <= max_wait:
			var s = sim.clone()
			var dead_early := false
			for i in wait:
				s.step(false)
				if s.mode != SimulationScript.Mode.IN_CANNON:
					dead_early = true
					break
			if dead_early:
				break
			var taps: Array = item["taps"].duplicate()
			taps.append(s.tick + 1)
			var jump_options := [-1]
			if int(info.get("jumps", 0)) > 0:
				for j in range(4, 90, 4):
					jump_options.append(j)
			for jump_at in jump_options:
				var f = s.clone() if jump_options.size() > 1 else s
				var ftaps := taps.duplicate()
				f.step(true)
				var flight := 0
				while f.mode == SimulationScript.Mode.FLYING or f.mode == SimulationScript.Mode.DASHING:
					flight += 1
					var tap: bool = jump_at > 0 and flight == jump_at
					if tap:
						ftaps.append(f.tick + 1)
					f.step(tap)
					if flight > FLIGHT_CAP:
						break
				if f.mode == SimulationScript.Mode.FINISHED:
					if best.is_empty() or f.finish_ticks < best["ticks"]:
						best = {"ticks": f.finish_ticks, "taps": ftaps}
				elif f.mode == SimulationScript.Mode.IN_CANNON and f.tick < MAX_TICKS:
					var key: int = f.cannon_index * 100000 + f.tick
					if not visited.has(key):
						visited[key] = true
						queue.append({"sim": f, "taps": ftaps})
			wait += WAIT_STEP
			if max_wait == 0:
				break
	return best
