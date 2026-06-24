extends GridMap

@export var ground_size_x := 24
@export var ground_size_z := 24
@export var max_build_height := 16
@export var regenerate_ground_on_ready := true

@export_enum("Solid", "Checker", "Noise") var ground_generation_mode := 0
@export var generation_seed := 12345
@export_range(0.01, 1.0, 0.01) var noise_frequency := 0.12
@export_range(-1.0, 1.0, 0.01) var noise_cutoff := 0.2

@export var ground_item := 6
@export var alternate_ground_item := 7
@export var noise_ground_item := 8
@export var block_item := 5
@export var allow_side_face_placement := false
@export var max_raycast_steps := 512
@export var raycast_epsilon := 0.0001

@export var valid_preview_color := Color(0.15, 0.85, 1.0, 0.35)
@export var blocked_preview_color := Color(1.0, 0.2, 0.1, 0.35)
@export var footprint_color := Color(1.0, 1.0, 1.0, 0.45)

var preview: MeshInstance3D
var preview_material: StandardMaterial3D
var footprint_preview: MeshInstance3D
var footprint_material: StandardMaterial3D
var terrain_noise := FastNoiseLite.new()


func _ready():
	cell_size = Vector3.ONE
	terrain_noise.seed = generation_seed
	terrain_noise.frequency = noise_frequency
	_create_preview()

	if regenerate_ground_on_ready:
		clear()
		_generate_ground()


func _process(_delta):
	_update_preview()


func _unhandled_input(event):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MouseButton.MOUSE_BUTTON_LEFT:
			place_block_at_mouse(event.position)
			get_viewport().set_input_as_handled()
		elif event.button_index == MouseButton.MOUSE_BUTTON_MIDDLE:
			delete_block_at_mouse(event.position)
			get_viewport().set_input_as_handled()

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_X or event.keycode == KEY_DELETE:
			delete_block_at_mouse()
			get_viewport().set_input_as_handled()


func place_block_at_mouse(mouse_position: Vector2 = Vector2(-1.0, -1.0)):
	var target := _get_mouse_target(mouse_position)
	if target.is_empty():
		return

	var cell: Vector3i = target["place_cell"]
	if _can_place_block(cell):
		set_cell_item(cell, block_item)


func delete_block_at_mouse(mouse_position: Vector2 = Vector2(-1.0, -1.0)):
	var target := _get_mouse_target(mouse_position)
	if target.is_empty():
		return

	var cell: Vector3i = target["delete_cell"]
	if cell.y > 0:
		set_cell_item(cell, INVALID_CELL_ITEM)


func _generate_ground():
	var min_x := -floori(ground_size_x * 0.5)
	var min_z := -floori(ground_size_z * 0.5)
	var max_x := min_x + ground_size_x
	var max_z := min_z + ground_size_z

	for x in range(min_x, max_x):
		for z in range(min_z, max_z):
			set_cell_item(Vector3i(x, 0, z), _choose_ground_item(x, z))


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


func _update_preview():
	var target := _get_mouse_target()
	if target.is_empty():
		preview.visible = false
		footprint_preview.visible = false
		return

	var cell: Vector3i = target["place_cell"]
	var can_place := _can_place_block(cell)

	preview.visible = true
	preview.position = _get_block_visual_center(cell)
	preview_material.albedo_color = valid_preview_color if can_place else blocked_preview_color

	footprint_preview.visible = true
	footprint_preview.position = map_to_local(Vector3i(cell.x, 0, cell.z)) + Vector3(0.0, 0.025, 0.0)
	footprint_material.albedo_color = footprint_color if can_place else blocked_preview_color


