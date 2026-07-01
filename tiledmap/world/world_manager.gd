extends Node3D

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

@onready var grid_map: GridMap = $GridMap

@export var tree_spawner: TreeSpawner
@export var animal_spawner: AnimalSpawner

@export var generation_seed: int = 1234
@export var water_level: int = 0

@export var grass_item: int = 0
@export var dirt_item: int = 1
@export var tree_item: int = 2

@export var mountain_level: int = 5
@export var lake_threshold: float = 0.4
@export var dirt_surface_chance: float = 0.5

@export var spawn_protection_radius: int = 5
@export var max_visible_cliff_depth: int = 3

@export var size: int = 16


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

var _terrain: GridTerrainGenerator


func _ready() -> void:

	if tree_spawner == null:
		push_error("Chưa gán TreeSpawner!")
		return

	if animal_spawner == null:
		push_error("Chưa gán AnimalSpawner!")
		return

	# Khởi tạo Terrain Generator
	_terrain = GridTerrainGenerator.new()

	# Cấu hình
	_terrain.generation_seed = generation_seed
	_terrain.water_level = water_level

	_terrain.grass_item = grass_item
	_terrain.dirt_item = dirt_item
	_terrain.tree_item = tree_item

	_terrain.mountain_level = mountain_level
	_terrain.lake_threshold = lake_threshold
	_terrain.dirt_surface_chance = dirt_surface_chance
	_terrain.spawn_protection_radius = spawn_protection_radius
	_terrain.max_visible_cliff_depth = max_visible_cliff_depth

	add_child(_terrain)

	# Dependency Injection
	_terrain.set_tree_spawner(tree_spawner)
	_terrain.set_animal_spawner(animal_spawner)

	generate_test_world()


func generate_test_world() -> void:

	if grid_map.mesh_library == null:
		push_error("GridMap chưa có MeshLibrary!")
		return

	_terrain.generate(grid_map)

	print("Generated world: ", size, "x", size)


func _process(delta: float) -> void:

	if _terrain != null:
		_terrain.update_stream(grid_map, delta)
