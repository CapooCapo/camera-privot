extends Node3D

@export var move_speed := 10.0
@export var zoom_speed := 1.5
@export var rotate_speed := 90.0
@export var pitch_speed := 60.0
@export var mouse_rotate_sensitivity := 0.15

@export_range(20.0, 85.0, 1.0) var min_pitch_degrees := 35.0
@export_range(20.0, 85.0, 1.0) var max_pitch_degrees := 72.0
@export_range(2.0, 40.0, 0.5) var camera_distance := 14.0
@export_range(2.0, 30.0, 0.5) var min_zoom := 4.0
@export_range(2.0, 30.0, 0.5) var max_zoom := 18.0

@export var yaw_degrees := 45.0
@export var pitch_degrees := 55.0
@export var follow_target_path: NodePath = ^"../Player"
@export var build_grid_path: NodePath = ^"../BuildGrid"
@export var follow_target_height_offset := 1.5
@export var follow_lerp_speed := 12.0
@export var build_pan_radius := 10.0
@export var follow_terrain_height := true
@export var terrain_grid_path: NodePath = ^"../GridMap"
@export var terrain_height_offset := 2.0
@export var terrain_height_lerp_speed := 8.0
@export var terrain_sample_min_y := 0
@export var terrain_sample_max_y := 32
@export var hide_mouse_during_gameplay := true
@export var show_mouse_key := KEY_ALT

@onready var camera = $Camera3D
@onready var follow_target: Node3D = get_node_or_null(follow_target_path)
@onready var build_grid: Node = get_node_or_null(build_grid_path)
@onready var terrain_grid: GridMap = get_node_or_null(terrain_grid_path)

var is_rotating_with_mouse := false
var build_pan_offset := Vector3.ZERO

func _ready():
	camera.current = true
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = clamp(camera.size, min_zoom, max_zoom)
	_update_mouse_visibility()
	_update_follow_position(0.0)
	_update_camera_transform()

func _process(delta):
	_update_mouse_visibility()

	if _is_build_mode_enabled():
		_update_build_pan_offset(delta)
	else:
		build_pan_offset = Vector3.ZERO

	var yaw_input := 0
	var pitch_input := 0

	if Input.is_key_pressed(KEY_E):
		yaw_input += 1
	if Input.is_key_pressed(KEY_Q):
		yaw_input -= 1
	if Input.is_key_pressed(KEY_R):
		pitch_input += 1
	if Input.is_key_pressed(KEY_F):
		pitch_input -= 1

	if yaw_input != 0:
		yaw_degrees += yaw_input * rotate_speed * delta
	if pitch_input != 0:
		pitch_degrees = clamp(
			pitch_degrees + pitch_input * pitch_speed * delta,
			min_pitch_degrees,
			max_pitch_degrees
		)

	if yaw_input != 0 or pitch_input != 0:
		_update_camera_transform()

	_update_follow_position(delta)

func _unhandled_input(event):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MouseButton.MOUSE_BUTTON_WHEEL_UP:
			camera.size = clamp(camera.size - zoom_speed, min_zoom, max_zoom)
		elif event.button_index == MouseButton.MOUSE_BUTTON_WHEEL_DOWN:
			camera.size = clamp(camera.size + zoom_speed, min_zoom, max_zoom)

	if event is InputEventMouseButton and event.button_index == MouseButton.MOUSE_BUTTON_RIGHT:
		is_rotating_with_mouse = event.pressed

	if event is InputEventMouseMotion and is_rotating_with_mouse:
		yaw_degrees -= event.relative.x * mouse_rotate_sensitivity
		pitch_degrees = clamp(
			pitch_degrees - event.relative.y * mouse_rotate_sensitivity,
			min_pitch_degrees,
			max_pitch_degrees
		)
		_update_camera_transform()

func _update_camera_transform():
	pitch_degrees = clamp(pitch_degrees, min_pitch_degrees, max_pitch_degrees)
	rotation.y = deg_to_rad(yaw_degrees)

	var pitch_radians = deg_to_rad(pitch_degrees)
	camera.position = Vector3(
		0.0,
		sin(pitch_radians) * camera_distance,
		cos(pitch_radians) * camera_distance
	)
	camera.look_at(global_position, Vector3.UP)


func _update_build_pan_offset(delta: float):
	var input_dir := _get_pan_input()
	if input_dir == Vector2.ZERO:
		return

	var yaw_basis := Basis(Vector3.UP, deg_to_rad(yaw_degrees))
	var right := yaw_basis.x
	var forward := -yaw_basis.z
	var move_direction := right * input_dir.x + forward * -input_dir.y
	if move_direction.length_squared() <= 0.0001:
		return

	build_pan_offset += move_direction.normalized() * move_speed * delta
	build_pan_offset.y = 0.0
	if build_pan_offset.length() > build_pan_radius:
		build_pan_offset = build_pan_offset.normalized() * build_pan_radius


func _get_pan_input() -> Vector2:
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


func _update_follow_position(delta: float):
	if follow_target == null:
		follow_target = get_node_or_null(follow_target_path)

	if follow_target != null:
		var target_position := follow_target.global_position
		target_position.y += follow_target_height_offset
		target_position += build_pan_offset

		var follow_weight := 1.0 if delta <= 0.0 else clampf(delta * follow_lerp_speed, 0.0, 1.0)
		global_position = global_position.lerp(target_position, follow_weight)
		_update_camera_transform()
		return

	_update_terrain_height(delta)


func _update_terrain_height(delta: float):
	if not follow_terrain_height or terrain_grid == null:
		return

	var local_position := terrain_grid.to_local(global_position)
	var cell := terrain_grid.local_to_map(local_position)
	var top_y := _get_top_terrain_y(cell.x, cell.z)
	if top_y < terrain_sample_min_y:
		return

	var target_local := terrain_grid.map_to_local(Vector3i(cell.x, top_y, cell.z))
	var target_world_y := terrain_grid.to_global(target_local).y + terrain_height_offset
	position.y = lerpf(
		position.y,
		target_world_y,
		clampf(delta * terrain_height_lerp_speed, 0.0, 1.0)
	)
	_update_camera_transform()


func _get_top_terrain_y(cell_x: int, cell_z: int) -> int:
	var top_y := terrain_sample_min_y - 1

	for y in range(terrain_sample_min_y, terrain_sample_max_y + 1):
		if terrain_grid.get_cell_item(Vector3i(cell_x, y, cell_z)) != GridMap.INVALID_CELL_ITEM:
			top_y = y

	return top_y


func _update_mouse_visibility():
	if not hide_mouse_during_gameplay:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return

	Input.mouse_mode = (
		Input.MOUSE_MODE_VISIBLE
		if Input.is_key_pressed(show_mouse_key)
		else Input.MOUSE_MODE_HIDDEN
	)


func _is_build_mode_enabled() -> bool:
	if build_grid == null:
		build_grid = get_node_or_null(build_grid_path)
	if build_grid == null or not build_grid.has_method("is_build_mode_enabled"):
		return false

	return build_grid.is_build_mode_enabled()
