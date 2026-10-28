extends SceneTree
## Diagnostic: for each cannon of a level, the closest the ball gets to the next cannon
## over all launch ticks (and jump ticks for Hopper). Prints the best wait per hop.

const SimulationScript := preload("res://scripts/simulation.gd")
const LevelsScript := preload("res://levels/builtin_levels.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var level: Dictionary = LevelsScript.LEVELS[int(args[0])].duplicate(true)
	var n: int = level["cannons"].size()
	for i in n:
		var target := i + 1
		var best := 1e9
		var best_wait := -1
		var best_jump := -1
		var info = SimulationScript.type_info(str(level["cannons"][i].get("type", "normal")))
		var max_wait := 360
		if info.has("auto_fire_ticks"):
			max_wait = int(info["auto_fire_ticks"])
		var jumps := [-1]
		if int(info.get("jumps", 0)) > 0:
			for j in range(4, 90, 2):
				jumps.append(j)
		for wait in range(0, max_wait + 1, 2):
			for jump_at in jumps:
				var s = SimulationScript.new(level)
				s.cannon_index = i
				s.set_tick(wait)
				s.step(true)
				var flight := 0
				while s.mode == SimulationScript.Mode.FLYING and flight < 400:
					flight += 1
					s.step(jump_at > 0 and flight == jump_at)
					if target < n:
						var d: float = s.pos.distance_to(s.cannon_states[target]["pos"])
						if d < best:
							best = d
							best_wait = wait
							best_jump = jump_at
					elif s.mode == SimulationScript.Mode.FINISHED:
						best = 0.0
						best_wait = wait
				if s.mode == SimulationScript.Mode.IN_CANNON and s.cannon_index == target:
					best = 0.0
					best_wait = wait
					best_jump = jump_at
		print("hop %d -> %d: closest %.0f px at wait %d jump %d" % [i, target, best, best_wait, best_jump])
	quit()
