extends PanelContainer

class MinimapOverlay:
	extends Control

	var player_heading := 0.0
	var marker_color := Color(0.15, 0.75, 1.0, 0.95)
	var marker_shadow_color := Color(0.0, 0.0, 0.0, 0.45)

	func _ready():
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_heading(value: float):
		player_heading = value
		queue_redraw()

	func _draw():
		var center := size * 0.5
		var forward := Vector2(0.0, -1.0).rotated(player_heading)
		var right := Vector2(forward.y, -forward.x)
		var shadow_offset := Vector2(1.5, 1.5)
		var marker := PackedVector2Array([
			center + forward * 12.0,
			center - forward * 8.0 + right * 6.0,
			center - forward * 8.0 - right * 6.0,
		])
		var shadow := PackedVector2Array([
			marker[0] + shadow_offset,
			marker[1] + shadow_offset,
			marker[2] + shadow_offset,
		])

		draw_colored_polygon(shadow, marker_shadow_color)
		draw_colored_polygon(marker, marker_color)
		draw_circle(center, 3.0, Color(0.75, 0.95, 1.0, 0.95))


@export var player_path: NodePath = ^"../../../Player"
@export var player_visual_path: NodePath = ^"../../../Player/Node3D"
@export var camera_pivot_path: NodePath = ^"../../../CameraPivot"
@export var grid_map_path: NodePath = ^"../../../GridMap"
@export var viewport_size := Vector2i(256, 154)
@export_range(10.0, 120.0, 1.0) var orthographic_size := 34.0
@export_range(20.0, 160.0, 1.0) var camera_height := 54.0
@export_range(35.0, 88.0, 1.0) var camera_pitch_degrees := 50.0
@export var minimap_yaw_degrees := 45.0
@export var rotate_with_game_camera := false
@export var follow_lerp_speed := 14.0
@export var focus_height_offset := 1.2
@export var zoom_step := 4.0

@onready var player: Node3D = get_node_or_null(player_path)
@onready var player_visual: Node3D = get_node_or_null(player_visual_path)
@onready var camera_pivot: Node3D = get_node_or_null(camera_pivot_path)
@onready var grid_map: GridMap = get_node_or_null(grid_map_path)

var sub_viewport: SubViewport
var viewport_container: SubViewportContainer
var viewport_frame: Control
var minimap_camera: Camera3D
var overlay: MinimapOverlay
var focus_position := Vector3.ZERO
var has_focus_position := false


func _ready():
	_configure_panel()
	_build_minimap_ui()
	call_deferred("_sync_minimap_world")
	set_process(true)


func _process(delta: float):
	_resolve_scene_nodes()
	_resize_subviewport()
	_update_minimap_camera(delta)


func _configure_panel():
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -304.0
	offset_top = 16.0
	offset_right = -16.0
	offset_bottom = 230.0
	custom_minimum_size = Vector2(288.0, 214.0)
	mouse_filter = Control.MOUSE_FILTER_PASS

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.015, 0.035, 0.035, 0.88)
	panel_style.border_color = Color(0.22, 0.62, 0.76, 0.9)
	panel_style.set_border_width_all(1)
	panel_style.corner_radius_top_left = 6
	panel_style.corner_radius_top_right = 6
	panel_style.corner_radius_bottom_left = 6
	panel_style.corner_radius_bottom_right = 6
	panel_style.set_content_margin_all(10.0)
	add_theme_stylebox_override("panel", panel_style)


func _build_minimap_ui():
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 6)
	add_child(layout)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	layout.add_child(header)

	var title := Label.new()
	title.text = "MINIMAP"
	title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.28, 1.0))
	title.add_theme_font_size_override("font_size", 15)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var zoom_out := Button.new()
	zoom_out.text = "-"
	zoom_out.tooltip_text = "Zoom out minimap"
	zoom_out.custom_minimum_size = Vector2(28.0, 26.0)
	zoom_out.pressed.connect(_on_zoom_out_pressed)
	header.add_child(zoom_out)

	var zoom_in := Button.new()
	zoom_in.text = "+"
	zoom_in.tooltip_text = "Zoom in minimap"
	zoom_in.custom_minimum_size = Vector2(28.0, 26.0)
	zoom_in.pressed.connect(_on_zoom_in_pressed)
	header.add_child(zoom_in)

	var frame_panel := PanelContainer.new()
	frame_panel.custom_minimum_size = Vector2(float(viewport_size.x), float(viewport_size.y))
	frame_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = Color(0.02, 0.06, 0.05, 1.0)
	frame_style.border_color = Color(0.35, 0.46, 0.48, 0.85)
	frame_style.set_border_width_all(1)
	frame_panel.add_theme_stylebox_override("panel", frame_style)
	layout.add_child(frame_panel)

	viewport_frame = Control.new()
	viewport_frame.clip_contents = true
	viewport_frame.custom_minimum_size = Vector2(float(viewport_size.x), float(viewport_size.y))
	frame_panel.add_child(viewport_frame)

	viewport_container = SubViewportContainer.new()
	viewport_container.stretch = true
	viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	viewport_frame.add_child(viewport_container)

	sub_viewport = SubViewport.new()
	sub_viewport.size = viewport_size
	sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub_viewport.transparent_bg = false
	sub_viewport.own_world_3d = false
	viewport_container.add_child(sub_viewport)

	minimap_camera = Camera3D.new()
	minimap_camera.name = "MinimapCamera3D"
	minimap_camera.current = true
	minimap_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	minimap_camera.size = orthographic_size
	minimap_camera.near = 0.05
	minimap_camera.far = 300.0
	sub_viewport.add_child(minimap_camera)

	_add_compass_labels()

	overlay = MinimapOverlay.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	viewport_frame.add_child(overlay)


