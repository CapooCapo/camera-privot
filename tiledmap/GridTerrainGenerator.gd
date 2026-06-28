class_name GridTerrainGenerator
extends Node

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
@export_range(0.0, 1.0, 0.01) var flat_region_chance := 0.70
@export_range(0.0, 1.0, 0.01) var rough_region_chance := 0.20
@export_range(0.0, 1.0, 0.01) var flat_detail_chance := 0.08
@export_range(0.0, 1.0, 0.01) var lake_threshold := 0.20
@export_range(0.0, 1.0, 0.01) var dirt_surface_chance := 0.12
@export var spawn_protection_radius := 24
@export var show_block_grid := true
@export var block_grid_color := Color(0.015, 0.025, 0.015, 0.55)
@export var block_grid_y_offset := 0.018

@export var grass_item := 6
@export var dirt_item := 7
@export var stone_item := 8
@export var water_item := 9
@export var tree_item := 10

var elevation_noise := FastNoiseLite.new()
var detail_noise := FastNoiseLite.new()
var lake_noise := FastNoiseLite.new()
var biome_noise := FastNoiseLite.new()
var moisture_noise := FastNoiseLite.new()
var tree_density_noise := FastNoiseLite.new()
var loaded_chunks := {}
var rendered_cells_by_chunk := {}
var saved_cells_by_chunk := {}
var stream_time := 0.0
var block_grid_overlay: MeshInstance3D
var block_grid_material: StandardMaterial3D


func generate(grid_map: GridMap):
	_setup_noise()

	if clear_grid_on_ready:
		grid_map.clear()
		loaded_chunks.clear()
		rendered_cells_by_chunk.clear()

	_ensure_block_grid_overlay(grid_map)
	update_stream(grid_map, 0.0, true)


func update_stream(grid_map: GridMap, delta: float, force := false):
	stream_time += delta
	if not force and stream_time < stream_update_interval:
		return

	stream_time = 0.0
	var wanted_chunks := _get_wanted_chunks(grid_map)
	var changed := false

	for chunk_coord in wanted_chunks.keys():
		if not loaded_chunks.has(chunk_coord):
			_load_chunk(grid_map, chunk_coord)
			changed = true

	for chunk_coord in loaded_chunks.keys():
		if not wanted_chunks.has(chunk_coord):
			_unload_chunk(grid_map, chunk_coord)
			changed = true

	if changed:
		_rebuild_block_grid_overlay(grid_map)


func set_runtime_cell(grid_map: GridMap, cell: Vector3i, item_id: int):
	var chunk_coord := _chunk_coord_for_cell(cell.x, cell.z)
	var saved_cells: Dictionary = saved_cells_by_chunk.get(chunk_coord, {})

	if item_id == GridMap.INVALID_CELL_ITEM:
		saved_cells.erase(cell)
	else:
		saved_cells[cell] = item_id

	if saved_cells.is_empty():
		saved_cells_by_chunk.erase(chunk_coord)
	else:
		saved_cells_by_chunk[chunk_coord] = saved_cells

	if loaded_chunks.has(chunk_coord):
		grid_map.set_cell_item(cell, item_id)


func get_loaded_chunk_count() -> int:
	return loaded_chunks.size()


func get_saved_cell_count() -> int:
	var count := 0
	for saved_cells in saved_cells_by_chunk.values():
		count += saved_cells.size()
	return count


func get_surface_cell(world_x: int, world_z: int) -> Vector3i:
	var terrain := _sample_terrain(world_x, world_z)
	return Vector3i(world_x, int(terrain["surface_y"]), world_z)


func _setup_noise():
	elevation_noise.seed = generation_seed
	elevation_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	elevation_noise.frequency = 0.012
	elevation_noise.fractal_octaves = 2
	elevation_noise.fractal_gain = 0.45

	detail_noise.seed = generation_seed + 101
	detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	detail_noise.frequency = 0.05
	detail_noise.fractal_octaves = 2

	lake_noise.seed = generation_seed + 151
	lake_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	lake_noise.frequency = 0.018
	lake_noise.fractal_octaves = 3

	biome_noise.seed = generation_seed + 177
	biome_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	biome_noise.frequency = 0.018
	biome_noise.fractal_octaves = 2

	moisture_noise.seed = generation_seed + 202
	moisture_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	moisture_noise.frequency = 0.026

	tree_density_noise.seed = generation_seed + 303
	tree_density_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	tree_density_noise.frequency = 0.075
	tree_density_noise.fractal_octaves = 2


