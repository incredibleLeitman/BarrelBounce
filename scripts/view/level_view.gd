class_name LevelView
extends Node2D
## Renders a [Simulation]. Shared by the game scene, the editor and the main menu.
## Keeps the 1280x720 play area centred in whatever window / phone aspect we get.

var sim: Simulation
## Optional second simulation replaying the best run, drawn as a translucent ghost.
var ghost_sim: Simulation
var cannon_nodes: Array = []
var player_node: PlayerNode
var ghost_node: PlayerNode
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
	ghost_node = PlayerNode.new()
	ghost_node.ghost = true
	ghost_node.z_index = 2
	ghost_node.visible = false
	add_child(ghost_node)
	player_node = PlayerNode.new()
	player_node.z_index = 2   # above every cannon, selected ones included
	add_child(player_node)
	center_in_viewport()
	get_viewport().size_changed.connect(center_in_viewport)
	if sim:
		rebuild()


## Play area size of the bound level (the default until a simulation is bound).
func level_size() -> Vector2:
	return sim.size if sim else Simulation.BASE_SIZE


func center_in_viewport() -> void:
	var vp := get_viewport_rect().size
	var size := level_size()
	if fit_inset == Rect2():
		scale = Vector2.ONE
		position = ((vp - size) * 0.5).floor()
		return
	var avail := vp - fit_inset.position - fit_inset.size
	var s := minf(1.0, minf(avail.x / size.x, avail.y / size.y))
	scale = Vector2(s, s)
	position = (fit_inset.position + (avail - size * s) * 0.5).floor()


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
	backdrop.level_size = sim.size
	backdrop.world_rect = sim.world
	backdrop.queue_redraw()
	center_in_viewport()
	var per_type: Dictionary = {}
	for c in sim.cannons:
		var node := CannonNode.new(c)
		node.show_hints = show_hints
		var t := str(c.get("type", "normal"))
		node.shade_index = int(per_type.get(t, 0))
		per_type[t] = node.shade_index + 1
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
	if ghost_sim:
		ghost_node.update_from(ghost_sim)


func bind_ghost(s: Simulation) -> void:
	ghost_sim = s
	ghost_node.visible = s != null
	ghost_node.clear_trail()
	var bg := str(sim.level.get("background", "space"))
	if bg != backdrop.theme_name:
		backdrop.theme_name = bg


func set_selection(indices: Array, finish_selected: bool) -> void:
	for i in cannon_nodes.size():
		var on: bool = indices.has(i)
		cannon_nodes[i].selected = on
		cannon_nodes[i].z_index = 1 if on else 0   # selected patterns draw above the others
		cannon_nodes[i].queue_redraw()
	finish_node.selected = finish_selected


## Rubber-band selection rectangle in level coordinates; an empty rect hides it.
func set_band(r: Rect2) -> void:
	if band_node == null:
		band_node = BandNode.new()
		add_child(band_node)
	band_node.rect = r
	band_node.queue_redraw()


var band_node: BandNode


class BandNode extends Node2D:
	var rect := Rect2()

	func _draw() -> void:
		if rect.size == Vector2.ZERO:
			return
		draw_rect(rect, Color(UI.ACCENT_2, 0.15))
		draw_rect(rect, UI.ACCENT_2, false, -1.0)


func redraw_all() -> void:
	for n in cannon_nodes:
		n.queue_redraw()


func world_mouse() -> Vector2:
	return to_local(get_global_mouse_position())