func _add_compass_labels():
	_add_compass_label("N", Vector2(0.5, 0.0), Vector2(-8.0, 2.0), Vector2(16.0, 18.0))
	_add_compass_label("S", Vector2(0.5, 1.0), Vector2(-8.0, -20.0), Vector2(16.0, 18.0))
	_add_compass_label("W", Vector2(0.0, 0.5), Vector2(4.0, -9.0), Vector2(18.0, 18.0))
	_add_compass_label("E", Vector2(1.0, 0.5), Vector2(-22.0, -9.0), Vector2(18.0, 18.0))


func _add_compass_label(text: String, anchor: Vector2, offset: Vector2, label_size: Vector2):
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(0.9, 0.95, 0.9, 0.95))
	label.add_theme_font_size_override("font_size", 12)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.anchor_left = anchor.x
	label.anchor_top = anchor.y
	label.anchor_right = anchor.x
	label.anchor_bottom = anchor.y
	label.offset_left = offset.x
	label.offset_top = offset.y
	label.offset_right = offset.x + label_size.x
	label.offset_bottom = offset.y + label_size.y
	viewport_frame.add_child(label)


func _sync_minimap_world():
	if sub_viewport == null:
		return

	var root_viewport := get_viewport()
	if root_viewport == null:
		return

	sub_viewport.world_3d = root_viewport.world_3d


func _resolve_scene_nodes():
	if player == null:
		player = get_node_or_null(player_path)
	if player_visual == null:
		player_visual = get_node_or_null(player_visual_path)
	if player_visual == null and player != null:
		player_visual = player.get_node_or_null("Node3D")
	if camera_pivot == null:
		camera_pivot = get_node_or_null(camera_pivot_path)
	if grid_map == null:
		grid_map = get_node_or_null(grid_map_path)


func _resize_subviewport():
	if sub_viewport == null or viewport_frame == null:
		return

	var frame_size := viewport_frame.size
	if frame_size.x < 1.0 or frame_size.y < 1.0:
		return

	var wanted_size := Vector2i(roundi(frame_size.x), roundi(frame_size.y))
	if sub_viewport.size != wanted_size:
		sub_viewport.size = wanted_size


func _update_minimap_camera(delta: float):
	if minimap_camera == null:
		return

	var target := _get_focus_position()
	var weight := 1.0 if delta <= 0.0 else clampf(delta * follow_lerp_speed, 0.0, 1.0)
	if not has_focus_position:
		focus_position = target
		has_focus_position = true
	else:
		focus_position = focus_position.lerp(target, weight)

	var yaw_degrees := _get_minimap_yaw_degrees()
	var yaw := deg_to_rad(yaw_degrees)
	var pitch := deg_to_rad(camera_pitch_degrees)
	var horizontal_distance := camera_height / maxf(tan(pitch), 0.01)
	var camera_offset := Vector3(
		sin(yaw) * horizontal_distance,
		camera_height,
		cos(yaw) * horizontal_distance
	)

	minimap_camera.global_position = focus_position + camera_offset
	minimap_camera.look_at(focus_position, Vector3.UP)
	minimap_camera.size = orthographic_size

	if overlay != null:
		overlay.set_heading(_get_player_marker_heading())


func _get_focus_position() -> Vector3:
	if player != null:
		return player.global_position + Vector3.UP * focus_height_offset
	if camera_pivot != null:
		return camera_pivot.global_position
	if grid_map != null:
		return grid_map.global_position
	return Vector3.ZERO


func _get_minimap_yaw_degrees() -> float:
	if rotate_with_game_camera and camera_pivot != null:
		return camera_pivot.rotation_degrees.y
	return minimap_yaw_degrees


func _get_player_marker_heading() -> float:
	if player == null:
		return 0.0

	var forward := _get_player_forward()
	if forward.length_squared() <= 0.0001:
		return 0.0

	var marker_position := player.global_position + Vector3.UP * focus_height_offset
	var screen_center := minimap_camera.unproject_position(marker_position)
	var screen_forward := minimap_camera.unproject_position(marker_position + forward.normalized() * 2.0)
	var screen_direction := screen_forward - screen_center
	if screen_direction.length_squared() <= 0.0001:
		return 0.0

	return Vector2(0.0, -1.0).angle_to(screen_direction.normalized())


func _get_player_forward() -> Vector3:
	var facing_source := player_visual if player_visual != null else player
	var forward := facing_source.global_transform.basis.z
	forward.y = 0.0
	return forward.normalized()


func _on_zoom_in_pressed():
	orthographic_size = clampf(orthographic_size - zoom_step, 10.0, 120.0)


func _on_zoom_out_pressed():
	orthographic_size = clampf(orthographic_size + zoom_step, 10.0, 120.0)
