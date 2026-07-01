class_name Chicken
extends VoxelActor

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	move_in_direction(Vector3.ZERO, delta)
