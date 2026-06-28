extends Node3D

@onready var grid_map: GridMap = $GridMap

@export var ground_item_id: int = 0
@export var size: int = 16


func _ready() -> void:
	print("WorldManager started")
	print("GridMap =", grid_map)
	print("MeshLibrary =", grid_map.mesh_library)

	generate_test_world()


func generate_test_world() -> void:
	if grid_map.mesh_library == null:
		push_error("GridMap chưa có MeshLibrary!")
		return

	grid_map.clear()

	var half := size / 2

	for x in range(-half, half):
		for z in range(-half, half):
			grid_map.set_cell_item(Vector3i(x, 0, z), ground_item_id)

	print("Generated test world: ", size, "x", size)