func _get_wanted_chunks(grid_map: GridMap) -> Dictionary:
	var bounds := _get_visible_cell_bounds(grid_map)
	var min_chunk := _chunk_coord_for_cell(bounds["min_x"], bounds["min_z"])
	var max_chunk := _chunk_coord_for_cell(bounds["max_x"], bounds["max_z"])
	var wanted := {}

	for chunk_z in range(min_chunk.y - load_margin_chunks, max_chunk.y + load_margin_chunks + 1):
		for chunk_x in range(min_chunk.x - load_margin_chunks, max_chunk.x + load_margin_chunks + 1):
			wanted[Vector2i(chunk_x, chunk_z)] = true

	return wanted


func _get_visible_cell_bounds(grid_map: GridMap) -> Dictionary:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return _fallback_cell_bounds(grid_map)

	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return _fallback_cell_bounds(grid_map)

	var corners := [
		Vector2(0.0, 0.0),
		Vector2(viewport_size.x, 0.0),
		Vector2(0.0, viewport_size.y),
		viewport_size,
	]
	var cells: Array[Vector3i] = []

	for corner in corners:
		var cell = _project_screen_to_ground_cell(grid_map, camera, corner)
		if cell != null:
			cells.append(cell)

	if cells.is_empty():
		return _fallback_cell_bounds(grid_map)

	var min_x := cells[0].x
	var max_x := cells[0].x
	var min_z := cells[0].z
	var max_z := cells[0].z

	for cell in cells:
		min_x = mini(min_x, cell.x)
		max_x = maxi(max_x, cell.x)
		min_z = mini(min_z, cell.z)
		max_z = maxi(max_z, cell.z)

	return {
		"min_x": min_x,
		"max_x": max_x,
		"min_z": min_z,
		"max_z": max_z,
	}


func _fallback_cell_bounds(grid_map: GridMap) -> Dictionary:
	var camera := get_viewport().get_camera_3d()
	var center_cell := Vector3i.ZERO

	if camera != null:
		center_cell = grid_map.local_to_map(grid_map.to_local(camera.global_position))

	var radius := fallback_chunk_radius * chunk_size
	return {
		"min_x": center_cell.x - radius,
		"max_x": center_cell.x + radius,
		"min_z": center_cell.z - radius,
		"max_z": center_cell.z + radius,
	}


func _project_screen_to_ground_cell(grid_map: GridMap, camera: Camera3D, screen_pos: Vector2):
	var ray_origin_world := camera.project_ray_origin(screen_pos)
	var ray_direction_world := camera.project_ray_normal(screen_pos)
	var ray_origin := grid_map.to_local(ray_origin_world)
	var ray_direction := (grid_map.global_transform.basis.inverse() * ray_direction_world).normalized()

	if absf(ray_direction.y) < 0.0001:
		return null

	var ground_y := grid_map.map_to_local(Vector3i(0, water_level, 0)).y
	var distance := (ground_y - ray_origin.y) / ray_direction.y
	if distance < 0.0:
		return null

	return grid_map.local_to_map(ray_origin + ray_direction * distance)


func _load_chunk(grid_map: GridMap, chunk_coord: Vector2i):
	loaded_chunks[chunk_coord] = true

	var origin_x := chunk_coord.x * chunk_size
	var origin_z := chunk_coord.y * chunk_size
	var rendered_cells: Array[Vector3i] = []

	for local_z in range(chunk_size):
		for local_x in range(chunk_size):
			var world_x := origin_x + local_x
			var world_z := origin_z + local_z
			rendered_cells.append_array(_render_terrain_column(grid_map, world_x, world_z))

	rendered_cells_by_chunk[chunk_coord] = rendered_cells

	var saved_cells: Dictionary = saved_cells_by_chunk.get(chunk_coord, {})
	for cell in saved_cells.keys():
		grid_map.set_cell_item(cell, saved_cells[cell])


func _unload_chunk(grid_map: GridMap, chunk_coord: Vector2i):
	loaded_chunks.erase(chunk_coord)

	var rendered_cells: Array = rendered_cells_by_chunk.get(chunk_coord, [])
	for cell in rendered_cells:
		grid_map.set_cell_item(cell, GridMap.INVALID_CELL_ITEM)
	rendered_cells_by_chunk.erase(chunk_coord)

	var saved_cells: Dictionary = saved_cells_by_chunk.get(chunk_coord, {})
	for cell in saved_cells.keys():
		grid_map.set_cell_item(cell, GridMap.INVALID_CELL_ITEM)


