@tool
extends CharacterBody3D

@export var move_speed := 5.0
@export var acceleration := 18.0
@export var rotation_speed := 12.0
@export var body_radius := 0.35
@export var body_height := 1.8
@export var max_movement_substep := 0.12
@export var max_step_height := 1.05
@export var ground_snap_up_tolerance := 0.08
@export var ground_snap_down_tolerance := 0.18
@export var gravity := 24.0
@export var terminal_fall_speed := 40.0
@export var surface_height_offset := 0.05
@export var min_surface_y := -16
@export var max_surface_y := 48
@export var disable_movement_in_build_mode := true
@export var grid_map_path: NodePath = ^"../GridMap"
@export var camera_pivot_path: NodePath = ^"../CameraPivot"
@export var build_grid_path: NodePath = ^"../BuildGrid"
@export var visual_root_path: NodePath = ^"Node3D"
@export var animation_player_path: NodePath = ^"AnimationPlayer"
@export var model_root_path: NodePath = ^"Node3D/Man_01_02"
@export var idle_animation := &"Idle_breath"
@export var walk_animation := &"Walk"
@export var animation_blend_time := 0.15
@export var floor_items: Array[int] = [5, 6, 7, 8, 9]
@export var blocking_items: Array[int] = [5, 6, 7, 8, 10]

@onready var grid_map: GridMap = get_node_or_null(grid_map_path)
@onready var camera_pivot: Node3D = get_node_or_null(camera_pivot_path)
@onready var build_grid: Node = get_node_or_null(build_grid_path)
@onready var visual_root: Node3D = get_node_or_null(visual_root_path)
@onready var animation_player: AnimationPlayer = get_node_or_null(animation_player_path)
@onready var model_root: Node = get_node_or_null(model_root_path)

var spawn_snap_pending := true
var vertical_speed := 0.0
var animations_sanitized := false
var resolved_idle_animation := &""
var resolved_walk_animation := &""


func _ready():
	_resolve_nodes()
	_setup_animation_player()
	if Engine.is_editor_hint():
		set_process(true)
		set_physics_process(false)
		return
	_play_animation(resolved_idle_animation)
	_try_snap_to_spawn_surface()


func _process(_delta):
	if Engine.is_editor_hint():
		_resolve_nodes()
		_sanitize_animation_library()
		_resolve_animation_names()


func _physics_process(delta):
	if Engine.is_editor_hint():
		return

	_resolve_nodes()
	if grid_map != null and spawn_snap_pending:
		_try_snap_to_spawn_surface()
		if spawn_snap_pending:
			return

	var input_dir := _get_move_input()
	if disable_movement_in_build_mode and _is_build_mode_enabled():
		input_dir = Vector2.ZERO

	var move_direction := _get_camera_relative_direction(input_dir)
	var target_velocity := move_direction * move_speed
	velocity.x = move_toward(velocity.x, target_velocity.x, acceleration * delta)
	velocity.y = 0.0
	velocity.z = move_toward(velocity.z, target_velocity.z, acceleration * delta)

	if grid_map == null:
		global_position += Vector3(velocity.x, 0.0, velocity.z) * delta
	else:
		var next_position := global_position
		var motion: Vector3 = Vector3(velocity.x, 0.0, velocity.z) * delta
		var substeps := maxi(1, ceili(motion.length() / maxf(max_movement_substep, 0.01)))
		var step_motion: Vector3 = motion / float(substeps)
		for _i in range(substeps):
			next_position = _try_move_axis(next_position, Vector3(step_motion.x, 0.0, 0.0))
			next_position = _try_move_axis(next_position, Vector3(0.0, 0.0, step_motion.z))
		next_position = _apply_vertical_movement(next_position, delta)
		global_position = next_position

	_update_visual_rotation(move_direction, delta)
	_update_animation()


func _resolve_nodes():
	if grid_map == null:
		grid_map = get_node_or_null(grid_map_path)
	if camera_pivot == null:
		camera_pivot = get_node_or_null(camera_pivot_path)
	if build_grid == null:
		build_grid = get_node_or_null(build_grid_path)
	if animation_player == null:
		animation_player = get_node_or_null(animation_player_path)
	if model_root == null:
		model_root = get_node_or_null(model_root_path)


func _setup_animation_player():
	if animation_player == null:
		return

	_sanitize_animation_library()
	_resolve_animation_names()


func _sanitize_animation_library():
	if animations_sanitized and not Engine.is_editor_hint():
		return
	if animation_player == null:
		return
	if model_root == null:
		return

	for animation_name in animation_player.get_animation_list():
		var animation := animation_player.get_animation(animation_name)
		if animation == null:
			continue

		animation.loop_mode = Animation.LOOP_LINEAR
		_sanitize_animation_tracks(animation)

	if not Engine.is_editor_hint():
		animations_sanitized = true


func _resolve_animation_names():
	resolved_idle_animation = _get_existing_animation_name(idle_animation, [&"Idle_breath", &"Idle"])
	resolved_walk_animation = _get_existing_animation_name(walk_animation, [&"Walk", &"walk"])


