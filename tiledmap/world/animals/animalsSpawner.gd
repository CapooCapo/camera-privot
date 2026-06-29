class_name AnimalSpawner extends Node3D

var spawned_animals_by_chunk := {}

func clear_all():
	for chunk_animals in spawned_animals_by_chunk.values():
		for animal in chunk_animals:
			if is_instance_valid(animal): animal.queue_free()
	spawned_animals_by_chunk.clear()

func spawn_chunk(chunk_coord: Vector2i, animal_data_array: Array, scenes: Array[PackedScene]):
	var chunk_animals: Array[Node] = []
	for data in animal_data_array:
		var scene = scenes[data.index]
		if scene:
			var animal_node = scene.instantiate()
			animal_node.position = data.pos
			animal_node.rotation.y = data.rot_y
			add_child(animal_node) # Spawner làm cha, dễ quản lý hơn nhét vào GridMap
			chunk_animals.append(animal_node)
			
	spawned_animals_by_chunk[chunk_coord] = chunk_animals

func clear_chunk(chunk_coord: Vector2i):
	if spawned_animals_by_chunk.has(chunk_coord):
		for animal in spawned_animals_by_chunk[chunk_coord]:
			if is_instance_valid(animal): animal.queue_free()
		spawned_animals_by_chunk.erase(chunk_coord)
