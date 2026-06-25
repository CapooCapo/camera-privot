class_name GridTerrainGenerator
extends Node

@export var ground_size_x := 24
@export var ground_size_z := 24
@export var regenerate_ground_on_ready := true

@export_enum("Solid", "Checker", "Noise") var ground_generation_mode := 0
@export var generation_seed := 12345
@export_range(0.01, 1.0, 0.01) var noise_frequency := 0.12
@export_range(-1.0, 1.0, 0.01) var noise_cutoff := 0.2

@export var ground_item := 6
@export var alternate_ground_item := 7
@export var noise_ground_item := 8

var terrain_noise := FastNoiseLite.new()


func generate(grid_map: GridMap):
	terrain_noise.seed = generation_seed
	terrain_noise.frequency = noise_frequency

	if not regenerate_ground_on_ready:
		return

	grid_map.clear()

	var min_x := -floori(ground_size_x * 0.5)
	var min_z := -floori(ground_size_z * 0.5)
	var max_x := min_x + ground_size_x
	var max_z := min_z + ground_size_z

	for x in range(min_x, max_x):
		for z in range(min_z, max_z):
			grid_map.set_cell_item(Vector3i(x, 0, z), _choose_ground_item(x, z))


func _choose_ground_item(x: int, z: int) -> int:
	match ground_generation_mode:
		1:
			if abs(x + z) % 2 == 0:
				return ground_item
			return alternate_ground_item
		2:
			var value := terrain_noise.get_noise_2d(x, z)
			if value > noise_cutoff:
				return alternate_ground_item
			if value < -noise_cutoff:
				return noise_ground_item
			return ground_item
		_:
			return ground_item
