class_name TreeSpawner
extends Node

# Gán trees.tscn vào đây từ Inspector (hoặc từ code)
@export var tree_scene: PackedScene

# chunk_coord (Vector2i) -> Array[Node3D]
var _trees_by_chunk: Dictionary = {}


func spawn_trees_for_chunk(
	chunk_coord: Vector2i,
	tree_cells: Array,
	grid_map: GridMap
) -> void:
	if tree_scene == null:
		return
	if tree_cells.is_empty():
		return

	var instances: Array[Node3D] = []

	for cell in tree_cells:
		var local_pos: Vector3 = grid_map.map_to_local(cell)
		var world_pos: Vector3 = grid_map.to_global(local_pos)

		var tree: Node3D = tree_scene.instantiate()
		add_child(tree)
		tree.global_position = world_pos
		instances.append(tree)

	_trees_by_chunk[chunk_coord] = instances


func despawn_trees_for_chunk(chunk_coord: Vector2i) -> void:
	var instances: Array = _trees_by_chunk.get(chunk_coord, [])
	for tree in instances:
		if is_instance_valid(tree):
			tree.queue_free()
	_trees_by_chunk.erase(chunk_coord)


func clear_all() -> void:
	for chunk_coord in _trees_by_chunk.keys().duplicate():
		despawn_trees_for_chunk(chunk_coord)
