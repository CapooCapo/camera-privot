class_name GridTerrainGenerator
extends Node

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

@export var chunk_size := 16
@export var load_margin_chunks := 1
@export var fallback_chunk_radius := 2
@export var stream_update_interval := 0.12
@export var clear_grid_on_ready := true

@export var generation_seed := 12345
@export var water_level := 2
@export var mountain_level := 8
@export var max_terrain_height := 10
@export var max_visible_cliff_depth := 2
@export var terrain_region_size := 32

@export_range(0.0, 1.0, 0.01)
var flat_region_chance := 0.70

@export_range(0.0, 1.0, 0.01)
var rough_region_chance := 0.20

@export_range(0.0, 1.0, 0.01)
var flat_detail_chance := 0.08

@export_range(0.0, 1.0, 0.01)
var lake_threshold := 0.20

@export_range(0.0, 1.0, 0.01)
var dirt_surface_chance := 0.12

@export var spawn_protection_radius := 24

@export var show_block_grid := true
@export var block_grid_color := Color(0.015, 0.025, 0.015, 0.55)
@export var block_grid_y_offset := 0.018

@export var grass_item := 6
@export var dirt_item := 7
@export var stone_item := 8
@export var water_item := 9
@export var tree_item := 10


# ---------------------------------------------------------------------------
# Modules
# ---------------------------------------------------------------------------

var _cfg: TerrainConfig
var _noise: TerrainNoise
var _profile: TerrainProfile
var _sampler: TerrainSampler
var _loader: ChunkLoader
var _streamer: ChunkStreamer
var _overlay: BlockGridOverlay

var _tree_spawner: TreeSpawner
var _animal_spawner: AnimalSpawner


func _ready():
	_build_config()


# ---------------------------------------------------------------------------
# Dependency Injection
# ---------------------------------------------------------------------------

func set_tree_spawner(spawner: TreeSpawner) -> void:
	_tree_spawner = spawner


func set_animal_spawner(spawner: AnimalSpawner) -> void:
	_animal_spawner = spawner


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func generate(grid_map):
	if _loader == null:
		_wire_modules()
	if clear_grid_on_ready:
		grid_map.clear()
		_loader.loaded_chunks.clear()
		_loader.rendered_cells_by_chunk.clear()
		if _tree_spawner:
			_tree_spawner.clear_all()
		if _animal_spawner:
			_animal_spawner.clear_all()
	_overlay.ensure(grid_map)
	update_stream(grid_map,0,true)


func update_stream(
	grid_map: GridMap,
	delta: float,
	force := false
) -> void:

	_streamer.update_stream(
		grid_map,
		delta,
		force
	)


func set_runtime_cell(
	grid_map: GridMap,
	cell: Vector3i,
	item_id: int
) -> void:

	_loader.set_runtime_cell(
		grid_map,
		cell,
		item_id
	)


func get_loaded_chunk_count() -> int:
	return _loader.loaded_chunks.size()


func get_saved_cell_count() -> int:
	return _loader.get_saved_cell_count()


func get_surface_cell(
	world_x: int,
	world_z: int
) -> Vector3i:

	return _loader.get_surface_cell(
		world_x,
		world_z
	)


# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

func _build_config() -> void:

	_cfg = TerrainConfig.new()

	_cfg.chunk_size = chunk_size
	_cfg.load_margin_chunks = load_margin_chunks
	_cfg.fallback_chunk_radius = fallback_chunk_radius
	_cfg.stream_update_interval = stream_update_interval
	_cfg.clear_grid_on_ready = clear_grid_on_ready

	_cfg.generation_seed = generation_seed
	_cfg.water_level = water_level
	_cfg.mountain_level = mountain_level
	_cfg.max_terrain_height = max_terrain_height
	_cfg.max_visible_cliff_depth = max_visible_cliff_depth

	_cfg.terrain_region_size = terrain_region_size

	_cfg.flat_region_chance = flat_region_chance
	_cfg.rough_region_chance = rough_region_chance
	_cfg.flat_detail_chance = flat_detail_chance

	_cfg.lake_threshold = lake_threshold
	_cfg.dirt_surface_chance = dirt_surface_chance
	_cfg.spawn_protection_radius = spawn_protection_radius

	_cfg.show_block_grid = show_block_grid
	_cfg.block_grid_color = block_grid_color
	_cfg.block_grid_y_offset = block_grid_y_offset

	_cfg.grass_item = grass_item
	_cfg.dirt_item = dirt_item
	_cfg.stone_item = stone_item
	_cfg.water_item = water_item
	_cfg.tree_item = tree_item


# ---------------------------------------------------------------------------
# Wiring
# ---------------------------------------------------------------------------

func _wire_modules() -> void:

	_noise = TerrainNoise.new()
	_noise.setup(_cfg)

	_profile = TerrainProfile.new()
	_profile.setup(
		_cfg,
		_noise
	)

	_sampler = TerrainSampler.new()
	_sampler.setup(
		_cfg,
		_noise,
		_profile
	)

	_loader = ChunkLoader.new()
	_loader.setup(
		_cfg,
		_sampler,
		_tree_spawner,
		_animal_spawner
	)

	_overlay = BlockGridOverlay.new()
	_overlay.setup(_cfg)

	_streamer = ChunkStreamer.new()
	_streamer.setup(
		_cfg,
		_loader,
		_overlay,
		self
	)
