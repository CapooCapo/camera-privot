extends Node3D

const MOVE_SPEED = 10.0
const ZOOM_SPEED = 1.5

@onready var camera = $Camera3D

func _process(delta):
	print("Tọa độ hiện tại: ", position)
	var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	position += direction * MOVE_SPEED * delta

func _unhandled_input(event):
	# Xử lý sự kiện cuộn chuột để Zoom (Với5Projection Orthogonal phải can thiệp thuộc tính 'size')
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MouseButton.MOUSE_BUTTON_WHEEL_UP:
			camera.size = clamp(camera.size - ZOOM_SPEED, 2.0, 30.0)
		elif event.button_index == MouseButton.MOUSE_BUTTON_WHEEL_DOWN:
			camera.size = clamp(camera.size + ZOOM_SPEED, 2.0, 30.0)
