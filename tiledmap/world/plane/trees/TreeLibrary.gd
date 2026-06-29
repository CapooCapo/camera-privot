@tool
extends Node3D

@export var tree_material: Material = preload("res://Assets/Fbx/TreeMat.tres")

# Tạo một checkbox đóng vai trò như nút bấm trên Inspector
@export var trigger_apply: bool = false:
	set(value):
		if value and tree_material != null:
			_apply_material_override(self)
		trigger_apply = false # Tự động tắt checkbox sau khi chạy xong

func _apply_material_override(current_node: Node):
	if current_node is MeshInstance3D:
		current_node.material_override = tree_material
	
	for child in current_node.get_children():
		_apply_material_override(child)
