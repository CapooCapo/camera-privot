class_name VoxelActor
extends CharacterBody3D

# ------------------------------------------------------------------
# BuildGrid reference
# ------------------------------------------------------------------

@export var build_grid_path: NodePath = ^"../BuildGrid"
@onready var build_grid: BuildGrid = get_node_or_null(build_grid_path)

# ------------------------------------------------------------------
# Movement config
# ------------------------------------------------------------------

@export var move_speed: float = 5.0
@export var acceleration: float = 18.0

@export var body_radius: float = 0.35
@export var body_height: float = 1.8

@export var max_movement_substep: float = 0.12
@export var max_step_height: float = 1.05

@export var ground_snap_up: float = 0.08
@export var ground_snap_down: float = 0.18

@export var gravity: float = 24.0
@export var terminal_fall_speed: float = 40.0

@export var surface_offset: float = 0.05

@export var min_y: int = -16
@export var max_y: int = 48

@export var floor_items: Array[int] = [5, 6, 7, 8, 9]
@export var blocking_items: Array[int] = [5, 6, 7, 8, 10]

# ------------------------------------------------------------------
# Runtime
# ------------------------------------------------------------------

var spawn_snap_pending: bool = true
var vertical_speed: float = 0.0


# ------------------------------------------------------------------
# Life cycle
# ------------------------------------------------------------------

func _ready() -> void:
	if not Engine.is_editor_hint():
		await get_tree().process_frame
		_try_snap_to_ground()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	move_in_direction(Vector3.ZERO, delta)


# ------------------------------------------------------------------
# BuildGrid access
# ------------------------------------------------------------------

func _grid() -> GridMap:
	if build_grid == null:
		return null
	return build_grid.grid_map


# ------------------------------------------------------------------
# Movement
# ------------------------------------------------------------------

func move_in_direction(dir: Vector3, delta: float) -> void:
	var grid := _grid()
	if grid == null:
		return

	if spawn_snap_pending:
		_try_snap_to_ground()
		if spawn_snap_pending:
			return

	var target := dir * move_speed

	velocity.x = move_toward(velocity.x, target.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target.z, acceleration * delta)
	velocity.y = 0.0

	var motion := Vector3(velocity.x, 0, velocity.z) * delta
	var steps := maxi(1, ceili(motion.length() / max(0.01, max_movement_substep)))
	var step := motion / float(steps)

	var pos := global_position

	for i in steps:
		pos = _move_axis(pos, Vector3(step.x, 0, 0))
		pos = _move_axis(pos, Vector3(0, 0, step.z))

	pos = _apply_vertical(pos, delta)

	global_position = pos


# ------------------------------------------------------------------
# Axis move
# ------------------------------------------------------------------

func _move_axis(pos: Vector3, delta_axis: Vector3) -> Vector3:
	if delta_axis.length_squared() < 0.000001:
		return pos

	var candidate := pos + delta_axis

	var surface_y: float = _find_surface(
		candidate,
		pos.y,
		max_step_height,
		ground_snap_down
	)

	if surface_y != -INF:
		candidate.y = surface_y

	if not _has_clearance(candidate):
		return pos

	return candidate


# ------------------------------------------------------------------
# Vertical physics
# ------------------------------------------------------------------

func _apply_vertical(pos: Vector3, delta: float) -> Vector3:
	var ground_y: float = _find_surface(pos, pos.y, ground_snap_up, ground_snap_down)

	if vertical_speed <= 0.0 and ground_y != -INF:
		vertical_speed = 0.0
		pos.y = ground_y
		return pos

	vertical_speed = maxf(vertical_speed - gravity * delta, -terminal_fall_speed)

	pos.y += vertical_speed * delta

	var landing: float = _find_surface(pos, pos.y, ground_snap_up, ground_snap_down)

	if landing != -INF:
		pos.y = landing
		vertical_speed = 0.0

	return pos


# ------------------------------------------------------------------
# Spawn snap
# ------------------------------------------------------------------

func _try_snap_to_ground() -> void:
	var y: float = _find_surface(global_position, global_position.y, 2.0, 2.0)

	if y == -INF:
		return

	global_position.y = y
	vertical_speed = 0.0
	spawn_snap_pending = false


# ------------------------------------------------------------------
# Terrain query (BuildGrid version)
# ------------------------------------------------------------------

func _find_surface(world_pos: Vector3, ref_y: float, up: float, down: float) -> float:
	var grid := _grid()
	if grid == null:
		return -INF

	var best := -INF
	var found := false

	var footprint := _get_footprint(world_pos)

	for y in range(max_y, min_y - 1, -1):
		for xz in footprint:

			var cell := Vector3i(xz.x, y, xz.y)
			var id := grid.get_cell_item(cell)

			if id == GridMap.INVALID_CELL_ITEM:
				continue

			if floor_items.size() > 0 and not floor_items.has(id):
				continue

			var top_y := grid.to_global(grid.map_to_local(cell)).y
			var player_y := top_y + surface_offset

			if abs(player_y - ref_y) > up:
				continue

			if not _has_clearance(Vector3(world_pos.x, player_y, world_pos.z)):
				continue

			if not found or player_y > best:
				best = player_y
				found = true

	return best if found else -INF


# ------------------------------------------------------------------
# Collision
# ------------------------------------------------------------------

func _has_clearance(pos: Vector3) -> bool:
	var grid := _grid()
	if grid == null:
		return false

	var top := pos.y + body_height
	var bottom := pos.y - surface_offset

	for c in _get_footprint(pos):
		for y in range(min_y, max_y):

			var cell := Vector3i(c.x, y, c.y)
			var id := grid.get_cell_item(cell)

			if id == GridMap.INVALID_CELL_ITEM:
				continue

			if blocking_items.size() > 0 and not blocking_items.has(id):
				continue

			var cell_top := grid.to_global(grid.map_to_local(cell)).y
			var cell_bottom := cell_top - grid.cell_size.y

			if cell_bottom < top and cell_top > bottom:
				return false

	return true


# ------------------------------------------------------------------
# Footprint
# ------------------------------------------------------------------

func _get_footprint(pos: Vector3) -> Array[Vector2i]:
	var r := body_radius

	var offsets := [
		Vector3.ZERO,
		Vector3(r, 0, 0),
		Vector3(-r, 0, 0),
		Vector3(0, 0, r),
		Vector3(0, 0, -r),
	]

	var out: Array[Vector2i] = []
	var seen := {}

	for o in offsets:
		var c := _grid().local_to_map(_grid().to_local(pos + o))
		var key := Vector2i(c.x, c.z)

		if seen.has(key):
			continue

		seen[key] = true
		out.append(key)

	return out
