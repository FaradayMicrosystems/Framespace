extends Node3D
## One real-world surface or object from the headset's Space Setup (walls, floor, tables, the room mesh).
## Instanced by OpenXRFbSceneManager for each scene anchor. Gives the surface a collider on the
## ROOM layer so tape points, the reticle and dropped shapes land on it, and a light outline + size label.

const LAYER_ROOM := 2
const COMPONENT_BOUNDED_2D := 3
const COMPONENT_SEMANTIC_LABELS := 5

var label_name := "surface"
var size_2d := Vector2.ZERO


func setup_scene(entity) -> void:
	var main = get_tree().root.get_node_or_null("Main")
	if entity.is_component_enabled(COMPONENT_SEMANTIC_LABELS):
		var labels: PackedStringArray = entity.get_semantic_labels()
		if labels.size() > 0:
			label_name = String(labels[0]).to_lower().replace("_", " ")
	var is_global_mesh := label_name.contains("global mesh")

	var col = entity.create_collision_shape()
	if col:
		var body := StaticBody3D.new()
		body.collision_layer = LAYER_ROOM
		body.collision_mask = 0
		body.add_child(col)
		add_child(body)

	if not is_global_mesh:
		var mi = entity.create_mesh_instance()
		if mi:
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.albedo_color = Color(0.0, 0.9, 1.0, 0.06)
			mi.material_override = m
			add_child(mi)
		if entity.is_component_enabled(COMPONENT_BOUNDED_2D):
			var r: Rect2 = entity.get_bounding_box_2d()
			size_2d = r.size
			if main:
				var lbl: Label3D = main.make_room_label(label_name, r.size)
				var c := r.get_center()
				lbl.position = Vector3(c.x, c.y, 0.03)
				add_child(lbl)

	if main:
		main.register_surface(self)
