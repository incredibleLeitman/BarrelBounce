extends Node
## Autoload: navigation between scenes, level storage and high scores.

const USER_DIR := "user://levels/"
const SCORES_PATH := "user://scores.json"

const SCENE_MENU := "res://scenes/main_menu.tscn"
const SCENE_SELECT := "res://scenes/level_select.tscn"
const SCENE_LEVEL := "res://scenes/level.tscn"
const SCENE_EDITOR := "res://scenes/editor.tscn"

## Level handed to the level scene.
var current_level: Dictionary = {}
## Where the level scene returns to (level select or editor).
var return_scene: String = SCENE_SELECT
## Level currently open in the editor (survives a test play round trip).
var editor_level: Dictionary = {}
## level id -> best time in ticks
var scores: Dictionary = {}
var is_mobile: bool = false


func _ready() -> void:
	is_mobile = OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
	DirAccess.make_dir_recursive_absolute(USER_DIR)
	_load_scores()


func go(scene_path: String) -> void:
	get_tree().call_deferred("change_scene_to_file", scene_path)


func play_level(level: Dictionary, back_to: String = SCENE_SELECT) -> void:
	current_level = level
	return_scene = back_to
	go(SCENE_LEVEL)


# ---------------------------------------------------------------- levels

func builtin_levels() -> Array:
	var out: Array = []
	for l in BuiltinLevels.LEVELS:
		out.append(l.duplicate(true))
	return out


func builtin_index(level_id: String) -> int:
	for i in BuiltinLevels.LEVELS.size():
		if BuiltinLevels.LEVELS[i].get("id", "") == level_id:
			return i
	return -1


func user_levels() -> Array:
	var out: Array = []
	var dir := DirAccess.open(USER_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".json"):
			var l := load_level_file(USER_DIR + f)
			if not l.is_empty():
				out.append(l)
	out.sort_custom(func(a, b): return float(a.get("modified", 0)) > float(b.get("modified", 0)))
	return out


func load_level_file(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	return normalize_level(data)


## Fills in defaults so that every consumer can rely on the keys being present.
func normalize_level(l: Dictionary) -> Dictionary:
	if not l.has("id") or str(l["id"]).is_empty():
		l["id"] = new_level_id()
	if not l.has("name"):
		l["name"] = "Untitled"
	if not l.has("author"):
		l["author"] = "You"
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
	return l


func is_builtin(level: Dictionary) -> bool:
	return str(level.get("id", "")).begins_with("builtin_")


func new_level_id() -> String:
	return "user_%d_%04d" % [Time.get_unix_time_from_system(), randi() % 10000]


func new_level() -> Dictionary:
	return normalize_level({
		"format": 1,
		"name": "My Level",
		"author": "You",
		"cannons": [{"x": 160.0, "y": 560.0, "angle": -45.0, "type": "normal", "behaviors": []}],
		"finish": {"x": 1000.0, "y": 160.0, "w": 60.0, "h": 420.0},
		"start": 0,
	})


func save_user_level(level: Dictionary) -> bool:
	level["modified"] = Time.get_unix_time_from_system()
	var f := FileAccess.open(USER_DIR + str(level["id"]) + ".json", FileAccess.WRITE)
	if f == null:
		push_error("Could not save level: " + str(FileAccess.get_open_error()))
		return false
	f.store_string(JSON.stringify(level, "\t"))
	return true


func delete_user_level(level_id: String) -> void:
	var dir := DirAccess.open(USER_DIR)
	if dir and dir.file_exists(level_id + ".json"):
		dir.remove(level_id + ".json")


# ---------------------------------------------------------------- scores

func best_ticks(level_id: String) -> int:
	return int(scores.get(level_id, -1))


## Returns true when this is a new best time.
func record_time(level_id: String, ticks: int) -> bool:
	var best := best_ticks(level_id)
	if best >= 0 and ticks >= best:
		return false
	scores[level_id] = ticks
	_save_scores()
	return true


func _load_scores() -> void:
	var f := FileAccess.open(SCORES_PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) == TYPE_DICTIONARY:
		scores = data


func _save_scores() -> void:
	var f := FileAccess.open(SCORES_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(scores))
