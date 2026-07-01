class_name TerrainNoise
extends RefCounted

var elevation_noise := FastNoiseLite.new()
var detail_noise    := FastNoiseLite.new()
var lake_noise      := FastNoiseLite.new()
var biome_noise     := FastNoiseLite.new()
var moisture_noise  := FastNoiseLite.new()
var tree_density_noise := FastNoiseLite.new()
var animal_density_noise: FastNoiseLite


func setup(cfg: TerrainConfig) -> void:
	elevation_noise.seed = cfg.generation_seed
	elevation_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	elevation_noise.frequency = 0.012
	elevation_noise.fractal_octaves = 2
	elevation_noise.fractal_gain = 0.45

	detail_noise.seed = cfg.generation_seed + 101
	detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	detail_noise.frequency = 0.05
	detail_noise.fractal_octaves = 2

	lake_noise.seed = cfg.generation_seed + 151
	lake_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	lake_noise.frequency = 0.018
	lake_noise.fractal_octaves = 3

	biome_noise.seed = cfg.generation_seed + 177
	biome_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	biome_noise.frequency = 0.018
	biome_noise.fractal_octaves = 2

	moisture_noise.seed = cfg.generation_seed + 202
	moisture_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	moisture_noise.frequency = 0.026

	tree_density_noise.seed = cfg.generation_seed + 303
	tree_density_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	tree_density_noise.frequency = 0.075
	tree_density_noise.fractal_octaves = 2

	# animals
	animal_density_noise = FastNoiseLite.new()
	animal_density_noise.seed = cfg.generation_seed + 7
	animal_density_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	animal_density_noise.frequency = 0.03
	animal_density_noise.fractal_octaves = 2
