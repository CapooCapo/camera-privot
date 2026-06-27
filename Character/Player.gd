extends CharacterBody3D

@export var move_speed := 5.0
@export var acceleration := 18.0
@export var rotation_speed := 12.0
@export var surface_snap_speed := 24.0
@export var surface_height_offset := 0.0
@export var min_surface_y := -16
@export var max_surface_y := 48
@export var disable_movement_in_build_mode := true
@export var grid_map_path: NodePath = ^"../GridMap"
@export var camera_pivot_path: NodePath = ^"../CameraPivot"
@export var build_grid_path: NodePath = ^"../BuildGrid"
@export var visual_root_path: NodePath = ^"Node3D"
@export var walkable_items: Array[int] = [5, 6, 7, 8, 9]

@onready var grid_map: GridMap = get_node_or_null(grid_map_path)
@onready var camera_pivot: Node3D = get_node_or_null(camera_pivot_path)
@onready var build_grid: Node = get_node_or_null(build_grid_path)
@onready var visual_root: Node3D = get_node_or_null(visual_root_path)


func _ready():
	_snap_to_surface(1.0)


func _physics_process(delta):
	var input_dir := _get_move_input()
	if disable_movement_in_build_mode and _is_build_mode_enabled():
		input_dir = Vector2.ZERO

	var move_direction := _get_camera_relative_direction(input_dir)
	var target_velocity := move_direction * move_speed
	velocity.x = move_toward(velocity.x, target_velocity.x, acceleration * delta)
	velocity.y = 0.0
	velocity.z = move_toward(velocity.z, target_velocity.z, acceleration * delta)

	move_and_slide()
	_snap_to_surface(delta)
	_update_visual_rotation(move_direction, delta)


func _get_move_input() -> Vector2:
	var input_dir := Vector2.ZERO

	if Input.is_key_pressed(KEY_D):
		input_dir.x += 1.0
	if Input.is_key_pressed(KEY_A):
		input_dir.x -= 1.0
	if Input.is_key_pressed(KEY_S):
		input_dir.y += 1.0
	if Input.is_key_pressed(KEY_W):
		input_dir.y -= 1.0

	return input_dir.normalized() if input_dir.length() > 1.0 else input_dir


func _get_camera_relative_direction(input_dir: Vector2) -> Vector3:
	if input_dir == Vector2.ZERO:
		return Vector3.ZERO

	if camera_pivot == null:
		camera_pivot = get_node_or_null(camera_pivot_path)

	var right := Vector3.RIGHT
	var forward := Vector3.FORWARD
	if camera_pivot != null:
		right = camera_pivot.global_transform.basis.x
		forward = -camera_pivot.global_transform.basis.z

	right.y = 0.0
	forward.y = 0.0
	right = right.normalized()
	forward = forward.normalized()

	return (right * input_dir.x + forward * -input_dir.y).normalized()


func _snap_to_surface(delta: float):
	if grid_map == null:
		grid_map = get_node_or_null(grid_map_path)
	if grid_map == null:
		return

	var local_position := grid_map.to_local(global_position)
	var cell := grid_map.local_to_map(local_position)
	var surface_y := _get_walkable_surface_y(cell.x, cell.z)
	if surface_y < min_surface_y:
		return

	var surface_local := grid_map.map_to_local(Vector3i(cell.x, surface_y, cell.z))
	var target_world_y := grid_map.to_global(surface_local).y + surface_height_offset
	var snap_weight := 1.0 if delta <= 0.0 else clampf(delta * surface_snap_speed, 0.0, 1.0)
	global_position.y = lerpf(global_position.y, target_world_y, snap_weight)


func _get_walkable_surface_y(cell_x: int, cell_z: int) -> int:
	for y in range(max_surface_y, min_surface_y - 1, -1):
		var item_id := grid_map.get_cell_item(Vector3i(cell_x, y, cell_z))
		if item_id == GridMap.INVALID_CELL_ITEM:
			continue
		if walkable_items.is_empty() or walkable_items.has(item_id):
			return y

	return min_surface_y - 1


func _update_visual_rotation(move_direction: Vector3, delta: float):
	if visual_root == null or move_direction.length_squared() < 0.0001:
		return

	var target_yaw := atan2(move_direction.x, move_direction.z)
	visual_root.rotation.y = lerp_angle(
		visual_root.rotation.y,
		target_yaw,
		clampf(delta * rotation_speed, 0.0, 1.0)
	)


func _is_build_mode_enabled() -> bool:
	if build_grid == null:
		build_grid = get_node_or_null(build_grid_path)
	if build_grid == null or not build_grid.has_method("is_build_mode_enabled"):
		return false

	return build_grid.is_build_mode_enabled()
