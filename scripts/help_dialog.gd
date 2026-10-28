class_name HelpDialog
extends RefCounted
## "How to play" dialog: the one rule, every cannon type drawn as in the game, every movement
## with its pattern drawn as in the editor, and the two ways movement blocks combine.

const BEHAVIOR_HELP := {
	"rotate": "Turns continuously at a fixed speed. Positive values turn clockwise.",
	"sweep": "Swings back and forth between two angles (relative to the base angle) in the given period.",
	"move": "Slides from its base position in one of 8 directions and back, over the given range and period.",
	"orbit": "Circles around its base position with the given radius and period.",
	"path": "Follows a path of points you place in the editor, as a smooth curve or straight lines, looping around or going back and forth.",
}

## Demo behaviours for the figures (sized for a 0.55 scaled cannon in a 130 x 84 box).
const BEHAVIOR_FIGURES := {
	"rotate": [{"type": "rotate", "speed": 90.0}],
	"sweep": [{"type": "sweep", "from": -45.0, "to": 45.0, "period": 2.0}],
	"move": [{"type": "move", "dir": "right", "range": 110.0, "period": 2.0}],
	"orbit": [{"type": "orbit", "radius": 60.0, "period": 3.0}],
	"path": [{"type": "path", "points": [[70.0, -50.0], [140.0, -20.0], [110.0, 50.0]], "period": 4.0, "smooth": true, "closed": true}],
}


static func show(parent: Control) -> VBoxContainer:
	var body := UI.dialog(parent, "How to play", 760)
	var intro := UI.label("You sit in a cannon. Tap anywhere (or click, press any key or gamepad button) and it fires you " +
		"wherever it points. Land in another cannon to fire again, cross the green gate to finish. " +
		"Fall off the world and you restart with the clock reset. Cannons move on fixed patterns that " +
		"restart from zero every attempt, so it is all about timing.", 17, UI.MUTED, true)
	body.add_child(intro)
	body.add_child(UI.label("Zoom with the mouse wheel or a pinch, hold and drag to look around. Escape restarts the attempt. " +
		"A translucent ghost replays the best run; switch it off with the Ghost button or under Player.", 15, UI.MUTED, true))

	body.add_child(UI.spacer(6))
	body.add_child(UI.label("Cannon types", 24))
	for key in Simulation.TYPE_ORDER:
		var info: Dictionary = Simulation.TYPES[key]
		var extra := ""
		if key == Simulation.START_TYPE:
			extra = " The start cannon is always this type."
		_row(body, _cannon_figure(key, []), info["label"], info["hint"] + extra)

	body.add_child(UI.spacer(6))
	body.add_child(UI.label("Movement (combine as many as you like)", 24))
	for key in Simulation.BEHAVIOR_ORDER:
		_row(body, _cannon_figure("normal", BEHAVIOR_FIGURES[key], true), Simulation.BEHAVIORS[key]["label"], BEHAVIOR_HELP[key])

	body.add_child(UI.spacer(6))
	body.add_child(UI.label("Together or one after another", 24))
	_row(body, _icon_figure("par"), "Together",
		"The default. The block runs all the time and its movement is added to the other blocks. " +
		"Two moves in opposite directions cancel each other out.")
	_row(body, _icon_figure("seq"), "Step",
		"Numbered blocks play one after another, each for its duration, each starting where the previous " +
		"step ended. The sequence loops or plays back and forth. \"Move left, then move right\" goes there and back. " +
		"Click the icon on a block in the editor to switch.")
	return body


## A cannon drawn exactly like in the game, optionally with its movement pattern.
static func _cannon_figure(type_key: String, behaviors: Array, with_hints: bool = false) -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(130, 84)
	box.clip_contents = true
	var pos := Vector2(30, 50) if with_hints else Vector2(65, 44)
	# Hints are drawn around the stored base minus the node position: with base == position
	# they sit on the cannon, which is the pose at tick 0 we want to show.
	var data := {"x": pos.x, "y": pos.y, "angle": -30.0, "type": type_key, "behaviors": behaviors.duplicate(true)}
	var node := CannonNode.new(data)
	node.show_hints = with_hints
	node.scale = Vector2(0.55, 0.55)
	node.apply_state({"pos": pos, "angle": -30.0}, false)
	box.add_child(node)
	return box


static func _icon_figure(icon_name: String) -> Control:
	var box := CenterContainer.new()
	box.custom_minimum_size = Vector2(130, 60)
	var tex := TextureRect.new()
	tex.texture = load("res://assets/icons/%s.svg" % icon_name)
	tex.custom_minimum_size = Vector2(44, 44)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(tex)
	return box


static func _row(body: VBoxContainer, figure: Control, name: String, text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	body.add_child(row)
	figure.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(figure)
	var name_label := UI.label(name, 18)
	name_label.custom_minimum_size.x = 120
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(name_label)
	var desc := UI.label(text, 15, UI.MUTED, true)
	desc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(desc)
