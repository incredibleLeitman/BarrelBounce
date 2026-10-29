extends Node2D
## Level select: tabs for your own levels, the built-in set, and a placeholder for
## community levels. Each row shows the best time and offers Play / Edit / Delete.

enum Tab { MINE, BUILTIN, COMMUNITY }

var tab: int = Tab.BUILTIN
var ui: CanvasLayer
var list: VBoxContainer
var tab_buttons: Array = []
var backdrop: Backdrop
## Server-side status of the player's published levels (id -> row of my_levels) and the
## totals that gate publishing; fetched whenever the My levels tab is shown.
var my_status: Dictionary = {}
var my_info: Dictionary = {"pending": false, "count": 0, "max": 3}
var my_loaded := false
var my_fetching := false
## World records (id -> fastest verified run) for the rows on screen, and the community
## rows as last listed, so a record fetch can redraw without reloading the list.
var records: Dictionary = {}
var records_fetched: Dictionary = {}
var community_rows: Array = []


func _ready() -> void:
	backdrop = Backdrop.new()
	add_child(backdrop)
	if GameState.user_levels().size() > 0:
		tab = Tab.MINE
	if GameState.last_tab >= 0:
		tab = GameState.last_tab
	_build_ui()
	_refresh()


func _build_ui() -> void:
	ui = UI.layer()
	add_child(ui)
	var root := UI.root_of(ui)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	root.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	margin.add_child(col)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	col.add_child(top)
	var back := UI.small_button("  < Menu  ")
	back.pressed.connect(func(): GameState.go(GameState.SCENE_MENU))
	top.add_child(back)
	top.add_child(UI.spacer(8, false))
	top.add_child(UI.title("Levels", 40))
	top.add_child(UI.hspacer_expand())
	var import_btn := UI.button("Import code", 48, 20)
	import_btn.pressed.connect(_show_import)
	top.add_child(import_btn)
	var new_btn := UI.accent_button("+ New level", 48, 20)
	new_btn.pressed.connect(func():
		GameState.editor_level = GameState.new_level()
		GameState.go(GameState.SCENE_EDITOR))
	top.add_child(new_btn)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	col.add_child(tabs)
	for pair in [["My levels", Tab.MINE], ["Built-in", Tab.BUILTIN], ["Community", Tab.COMMUNITY]]:
		var b := UI.button(pair[0], 48, 20)
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var which: int = pair[1]
		b.pressed.connect(func():
			tab = which
			GameState.last_tab = which
			_refresh())
		tabs.add_child(b)
		tab_buttons.append(b)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)


func _refresh() -> void:
	community_rows.clear()
	_render()
	if tab == Tab.MINE and Online.enabled():
		_fetch_my_levels()


## Fetches the world records for [param levels] (dicts with id and rev) once, then redraws.
func _fetch_records(levels: Array) -> void:
	if not Online.enabled():
		return
	var pairs: Array = []
	for l in levels:
		var id := str(l.get("id", ""))
		if not records_fetched.has(id):
			records_fetched[id] = true
			pairs.append("%s:%s" % [id, str(l.get("rev", ""))])
	if pairs.is_empty():
		return
	var shown_tab := tab
	Online.records(pairs, func(ok: bool, data: Dictionary):
		if not is_instance_valid(list) or not ok:
			return
		var got = data.get("records", {})
		if typeof(got) != TYPE_DICTIONARY:
			return
		for id in got.keys():
			records[str(id)] = got[id]
		if tab == shown_tab:
			_render())


## Asks the server for the status of the player's published levels, then redraws the tab.
func _fetch_my_levels() -> void:
	if my_fetching:
		return
	my_fetching = true
	Online.my_levels(func(ok: bool, data: Dictionary):
		my_fetching = false
		if not is_instance_valid(list) or not ok:
			return
		my_status.clear()
		for r in data.get("rows", []):
			my_status[str(r.get("id", ""))] = r
		my_info = {"pending": bool(data.get("pending", false)), "count": int(data.get("count", 0)), "max": int(data.get("max", 3))}
		my_loaded = true
		if tab == Tab.MINE:
			_render())


