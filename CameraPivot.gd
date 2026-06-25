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
@export var follow_terrain_height := true
@export var terrain_grid_path: NodePath = ^"../GridMap"
@export var terrain_height_offset := 2.0
@export var terrain_height_lerp_speed := 8.0
@export var terrain_sample_min_y := 0
@export var terrain_sample_max_y := 32

@onready var camera = $Camera3D
@onready var terrain_grid: GridMap = get_node_or_null(terrain_grid_path)

var is_rotating_with_mouse := false

func _ready():
	camera.current = true
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = clamp(camera.size, min_zoom, max_zoom)
	_update_camera_transform()

func _process(delta):
	var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var key_dir := Vector2.ZERO

	if Input.is_key_pressed(KEY_D):
		key_dir.x += 1.0
	if Input.is_key_pressed(KEY_A):
		key_dir.x -= 1.0
	if Input.is_key_pressed(KEY_S):
		key_dir.y += 1.0
	if Input.is_key_pressed(KEY_W):
		key_dir.y -= 1.0

	input_dir += key_dir
	if input_dir.length() > 1.0:
		input_dir = input_dir.normalized()

	var yaw_basis = Basis(Vector3.UP, deg_to_rad(yaw_degrees))
	var right = yaw_basis.x
	var forward = -yaw_basis.z
	var move_direction = (right * input_dir.x + forward * -input_dir.y).normalized()
	position += move_direction * move_speed * delta
	_update_terrain_height(delta)

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
