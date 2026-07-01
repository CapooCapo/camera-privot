class_name Sheep
extends VoxelActor

## Same idea as Cow, but picks a new random wander direction every so often
## to show how a subclass can drive its own behaviour while VoxelActor still
## handles all terrain physics.

@export var wander_interval_min := 1.5
@export var wander_interval_max := 4.0

var current_direction: Vector3 = Vector3.ZERO
var _time_until_next_direction := 0.0


func _ready() -> void:
	super._ready()
	_time_until_next_direction = randf_range(wander_interval_min, wander_interval_max)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	_time_until_next_direction -= delta
	if _time_until_next_direction <= 0.0:
		_pick_new_direction()

	move_in_direction(current_direction, delta)


func _pick_new_direction() -> void:
	var angle := randf_range(0.0, TAU)
	# 1-in-4 chance to just stand still for a bit, like a real sheep would.
	current_direction = Vector3.ZERO if randi() % 4 == 0 else Vector3(sin(angle), 0.0, cos(angle))
	_time_until_next_direction = randf_range(wander_interval_min, wander_interval_max)