func _render() -> void:
	for i in tab_buttons.size():
		tab_buttons[i].button_pressed = i == tab
	for c in list.get_children():
		c.queue_free()
	match tab:
		Tab.MINE:
			var levels := GameState.user_levels()
			if levels.is_empty():
				_empty_message("You have no levels yet. Hit “+ New level” to build one!")
			elif Online.enabled() and my_loaded:
				var hint := UI.label(tr("Published %d of %d levels  ·  one submission at a time, verification takes up to 30 minutes") % [my_info["count"], my_info["max"]], 15, UI.MUTED, true)
				hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				list.add_child(hint)
			for l in levels:
				_add_row(l, true)
		Tab.BUILTIN:
			for l in GameState.builtin_levels():
				_add_row(l, false)
		Tab.COMMUNITY:
			if not Online.enabled():
				_empty_message("Online play is not set up in this build.\nShare levels as codes in the meantime!")
			else:
				_load_community()


func _empty_message(text: String) -> void:
	var l := UI.label(text, 22, UI.MUTED)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_child(UI.spacer(40))
	list.add_child(l)


func _add_row(level: Dictionary, editable: bool) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(info)
	info.add_child(UI.label(str(level.get("name", "Untitled")), 26))
	var id := str(level.get("id", ""))
	var rev := GameState.level_hash(level)
	var author := GameState.display_name(str(level.get("author", "?")), str(level.get("author_id", "")))
	var meta_row := HBoxContainer.new()
	meta_row.add_theme_constant_override("separation", 0)
	info.add_child(meta_row)
	meta_row.add_child(UI.label(tr("by %s  ·  %d cannons  ·  ") % [author, level.get("cannons", []).size()], 16, UI.MUTED))
	var creator := GameState.creator_proof(level)
	# Proofs from before player ids existed carry none: they belong to the level's author.
	var creator_is_me := not creator.is_empty() and (str(creator.get("player_id", "")) == GameState.player_id() \
		or (not creator.has("player_id") and str(level.get("author_id", "")) == GameState.player_id()))
	_add_times(meta_row, id, rev, int(creator.get("ticks", -1)), str(creator.get("player", "creator")), creator_is_me)

	if editable and Online.enabled():
		_add_publish_controls(level, id, rev, info, row)
	if editable:
		var share := UI.small_button("  Share  ")
		if GameState.can_share(level):
			share.pressed.connect(func(): _show_share(level))
		else:
			share.disabled = true
			share.tooltip_text = tr("Finish this version of the level once, then you can share it.")
		row.add_child(share)
		var del := UI.icon_button("", "trash")
		del.pressed.connect(func():
			UI.confirm(UI.root_of(ui), "Delete level?", "“%s” will be gone for good." % str(level.get("name", "")), "Delete", func():
				GameState.delete_user_level(str(level["id"]))
				_refresh()))
		row.add_child(del)
	var edit := UI.icon_button(tr("Edit") if editable else tr("Remix"), "pen")
	edit.pressed.connect(func():
		var copy: Dictionary = level.duplicate(true)
		if not editable:
			copy["id"] = GameState.new_level_id()
			copy["name"] = str(level.get("name", "Level")) + " remix"
			copy["author"] = GameState.player_name()
		GameState.editor_level = copy
		GameState.go(GameState.SCENE_EDITOR))
	row.add_child(edit)
	var play := UI.accent_button("  Play  ", 48, 20)
	play.pressed.connect(func(): GameState.play_level(level))
	row.add_child(play)


## The times of one level, the same way in every tab: your best (orange when nobody is
## faster), the creator's time, and the world record with its holder.
func _add_times(meta_row: HBoxContainer, id: String, rev: String, creator_ticks: int, creator_name: String, creator_is_me: bool) -> void:
	var best := GameState.best_ticks(id, rev)
	var rec: Dictionary = records.get(id, {})
	var rec_is_me := not rec.is_empty() and str(rec.get("player_id", "")) == GameState.player_id()
	if best >= 0:
		# Orange when you hold the record: nobody verified is faster, and the creator's
		# time (when it is not yours) is not better either.
		var top := (rec.is_empty() or rec_is_me or best <= int(rec["ticks"])) \
			and (creator_ticks < 0 or creator_is_me or best <= creator_ticks)
		meta_row.add_child(UI.label(tr("best %s") % Simulation.format_ticks(best), 16, UI.ACCENT if top else UI.MUTED))
	elif GameState.best_is_stale(id, rev):
		meta_row.add_child(UI.label("level changed: best time reset", 16, UI.MUTED))
	else:
		meta_row.add_child(UI.label("not finished yet", 16, UI.MUTED))
	if creator_ticks >= 0 and not creator_is_me:
		meta_row.add_child(UI.label(tr("  ·  %s: %s") % [creator_name, Simulation.format_ticks(creator_ticks)], 16, UI.MUTED))
	if not rec.is_empty():
		var holder := GameState.display_name(str(rec.get("player_name", "?")), str(rec.get("player_id", "")))
		meta_row.add_child(UI.label(tr("  ·  world record %s by %s") % [Simulation.format_ticks(int(rec["ticks"])), holder], 16, UI.ACCENT if rec_is_me else UI.MUTED))


