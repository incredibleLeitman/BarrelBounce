extends Node
## Autoload: navigation between scenes, level storage and high scores.

const USER_DIR := "user://levels/"
const SCORES_PATH := "user://scores.json"

const SCENE_MENU := "res://scenes/main_menu.tscn"
const SCENE_SELECT := "res://scenes/level_select.tscn"
const SCENE_LEVEL := "res://scenes/level.tscn"
const SCENE_EDITOR := "res://scenes/editor.tscn"
const SCENE_SETTINGS := "res://scenes/settings.tscn"

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
	_load_profile()


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
	if not l.has("background") or not Backdrop.THEMES.has(str(l["background"])):
		l["background"] = "space"
	Simulation.enforce_start_type(l)
	return l


func is_builtin(level: Dictionary) -> bool:
	return str(level.get("id", "")).begins_with("builtin_")


func new_level_id() -> String:
	return "user_%d_%04d" % [Time.get_unix_time_from_system(), randi() % 10000]


func new_level() -> Dictionary:
	return normalize_level({
		"format": 1,
		"name": "My Level",
		"author": player_name(),
		"author_id": player_id(),
		"cannons": [{"x": 160.0, "y": 560.0, "angle": -40.0, "type": "normal", "behaviors": []}],
		"finish": {"x": 700.0, "y": 300.0, "w": 60.0, "h": 360.0},
		"start": 0,
		"background": "space",
	})


# ---------------------------------------------------------------- player profile

const PROFILE_PATH := "user://profile.json"
const PLAYER_COLORS := [
	"#ffd166", "#ff8a3d", "#e5484d", "#ff6fb5", "#c77dff", "#4cc9f0", "#9bd36a", "#f1f3f8",
]
const NAME_ADJECTIVES := [
	"Bouncy", "Rusty", "Turbo", "Sleepy", "Mighty", "Sneaky", "Fuzzy", "Jolly", "Wobbly", "Zesty",
	"Lucky", "Grumpy", "Shiny", "Dizzy", "Brave", "Cosmic", "Soggy", "Nimble", "Spicy", "Loopy",
]
const NAME_NOUNS := [
	"Barrel", "Cannonball", "Otter", "Pigeon", "Comet", "Walrus", "Pickle", "Rocket", "Badger",
	"Noodle", "Meteor", "Penguin", "Muffin", "Yeti", "Llama", "Pebble", "Hedgehog", "Torpedo",
]

var profile: Dictionary = {}


func player_name() -> String:
	return str(profile.get("name", "Player"))


## Stable id of this player, generated once; names can change, the id cannot.
func player_id() -> String:
	return str(profile.get("id", ""))


## A player's name for display: "You" when it is this player.
func display_name(name: String, id: String) -> String:
	if id != "" and id == player_id():
		return "You"
	return name


func player_color() -> Color:
	return Color(str(profile.get("color", PLAYER_COLORS[0])))


func help_seen() -> bool:
	return bool(profile.get("help_seen", false))


func mark_help_seen() -> void:
	profile["help_seen"] = true
	set_profile(str(profile["name"]), str(profile["color"]))


func ghost_enabled() -> bool:
	return bool(profile.get("ghost", true))


func set_ghost_enabled(on: bool) -> void:
	profile["ghost"] = on
	var f := FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(profile))


func random_name() -> String:
	return "%s %s" % [NAME_ADJECTIVES[randi() % NAME_ADJECTIVES.size()], NAME_NOUNS[randi() % NAME_NOUNS.size()]]


func set_profile(name: String, color_hex: String) -> void:
	profile["name"] = name
	profile["color"] = color_hex
	var f := FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(profile))


func _load_profile() -> void:
	var f := FileAccess.open(PROFILE_PATH, FileAccess.READ)
	if f:
		var data = JSON.parse_string(f.get_as_text())
		if typeof(data) == TYPE_DICTIONARY:
			profile = data
	if not profile.has("name"):
		profile["name"] = random_name()
	if not profile.has("color"):
		profile["color"] = PLAYER_COLORS[randi() % PLAYER_COLORS.size()]
	if not profile.has("id") or str(profile["id"]).is_empty():
		profile["id"] = "p_%d_%08x" % [Time.get_unix_time_from_system(), randi()]
		set_profile(str(profile["name"]), str(profile["color"]))


## Hash of everything that affects play (not the name, author or background). A best time
## belongs to one revision: edit the level and the old times no longer count.
func level_hash(level: Dictionary) -> String:
	return LevelCheck.level_hash(level)


## Replays [param taps] (absolute ticks) on a copy of the level. Returns the finish time in
## ticks, or -1 when the run does not finish. This is the proof check used for shared levels
## and the basis for server-side leaderboard verification.
func verify_run(level: Dictionary, taps: Array, max_ticks: int = 36000) -> int:
	return LevelCheck.verify_run(normalize_level(level.duplicate(true)), taps, max_ticks)


## True when the level carries a proof run that matches its current revision.
func is_verified(level: Dictionary) -> bool:
	var v = level.get("verified")
	return typeof(v) == TYPE_DICTIONARY and str(v.get("rev", "")) == level_hash(level)


## The proof run for the level's current revision: the one stored in the level, or the
## player's own best of this revision (a finish from the level select never re-saves the
## file, so the live score counts too). {} when there is none.
func proof_for(level: Dictionary) -> Dictionary:
	if is_verified(level):
		return level["verified"]
	var rev := level_hash(level)
	var best := best_entry(str(level.get("id", "")), rev)
	if best.is_empty():
		return {}
	return {"rev": rev, "ticks": best["ticks"], "taps": best.get("taps", []), "player": best.get("player", player_name()),
		"player_id": best.get("player_id", player_id()), "color": best.get("color", str(profile.get("color", PLAYER_COLORS[0])))}


