class_name GridPlacementRules
extends Node

@export var max_build_height := 16
@export var block_item := 5
@export var require_ground_under_blocks := false
@export var require_block_support := false


func can_place_block(grid_map: GridMap, cell: Vector3i) -> bool:
	if cell.y <= 0 or cell.y > max_build_height:
		return false
	if grid_map.get_cell_item(cell) != GridMap.INVALID_CELL_ITEM:
		return false
	if require_ground_under_blocks and not has_ground(grid_map, cell.x, cell.z):
		return false
	if require_block_support and not has_support(grid_map, cell):
		return false

	return true


func has_support(grid_map: GridMap, cell: Vector3i) -> bool:
	return grid_map.get_cell_item(cell + Vector3i.DOWN) != GridMap.INVALID_CELL_ITEM


func has_ground(grid_map: GridMap, x: int, z: int) -> bool:
	return get_top_occupied_y(grid_map, x, z) != -1


func is_build_block_cell(grid_map: GridMap, cell: Vector3i) -> bool:
	return (
		cell.y > 0
		and cell.y <= max_build_height
		and grid_map.get_cell_item(cell) == block_item
	)


func get_top_block_y(grid_map: GridMap, x: int, z: int) -> int:
	var top_y := 0

	for y in range(1, max_build_height + 1):
		if grid_map.get_cell_item(Vector3i(x, y, z)) == block_item:
			top_y = y

	return top_y


func get_top_occupied_y(grid_map: GridMap, x: int, z: int) -> int:
	var top_y := -1

	for y in range(0, max_build_height + 1):
		if grid_map.get_cell_item(Vector3i(x, y, z)) != GridMap.INVALID_CELL_ITEM:
			top_y = y

	return top_y


func get_block_visual_center(grid_map: GridMap, cell: Vector3i) -> Vector3:
	return grid_map.map_to_local(cell) + Vector3(0.0, -grid_map.cell_size.y * 0.5, 0.0)


func get_block_aabb(grid_map: GridMap, cell: Vector3i) -> AABB:
	var center := get_block_visual_center(grid_map, cell)
	var half_size := grid_map.cell_size * 0.5
	return AABB(center - half_size, grid_map.cell_size)