func _render_terrain_column(grid_map: GridMap, world_x: int, world_z: int) -> Array[Vector3i]:
	var rendered_cells: Array[Vector3i] = []
	var terrain := _sample_terrain(world_x, world_z)
	var surface_y: int = terrain["surface_y"]
	var surface_item: int = terrain["surface_item"]

	var surface_cell := Vector3i(world_x, surface_y, world_z)
	grid_map.set_cell_item(surface_cell, surface_item)
	rendered_cells.append(surface_cell)

	for cell in _get_exposed_cliff_cells(world_x, world_z, surface_y):
		var item_id := stone_item if cell.y < surface_y - 1 else dirt_item
		grid_map.set_cell_item(cell, item_id)
		rendered_cells.append(cell)

	if terrain["has_water"]:
		var water_cell := Vector3i(world_x, water_level, world_z)
		grid_map.set_cell_item(water_cell, water_item)
		rendered_cells.append(water_cell)

	if terrain["has_tree"]:
		var tree_cell := Vector3i(world_x, surface_y + 1, world_z)
		grid_map.set_cell_item(tree_cell, tree_item)
		rendered_cells.append(tree_cell)

	return rendered_cells


func _ensure_block_grid_overlay(grid_map: GridMap):
	if block_grid_overlay != null:
		return

	block_grid_overlay = MeshInstance3D.new()
	block_grid_overlay.name = "BlockGridOverlay"
	block_grid_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	block_grid_material = StandardMaterial3D.new()
	block_grid_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	block_grid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	block_grid_material.albedo_color = block_grid_color
	block_grid_overlay.material_override = block_grid_material
	grid_map.add_child(block_grid_overlay)


func _rebuild_block_grid_overlay(grid_map: GridMap):
	_ensure_block_grid_overlay(grid_map)
	block_grid_overlay.visible = show_block_grid
	if not show_block_grid:
		block_grid_overlay.mesh = null
		return

	block_grid_material.albedo_color = block_grid_color
	var vertices := PackedVector3Array()

	for rendered_cells in rendered_cells_by_chunk.values():
		for cell in rendered_cells:
			var item_id := grid_map.get_cell_item(cell)
			if item_id != grass_item and item_id != dirt_item and item_id != stone_item and item_id != water_item:
				continue
			_add_block_top_outline(vertices, grid_map, cell)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices

	var mesh := ArrayMesh.new()
	if not vertices.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	block_grid_overlay.mesh = mesh


func _add_block_top_outline(vertices: PackedVector3Array, grid_map: GridMap, cell: Vector3i):
	var center := grid_map.map_to_local(cell)
	var y := center.y + block_grid_y_offset
	var min_x := center.x - grid_map.cell_size.x * 0.5
	var max_x := center.x + grid_map.cell_size.x * 0.5
	var min_z := center.z - grid_map.cell_size.z * 0.5
	var max_z := center.z + grid_map.cell_size.z * 0.5
	var a := Vector3(min_x, y, min_z)
	var b := Vector3(max_x, y, min_z)
	var c := Vector3(max_x, y, max_z)
	var d := Vector3(min_x, y, max_z)

	vertices.append(a)
	vertices.append(b)
	vertices.append(b)
	vertices.append(c)
	vertices.append(c)
	vertices.append(d)
	vertices.append(d)
	vertices.append(a)


func _get_exposed_cliff_cells(world_x: int, world_z: int, surface_y: int) -> Array[Vector3i]:
	var cells_by_key := {}
	var neighbor_offsets := [
		Vector2i.LEFT,
		Vector2i.RIGHT,
		Vector2i.UP,
		Vector2i.DOWN,
	]

	for offset in neighbor_offsets:
		var neighbor := _sample_terrain(world_x + offset.x, world_z + offset.y)
		var neighbor_y: int = neighbor["surface_y"]
		if neighbor_y >= surface_y - 1:
			continue

		var lowest_y := maxi(neighbor_y + 1, surface_y - max_visible_cliff_depth)
		for y in range(lowest_y, surface_y):
			var cell := Vector3i(world_x, y, world_z)
			cells_by_key[cell] = cell

	var exposed_cells: Array[Vector3i] = []
	for cell in cells_by_key.values():
		exposed_cells.append(cell)

	return exposed_cells


