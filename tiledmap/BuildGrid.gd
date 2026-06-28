class_name BuildGrid
extends Node

signal build_mode_changed(enabled: bool)

@export var grid_map_path: NodePath = ^"../GridMap"
@export var terrain_generator_path: NodePath = ^"TerrainGenerator"
@export var placement_rules_path: NodePath = ^"PlacementRules"
@export var targeter_path: NodePath = ^"Targeting"
@export var preview_path: NodePath = ^"Preview"
@export var player_path: NodePath = ^"../Player"
@export var build_mode_enabled := false
@export var build_mode_toggle_key := KEY_B

@onready var grid_map: GridMap = get_node(grid_map_path)
@onready var terrain_generator: Node = get_node(terrain_generator_path)
@onready var placement_rules: Node = get_node(placement_rules_path)
@onready var targeter: Node = get_node(targeter_path)
@onready var preview: Node = get_node(preview_path)
@onready var player: Node = get_node_or_null(player_path)


func _ready():
	grid_map.cell_size = Vector3.ONE
	preview.setup(grid_map.cell_size)
	terrain_generator.generate(grid_map)


func _process(delta):
	terrain_generator.update_stream(grid_map, delta)
	if build_mode_enabled:
		_update_preview()
	else:
		preview.hide_preview()


func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == build_mode_toggle_key:
			set_build_mode_enabled(not build_mode_enabled)
			get_viewport().set_input_as_handled()
			return

	if not build_mode_enabled:
		return

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


func set_build_mode_enabled(enabled: bool):
	if build_mode_enabled == enabled:
		return

	build_mode_enabled = enabled
	if not build_mode_enabled:
		preview.hide_preview()
	build_mode_changed.emit(build_mode_enabled)


func is_build_mode_enabled() -> bool:
	return build_mode_enabled


func place_block_at_mouse(mouse_position: Vector2 = Vector2(-1.0, -1.0)):
	var target: Dictionary = targeter.get_mouse_target(grid_map, placement_rules, mouse_position)
	if target.is_empty():
		return

	var cell: Vector3i = target["place_cell"]
	if _can_place_block(cell):
		terrain_generator.set_runtime_cell(grid_map, cell, placement_rules.block_item)


func delete_block_at_mouse(mouse_position: Vector2 = Vector2(-1.0, -1.0)):
	var target: Dictionary = targeter.get_mouse_target(grid_map, placement_rules, mouse_position)
	if target.is_empty():
		return

	var cell: Vector3i = target["delete_cell"]
	if placement_rules.is_build_block_cell(grid_map, cell):
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
		_can_place_block(cell)
	)


func _can_place_block(cell: Vector3i) -> bool:
	if not placement_rules.can_place_block(grid_map, cell):
		return false
	if _cell_overlaps_player_body(cell):
		return false

	return true


func _cell_overlaps_player_body(cell: Vector3i) -> bool:
	if player == null:
		player = get_node_or_null(player_path)
	if player == null or not player.has_method("would_block_body_cell"):
		return false

	return player.would_block_body_cell(cell)