## Publish / Update / Cancel / Unpublish for one of the player's levels, plus a status line
## ("waiting for verification", "published", "rejected: why") from the server.
func _add_publish_controls(level: Dictionary, id: String, rev: String, info: VBoxContainer, row: HBoxContainer) -> void:
	var st: Dictionary = my_status.get(id, {})
	# A level the server does not know any more (removed elsewhere) counts as unpublished.
	var published := level.has("online_id") and (not my_loaded or not st.is_empty())
	var status := str(st.get("status", "pending")) if published else ""
	if published:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 0)
		info.add_child(line)
		match status:
			"verified":
				line.add_child(UI.label(tr("published  ·  %d plays  ·  %d stars") % [int(st.get("plays", 0)), int(st.get("stars", 0))], 15, UI.GOOD))
			"rejected":
				line.add_child(UI.label(tr("rejected: %s") % Online.reason_text(str(st.get("reason", ""))), 15, UI.BAD))
			_:
				line.add_child(UI.label("waiting for verification (up to 30 minutes)", 15, UI.ACCENT_2))
		# Send the current version again: a newer revision, or the same one once more (which
		# re-verifies it and puts the proof run on the leaderboard).
		if status != "pending":
			var update := UI.small_button("  Update  ")
			if str(st.get("rev", "")) == rev:
				update.tooltip_text = tr("Send this version again.")
			if GameState.can_share(level) and not my_info["pending"]:
				update.pressed.connect(func(): _publish(level))
			else:
				update.disabled = true
				update.tooltip_text = tr("Finish this version of the level once, then you can publish it.") if not GameState.can_share(level) \
					else tr("You already have a level waiting for verification. Wait for it or cancel it first.")
			row.add_child(update)
		var remove := UI.small_button("  Cancel  " if status == "pending" else "  Unpublish  ")
		remove.pressed.connect(func():
			var title := "Cancel the submission?" if status == "pending" else "Unpublish level?"
			var msg := tr("“%s” is taken off the server; other players' times on it are lost.") % str(level.get("name", ""))
			UI.confirm(UI.root_of(ui), title, msg, "Cancel submission" if status == "pending" else "Unpublish", func():
				_unpublish(id, str(level.get("name", "")))))
		row.add_child(remove)
		return
	var publish := UI.small_button("  Publish  ")
	if not GameState.can_share(level):
		publish.disabled = true
		publish.tooltip_text = tr("Finish this version of the level once, then you can publish it.")
	elif my_loaded and my_info["pending"]:
		publish.disabled = true
		publish.tooltip_text = tr("You already have a level waiting for verification. Wait for it or cancel it first.")
	elif my_loaded and int(my_info["count"]) >= int(my_info["max"]):
		publish.disabled = true
		publish.tooltip_text = tr("You can have at most %d published levels. Unpublish one first.") % int(my_info["max"])
	else:
		publish.pressed.connect(func(): _publish(level))
	row.add_child(publish)


func _unpublish(id: String, level_name: String) -> void:
	var root := UI.root_of(ui)
	Online.unpublish(id, func(ok: bool, data: Dictionary):
		if not is_instance_valid(root):
			return
		if ok:
			GameState.mark_unpublished(id)
			my_status.erase(id)
			UI.toast(root, tr("“%s” was removed from the server.") % level_name, UI.GOOD)
			_refresh()
		else:
			UI.toast(root, tr("Could not remove the level: %s") % Online.error_text(data), UI.BAD))


# ---------------------------------------------------------------- level codes

