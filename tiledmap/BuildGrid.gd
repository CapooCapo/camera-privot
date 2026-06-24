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
@export var allow_side_face_placement := true
@export var require_ground_under_blocks := false
@export var require_block_support := false
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
		var hit_cell := Vector3i(block_hit["cell"])
		var hit_normal := Vector3i(block_hit["normal"])
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

	var best_cell := Vector3i.ZERO
	var best_normal := Vector3i.ZERO
	var best_distance := max_distance + raycast_epsilon
	var has_hit := false

	for cell in get_used_cells():
		if not _is_build_block_cell(cell):
			continue

		var hit := _ray_intersects_cell_aabb(ray_origin, ray_direction, _get_block_aabb(cell))
		if hit.is_empty():
			continue

		var hit_distance := float(hit["distance"])
		if hit_distance < best_distance:
			best_distance = hit_distance
			best_cell = cell
			best_normal = Vector3i(hit["normal"])
			has_hit = true

	if has_hit:
		return {
			"cell": best_cell,
			"normal": best_normal,
			"distance_sq": best_distance * best_distance,
		}

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


func _get_top_block_y(x: int, z: int) -> int:
	var top_y := 0

	for y in range(1, max_build_height + 1):
		if get_cell_item(Vector3i(x, y, z)) != INVALID_CELL_ITEM:
			top_y = y

	return top_y


func _can_place_block(cell: Vector3i) -> bool:
	if cell.y <= 0 or cell.y > max_build_height:
		return false
	if get_cell_item(cell) != INVALID_CELL_ITEM:
		return false
	if require_ground_under_blocks and not _has_ground(cell.x, cell.z):
		return false
	if require_block_support and not _has_support(cell):
		return false

	return true


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


func _get_block_visual_center(cell: Vector3i) -> Vector3:
	return map_to_local(cell) + Vector3(0.0, -cell_size.y * 0.5, 0.0)


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
