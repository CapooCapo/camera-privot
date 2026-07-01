class_name Cow
extends VoxelActor

var current_direction := Vector3.ZERO
var change_timer := 0.0


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	change_timer -= delta

	if change_timer <= 0.0:
		current_direction = _random_flat_direction()
		change_timer = randf_range(2.0, 5.0)

	move_in_direction(current_direction, delta)


func _random_flat_direction() -> Vector3:
	var angle = randf() * TAU
	return Vector3(cos(angle), 0.0, sin(angle))