func _get_existing_animation_name(preferred_name: StringName, fallback_names: Array[StringName]) -> StringName:
	if animation_player == null:
		return &""
	if animation_player.has_animation(preferred_name):
		return preferred_name

	for fallback_name in fallback_names:
		if animation_player.has_animation(fallback_name):
			return fallback_name

	return &""


func _sanitize_animation_tracks(animation: Animation):
	for track_index in range(animation.get_track_count()):
		var track_path := String(animation.track_get_path(track_index))
		var remapped_path := _get_existing_bone_track_path(track_path)
		if remapped_path.is_empty():
			animation.track_set_enabled(track_index, false)
			continue

		if remapped_path != track_path:
			animation.track_set_path(track_index, NodePath(remapped_path))
		animation.track_set_enabled(track_index, true)


func _get_existing_bone_track_path(track_path: String) -> String:
	var separator_index := track_path.find(":")
	if separator_index == -1:
		return ""

	var bone_name := track_path.substr(separator_index + 1)
	if bone_name.is_empty():
		return ""

	var skeleton := _find_skeleton_with_bone(bone_name)
	if skeleton == null:
		return ""

	var skeleton_path := String(model_root.get_path_to(skeleton))
	return "%s:%s" % [skeleton_path, bone_name]


func _find_skeleton_with_bone(bone_name: String) -> Skeleton3D:
	if model_root == null:
		return null

	return _find_skeleton_with_bone_recursive(model_root, bone_name)


func _find_skeleton_with_bone_recursive(node: Node, bone_name: String) -> Skeleton3D:
	if node is Skeleton3D and node.find_bone(bone_name) != -1:
		return node

	for child in node.get_children():
		var skeleton := _find_skeleton_with_bone_recursive(child, bone_name)
		if skeleton != null:
			return skeleton

	return null


func _update_animation():
	if animation_player == null:
		return
	if String(resolved_idle_animation).is_empty() or String(resolved_walk_animation).is_empty():
		_resolve_animation_names()

	var horizontal_speed_sq := velocity.x * velocity.x + velocity.z * velocity.z
	if horizontal_speed_sq > 0.01:
		_play_animation(resolved_walk_animation)
	else:
		_play_animation(resolved_idle_animation)


func _play_animation(animation_name: StringName):
	if String(animation_name).is_empty():
		return
	if animation_player.current_animation == animation_name:
		return
	if not animation_player.has_animation(animation_name):
		return

	animation_player.play(animation_name, animation_blend_time)


func _try_move_axis(current_position: Vector3, axis_delta: Vector3) -> Vector3:
	if axis_delta.length_squared() <= 0.000001:
		return _snap_to_valid_surface(current_position, current_position.y)

	var candidate := current_position + axis_delta
	var surface_y: Variant = _find_surface_y(
		candidate,
		current_position.y,
		max_step_height,
		ground_snap_down_tolerance
	)
	if surface_y != null:
		candidate.y = float(surface_y)

	if not _has_body_clearance(candidate):
		_zero_blocked_velocity(axis_delta)
		return _snap_to_valid_surface(current_position, current_position.y)

	return candidate


func _snap_to_valid_surface(position: Vector3, reference_y: float) -> Vector3:
	var snapped := position
	var surface_y: Variant = _find_surface_y(
		position,
		reference_y,
		ground_snap_up_tolerance,
		ground_snap_down_tolerance
	)
	if surface_y != null and _has_body_clearance(Vector3(position.x, float(surface_y), position.z)):
		snapped.y = float(surface_y)
	return snapped


func _apply_vertical_movement(position: Vector3, delta: float) -> Vector3:
	var grounded_y: Variant = _find_surface_y(
		position,
		position.y,
		ground_snap_up_tolerance,
		ground_snap_down_tolerance
	)
	if grounded_y != null and vertical_speed <= 0.0:
		vertical_speed = 0.0
		position.y = float(grounded_y)
		return position

	vertical_speed = maxf(vertical_speed - gravity * delta, -terminal_fall_speed)
	var next_position := position
	next_position.y += vertical_speed * delta

	var fall_distance := maxf(position.y - next_position.y, 0.0) + ground_snap_down_tolerance
	var landing_y: Variant = _find_surface_y(next_position, position.y, ground_snap_up_tolerance, fall_distance)
	if landing_y != null and float(landing_y) >= next_position.y - 0.001:
		next_position.y = float(landing_y)
		vertical_speed = 0.0

	return next_position


func _zero_blocked_velocity(axis_delta: Vector3):
	if absf(axis_delta.x) > 0.0:
		velocity.x = 0.0
	if absf(axis_delta.z) > 0.0:
		velocity.z = 0.0


func would_block_body_cell(cell: Vector3i) -> bool:
	if grid_map == null:
		_resolve_nodes()
	if grid_map == null:
		return false

	var body_bottom_y := global_position.y - surface_height_offset + 0.02
	var body_top_y := global_position.y + body_height
	var block_top_y := _cell_top_world_y(cell)
	var block_bottom_y := block_top_y - grid_map.cell_size.y
	if block_bottom_y >= body_top_y or block_top_y <= body_bottom_y:
		return false

	var footprint_cells := _get_footprint_cells(global_position)
	for cell_xz in footprint_cells:
		if cell_xz == Vector2i(cell.x, cell.z):
			return true

	return false


