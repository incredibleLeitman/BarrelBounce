class_name LevelView
extends Node2D
## Renders a [Simulation]. Shared by the game scene, the editor and the main menu.
## Keeps the 1280x720 play area centred in whatever window / phone aspect we get.

var sim: Simulation
var cannon_nodes: Array = []
var player_node: PlayerNode
var finish_node: FinishNode
var backdrop: Backdrop
var show_hints := false
## Screen-space insets (left, top, right, bottom) to keep clear of UI. When set, the play
## area is scaled down to fit the remaining space (the editor uses this for its inspector).
var fit_inset := Rect2()


func _ready() -> void:
	backdrop = Backdrop.new()
	add_child(backdrop)
	finish_node = FinishNode.new()
	add_child(finish_node)
	player_node = PlayerNode.new()
	add_child(player_node)
	center_in_viewport()
	get_viewport().size_changed.connect(center_in_viewport)
	if sim:
		rebuild()


func center_in_viewport() -> void:
	var vp := get_viewport_rect().size
	if fit_inset == Rect2():
		scale = Vector2.ONE
		position = ((vp - Simulation.BASE_SIZE) * 0.5).floor()
		return
	var avail := vp - fit_inset.position - fit_inset.size
	var s := minf(1.0, minf(avail.x / Simulation.BASE_SIZE.x, avail.y / Simulation.BASE_SIZE.y))
	scale = Vector2(s, s)
	position = (fit_inset.position + (avail - Simulation.BASE_SIZE * s) * 0.5).floor()


func bind(s: Simulation) -> void:
	sim = s
	if is_inside_tree():
		rebuild()


## Recreate cannon nodes after cannons were added/removed in the editor.
func rebuild() -> void:
	for n in cannon_nodes:
		n.queue_free()
	cannon_nodes.clear()
	backdrop.show_bounds = show_hints
	backdrop.queue_redraw()
	for c in sim.cannons:
		var node := CannonNode.new(c)
		node.show_hints = show_hints
		add_child(node)
		cannon_nodes.append(node)
	# Player above cannons.
	move_child(player_node, get_child_count() - 1)
	refresh()


## Sync every node with the simulation state.
func refresh() -> void:
	if sim == null:
		return
	if cannon_nodes.size() != sim.cannons.size():
		rebuild()
		return
	for i in cannon_nodes.size():
		var occupied := sim.mode == Simulation.Mode.IN_CANNON and sim.cannon_index == i
		cannon_nodes[i].apply_state(sim.cannon_states[i], occupied, sim.fuse_left(i))
	finish_node.set_rect(sim.finish_rect())
	player_node.update_from(sim)
	var bg := str(sim.level.get("background", "space"))
	if bg != backdrop.theme_name:
		backdrop.theme_name = bg


func set_selection(cannon_index: int, finish_selected: bool) -> void:
	for i in cannon_nodes.size():
		cannon_nodes[i].selected = i == cannon_index
		cannon_nodes[i].queue_redraw()
	finish_node.selected = finish_selected


func redraw_all() -> void:
	for n in cannon_nodes:
		n.queue_redraw()


func world_mouse() -> Vector2:
	return to_local(get_global_mouse_position())
