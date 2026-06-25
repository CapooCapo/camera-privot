class_name GridTargeting
extends Node

@export var allow_side_face_placement := true
@export var raycast_epsilon := 0.0001
@export var ground_pick_y_offset := 0.0
@export var ray_march_step := 0.2
@export var max_raycast_distance := 128.0


func get_mouse_target(
	grid_map: GridMap,
	placement_rules: Node,
	mouse_position: Vector2 = Vector2(-1.0, -1.0)
) -> Dictionary:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return {}

	var viewport_mouse_position := mouse_position
	if viewport_mouse_position.x < 0.0 or viewport_mouse_position.y < 0.0:
		viewport_mouse_position = get_viewport().get_mouse_position()

	var ray_origin_world := camera.project_ray_origin(viewport_mouse_position)
	var ray_direction_world := camera.project_ray_normal(viewport_mouse_position)
	var ray_origin := grid_map.to_local(ray_origin_world)
	var ray_direction := (grid_map.global_transform.basis.inverse() * ray_direction_world).normalized()

	var ground_hit = _intersect_ground_plane(
		ray_origin,
		ray_direction,
		_get_ground_pick_y(grid_map)
	)
	var max_distance := INF
	if ground_hit != null:
		max_distance = ray_origin.distance_to(ground_hit) + grid_map.cell_size.length() * 16.0

	var block_hit := _raycast_occupied_cells(grid_map, placement_rules, ray_origin, ray_direction, max_distance)

	if not block_hit.is_empty():
		var hit_cell := Vector3i(block_hit["cell"])
		var hit_normal := Vector3i(block_hit["normal"])
		var is_top_face := hit_normal == Vector3i.UP
		var is_build_block: bool = placement_rules.is_build_block_cell(grid_map, hit_cell)

		var place_cell := Vector3i(
			hit_cell.x,
			placement_rules.get_top_occupied_y(grid_map, hit_cell.x, hit_cell.z) + 1,
			hit_cell.z
		)
		if is_build_block and (is_top_face or allow_side_face_placement):
			place_cell = hit_cell + hit_normal
		elif is_build_block and not is_top_face and not allow_side_face_placement:
			place_cell = Vector3i(
				hit_cell.x,
				placement_rules.get_top_block_y(grid_map, hit_cell.x, hit_cell.z) + 1,
				hit_cell.z
			)

		return {
			"place_cell": place_cell,
			"delete_cell": hit_cell,
		}

	if ground_hit == null:
		return {}

	var ground_cell := _point_to_ground_cell(grid_map, ground_hit)
	if not placement_rules.has_ground(grid_map, ground_cell.x, ground_cell.z):
		return {}

	return {
		"place_cell": Vector3i(
			ground_cell.x,
			placement_rules.get_top_occupied_y(grid_map, ground_cell.x, ground_cell.z) + 1,
			ground_cell.z
		),
		"delete_cell": Vector3i(
			ground_cell.x,
			placement_rules.get_top_block_y(grid_map, ground_cell.x, ground_cell.z),
			ground_cell.z
		),
	}


func _raycast_occupied_cells(
	grid_map: GridMap,
	placement_rules: Node,
	ray_origin: Vector3,
	ray_direction: Vector3,
	max_distance: float
) -> Dictionary:
	if ray_direction == Vector3.ZERO:
		return {}

	var march_distance = minf(max_distance, max_raycast_distance)
	if is_inf(march_distance):
		march_distance = max_raycast_distance

	var previous_cell := grid_map.local_to_map(ray_origin)
	var distance := 0.0

	while distance <= march_distance:
		var point := ray_origin + ray_direction * distance
		var cell := grid_map.local_to_map(point)

		if grid_map.get_cell_item(cell) != GridMap.INVALID_CELL_ITEM:
			var normal := _normal_from_entered_cell(previous_cell, cell)
			if normal == Vector3i.ZERO:
				normal = Vector3i.UP

			return {
				"cell": cell,
				"normal": normal,
				"distance_sq": distance * distance,
			}

		previous_cell = cell
		distance += ray_march_step

	return {}


func _normal_from_entered_cell(previous_cell: Vector3i, current_cell: Vector3i) -> Vector3i:
	var delta := previous_cell - current_cell
	if delta == Vector3i.ZERO:
		return Vector3i.ZERO

	if absi(delta.x) >= absi(delta.y) and absi(delta.x) >= absi(delta.z):
		return Vector3i(signi(delta.x), 0, 0)
	if absi(delta.y) >= absi(delta.z):
		return Vector3i(0, signi(delta.y), 0)

	return Vector3i(0, 0, signi(delta.z))


