extends Node
## Autoload: the online API client (leaderboards and community levels).
##
## Set API_URL to your server's api.php to enable it; leave it empty and the game is purely
## offline (no requests, no UI for online features). Every call is fire-and-forget with a
## callback `cb.call(ok: bool, data: Dictionary)`; a failed request calls back with ok = false.

## Example: "https://example.com/barrelbounce/api.php"
const API_URL := "https://games.ctrlaltpaw.com/BarrelBounce/api/api.php"
const TIMEOUT := 12.0
## Tests set this so a headless run never talks to the real server.
var disabled_for_tests := false


func enabled() -> bool:
	return API_URL != "" and not disabled_for_tests


# ---------------------------------------------------------------- calls

## Posts a finished run. The server keeps one row per player and revision and only lists it
## once the verifier replayed the taps.
func submit_run(level: Dictionary, rev: String, ticks: int, taps: Array, cb: Callable = Callable()) -> void:
	_call("submit_run", HTTPClient.METHOD_POST, {
		"level_id": str(level.get("id", "")), "rev": rev,
		"player_id": GameState.player_id(), "player_name": GameState.player_name(),
		"player_color": str(GameState.profile.get("color", "#ffd166")),
		"ticks": ticks, "taps": taps,
	}, cb)


func leaderboard(level_id: String, rev: String, cb: Callable) -> void:
	_call("leaderboard&level_id=%s&rev=%s&player_id=%s" % [level_id.uri_encode(), rev.uri_encode(), GameState.player_id().uri_encode()],
		HTTPClient.METHOD_GET, {}, cb)


## Publishes a user level (must carry its proof run). Re-publishing the same id updates it.
func publish_level(level: Dictionary, cb: Callable) -> void:
	var payload := level.duplicate(true)
	payload.erase("modified")
	payload["rev_hint"] = GameState.level_hash(level)
	_call("publish_level", HTTPClient.METHOD_POST, {"level": payload}, cb)


func list_levels(offset: int, cb: Callable) -> void:
	_call("levels&offset=%d" % offset, HTTPClient.METHOD_GET, {}, cb)


func fetch_level(level_id: String, cb: Callable) -> void:
	_call("level&id=%s" % level_id.uri_encode(), HTTPClient.METHOD_GET, {}, cb)


# ---------------------------------------------------------------- plumbing

func _call(query: String, method: int, body: Dictionary, cb: Callable) -> void:
	if not enabled():
		if cb.is_valid():
			cb.call(false, {"error": "offline"})
		return
	var req := HTTPRequest.new()
	req.timeout = TIMEOUT
	add_child(req)
	req.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, raw: PackedByteArray):
		req.queue_free()
		# Only parse what looks like JSON: a 404 page or a PHP error is HTML and would
		# otherwise spam the log with parse errors.
		var text := raw.get_string_from_utf8().strip_edges()
		var data = JSON.parse_string(text) if text.begins_with("{") else null
		var ok := result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300 \
			and typeof(data) == TYPE_DICTIONARY and bool(data.get("ok", false))
		if typeof(data) != TYPE_DICTIONARY:
			if result != HTTPRequest.RESULT_SUCCESS:
				data = {"error": "no connection (%d)" % result}
			else:
				data = {"error": "HTTP %d, not JSON: %s" % [code, text.left(60)]}
			push_warning("Online: %s %s -> %s" % [query.get_slice("&", 0), API_URL, str(data["error"])])
		if cb.is_valid():
			cb.call(ok, data))
	var url := API_URL + ("&" if "?" in API_URL else "?") + "action=" + query
	var headers := PackedStringArray(["Content-Type: application/json"])
	var err := req.request(url, headers, method, JSON.stringify(body) if method == HTTPClient.METHOD_POST else "")
	if err != OK:
		req.queue_free()
		if cb.is_valid():
			cb.call(false, {"error": "request failed (%d)" % err})
