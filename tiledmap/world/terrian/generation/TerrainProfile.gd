class_name TerrainProfile
extends RefCounted

var _cfg: TerrainConfig
var _noise: TerrainNoise


func setup(cfg: TerrainConfig, noise: TerrainNoise) -> void:
	_cfg = cfg
	_noise = noise


func get_terrain_profile(world_x: int, world_z: int) -> String:
	var region_x := floori(float(world_x) / float(_cfg.terrain_region_size))
	var region_z := floori(float(world_z) / float(_cfg.terrain_region_size))
	var roll := TerrainUtils.random_01(region_x, region_z, 701, _cfg.generation_seed)

	if roll < _cfg.flat_region_chance:
		return "flat"
	if roll < _cfg.flat_region_chance + _cfg.rough_region_chance:
		return "rough"
	return "cliff"


func sample_surface_height(world_x: int, world_z: int, profile: String) -> int:
	var region_x := floori(float(world_x) / float(_cfg.terrain_region_size))
	var region_z := floori(float(world_z) / float(_cfg.terrain_region_size))
	var base_roll := TerrainUtils.random_01(region_x, region_z, 811, _cfg.generation_seed)
	var base_height := 3 + int(roundf(base_roll * 2.0))
	var detail := _noise.detail_noise.get_noise_2d(world_x, world_z)

	match profile:
		"flat":
			if TerrainUtils.random_01(world_x, world_z, 821, _cfg.generation_seed) < _cfg.flat_detail_chance:
				return clampi(base_height + TerrainUtils.signi(roundi(detail)), _cfg.water_level, _cfg.max_terrain_height)
			return clampi(base_height, _cfg.water_level, _cfg.max_terrain_height)
		"rough":
			return clampi(base_height + roundi(detail * 2.0), _cfg.water_level - 1, _cfg.max_terrain_height)
		"cliff":
			var ridge := absf(_noise.elevation_noise.get_noise_2d(world_x, world_z))
			return clampi(base_height + roundi(ridge * 5.0) + roundi(detail * 2.0), _cfg.water_level, _cfg.max_terrain_height)

	return base_height
