class_name HelpDialog
extends RefCounted
## "How to play" dialog: the one rule, every cannon type and every movement behaviour.

const BEHAVIOR_HELP := {
	"rotate": "Turns continuously at a fixed speed. Positive values turn clockwise.",
	"sweep": "Swings back and forth between two angles (relative to the base angle) in the given period.",
	"move": "Slides from its base position in one of 8 directions and back, over the given range and period.",
	"orbit": "Circles around its base position with the given radius and period.",
}


static func show(parent: Control) -> void:
	var body := UI.dialog(parent, "How to play")
	var intro := UI.label("You sit in a cannon. Tap anywhere (or click, press any key or gamepad button) and it fires you " +
		"wherever it points. Land in another cannon to fire again, cross the green gate to finish. " +
		"Fall off the world and you restart with the clock reset. Cannons move on fixed patterns that " +
		"restart from zero every attempt, so it is all about timing.", 17, UI.MUTED)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD
	intro.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(intro)
	body.add_child(UI.label("Zoom with the mouse wheel or a pinch, hold and drag to look around.", 15, UI.MUTED))

	body.add_child(UI.spacer(6))
	body.add_child(UI.label("Cannon types", 24))
	for key in Simulation.TYPE_ORDER:
		var info: Dictionary = Simulation.TYPES[key]
		var extra := ""
		if key == Simulation.START_TYPE:
			extra = " The start cannon is always this type."
		_row(body, info["color"], info["label"], info["hint"] + extra)

	body.add_child(UI.spacer(6))
	body.add_child(UI.label("Movement (combine as many as you like)", 24))
	for key in Simulation.BEHAVIOR_ORDER:
		_row(body, UI.ACCENT_2, Simulation.BEHAVIORS[key]["label"], BEHAVIOR_HELP[key])


static func _row(body: VBoxContainer, color: Color, name: String, text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	body.add_child(row)
	var swatch := ColorRect.new()
	swatch.color = color
	swatch.custom_minimum_size = Vector2(22, 22)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(swatch)
	var name_label := UI.label(name, 18)
	name_label.custom_minimum_size.x = 130
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(name_label)
	var desc := UI.label(text, 15, UI.MUTED)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(desc)