## The level creator's proof run for the current revision, or {}.
func creator_proof(level: Dictionary) -> Dictionary:
	return level["verified"] if is_verified(level) else {}


func can_share(level: Dictionary) -> bool:
	return not proof_for(level).is_empty()


func save_user_level(level: Dictionary) -> bool:
	level["modified"] = Time.get_unix_time_from_system()
	if not level.has("author_id"):
		level["author_id"] = player_id()
	# The level's proof is the creator's run of this exact revision. A proof that came with
	# an imported level is kept; our own best replaces it only when it is ours anyway or
	# when there is none for this revision.
	var rev := level_hash(level)
	var existing = level.get("verified")
	var keep := typeof(existing) == TYPE_DICTIONARY and str(existing.get("rev", "")) == rev \
		and str(existing.get("player_id", "")) != player_id()
	var best := best_entry(str(level["id"]), rev)
	if keep:
		pass
	elif best.is_empty():
		level.erase("verified")
	else:
		level["verified"] = {"rev": rev, "ticks": best["ticks"], "taps": best.get("taps", []),
			"player": best.get("player", player_name()), "player_id": best.get("player_id", player_id()),
			"color": best.get("color", str(profile.get("color", PLAYER_COLORS[0])))}
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


# ---------------------------------------------------------------- level codes

const CODE_PREFIX := "BB1:"
const CODE_MAX_BYTES := 1 << 20


## A level as a shareable text: deflate-compressed JSON, base64, with a version prefix.
func level_to_code(level: Dictionary) -> String:
	var payload := level.duplicate(true)
	payload.erase("modified")
	payload.erase("id")
	# The code always carries the best available proof run for this revision.
	var proof := proof_for(level)
	if proof.is_empty():
		payload.erase("verified")
	else:
		payload["verified"] = proof
	var raw := JSON.stringify(payload).to_utf8_buffer()
	return CODE_PREFIX + Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_DEFLATE))


## Inverse of [method level_to_code]. Returns {} for anything that is not a valid level.
## The imported level gets a fresh id so it never overwrites an existing one.
func level_from_code(code: String) -> Dictionary:
	var text := code.strip_edges().replace("\n", "").replace(" ", "")
	if not text.begins_with(CODE_PREFIX):
		return {}
	var packed := Marshalls.base64_to_raw(text.substr(CODE_PREFIX.length()))
	if packed.is_empty():
		return {}
	var raw := packed.decompress_dynamic(CODE_MAX_BYTES, FileAccess.COMPRESSION_DEFLATE)
	if raw.is_empty():
		return {}
	var data = JSON.parse_string(raw.get_string_from_utf8())
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	if typeof(data.get("cannons")) != TYPE_ARRAY or data["cannons"].is_empty():
		return {}
	for c in data["cannons"]:
		if typeof(c) != TYPE_DICTIONARY or not c.has("x") or not c.has("y"):
			return {}
	if typeof(data.get("finish")) != TYPE_DICTIONARY:
		return {}
	data["id"] = new_level_id()
	var level := normalize_level(data)
	# A shared level must carry a proof run that really finishes this revision.
	var v = level.get("verified")
	if typeof(v) != TYPE_DICTIONARY or typeof(v.get("taps")) != TYPE_ARRAY:
		return {}
	if str(v.get("rev", "")) != level_hash(level):
		return {}
	var ticks := verify_run(level, v["taps"])
	if ticks < 0 or ticks != int(v.get("ticks", -2)):
		return {}
	return level


# ---------------------------------------------------------------- scores
#
# scores[level_id] = {"rev": revision hash, "ticks": int, "taps": [ticks...], "player": name}
# The taps are the whole run: they drive the ghost and prove the time.

## Best entry for a level revision, or {} when there is none for that revision.
func best_entry(level_id: String, rev: String) -> Dictionary:
	var e = scores.get(level_id)
	if typeof(e) != TYPE_DICTIONARY:
		return {}
	if str(e.get("rev", "")) != rev:
		return {}
	return e


func best_ticks(level_id: String, rev: String) -> int:
	var e := best_entry(level_id, rev)
	return int(e["ticks"]) if not e.is_empty() else -1


## True when a best exists for the level but for another revision (the level was edited).
func best_is_stale(level_id: String, rev: String) -> bool:
	var e = scores.get(level_id)
	return typeof(e) == TYPE_DICTIONARY and str(e.get("rev", "")) != rev


## Returns true when this is a new best time for the given revision.
func record_time(level_id: String, rev: String, ticks: int, taps: Array = []) -> bool:
	var best := best_ticks(level_id, rev)
	if best >= 0 and ticks >= best:
		return false
	scores[level_id] = {"rev": rev, "ticks": ticks, "taps": taps.duplicate(), "player": player_name(),
		"player_id": player_id(), "color": str(profile.get("color", PLAYER_COLORS[0]))}
	_save_scores()
	return true


func _load_scores() -> void:
	var f := FileAccess.open(SCORES_PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return
	# Entries from before revisions were plain tick counts; they carry no proof and no
	# revision, so they are dropped rather than trusted.
	for key in data.keys():
		if typeof(data[key]) == TYPE_DICTIONARY:
			scores[key] = data[key]


func _save_scores() -> void:
	var f := FileAccess.open(SCORES_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(scores))
