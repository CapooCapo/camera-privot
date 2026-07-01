class_name AnimalSpawner
extends Node

# ------------------------------------------------------------------
# Animal Scenes
# ------------------------------------------------------------------

@export var chicken_scene: PackedScene
@export var pig_scene: PackedScene
@export var cow_scene: PackedScene
@export var sheep_scene: PackedScene

var _animals_by_chunk: Dictionary = {}


# ------------------------------------------------------------------
# Spawn
# ------------------------------------------------------------------

func spawn_animals_for_chunk(chunk_coord: Vector2i, animals: Array, grid_map: GridMap) -> void:

	if animals.is_empty():
		return

	if _animals_by_chunk.has(chunk_coord):
		return

	var instances: Array[Node3D] = []

	for animal_data in animals:

		var cell: Vector3i = animal_data["cell"]
		var animal_type: int = animal_data["type"]

		var scene := _get_scene(animal_type)
		if scene == null:
			continue

		var animal: Node3D = scene.instantiate()

		add_child(animal)

		var world_pos: Vector3 = grid_map.to_global(grid_map.map_to_local(cell))
		world_pos.y += 0.05

		animal.global_position = world_pos
		animal.rotation.y = randf() * TAU

		if animal is VoxelActor:
			animal.spawn_snap_pending = true

		instances.append(animal)

	_animals_by_chunk[chunk_coord] = instances


# ------------------------------------------------------------------
# Remove
# ------------------------------------------------------------------

func despawn_animals_for_chunk(chunk_coord: Vector2i) -> void:

	if not _animals_by_chunk.has(chunk_coord):
		return

	for animal: Node3D in _animals_by_chunk[chunk_coord]:
		if is_instance_valid(animal):
			animal.queue_free()

	_animals_by_chunk.erase(chunk_coord)


func clear_all() -> void:

	for chunk_coord in _animals_by_chunk.keys().duplicate():
		despawn_animals_for_chunk(chunk_coord)


# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------

func _get_scene(animal_type: int) -> PackedScene:

	match animal_type:
		TerrainSampler.AnimalType.RABBIT:
			return chicken_scene

		TerrainSampler.AnimalType.COW:
			return cow_scene

		TerrainSampler.AnimalType.FROG:
			return pig_scene

		TerrainSampler.AnimalType.GOAT:
			return sheep_scene

	return null
