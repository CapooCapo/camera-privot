class_name TerrainSampler
extends RefCounted

var _cfg: TerrainConfig
var _noise: TerrainNoise
var _profile: TerrainProfile


func setup(cfg: TerrainConfig, noise: TerrainNoise, profile: TerrainProfile) -> void:
	_cfg = cfg
	_noise = noise
	_profile = profile


func sample_terrain(world_x: int, world_z: int) -> Dictionary:
	var profile := _profile.get_terrain_profile(world_x, world_z)
	var biome := _get_biome(world_x, world_z, profile)
	var surface_y := _profile.sample_surface_height(world_x, world_z, profile)
	var moisture := (_noise.moisture_noise.get_noise_2d(world_x, world_z) + 1.0) * 0.5
	var lake_value := (_noise.lake_noise.get_noise_2d(world_x, world_z) + 1.0) * 0.5
	var is_spawn_area := Vector2(world_x, world_z).length() < float(_cfg.spawn_protection_radius)
	var object_value := TerrainUtils.random_01(world_x, world_z, 303, _cfg.generation_seed)
	var tree_density := (_noise.tree_density_noise.get_noise_2d(world_x, world_z) + 1.0) * 0.5

	var has_lake_basin := (
		not is_spawn_area
		and profile != "cliff"
		and lake_value < _cfg.lake_threshold
	)
	var has_water := has_lake_basin or (
		not is_spawn_area
		and profile != "flat"
		and surface_y < _cfg.water_level
	)
	var surface_item := _cfg.grass_item

	if has_water:
		surface_y = maxi(0, _cfg.water_level - 1)
		surface_item = _cfg.dirt_item
	elif surface_y >= _cfg.mountain_level or biome == "rocky":
		surface_item = _cfg.stone_item
	elif moisture < _cfg.dirt_surface_chance:
		surface_item = _cfg.dirt_item

	var tree_threshold := _get_tree_threshold(biome)
	var has_tree := (
		not is_spawn_area
		and not has_water
		and surface_item == _cfg.grass_item
		and surface_y < _cfg.mountain_level
		and object_value > tree_threshold
		and tree_density > tree_threshold - 0.08
	)

	return {
		"surface_y": surface_y,
		"surface_item": surface_item,
		"has_water": has_water,
		"has_tree": has_tree,
		"biome": biome,
		"profile": profile,
	}


func _get_biome(world_x: int, world_z: int, profile: String) -> String:
	if profile == "cliff":
		return "rocky"

	var moisture := (_noise.moisture_noise.get_noise_2d(world_x, world_z) + 1.0) * 0.5
	var biome_value := (_noise.biome_noise.get_noise_2d(world_x, world_z) + 1.0) * 0.5

	if moisture > 0.66 and biome_value > 0.42:
		return "forest"
	if moisture > 0.58 and biome_value <= 0.42:
		return "swamp"
	if moisture < 0.22:
		return "rocky"
	return "plains"


func _get_tree_threshold(biome: String) -> float:
	match biome:
		"forest": return 0.62
		"swamp":  return 0.82
		"plains": return 0.92
		"rocky":  return 1.1
	return 0.95
