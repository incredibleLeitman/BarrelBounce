extends Node2D
## Level select: tabs for your own levels, the built-in set, and a placeholder for
## community levels. Each row shows the best time and offers Play / Edit / Delete.

enum Tab { MINE, BUILTIN, COMMUNITY }

var tab: int = Tab.BUILTIN
var ui: CanvasLayer
var list: VBoxContainer
var tab_buttons: Array = []
var backdrop: Backdrop


func _ready() -> void:
	backdrop = Backdrop.new()
	add_child(backdrop)
	if GameState.user_levels().size() > 0:
		tab = Tab.MINE
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
	for i in tab_buttons.size():
		tab_buttons[i].button_pressed = i == tab
	for c in list.get_children():
		c.queue_free()
	match tab:
		Tab.MINE:
			var levels := GameState.user_levels()
			if levels.is_empty():
				_empty_message("You have no levels yet. Hit “+ New level” to build one!")
			for l in levels:
				_add_row(l, true)
		Tab.BUILTIN:
			for l in GameState.builtin_levels():
				_add_row(l, false)
		Tab.COMMUNITY:
			_empty_message("Community & friends levels are coming later.\nYour levels are plain JSON files – share them in the meantime!")


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
	var best := GameState.best_ticks(str(level.get("id", "")))
	var meta := "by %s  ·  %d cannons  ·  " % [str(level.get("author", "?")), level.get("cannons", []).size()]
	meta += ("best " + Simulation.format_ticks(best)) if best >= 0 else "not finished yet"
	info.add_child(UI.label(meta, 16, UI.MUTED))

	if editable:
		var del := UI.icon_button("", "trash")
		del.pressed.connect(func():
			UI.confirm(UI.root_of(ui), "Delete level?", "“%s” will be gone for good." % str(level.get("name", "")), "Delete", func():
				GameState.delete_user_level(str(level["id"]))
				_refresh()))
		row.add_child(del)
	var edit := UI.icon_button("Edit" if editable else "Remix", "pen")
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
