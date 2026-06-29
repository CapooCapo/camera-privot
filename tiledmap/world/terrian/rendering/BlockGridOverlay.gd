class_name BlockGridOverlay
extends RefCounted

var _cfg: TerrainConfig
var _overlay: MeshInstance3D
var _material: StandardMaterial3D


func setup(cfg: TerrainConfig) -> void:
	_cfg = cfg


func ensure(grid_map: GridMap) -> void:
	if _overlay != null:
		return

	_overlay = MeshInstance3D.new()
	_overlay.name = "BlockGridOverlay"
	_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.albedo_color = _cfg.block_grid_color
	_overlay.material_override = _material
	grid_map.add_child(_overlay)


func rebuild(grid_map: GridMap, rendered_cells_by_chunk: Dictionary) -> void:
	ensure(grid_map)
	_overlay.visible = _cfg.show_block_grid

	if not _cfg.show_block_grid:
		_overlay.mesh = null
		return

	_material.albedo_color = _cfg.block_grid_color
	var vertices := PackedVector3Array()

	for rendered_cells in rendered_cells_by_chunk.values():
		for cell in rendered_cells:
			var item_id := grid_map.get_cell_item(cell)
			if item_id != _cfg.grass_item \
			and item_id != _cfg.dirt_item \
			and item_id != _cfg.stone_item \
			and item_id != _cfg.water_item:
				continue
			_add_block_top_outline(vertices, grid_map, cell)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices

	var mesh := ArrayMesh.new()
	if not vertices.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	_overlay.mesh = mesh


func _add_block_top_outline(vertices: PackedVector3Array, grid_map: GridMap, cell: Vector3i) -> void:
	var center := grid_map.map_to_local(cell)
	var y := center.y + _cfg.block_grid_y_offset
	var min_x := center.x - grid_map.cell_size.x * 0.5
	var max_x := center.x + grid_map.cell_size.x * 0.5
	var min_z := center.z - grid_map.cell_size.z * 0.5
	var max_z := center.z + grid_map.cell_size.z * 0.5

	var a := Vector3(min_x, y, min_z)
	var b := Vector3(max_x, y, min_z)
	var c := Vector3(max_x, y, max_z)
	var d := Vector3(min_x, y, max_z)

	vertices.append(a); vertices.append(b)
	vertices.append(b); vertices.append(c)
	vertices.append(c); vertices.append(d)
	vertices.append(d); vertices.append(a)