func _get_mouse_target(mouse_position: Vector2 = Vector2(-1.0, -1.0)) -> Dictionary:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return {}

	var viewport_mouse_position := mouse_position
	if viewport_mouse_position.x < 0.0 or viewport_mouse_position.y < 0.0:
		viewport_mouse_position = get_viewport().get_mouse_position()

	var ray_origin_world := camera.project_ray_origin(viewport_mouse_position)
	var ray_direction_world := camera.project_ray_normal(viewport_mouse_position)
	var ray_origin := to_local(ray_origin_world)
	var ray_direction := (global_transform.basis.inverse() * ray_direction_world).normalized()

	var ground_hit = _intersect_ground_plane(ray_origin, ray_direction)
	var max_distance := INF
	if ground_hit != null:
		max_distance = ray_origin.distance_to(ground_hit) + cell_size.length()

	var block_hit := _raycast_blocks(ray_origin, ray_direction, max_distance)

	if not block_hit.is_empty():
		var hit_cell: Vector3i = block_hit["cell"]
		var hit_normal: Vector3i = block_hit["normal"]
		var is_top_face := hit_normal == Vector3i.UP

		var place_cell := hit_cell + hit_normal
		if not is_top_face and not allow_side_face_placement:
			place_cell = Vector3i(hit_cell.x, _get_top_block_y(hit_cell.x, hit_cell.z) + 1, hit_cell.z)

		return {
			"place_cell": place_cell,
			"delete_cell": hit_cell,
		}

	if ground_hit == null:
		return {}

	var ground_cell := _point_to_ground_cell(ground_hit)
	if not _has_ground(ground_cell.x, ground_cell.z):
		return {}

	return {
		"place_cell": Vector3i(ground_cell.x, 1, ground_cell.z),
		"delete_cell": Vector3i(ground_cell.x, _get_top_block_y(ground_cell.x, ground_cell.z), ground_cell.z),
	}


func _raycast_blocks(ray_origin: Vector3, ray_direction: Vector3, max_distance: float) -> Dictionary:
	if ray_direction == Vector3.ZERO:
		return {}

	var ray_start := ray_origin + ray_direction * raycast_epsilon
	var cell := _point_to_build_cell(ray_start)
	var distance := 0.0
	var step := Vector3i(
		_sign_nonzero(ray_direction.x),
		_sign_nonzero(ray_direction.y),
		_sign_nonzero(ray_direction.z)
	)

	var next_x := _next_x_boundary(cell.x, step.x)
	var next_y := _next_y_boundary(cell.y, step.y)
	var next_z := _next_z_boundary(cell.z, step.z)

	var t_max_x := _axis_distance(ray_start.x, ray_direction.x, next_x)
	var t_max_y := _axis_distance(ray_start.y, ray_direction.y, next_y)
	var t_max_z := _axis_distance(ray_start.z, ray_direction.z, next_z)
	var t_delta_x := _axis_step_distance(ray_direction.x, cell_size.x)
	var t_delta_y := _axis_step_distance(ray_direction.y, cell_size.y)
	var t_delta_z := _axis_step_distance(ray_direction.z, cell_size.z)

	for _i in range(max_raycast_steps):
		if distance > max_distance:
			break

		if _is_build_block_cell(cell):
			var aabb := _get_block_aabb(cell)
			var hit = aabb.intersects_ray(ray_origin, ray_direction)
			if hit != null:
				var hit_distance := ray_origin.distance_to(hit)
				if hit_distance <= max_distance + raycast_epsilon:
					return {
						"cell": cell,
						"normal": _get_aabb_hit_normal(aabb, hit),
						"distance_sq": ray_origin.distance_squared_to(hit),
					}

		if t_max_x <= t_max_y and t_max_x <= t_max_z:
			distance = t_max_x
			t_max_x += t_delta_x
			cell.x += step.x
		elif t_max_y <= t_max_z:
			distance = t_max_y
			t_max_y += t_delta_y
			cell.y += step.y
		else:
			distance = t_max_z
			t_max_z += t_delta_z
			cell.z += step.z

	return {}


func _intersect_ground_plane(ray_origin: Vector3, ray_direction: Vector3):
	if absf(ray_direction.y) < 0.0001:
		return null

	var distance := -ray_origin.y / ray_direction.y
	if distance < 0.0:
		return null

	return ray_origin + ray_direction * distance


func _point_to_ground_cell(point: Vector3) -> Vector3i:
	return Vector3i(
		floori(point.x / cell_size.x + 0.5),
		0,
		floori(point.z / cell_size.z + 0.5)
	)


func _point_to_build_cell(point: Vector3) -> Vector3i:
	return Vector3i(
		floori(point.x / cell_size.x + 0.5),
		floori(point.y / cell_size.y) + 1,
		floori(point.z / cell_size.z + 0.5)
	)


