class_name ChunkLoader
extends RefCounted

var _cfg: TerrainConfig
var _sampler: TerrainSampler
var _tree_spawner: TreeSpawner  # null nếu không dùng cây

var loaded_chunks: Dictionary = {}
var rendered_cells_by_chunk: Dictionary = {}
var saved_cells_by_chunk: Dictionary = {}


func setup(cfg: TerrainConfig, sampler: TerrainSampler, tree_spawner: TreeSpawner = null) -> void:
	_cfg = cfg
	_sampler = sampler
	_tree_spawner = tree_spawner


func load_chunk(grid_map: GridMap, chunk_coord: Vector2i) -> void:
	loaded_chunks[chunk_coord] = true

	var origin_x := chunk_coord.x * _cfg.chunk_size
	var origin_z := chunk_coord.y * _cfg.chunk_size
	var rendered_cells: Array[Vector3i] = []
	var tree_cells: Array[Vector3i] = []

	for local_z in range(_cfg.chunk_size):
		for local_x in range(_cfg.chunk_size):
			var world_x := origin_x + local_x
			var world_z := origin_z + local_z
			var result := _render_terrain_column(grid_map, world_x, world_z)
			rendered_cells.append_array(result["cells"])
			if result["tree_cell"] != Vector3i.ZERO:
				tree_cells.append(result["tree_cell"])

	rendered_cells_by_chunk[chunk_coord] = rendered_cells

	# Phục hồi các ô người chơi đã thay đổi
	var saved_cells: Dictionary = saved_cells_by_chunk.get(chunk_coord, {})
	for cell in saved_cells.keys():
		grid_map.set_cell_item(cell, saved_cells[cell])

	# Spawn cây (sau khi terrain đã vẽ xong)
	if _tree_spawner != null:
		_tree_spawner.spawn_trees_for_chunk(chunk_coord, tree_cells, grid_map)


func unload_chunk(grid_map: GridMap, chunk_coord: Vector2i) -> void:
	loaded_chunks.erase(chunk_coord)

	# Xóa terrain cells khỏi GridMap
	var rendered_cells: Array = rendered_cells_by_chunk.get(chunk_coord, [])
	for cell in rendered_cells:
		grid_map.set_cell_item(cell, GridMap.INVALID_CELL_ITEM)
	rendered_cells_by_chunk.erase(chunk_coord)

	# Xóa saved cells khỏi GridMap (giữ nguyên dictionary để load lại)
	var saved_cells: Dictionary = saved_cells_by_chunk.get(chunk_coord, {})
	for cell in saved_cells.keys():
		grid_map.set_cell_item(cell, GridMap.INVALID_CELL_ITEM)

	# Despawn cây
	if _tree_spawner != null:
		_tree_spawner.despawn_trees_for_chunk(chunk_coord)


func set_runtime_cell(grid_map: GridMap, cell: Vector3i, item_id: int) -> void:
	var chunk_coord := TerrainUtils.chunk_coord_for_cell(cell.x, cell.z, _cfg.chunk_size)
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


func get_surface_cell(world_x: int, world_z: int) -> Vector3i:
	var terrain := _sampler.sample_terrain(world_x, world_z)
	return Vector3i(world_x, int(terrain["surface_y"]), world_z)


func get_saved_cell_count() -> int:
	var count := 0
	for saved_cells in saved_cells_by_chunk.values():
		count += saved_cells.size()
	return count


# ---------------------------------------------------------------------------
# Private
# ---------------------------------------------------------------------------

# Trả về Dictionary { "cells": Array[Vector3i], "tree_cell": Vector3i }
# tree_cell = Vector3i.ZERO nếu không có cây (để tránh allocate thêm Array)
func _render_terrain_column(grid_map: GridMap, world_x: int, world_z: int) -> Dictionary:
	
	var rendered_cells: Array[Vector3i] = []
	var terrain := _sampler.sample_terrain(world_x, world_z)
	var surface_y: int = terrain["surface_y"]
	var surface_item: int = terrain["surface_item"]
	var tree_cell := Vector3i.ZERO

	var surface_cell := Vector3i(world_x, surface_y, world_z)
	grid_map.set_cell_item(surface_cell, surface_item)
	rendered_cells.append(surface_cell)

	for cell in _get_exposed_cliff_cells(world_x, world_z, surface_y):
		var item_id := _cfg.stone_item if cell.y < surface_y - 1 else _cfg.dirt_item
		grid_map.set_cell_item(cell, item_id)
		rendered_cells.append(cell)

	if terrain["has_water"]:
		var water_cell := Vector3i(world_x, _cfg.water_level, world_z)
		grid_map.set_cell_item(water_cell, _cfg.water_item)
		rendered_cells.append(water_cell)

	if terrain["has_tree"]:
		var tc := Vector3i(world_x, surface_y + 1, world_z)
		if _tree_spawner != null:
			print("DEBUG: Đã tìm thấy cây tại ", tc, " - Gọi TreeSpawner!") # Dòng này quan trọng
			tree_cell = tc
		else:
			print("DEBUG: Có cây nhưng _tree_spawner là NULL!") # Dòng này sẽ chỉ rõ lỗi injection
			grid_map.set_cell_item(tc, _cfg.tree_item)
			rendered_cells.append(tc)

	return {"cells": rendered_cells, "tree_cell": tree_cell}


func _get_exposed_cliff_cells(world_x: int, world_z: int, surface_y: int) -> Array[Vector3i]:
	var cells_by_key := {}
	var neighbor_offsets := [
		Vector2i.LEFT,
		Vector2i.RIGHT,
		Vector2i.UP,
		Vector2i.DOWN,
	]

	for offset in neighbor_offsets:
		var neighbor := _sampler.sample_terrain(world_x + offset.x, world_z + offset.y)
		var neighbor_y: int = neighbor["surface_y"]
		if neighbor_y >= surface_y - 1:
			continue

		var lowest_y := maxi(neighbor_y + 1, surface_y - _cfg.max_visible_cliff_depth)
		for y in range(lowest_y, surface_y):
			var cell := Vector3i(world_x, y, world_z)
			cells_by_key[cell] = cell

	var exposed_cells: Array[Vector3i] = []
	for cell in cells_by_key.values():
		exposed_cells.append(cell)

	return exposed_cells