func _try_snap_to_spawn_surface():
	if grid_map == null:
		return

	var start_y: Variant = _find_spawn_surface_y(global_position)
	if start_y == null:
		return

	global_position.y = float(start_y)
	vertical_speed = 0.0
	spawn_snap_pending = false


func _find_spawn_surface_y(world_position: Vector3):
	var footprint_cells := _get_footprint_cells(world_position)

	for y in range(max_surface_y, min_surface_y - 1, -1):
		for cell_xz in footprint_cells:
			var cell := Vector3i(cell_xz.x, y, cell_xz.y)
			if not _is_floor_cell(cell):
				continue

			var player_y := _cell_top_world_y(cell) + surface_height_offset
			if _has_body_clearance(Vector3(world_position.x, player_y, world_position.z)):
				return player_y

	return null


func _find_surface_y(
	world_position: Vector3,
	reference_player_y: float,
	step_up: float,
	drop_down: float
):
	var reference_floor_y := reference_player_y - surface_height_offset
	var highest_allowed := reference_floor_y + step_up
	var lowest_allowed := reference_floor_y - drop_down
	var footprint_cells := _get_footprint_cells(world_position)
	var best_player_y := -INF
	var found_surface := false

	for y in range(max_surface_y, min_surface_y - 1, -1):
		for cell_xz in footprint_cells:
			var cell := Vector3i(cell_xz.x, y, cell_xz.y)
			if not _is_floor_cell(cell):
				continue

			var top_world_y := _cell_top_world_y(cell)
			if top_world_y > highest_allowed + 0.001:
				continue
			if top_world_y < lowest_allowed - 0.001:
				continue

			var player_y := top_world_y + surface_height_offset
			if _has_body_clearance(Vector3(world_position.x, player_y, world_position.z)):
				if not found_surface or player_y > best_player_y:
					best_player_y = player_y
					found_surface = true

	if found_surface:
		return best_player_y

	return null


func _has_body_clearance(player_position: Vector3) -> bool:
	var floor_top_y := player_position.y - surface_height_offset
	var body_bottom_y := floor_top_y + 0.02
	var body_top_y := player_position.y + body_height
	var floor_cell_y := _world_y_to_cell_y(floor_top_y, player_position)
	var top_cell_y := _world_y_to_cell_y(body_top_y, player_position) + 1

	for cell_xz in _get_footprint_cells(player_position):
		for y in range(floor_cell_y + 1, top_cell_y + 1):
			var cell := Vector3i(cell_xz.x, y, cell_xz.y)
			if not _is_blocking_cell(cell):
				continue

			var block_top_y := _cell_top_world_y(cell)
			var block_bottom_y := block_top_y - grid_map.cell_size.y
			if block_bottom_y < body_top_y and block_top_y > body_bottom_y:
				return false

	return true


func _get_footprint_cells(player_position: Vector3) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var seen := {}
	var r := maxf(body_radius, 0.01)
	var offsets: Array[Vector3] = [
		Vector3.ZERO,
		Vector3(r, 0.0, 0.0),
		Vector3(-r, 0.0, 0.0),
		Vector3(0.0, 0.0, r),
		Vector3(0.0, 0.0, -r),
		Vector3(r, 0.0, r),
		Vector3(r, 0.0, -r),
		Vector3(-r, 0.0, r),
		Vector3(-r, 0.0, -r),
	]

	for offset in offsets:
		var cell := _world_position_to_cell(player_position + offset)
		var key := Vector2i(cell.x, cell.z)
		if seen.has(key):
			continue

		seen[key] = true
		cells.append(key)

	return cells


func _world_position_to_cell(world_position: Vector3) -> Vector3i:
	return grid_map.local_to_map(grid_map.to_local(world_position))


func _world_y_to_cell_y(world_y: float, at_position: Vector3) -> int:
	var local_position := grid_map.to_local(Vector3(at_position.x, world_y, at_position.z))
	return grid_map.local_to_map(local_position).y


func _cell_top_world_y(cell: Vector3i) -> float:
	return grid_map.to_global(grid_map.map_to_local(cell)).y


func _is_floor_cell(cell: Vector3i) -> bool:
	var item_id := grid_map.get_cell_item(cell)
	if item_id == GridMap.INVALID_CELL_ITEM:
		return false

	return floor_items.is_empty() or floor_items.has(item_id)


func _is_blocking_cell(cell: Vector3i) -> bool:
	var item_id := grid_map.get_cell_item(cell)
	if item_id == GridMap.INVALID_CELL_ITEM:
		return false

	return blocking_items.is_empty() or blocking_items.has(item_id)


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
	if build_grid == null or not build_grid.has_method("is_build_mode_enabled"):
		return false

	return build_grid.is_build_mode_enabled()