func _get_top_block_y(x: int, z: int) -> int:
	var top_y := 0

	for y in range(1, max_build_height + 1):
		if get_cell_item(Vector3i(x, y, z)) != INVALID_CELL_ITEM:
			top_y = y

	return top_y


func _can_place_block(cell: Vector3i) -> bool:
	return (
		cell.y > 0
		and cell.y <= max_build_height
		and _has_ground(cell.x, cell.z)
		and get_cell_item(cell) == INVALID_CELL_ITEM
		and _has_support(cell)
	)


func _has_support(cell: Vector3i) -> bool:
	if cell.y == 1:
		return _has_ground(cell.x, cell.z)

	return get_cell_item(cell + Vector3i.DOWN) != INVALID_CELL_ITEM


func _has_ground(x: int, z: int) -> bool:
	return get_cell_item(Vector3i(x, 0, z)) != INVALID_CELL_ITEM


func _is_build_block_cell(cell: Vector3i) -> bool:
	return (
		cell.y > 0
		and cell.y <= max_build_height
		and get_cell_item(cell) != INVALID_CELL_ITEM
	)


func _get_block_aabb(cell: Vector3i) -> AABB:
	var center := _get_block_visual_center(cell)
	var half_size := cell_size * 0.5
	return AABB(center - half_size, cell_size)


func _get_aabb_hit_normal(aabb: AABB, hit_position: Vector3) -> Vector3i:
	var local_hit := hit_position - aabb.get_center()
	var extents := aabb.size * 0.5
	var x_distance := absf(absf(local_hit.x) - extents.x)
	var y_distance := absf(absf(local_hit.y) - extents.y)
	var z_distance := absf(absf(local_hit.z) - extents.z)

	if y_distance <= x_distance and y_distance <= z_distance:
		return Vector3i.UP if local_hit.y >= 0.0 else Vector3i.DOWN
	if x_distance <= z_distance:
		return Vector3i.RIGHT if local_hit.x >= 0.0 else Vector3i.LEFT
	return Vector3i.BACK if local_hit.z >= 0.0 else Vector3i.FORWARD


func _get_block_visual_center(cell: Vector3i) -> Vector3:
	return map_to_local(cell) + Vector3(0.0, -cell_size.y * 0.5, 0.0)


func _sign_nonzero(value: float) -> int:
	if value < 0.0:
		return -1
	return 1


func _axis_distance(origin: float, direction: float, boundary: float) -> float:
	if absf(direction) < 0.000001:
		return INF
	return maxf((boundary - origin) / direction, 0.0)


func _axis_step_distance(direction: float, size: float) -> float:
	if absf(direction) < 0.000001:
		return INF
	return absf(size / direction)


func _next_x_boundary(cell_x: int, step_x: int) -> float:
	if step_x > 0:
		return (float(cell_x) + 0.5) * cell_size.x
	return (float(cell_x) - 0.5) * cell_size.x


func _next_y_boundary(cell_y: int, step_y: int) -> float:
	if step_y > 0:
		return float(cell_y) * cell_size.y
	return float(cell_y - 1) * cell_size.y


func _next_z_boundary(cell_z: int, step_z: int) -> float:
	if step_z > 0:
		return (float(cell_z) + 0.5) * cell_size.z
	return (float(cell_z) - 0.5) * cell_size.z


func _create_preview():
	preview = MeshInstance3D.new()
	preview.name = "BuildPreview"

	var box := BoxMesh.new()
	box.size = cell_size
	preview.mesh = box

	preview_material = StandardMaterial3D.new()
	preview_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	preview_material.albedo_color = valid_preview_color
	preview_material.no_depth_test = false
	preview.material_override = preview_material

	preview.visible = false
	add_child(preview)

	footprint_preview = MeshInstance3D.new()
	footprint_preview.name = "FootprintPreview"

	var footprint := BoxMesh.new()
	footprint.size = Vector3(cell_size.x * 0.96, 0.02, cell_size.z * 0.96)
	footprint_preview.mesh = footprint

	footprint_material = StandardMaterial3D.new()
	footprint_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	footprint_material.albedo_color = footprint_color
	footprint_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	footprint_preview.material_override = footprint_material

	footprint_preview.visible = false
	add_child(footprint_preview)
