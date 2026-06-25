class_name GridTerrainGenerator
extends Node

@export var chunk_size := 16
@export var load_margin_chunks := 1
@export var fallback_chunk_radius := 2
@export var stream_update_interval := 0.12
@export var clear_grid_on_ready := true

@export_enum("Solid", "Checker", "Noise") var ground_generation_mode := 2
@export var generation_seed := 12345
@export_range(0.01, 1.0, 0.01) var noise_frequency := 0.12
@export_range(-1.0, 1.0, 0.01) var noise_cutoff := 0.2

@export var ground_item := 6
@export var alternate_ground_item := 7
@export var noise_ground_item := 8

var terrain_noise := FastNoiseLite.new()
var loaded_chunks := {}
var saved_cells_by_chunk := {}
var stream_time := 0.0


func generate(grid_map: GridMap):
	terrain_noise.seed = generation_seed
	terrain_noise.frequency = noise_frequency

	if clear_grid_on_ready:
		grid_map.clear()
		loaded_chunks.clear()

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
	if cell.y <= 0:
		grid_map.set_cell_item(cell, item_id)
		return

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

	var ground_y := grid_map.map_to_local(Vector3i.ZERO).y
	var distance := (ground_y - ray_origin.y) / ray_direction.y
	if distance < 0.0:
		return null

	return grid_map.local_to_map(ray_origin + ray_direction * distance)


func _load_chunk(grid_map: GridMap, chunk_coord: Vector2i):
	loaded_chunks[chunk_coord] = true

	var origin_x := chunk_coord.x * chunk_size
	var origin_z := chunk_coord.y * chunk_size

	for local_z in range(chunk_size):
		for local_x in range(chunk_size):
			var world_x := origin_x + local_x
			var world_z := origin_z + local_z
			grid_map.set_cell_item(
				Vector3i(world_x, 0, world_z),
				_choose_ground_item(world_x, world_z)
			)

	var saved_cells: Dictionary = saved_cells_by_chunk.get(chunk_coord, {})
	for cell in saved_cells.keys():
		grid_map.set_cell_item(cell, saved_cells[cell])


func _unload_chunk(grid_map: GridMap, chunk_coord: Vector2i):
	loaded_chunks.erase(chunk_coord)

	var origin_x := chunk_coord.x * chunk_size
	var origin_z := chunk_coord.y * chunk_size

	for local_z in range(chunk_size):
		for local_x in range(chunk_size):
			grid_map.set_cell_item(
				Vector3i(origin_x + local_x, 0, origin_z + local_z),
				GridMap.INVALID_CELL_ITEM
			)

	var saved_cells: Dictionary = saved_cells_by_chunk.get(chunk_coord, {})
	for cell in saved_cells.keys():
		grid_map.set_cell_item(cell, GridMap.INVALID_CELL_ITEM)


func _chunk_coord_for_cell(cell_x: int, cell_z: int) -> Vector2i:
	return Vector2i(
		floori(float(cell_x) / float(chunk_size)),
		floori(float(cell_z) / float(chunk_size))
	)


func _choose_ground_item(x: int, z: int) -> int:
	match ground_generation_mode:
		1:
			if abs(x + z) % 2 == 0:
				return ground_item
			return alternate_ground_item
		2:
			var value := terrain_noise.get_noise_2d(x, z)
			if value > noise_cutoff:
				return alternate_ground_item
			if value < -noise_cutoff:
				return noise_ground_item
			return ground_item
		_:
			return ground_item
