class_name ChunkStreamer
extends RefCounted

var _cfg: TerrainConfig
var _loader: ChunkLoader
var _overlay: BlockGridOverlay
var _node_ref: Node

var _stream_time := 0.0


func setup(cfg: TerrainConfig, loader: ChunkLoader, overlay: BlockGridOverlay, node_ref: Node) -> void:
	_cfg = cfg
	_loader = loader
	_overlay = overlay
	_node_ref = node_ref


func update_stream(grid_map: GridMap, delta: float, force := false) -> void:
	_stream_time += delta
	if not force and _stream_time < _cfg.stream_update_interval:
		return

	_stream_time = 0.0
	var wanted_chunks := _get_wanted_chunks(grid_map)
	var changed := false

	# Load chunks mới
	for chunk_coord in wanted_chunks.keys():
		if not _loader.loaded_chunks.has(chunk_coord):
			_loader.load_chunk(grid_map, chunk_coord)
			changed = true

	# FIX: Không iterate và xóa loaded_chunks cùng lúc — snapshot keys trước
	var to_unload: Array = []
	for chunk_coord in _loader.loaded_chunks.keys():
		if not wanted_chunks.has(chunk_coord):
			to_unload.append(chunk_coord)

	for chunk_coord in to_unload:
		_loader.unload_chunk(grid_map, chunk_coord)
		changed = true

	if changed:
		_overlay.rebuild(grid_map, _loader.rendered_cells_by_chunk)


# ---------------------------------------------------------------------------
# Private
# ---------------------------------------------------------------------------

func _get_wanted_chunks(grid_map: GridMap) -> Dictionary:
	var bounds := _get_visible_cell_bounds(grid_map)
	var min_chunk := TerrainUtils.chunk_coord_for_cell(bounds["min_x"], bounds["min_z"], _cfg.chunk_size)
	var max_chunk := TerrainUtils.chunk_coord_for_cell(bounds["max_x"], bounds["max_z"], _cfg.chunk_size)
	var wanted := {}

	for chunk_z in range(min_chunk.y - _cfg.load_margin_chunks, max_chunk.y + _cfg.load_margin_chunks + 1):
		for chunk_x in range(min_chunk.x - _cfg.load_margin_chunks, max_chunk.x + _cfg.load_margin_chunks + 1):
			wanted[Vector2i(chunk_x, chunk_z)] = true

	return wanted


func _get_visible_cell_bounds(grid_map: GridMap) -> Dictionary:
	# FIX: Guard is_inside_tree() + null-check hoàn chỉnh trước mọi lần gọi get_viewport()
	if not _node_ref.is_inside_tree():
		return _fallback_cell_bounds(grid_map)

	var vp := _node_ref.get_viewport()
	if vp == null:
		return _fallback_cell_bounds(grid_map)

	var camera := vp.get_camera_3d()
	if camera == null:
		return _fallback_cell_bounds(grid_map)

	var viewport_size := vp.get_visible_rect().size
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
	# FIX: Dùng chung 1 điểm gọi get_viewport(), không gọi lại lần 2
	var camera: Camera3D = null
	if _node_ref.is_inside_tree():
		var vp := _node_ref.get_viewport()
		if vp != null:
			camera = vp.get_camera_3d()

	var center_cell := Vector3i.ZERO
	if camera != null:
		center_cell = grid_map.local_to_map(grid_map.to_local(camera.global_position))

	var radius := _cfg.fallback_chunk_radius * _cfg.chunk_size
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

	var ground_y := grid_map.map_to_local(Vector3i(0, _cfg.water_level, 0)).y
	var distance := (ground_y - ray_origin.y) / ray_direction.y
	if distance < 0.0:
		return null

	return grid_map.local_to_map(ray_origin + ray_direction * distance)