func _sample_terrain(world_x: int, world_z: int) -> Dictionary:
	var profile := _get_terrain_profile(world_x, world_z)
	var biome := _get_biome(world_x, world_z, profile)
	var surface_y := _sample_surface_height(world_x, world_z, profile)
	var moisture := (moisture_noise.get_noise_2d(world_x, world_z) + 1.0) * 0.5
	var lake_value := (lake_noise.get_noise_2d(world_x, world_z) + 1.0) * 0.5
	var is_spawn_area := Vector2(world_x, world_z).length() < float(spawn_protection_radius)
	var object_value := _random_01(world_x, world_z, 303)
	var tree_density := (tree_density_noise.get_noise_2d(world_x, world_z) + 1.0) * 0.5
	var has_lake_basin := (
		not is_spawn_area
		and profile != "cliff"
		and lake_value < lake_threshold
	)
	var has_water := has_lake_basin or (
		not is_spawn_area
		and profile != "flat"
		and surface_y < water_level
	)
	var surface_item := grass_item

	if has_water:
		surface_y = maxi(0, water_level - 1)
		surface_item = dirt_item
	elif surface_y >= mountain_level or biome == "rocky":
		surface_item = stone_item
	elif moisture < dirt_surface_chance:
		surface_item = dirt_item

	var tree_threshold := _get_tree_threshold(biome)
	var has_tree := (
		not is_spawn_area
		and not has_water
		and surface_item == grass_item
		and surface_y < mountain_level
		and object_value > tree_threshold
		and tree_density > tree_threshold - 0.08
	)

	return {
		"surface_y": surface_y,
		"surface_item": surface_item,
		"has_water": has_water,
		"has_tree": has_tree,
		"biome": biome,
		"profile": profile,
	}


func _get_terrain_profile(world_x: int, world_z: int) -> String:
	var region_x := floori(float(world_x) / float(terrain_region_size))
	var region_z := floori(float(world_z) / float(terrain_region_size))
	var roll := _random_01(region_x, region_z, 701)

	if roll < flat_region_chance:
		return "flat"
	if roll < flat_region_chance + rough_region_chance:
		return "rough"
	return "cliff"


func _sample_surface_height(world_x: int, world_z: int, profile: String) -> int:
	var region_x := floori(float(world_x) / float(terrain_region_size))
	var region_z := floori(float(world_z) / float(terrain_region_size))
	var base_roll := _random_01(region_x, region_z, 811)
	var base_height := 3 + int(roundf(base_roll * 2.0))
	var detail := detail_noise.get_noise_2d(world_x, world_z)

	match profile:
		"flat":
			if _random_01(world_x, world_z, 821) < flat_detail_chance:
				return clampi(base_height + signi(roundi(detail)), water_level, max_terrain_height)
			return clampi(base_height, water_level, max_terrain_height)
		"rough":
			return clampi(base_height + roundi(detail * 2.0), water_level - 1, max_terrain_height)
		"cliff":
			var ridge := absf(elevation_noise.get_noise_2d(world_x, world_z))
			return clampi(base_height + roundi(ridge * 5.0) + roundi(detail * 2.0), water_level, max_terrain_height)

	return base_height


func _get_biome(world_x: int, world_z: int, profile: String) -> String:
	if profile == "cliff":
		return "rocky"

	var moisture := (moisture_noise.get_noise_2d(world_x, world_z) + 1.0) * 0.5
	var biome_value := (biome_noise.get_noise_2d(world_x, world_z) + 1.0) * 0.5

	if moisture > 0.66 and biome_value > 0.42:
		return "forest"
	if moisture > 0.58 and biome_value <= 0.42:
		return "swamp"
	if moisture < 0.22:
		return "rocky"
	return "plains"


func _get_tree_threshold(biome: String) -> float:
	match biome:
		"forest":
			return 0.62
		"swamp":
			return 0.82
		"plains":
			return 0.92
		"rocky":
			return 1.1

	return 0.95


func _chunk_coord_for_cell(cell_x: int, cell_z: int) -> Vector2i:
	return Vector2i(
		floori(float(cell_x) / float(chunk_size)),
		floori(float(cell_z) / float(chunk_size))
	)


func _random_01(x: int, z: int, salt: int) -> float:
	var value := _hash_u32(x * 73856093 ^ z * 19349663 ^ generation_seed ^ salt)
	return float(value & 0x00ffffff) / 16777215.0


func _hash_u32(value: int) -> int:
	value = value ^ (value >> 16)
	value = value * 0x7feb352d
	value = value ^ (value >> 15)
	value = value * 0x846ca68b
	value = value ^ (value >> 16)
	return value


func signi(value: int) -> int:
	if value > 0:
		return 1
	if value < 0:
		return -1
	return 0
