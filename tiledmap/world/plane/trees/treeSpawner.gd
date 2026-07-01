class_name TreeSpawner
extends Node

# ------------------------------------------------------------------
# Tree Types
# ------------------------------------------------------------------

@export var oak_scene: PackedScene
@export var oak2_scene: PackedScene
@export var oak3_scene: PackedScene


# chunk_coord -> Array[Node3D]
var _trees_by_chunk: Dictionary = {}


# ------------------------------------------------------------------
# Spawn
# ------------------------------------------------------------------

func spawn_trees_for_chunk(
	chunk_coord: Vector2i,
	trees: Array,
	grid_map: GridMap
) -> void:

	if trees.is_empty():
		return

	if _trees_by_chunk.has(chunk_coord):
		return

	var instances: Array[Node3D] = []

	for tree_data: Dictionary in trees:

		var cell: Vector3i = tree_data["cell"]
		var tree_type: int = tree_data["type"]

		var scene: PackedScene = _get_scene(tree_type)

		if scene == null:
			continue

		var tree := scene.instantiate() as Node3D

		var local_pos: Vector3 = grid_map.map_to_local(cell)
		var world_pos: Vector3 = grid_map.to_global(local_pos)

		add_child(tree)

		tree.global_position = world_pos

		# Random rotation
		tree.rotation.y = randf() * TAU

		# Random scale
		var scale_factor := randf_range(0.9, 1.15)
		tree.scale = Vector3.ONE * scale_factor

		# Random offset
		tree.position += Vector3(
			randf_range(-0.15, 0.15),
			0.0,
			randf_range(-0.15, 0.15)
		)

		instances.append(tree)

	_trees_by_chunk[chunk_coord] = instances


# ------------------------------------------------------------------
# Remove
# ------------------------------------------------------------------

func despawn_trees_for_chunk(chunk_coord: Vector2i) -> void:

	if not _trees_by_chunk.has(chunk_coord):
		return

	for tree: Node3D in _trees_by_chunk[chunk_coord]:

		if is_instance_valid(tree):
			tree.queue_free()

	_trees_by_chunk.erase(chunk_coord)


func clear_all() -> void:

	for chunk_coord: Vector2i in _trees_by_chunk.keys().duplicate():
		despawn_trees_for_chunk(chunk_coord)


# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------

func _get_scene(tree_type: int) -> PackedScene:

	match tree_type:

		TerrainSampler.TreeType.OAK:
			return oak_scene

		TerrainSampler.TreeType.OAK2:
			return oak2_scene

		TerrainSampler.TreeType.OAK3:
			return oak3_scene

	return null