func signi(value: int) -> int:
	if value > 0:
		return 1
	if value < 0:
		return -1
	return 0


func _intersect_ground_plane(ray_origin: Vector3, ray_direction: Vector3, plane_y: float):
	if absf(ray_direction.y) < 0.0001:
		return null

	var distance := (plane_y - ray_origin.y) / ray_direction.y
	if distance < 0.0:
		return null

	return ray_origin + ray_direction * distance


func _point_to_ground_cell(grid_map: GridMap, point: Vector3) -> Vector3i:
	var cell := grid_map.local_to_map(point)
	return Vector3i(cell.x, 0, cell.z)


func _get_ground_pick_y(grid_map: GridMap) -> float:
	return grid_map.map_to_local(Vector3i.ZERO).y + ground_pick_y_offset


func _ray_intersects_cell_aabb(ray_origin: Vector3, ray_direction: Vector3, aabb: AABB) -> Dictionary:
	var min_point := aabb.position
	var max_point := aabb.position + aabb.size
	var enter_distance := -INF
	var exit_distance := INF
	var enter_normal := Vector3i.ZERO
	var exit_normal := Vector3i.ZERO

	var x_result := _intersect_axis(
		ray_origin.x,
		ray_direction.x,
		min_point.x,
		max_point.x,
		Vector3i.LEFT,
		Vector3i.RIGHT
	)
	if x_result.is_empty():
		return {}
	enter_distance = float(x_result["enter_distance"])
	exit_distance = float(x_result["exit_distance"])
	enter_normal = Vector3i(x_result["enter_normal"])
	exit_normal = Vector3i(x_result["exit_normal"])

	var y_result := _intersect_axis(
		ray_origin.y,
		ray_direction.y,
		min_point.y,
		max_point.y,
		Vector3i.DOWN,
		Vector3i.UP
	)
	if y_result.is_empty():
		return {}
	var y_enter_distance := float(y_result["enter_distance"])
	var y_exit_distance := float(y_result["exit_distance"])
	if y_enter_distance > enter_distance:
		enter_distance = y_enter_distance
		enter_normal = Vector3i(y_result["enter_normal"])
	if y_exit_distance < exit_distance:
		exit_distance = y_exit_distance
		exit_normal = Vector3i(y_result["exit_normal"])

	var z_result := _intersect_axis(
		ray_origin.z,
		ray_direction.z,
		min_point.z,
		max_point.z,
		Vector3i.FORWARD,
		Vector3i.BACK
	)
	if z_result.is_empty():
		return {}
	var z_enter_distance := float(z_result["enter_distance"])
	var z_exit_distance := float(z_result["exit_distance"])
	if z_enter_distance > enter_distance:
		enter_distance = z_enter_distance
		enter_normal = Vector3i(z_result["enter_normal"])
	if z_exit_distance < exit_distance:
		exit_distance = z_exit_distance
		exit_normal = Vector3i(z_result["exit_normal"])

	if enter_distance > exit_distance or exit_distance < 0.0:
		return {}

	if enter_distance >= 0.0:
		return {
			"distance": enter_distance,
			"normal": enter_normal,
		}

	return {
		"distance": 0.0,
		"normal": exit_normal,
	}


func _intersect_axis(
	origin: float,
	direction: float,
	min_value: float,
	max_value: float,
	min_normal: Vector3i,
	max_normal: Vector3i
) -> Dictionary:
	if absf(direction) < 0.000001:
		if origin < min_value or origin > max_value:
			return {}
		return {
			"enter_distance": -INF,
			"exit_distance": INF,
			"enter_normal": Vector3i.ZERO,
			"exit_normal": Vector3i.ZERO,
		}

	var min_distance := (min_value - origin) / direction
	var max_distance := (max_value - origin) / direction

	if min_distance <= max_distance:
		return {
			"enter_distance": min_distance,
			"exit_distance": max_distance,
			"enter_normal": min_normal,
			"exit_normal": max_normal,
		}

	return {
		"enter_distance": max_distance,
		"exit_distance": min_distance,
		"enter_normal": max_normal,
		"exit_normal": min_normal,
	}
