class_name TerrainConfig
extends Resource

# --- Chunk & streaming ---
@export var chunk_size := 16
@export var load_margin_chunks := 1
@export var fallback_chunk_radius := 2
@export var stream_update_interval := 0.12
@export var clear_grid_on_ready := true

# --- Generation seed & thresholds ---
@export var generation_seed := 12345
@export var water_level := 2
@export var mountain_level := 8
@export var max_terrain_height := 10
@export var max_visible_cliff_depth := 2
@export var terrain_region_size := 32
@export_range(0.0, 1.0, 0.01) var flat_region_chance := 0.70
@export_range(0.0, 1.0, 0.01) var rough_region_chance := 0.20
@export_range(0.0, 1.0, 0.01) var flat_detail_chance := 0.08
@export_range(0.0, 1.0, 0.01) var lake_threshold := 0.20
@export_range(0.0, 1.0, 0.01) var dirt_surface_chance := 0.12
@export var spawn_protection_radius := 24

# --- Block grid overlay ---
@export var show_block_grid := true
@export var block_grid_color := Color(0.015, 0.025, 0.015, 0.55)
@export var block_grid_y_offset := 0.018

# --- Item IDs ---
@export var grass_item := 6
@export var dirt_item := 7
@export var stone_item := 8
@export var water_item := 9
@export var tree_item := 10
