class_name GridTerrainGenerator
extends Node

@export var chunk_size := 16
@export var load_margin_chunks := 1
@export var fallback_chunk_radius := 2
@export var stream_update_interval := 0.12
@export var clear_grid_on_ready := true

@export var generation_seed := 12345
@export var water_level := 2
@export var mountain_level := 7
@export var max_terrain_height := 10
@export var dirt_surface_chance := 0.18
@export var tree_chance := 0.075

@export var grass_item := 6
@export var dirt_item := 7
@export var stone_item := 8
@export var water_item := 9
@export var tree_item := 10

var elevation_noise := FastNoiseLite.new()
var detail_noise := FastNoiseLite.new()
var moisture_noise := FastNoiseLite.new()
var loaded_chunks := {}
var rendered_cells_by_chunk := {}
var saved_cells_by_chunk := {}
var stream_time := 0.0


func generate(grid_map: GridMap):
	_setup_noise()

	if clear_grid_on_ready:
		grid_map.clear()
		loaded_chunks.clear()
		rendered_cells_by_chunk.clear()

	update_stream(grid_map, 0.0, true)


func update_stream(grid_map: GridMap, delta: float, force := false):
	stream_time += delta
	if not force and stream_time < stream_update_interval:
		return

	stream_time = 0.0
	var wanted_chunks := _get_wanted_chunks(grid_map)

	for chunk_coord in wanted_chunks.keys():
		if not loaded_chunks.has(chunk_coord):
			_load_chunk(grid_map, chunk_coord)

	for chunk_coord in loaded_chunks.keys():
		if not wanted_chunks.has(chunk_coord):
			_unload_chunk(grid_map, chunk_coord)


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
	elevation_noise.frequency = 0.035
	elevation_noise.fractal_octaves = 4
	elevation_noise.fractal_gain = 0.52

	detail_noise.seed = generation_seed + 101
	detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	detail_noise.frequency = 0.11
	detail_noise.fractal_octaves = 2

	moisture_noise.seed = generation_seed + 202
	moisture_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	moisture_noise.frequency = 0.055


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

	for y in range(0, surface_y):
		var item_id := stone_item if y < surface_y - 1 else dirt_item
		var cell := Vector3i(world_x, y, world_z)
		grid_map.set_cell_item(cell, item_id)
		rendered_cells.append(cell)

	var surface_cell := Vector3i(world_x, surface_y, world_z)
	grid_map.set_cell_item(surface_cell, surface_item)
	rendered_cells.append(surface_cell)

	if terrain["has_water"]:
		var water_cell := Vector3i(world_x, water_level, world_z)
		grid_map.set_cell_item(water_cell, water_item)
		rendered_cells.append(water_cell)

	if terrain["has_tree"]:
		var tree_cell := Vector3i(world_x, surface_y + 1, world_z)
		grid_map.set_cell_item(tree_cell, tree_item)
		rendered_cells.append(tree_cell)

	return rendered_cells


func _sample_terrain(world_x: int, world_z: int) -> Dictionary:
	var elevation := (elevation_noise.get_noise_2d(world_x, world_z) + 1.0) * 0.5
	var detail := detail_noise.get_noise_2d(world_x, world_z) * 0.18
	var height_ratio := clampf(elevation * 0.88 + detail, 0.0, 1.0)
	var surface_y := clampi(roundi(height_ratio * float(max_terrain_height)), 0, max_terrain_height)
	var moisture := (moisture_noise.get_noise_2d(world_x, world_z) + 1.0) * 0.5
	var object_value := _random_01(world_x, world_z, 303)
	var has_water := surface_y <= water_level
	var surface_item := grass_item

	if has_water:
		surface_y = maxi(0, water_level - 1)
		surface_item = dirt_item
	elif surface_y >= mountain_level:
		surface_item = stone_item
	elif moisture < dirt_surface_chance:
		surface_item = dirt_item

	var has_tree := (
		not has_water
		and surface_item == grass_item
		and surface_y < mountain_level
		and moisture > 0.35
		and object_value > 1.0 - tree_chance
	)

	return {
		"surface_y": surface_y,
		"surface_item": surface_item,
		"has_water": has_water,
		"has_tree": has_tree,
	}


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