func _show_share(level: Dictionary) -> void:
	var root := UI.root_of(ui)
	var body := UI.dialog(root, "Share “%s”" % str(level.get("name", "")), 640)
	body.add_child(UI.label(tr("Send this code to a friend. They paste it under “Import code”. It carries a %s run as proof the level can be finished.") % Simulation.format_ticks(int(GameState.proof_for(level)["ticks"])), 16, UI.MUTED, true))
	var code := GameState.level_to_code(level)
	var box := TextEdit.new()
	box.text = code
	box.editable = false
	box.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	box.custom_minimum_size = Vector2(0, 160)
	box.add_theme_font_size_override("font_size", 14)
	body.add_child(box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	body.add_child(row)
	var copy := UI.accent_button("Copy to clipboard", 48, 18)
	copy.pressed.connect(func():
		DisplayServer.clipboard_set(code)
		UI.toast(root, "Code copied", UI.GOOD))
	row.add_child(copy)
	body.add_child(UI.label(tr("%d characters") % code.length(), 13, UI.MUTED))
	# The whole code is selected from the start, ready for Ctrl+C.
	box.call_deferred("grab_focus")
	box.call_deferred("select_all")


func _show_import() -> void:
	var root := UI.root_of(ui)
	var body := UI.dialog(root, "Import a level code", 640)
	body.add_child(UI.label("Paste a code that starts with BB1: and the level is added to your levels.", 16, UI.MUTED))
	var box := TextEdit.new()
	box.placeholder_text = "BB1:..."
	box.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	box.custom_minimum_size = Vector2(0, 160)
	box.add_theme_font_size_override("font_size", 14)
	body.add_child(box)
	var status := UI.label("", 15, UI.BAD)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	body.add_child(row)
	var do_import := UI.accent_button("Import", 48, 18)
	var paste := UI.button("Paste & import", 48, 18)
	paste.pressed.connect(func():
		box.text = DisplayServer.clipboard_get()
		do_import.pressed.emit())
	row.add_child(paste)
	do_import.pressed.connect(func():
		var level := GameState.level_from_code(box.text)
		if level.is_empty():
			status.text = tr("That is not a valid level code, or its proof run does not finish the level.")
			return
		if GameState.save_user_level(level):
			# Close the dialog: its shade is the ColorRect ancestor of the body.
			var shade: Node = body
			while shade and not (shade is ColorRect):
				shade = shade.get_parent()
			if shade:
				shade.queue_free()
			tab = Tab.MINE
			_refresh()
			UI.toast(root, tr("Imported “%s” by %s") % [str(level.get("name", "")), GameState.display_name(str(level.get("author", "?")), str(level.get("author_id", "")))], UI.GOOD)
		else:
			status.text = tr("Could not save the level."))
	row.add_child(do_import)
	body.add_child(status)


# ---------------------------------------------------------------- online

func _publish(level: Dictionary) -> void:
	var root := UI.root_of(ui)
	var payload: Dictionary = level.duplicate(true)
	payload["verified"] = GameState.proof_for(level)
	UI.toast(root, tr("Publishing “%s”…") % str(level.get("name", "")), UI.ACCENT_2)
	Online.publish_level(payload, func(ok: bool, data: Dictionary):
		if not is_instance_valid(root):
			return
		if ok:
			level["online_id"] = str(level["id"])
			GameState.save_user_level(level)
			UI.toast(root, "Published. It appears under Community once verified (up to 30 minutes).", UI.GOOD)
			_refresh()
		else:
			UI.toast(root, tr("Publish failed: %s") % Online.error_text(data), UI.BAD))


func _load_community() -> void:
	var loading := UI.label("Loading community levels…", 20, UI.MUTED)
	loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_child(loading)
	Online.list_levels(0, func(ok: bool, data: Dictionary):
		if not is_instance_valid(list) or tab != Tab.COMMUNITY:
			return
		for c in list.get_children():
			c.queue_free()
		if not ok:
			_empty_message("Could not reach the server (%s)." % str(data.get("error", "offline")))
			return
		var rows: Array = data.get("rows", [])
		if rows.is_empty():
			_empty_message("No community levels yet. Publish one of yours!")
		community_rows = rows
		for r in rows:
			_add_community_row(r)
		_fetch_records(rows))


func _add_community_row(r: Dictionary) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(info)
	info.add_child(UI.label(str(r.get("name", "Untitled")), 26))
	var id := str(r.get("id", ""))
	var mine := bool(r.get("mine", false))
	var status := str(r.get("status", "verified"))
	var author := GameState.display_name(str(r.get("author_name", "?")), str(r.get("author_id", "")))
	var meta_row := HBoxContainer.new()
	meta_row.add_theme_constant_override("separation", 0)
	info.add_child(meta_row)
	meta_row.add_child(UI.label(tr("by %s  ·  %d plays  ·  %d stars  ·  ") % [author, int(r.get("plays", 0)), int(r.get("stars", 0))], 16, UI.MUTED))
	_add_times(meta_row, id, str(r.get("rev", "")), int(r.get("proof_ticks", -1)), author, mine)
	if mine:
		# The author sees their own pending / rejected levels here too, with a way out.
		match status:
			"pending":
				info.add_child(UI.label("waiting for verification (up to 30 minutes)", 15, UI.ACCENT_2))
			"rejected":
				info.add_child(UI.label(tr("rejected: %s  ·  fix it under My levels and publish again") % Online.reason_text(str(r.get("reason", ""))), 15, UI.BAD))
		var remove := UI.small_button("  Cancel  " if status == "pending" else "  Unpublish  ")
		remove.pressed.connect(func():
			var title := "Cancel the submission?" if status == "pending" else "Unpublish level?"
			var msg := tr("“%s” is taken off the server; other players' times on it are lost.") % str(r.get("name", ""))
			UI.confirm(UI.root_of(ui), title, msg, "Cancel submission" if status == "pending" else "Unpublish", func():
				_unpublish(id, str(r.get("name", "")))))
		row.add_child(remove)
	else:
		# Lambdas capture by value, so the toggle state lives in a dictionary (shared by reference).
		var state := {"starred": bool(r.get("starred", false)), "count": int(r.get("stars", 0))}
		var star := UI.icon_button(str(state["count"]), "star" if state["starred"] else "star_off")
		star.tooltip_text = tr("Mark as a favourite: starred levels are listed first.")
		star.pressed.connect(func():
			var want: bool = not state["starred"]
			star.disabled = true
			Online.star(id, want, func(ok: bool, data: Dictionary):
				if not is_instance_valid(star):
					return
				star.disabled = false
				if not ok:
					UI.toast(UI.root_of(ui), tr("Could not star the level: %s") % Online.error_text(data), UI.BAD)
					return
				state["starred"] = want
				state["count"] = int(data.get("stars", state["count"]))
				star.text = str(state["count"])
				star.icon = load("res://assets/icons/%s.svg" % ("star" if want else "star_off"))))
		row.add_child(star)
		var remix := UI.icon_button(tr("Remix"), "pen")
		remix.pressed.connect(func():
			remix.disabled = true
			Online.fetch_level(id, func(ok: bool, data: Dictionary):
				if not ok or typeof(data.get("level")) != TYPE_DICTIONARY:
					if is_instance_valid(remix):
						remix.disabled = false
					UI.toast(UI.root_of(ui), "Could not download the level.", UI.BAD)
					return
				# Your own copy: new id, your name, no proof run and no link to the server.
				var copy: Dictionary = GameState.normalize_level(data["level"])
				copy["id"] = GameState.new_level_id()
				copy["name"] = str(copy.get("name", "Level")) + " remix"
				copy["author"] = GameState.player_name()
				copy["author_id"] = GameState.player_id()
				copy.erase("verified")
				copy.erase("online_id")
				GameState.editor_level = copy
				GameState.go(GameState.SCENE_EDITOR)))
		row.add_child(remix)
	var play := UI.accent_button("  Play  ", 48, 20)
	play.pressed.connect(func():
		play.disabled = true
		play.text = tr("  …  ")
		Online.fetch_level(id, func(ok: bool, data: Dictionary):
			if not ok or typeof(data.get("level")) != TYPE_DICTIONARY:
				if is_instance_valid(play):
					play.disabled = false
					play.text = tr("  Play  ")
				UI.toast(UI.root_of(ui), "Could not download the level.", UI.BAD)
				return
			var level: Dictionary = GameState.normalize_level(data["level"])
			level["id"] = id
			level["online_id"] = id
			GameState.play_level(level)))
	row.add_child(play)
