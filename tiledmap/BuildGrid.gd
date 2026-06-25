class_name BuildGrid
extends Node

@export var grid_map_path: NodePath = ^"../GridMap"
@export var terrain_generator_path: NodePath = ^"TerrainGenerator"
@export var placement_rules_path: NodePath = ^"PlacementRules"
@export var targeter_path: NodePath = ^"Targeting"
@export var preview_path: NodePath = ^"Preview"

@onready var grid_map: GridMap = get_node(grid_map_path)
@onready var terrain_generator: Node = get_node(terrain_generator_path)
@onready var placement_rules: Node = get_node(placement_rules_path)
@onready var targeter: Node = get_node(targeter_path)
@onready var preview: Node = get_node(preview_path)


func _ready():
	grid_map.cell_size = Vector3.ONE
	preview.setup(grid_map.cell_size)
	terrain_generator.generate(grid_map)


func _process(delta):
	terrain_generator.update_stream(grid_map, delta)
	_update_preview()


func _unhandled_input(event):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MouseButton.MOUSE_BUTTON_LEFT:
			place_block_at_mouse(event.position)
			get_viewport().set_input_as_handled()
		elif event.button_index == MouseButton.MOUSE_BUTTON_MIDDLE:
			delete_block_at_mouse(event.position)
			get_viewport().set_input_as_handled()

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_X or event.keycode == KEY_DELETE:
			delete_block_at_mouse()
			get_viewport().set_input_as_handled()


func place_block_at_mouse(mouse_position: Vector2 = Vector2(-1.0, -1.0)):
	var target: Dictionary = targeter.get_mouse_target(grid_map, placement_rules, mouse_position)
	if target.is_empty():
		return

	var cell: Vector3i = target["place_cell"]
	if placement_rules.can_place_block(grid_map, cell):
		terrain_generator.set_runtime_cell(grid_map, cell, placement_rules.block_item)


func delete_block_at_mouse(mouse_position: Vector2 = Vector2(-1.0, -1.0)):
	var target: Dictionary = targeter.get_mouse_target(grid_map, placement_rules, mouse_position)
	if target.is_empty():
		return

	var cell: Vector3i = target["delete_cell"]
	if cell.y > 0:
		terrain_generator.set_runtime_cell(grid_map, cell, GridMap.INVALID_CELL_ITEM)


func _update_preview():
	var target: Dictionary = targeter.get_mouse_target(grid_map, placement_rules)
	if target.is_empty():
		preview.hide_preview()
		return

	var cell: Vector3i = target["place_cell"]
	preview.show_target(
		grid_map,
		placement_rules,
		cell,
		placement_rules.can_place_block(grid_map, cell)
	)
