class_name GridBuildPreview
extends Node3D

@export var valid_preview_color := Color(0.15, 0.85, 1.0, 0.35)
@export var blocked_preview_color := Color(1.0, 0.2, 0.1, 0.35)
@export var footprint_color := Color(1.0, 1.0, 1.0, 0.45)

var block_preview: MeshInstance3D
var block_material: StandardMaterial3D

var footprint_preview: MeshInstance3D
var footprint_material: StandardMaterial3D


func setup(cell_size: Vector3) -> void:
	_ensure_preview_nodes()

	var block_mesh := block_preview.mesh
	if block_mesh == null:
		block_mesh = BoxMesh.new()
		block_preview.mesh = block_mesh

	(block_mesh as BoxMesh).size = cell_size

	var footprint_mesh := footprint_preview.mesh
	if footprint_mesh == null:
		footprint_mesh = BoxMesh.new()
		footprint_preview.mesh = footprint_mesh

	(footprint_mesh as BoxMesh).size = Vector3(cell_size.x * 0.96, 0.02, cell_size.z * 0.96)


func show_target(
	grid_map: GridMap,
	placement_rules: Node,
	cell: Vector3i,
	can_place: bool
) -> void:

	_ensure_preview_nodes()

	block_preview.visible = true
	block_preview.position = placement_rules.get_block_visual_center(grid_map, cell)
	block_material.albedo_color = valid_preview_color if can_place else blocked_preview_color

	footprint_preview.visible = true

	var pos := grid_map.map_to_local(cell)
	pos.y += 0.025
	footprint_preview.position = pos

	footprint_material.albedo_color = footprint_color if can_place else blocked_preview_color


func hide_preview() -> void:
	_ensure_preview_nodes()
	block_preview.visible = false
	footprint_preview.visible = false


func _ensure_preview_nodes() -> void:

	if block_preview == null:
		block_preview = get_node_or_null("BlockPreview") as MeshInstance3D
		if block_preview == null:
			block_preview = MeshInstance3D.new()
			block_preview.name = "BlockPreview"
			add_child(block_preview)

	if block_material == null:
		block_material = block_preview.material_override as StandardMaterial3D
		if block_material == null:
			block_material = StandardMaterial3D.new()
			block_preview.material_override = block_material
			block_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			block_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	block_material.albedo_color = valid_preview_color
	block_preview.visible = false


	if footprint_preview == null:
		footprint_preview = get_node_or_null("FootprintPreview") as MeshInstance3D
		if footprint_preview == null:
			footprint_preview = MeshInstance3D.new()
			footprint_preview.name = "FootprintPreview"
			add_child(footprint_preview)

	if footprint_material == null:
		footprint_material = footprint_preview.material_override as StandardMaterial3D
		if footprint_material == null:
			footprint_material = StandardMaterial3D.new()
			footprint_preview.material_override = footprint_material
			footprint_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			footprint_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	footprint_material.albedo_color = footprint_color
	footprint_preview.visible = false
