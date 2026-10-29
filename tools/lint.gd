extends SceneTree
## Static check of every GDScript file. Run through tools/lint.sh, which raises every default
## warning to "error" for this run only (via override.cfg), so any warning makes a script fail
## to compile; this script then loads every .gd and reports the ones that failed.
## Needs an imported project (class cache). Used by the web workflow so warnings never reach main.

const ROOTS := ["res://scripts", "res://levels", "res://tools"]

var done := false


## Runs on the first frame, when the autoload singletons (GameState, Online) exist as global
## identifiers; in _init they do not, and every scene script would fail to compile.
func _process(_delta: float) -> bool:
	if done:
		return true
	done = true
	if int(ProjectSettings.get_setting("debug/gdscript/warnings/unused_variable", 1)) != 2:
		printerr("lint: run this through tools/lint.sh (warnings are not treated as errors)")
		quit(2)
		return true
	var files: Array[String] = []
	for dir_root in ROOTS:
		_collect(dir_root, files)
	files.sort()
	var bad := 0
	for path in files:
		var script = load(path)
		if script == null or not script.can_instantiate():
			bad += 1
			printerr("lint: FAIL " + path)
	if bad == 0:
		print("lint: %d scripts clean" % files.size())
	else:
		printerr("lint: %d script(s) with warnings or errors (details above)" % bad)
	quit(1 if bad > 0 else 0)
	return true


func _collect(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var path := dir_path.path_join(name)
		if dir.current_is_dir():
			if not name.begins_with("."):
				_collect(path, out)
		elif name.ends_with(".gd"):
			out.append(path)
		name = dir.get_next()
	dir.list_dir_end()
