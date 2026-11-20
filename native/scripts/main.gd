extends Node3D
## Framespace native (Meta Quest 3): wireframe design + measuring over passthrough, saved rooms.
## Port of the WebXR prototype (../app.js). Everything is built in code so the scene file stays tiny.
##
## Coordinates: shapes and measurements live under `content`, which follows the current room's
## spatial anchor. All shape/measure maths is done in content-local space; the grid is content-local
## X/Z, i.e. aligned to the direction you faced when the room was created (or recentered before it).

const UIPanel := preload("res://scripts/ui_panel.gd")
const SceneAnchorScene := preload("res://scene_anchor.tscn")

const BUILD := "0.3.0-native"
const MIN_SIZE := 0.01        # 1 cm smallest dimension
const SNAP_POINT := 0.025     # tape points snap to corners/points within 2.5 cm
const CLIP_MAX := 5

const LAYER_ROOM := 2
const LAYER_SHAPE := 4
const LAYER_HANDLE := 8
const LAYER_UI := 16

const COLORS := {"box": Color("00e5ff"), "sphere": Color("7cff6b"), "cylinder": Color("ffb020"), "cone": Color("ff5ad1")}
const NAMES := {"box": "Box", "sphere": "Sphere", "cylinder": "Cylinder", "cone": "Cone"}
const DEFAULT_DIMS := {"box": {"x": 0.3, "y": 0.3, "z": 0.3}, "sphere": {"r": 0.15}, "cylinder": {"r": 0.12, "h": 0.3}, "cone": {"r": 0.12, "h": 0.3}}
const C_YELLOW := Color("ffe14d")
const C_CYAN := Color("00e5ff")

# Hold X palette. Loaded at startup from res://objects.txt, which CI copies from the repo's objects.csv
# (one object per line, sizes in mm). Edit objects.csv, not this file. Fallback below if the file is missing.
const PALETTE_FALLBACK := [
	{"label": "Cube", "type": "box", "dims": {"x": 0.1, "y": 0.1, "z": 0.1}},
	{"label": "Sphere", "type": "sphere", "dims": {"r": 0.15}},
	{"label": "Cylinder", "type": "cylinder", "dims": {"r": 0.12, "h": 0.3}},
	{"label": "Cone", "type": "cone", "dims": {"r": 0.12, "h": 0.3}},
]
var PALETTE: Array = []
var label_counts := {}


# Optional side-view outline for a box (e.g. a vehicle), stored normalised to the unit box so it still scales as a box.
# outline "x/y ...", wheels "x/diameter ...", inner "x/y/length/width/height" (mm; x back from the front, y up from the ground).
static func _groups(t: String, n: int) -> Array:
	var out := []
	for p in t.strip_edges().split(" ", false):
		var parts := p.split("/")
		if parts.size() != n:
			continue
		var nums := []
		var ok := true
		for q in parts:
			if not q.is_valid_float():
				ok = false
			nums.append(q.to_float())
		if ok:
			out.append(nums)
	return out


static func parse_outline(outline: String, wheels: String, inner: String, L: float, H: float, W: float) -> Dictionary:
	var pts := []
	for p in _groups(outline, 2):
		pts.append([0.5 - p[0] / L, p[1] / H - 0.5])
	if pts.size() < 3:
		return {}
	var wh := []
	for p in _groups(wheels, 2):
		wh.append([0.5 - p[0] / L, p[1] / 2.0 / L, p[1] / 2.0 / H])
	var inn := []
	for p in _groups(inner, 5):
		inn.append([0.5 - (p[0] + p[2]) / L, 0.5 - p[0] / L, p[1] / H - 0.5, (p[1] + p[4]) / H - 0.5, p[3] / 2.0 / W])
	return {"pts": pts, "wheels": wh, "inner": inn}


var _outline_cache := {}


func outline_mesh(o: Dictionary) -> ArrayMesh:
	var key := JSON.stringify(o)
	if _outline_cache.has(key):
		return _outline_cache[key]
	var v := PackedVector3Array()
	var pts: Array = o.get("pts", [])
	var n := pts.size()
	for z in [-0.5, 0.5]:
		for i in n:
			var a: Array = pts[i]
			var b: Array = pts[(i + 1) % n]
			v.append_array([Vector3(a[0], a[1], z), Vector3(b[0], b[1], z)])
	for a in pts:
		v.append_array([Vector3(a[0], a[1], -0.5), Vector3(a[0], a[1], 0.5)])
	for b in o.get("inner", []):
		var c := [Vector2(b[0], b[2]), Vector2(b[1], b[2]), Vector2(b[1], b[3]), Vector2(b[0], b[3])]
		var zw: float = b[4]
		for z in [-zw, zw]:
			for i in 4:
				v.append_array([Vector3(c[i].x, c[i].y, z), Vector3(c[(i + 1) % 4].x, c[(i + 1) % 4].y, z)])
		for p in c:
			v.append_array([Vector3(p.x, p.y, -zw), Vector3(p.x, p.y, zw)])
	for w in o.get("wheels", []):
		var u: float = w[0]
		var ru: float = w[1]
		var rv: float = w[2]
		for z in [-0.45, 0.45]:
			_circle_pts(v, func(t): return Vector3(u + cos(t) * ru, -0.5 + rv + sin(t) * rv, z), 24)
	var m := _lines_mesh(v)
	_outline_cache[key] = m
	return m


static func parse_objects(text: String) -> Array:
	var out := []
	var header := PackedStringArray()
	for raw: String in text.split("\n"):
		var line := raw.strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		var cells := line.split(",")
		for i in cells.size():
			cells[i] = cells[i].strip_edges()
		if header.is_empty():
			for c in cells:
				header.append(c.to_lower())
			continue
		var row := {}
		for i in header.size():
			row[header[i]] = cells[i] if i < cells.size() else ""
		var mm := func(k: String) -> float: return String(row.get(k, "")).to_float() / 1000.0
		var type := String(row.get("shape", "")).to_lower()
		var dims := {}
		if type == "box":
			dims = {"x": mm.call("length_mm"), "y": mm.call("height_mm"), "z": mm.call("width_mm")}
		elif type == "sphere":
			dims = {"r": mm.call("diameter_mm") / 2.0}
		elif type == "cylinder" or type == "cone":
			dims = {"r": mm.call("diameter_mm") / 2.0, "h": mm.call("height_mm")}
		var ok: bool = String(row.get("name", "")) != "" and not dims.is_empty()
		for v in dims.values():
			if not (v > 0.0):
				ok = false
		if not ok:
			push_warning("objects.csv: skipped line " + line)
			continue
		var item := {"label": row.name, "type": type, "dims": dims, "note": row.get("note", "")}
		if type == "box" and String(row.get("outline", "")) != "":
			var o := parse_outline(row.outline, row.get("wheels", ""), row.get("inner", ""), dims.x * 1000.0, dims.y * 1000.0, dims.z * 1000.0)
			if not o.is_empty():
				item["outline"] = o
		out.append(item)
	return out


func load_palette() -> void:
	var f := FileAccess.open("res://objects.txt", FileAccess.READ)
	PALETTE = parse_objects(f.get_as_text()) if f else []
	if PALETTE.is_empty():
		push_warning("objects.txt missing or empty, using built-in shapes")
		PALETTE = PALETTE_FALLBACK.duplicate(true)

# Stick-click main menu, page "main". Rows of 4.
const MENU_MAIN := [
	"box", "sphere", "cylinder", "cone",
	"tape", "circle", "select", "units",
	"copy", "cut", "paste", "nextclip",
	"duplicate", "drop", "delete", "undo",
	"grid", "roomvis", "scan", "clear",
	"save", "rooms", "export", "quit",
]


class Shape:
	var type: String
	var name: String
	var dims: Dictionary
	var node: Node3D
	var wire: MeshInstance3D
	var fill: MeshInstance3D
	var body: StaticBody3D
	var col: CollisionShape3D
	var label: Node3D
	var color: Color
	var handles: Array = []
	var wire_mat: StandardMaterial3D
	var fill_mat: StandardMaterial3D
	var outline: Dictionary = {}


class Measure:
	var type: String          # line | circle
	var name: String
	var points: Array = []    # content-local Vector3
	var node: Node3D
	var center := Vector3.ZERO
	var normal := Vector3.UP
	var r := 0.0


class Ctrl:
	var node: XRController3D
	var hand: String
	var ray: MeshInstance3D
	var reticle: MeshInstance3D
	var o := Vector3.ZERO           # ray origin, content-local
	var d := Vector3.FORWARD        # ray direction, content-local
	var target = null               # {point, normal, dist, kind} content-local
	var ui = null                   # {panel, id, dist}
	var handle_hit = null           # handle Node3D
	var shape_hit = null            # {shape, point, normal, dist}
	var drag = null                 # Dictionary
	var btn := {}
	var a_down_at := -1.0
	var stick_down_at := -10.0
	var latch_x := true
	var latch_y := true
	var press_shape = null


# ---------------------------------------------------------------- state
var units := "metric"
var mode := "select"           # select | tape | circle
var grid := 0.05               # metres; 0 = off
var room_visible := true
var status := "Pick a shape or a measuring tool."
var shapes: Array = []
var measures: Array = []
var selected: Shape = null
var falling: Array = []
var clipboard: Array = []
var clip_index := 0
var history: Array = []
var pending: Array = []
var pending_dots: Array = []
var counters := {"box": 0, "sphere": 0, "cylinder": 0, "cone": 0, "m": 0}
var last_ctrl: Ctrl = null

var room := {}                 # {id, name, anchor, created}
# How a room is put back in the real world when it loads:
#   stand  = on the floor where you are standing, facing the way you look. Stand on your usual spot,
#            face your usual way and recenter (hold the Meta button): the room snaps back into place.
#   anchor = pinned to a Meta spatial anchor; reappears on its own, but only where the headset finds it.
var placement := "stand"
var anchor_node: Node3D = null
var anchor_state := "none"     # none | creating | loading | tracked | failed
var anchor_wait := 0.0
var surfaces: Array = []       # scene_anchor nodes
var save_dirty := false
var save_timer := 0.0
var menu_page := "main"
var menu_attach: Ctrl = null   # null = fixed in place
var menu_dirty := true
var selftest := false

var xr_interface: XRInterface
var xr_active := false
var origin: XROrigin3D
var camera: XRCamera3D
var content: Node3D
var ctrls: Array = []
var scene_mgr: Node = null
var anchor_mgr: Node = null
var menu: Node3D
var palette: Node3D
var ctx: Node3D
var grid_patch: MeshInstance3D
var grid_patch_size := -1.0
var preview: MeshInstance3D
var preview_label: Node3D

var unit_wire := {}
var unit_fill := {}
var mat_dot: StandardMaterial3D
var mat_measure: StandardMaterial3D
var mesh_dot: SphereMesh
var mesh_handle: BoxMesh
var mat_handle := {}


# ================================================================ setup
func _ready() -> void:
	name = "Main"
	selftest = OS.get_cmdline_user_args().has("--selftest")
	load_palette()
	_build_assets()
	_build_world()
	_init_xr()
	load_settings()
	if not xr_active:
		# Desktop / CI: no headset, so start the room straight away (no anchors).
		start_rooms.call_deferred()
	if selftest:
		var t = load("res://scripts/selftest.gd").new()
		add_child(t)
		t.run.call_deferred(self)


func _init_xr() -> void:
	xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.is_initialized() and not selftest:
		xr_active = true
		var vp := get_viewport()
		vp.use_xr = true
		vp.transparent_bg = true
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		if xr_interface.get_supported_environment_blend_modes().has(XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND):
			xr_interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
		xr_interface.session_begun.connect(_on_session_begun)
		xr_interface.session_stopping.connect(_on_session_stopping)
		if xr_interface.has_signal("pose_recentered"):
			xr_interface.pose_recentered.connect(_on_recentered)
	else:
		print("Framespace: OpenXR not running (desktop/CI mode).")


func _on_session_begun() -> void:
	# Give tracking a moment to settle before placing or finding the room anchor.
	await get_tree().create_timer(1.0).timeout
	start_rooms()


func _on_session_stopping() -> void:
	save_room_now()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_room_now()


func _unlit(color: Color, no_depth := false, alpha := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.no_depth_test = no_depth
	if alpha or color.a < 1.0 or no_depth:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _lines_mesh(pts: PackedVector3Array, strip := false) -> ArrayMesh:
	var am := ArrayMesh.new()
	if pts.size() < 2:
		return am
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pts
	am.add_surface_from_arrays(Mesh.PRIMITIVE_LINE_STRIP if strip else Mesh.PRIMITIVE_LINES, arr)
	return am


func _circle_pts(pts: PackedVector3Array, fn: Callable, n := 48) -> void:
	for i in n:
		pts.append(fn.call(float(i) / n * TAU))
		pts.append(fn.call(float(i + 1) / n * TAU))


func _build_assets() -> void:
	# Unit wireframes (scaled per shape) ------------------------------------------------
	var b := PackedVector3Array()
	for a in [-0.5, 0.5]:
		for c in [-0.5, 0.5]:
			b.append_array([Vector3(-0.5, a, c), Vector3(0.5, a, c), Vector3(a, -0.5, c), Vector3(a, 0.5, c), Vector3(a, c, -0.5), Vector3(a, c, 0.5)])
	unit_wire["box"] = _lines_mesh(b)
	var s := PackedVector3Array()
	for k in 12:
		var ang := float(k) / 12 * PI
		_circle_pts(s, func(t): return Vector3(cos(ang) * sin(t) * 0.5, cos(t) * 0.5, sin(ang) * sin(t) * 0.5))
	for r in range(1, 6):
		var phi := float(r) / 6 * PI
		var y := cos(phi) * 0.5
		var rad := sin(phi) * 0.5
		_circle_pts(s, func(t): return Vector3(cos(t) * rad, y, sin(t) * rad))
	unit_wire["sphere"] = _lines_mesh(s)
	var cy := PackedVector3Array()
	_circle_pts(cy, func(t): return Vector3(cos(t) * 0.5, 0.5, sin(t) * 0.5), 32)
	_circle_pts(cy, func(t): return Vector3(cos(t) * 0.5, -0.5, sin(t) * 0.5), 32)
	for k in 16:
		var t := float(k) / 16 * TAU
		cy.append_array([Vector3(cos(t) * 0.5, -0.5, sin(t) * 0.5), Vector3(cos(t) * 0.5, 0.5, sin(t) * 0.5)])
	unit_wire["cylinder"] = _lines_mesh(cy)
	var co := PackedVector3Array()
	_circle_pts(co, func(t): return Vector3(cos(t) * 0.5, -0.5, sin(t) * 0.5), 32)
	for k in 16:
		var t := float(k) / 16 * TAU
		co.append_array([Vector3(cos(t) * 0.5, -0.5, sin(t) * 0.5), Vector3(0, 0.5, 0)])
	unit_wire["cone"] = _lines_mesh(co)

	# Unit fills ---------------------------------------------------------------------
	var bm := BoxMesh.new()
	unit_fill["box"] = bm
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	unit_fill["sphere"] = sm
	var cm := CylinderMesh.new()
	cm.top_radius = 0.5
	cm.bottom_radius = 0.5
	cm.height = 1.0
	unit_fill["cylinder"] = cm
	var km := CylinderMesh.new()
	km.top_radius = 0.0
	km.bottom_radius = 0.5
	km.height = 1.0
	unit_fill["cone"] = km

	mesh_dot = SphereMesh.new()
	mesh_dot.radius = 0.006
	mesh_dot.height = 0.012
	mat_dot = _unlit(C_YELLOW, true)
	mat_dot.render_priority = 5
	mat_measure = _unlit(C_YELLOW, true)
	mat_measure.render_priority = 5
	mesh_handle = BoxMesh.new()
	mesh_handle.size = Vector3(0.03, 0.03, 0.03)
	mat_handle["face"] = _unlit(Color("ffe14d"))
	mat_handle["radius"] = _unlit(Color("ff8a1f"))


func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	origin = XROrigin3D.new()
	origin.name = "Origin"
	add_child(origin)
	camera = XRCamera3D.new()
	camera.name = "Camera"
	camera.position = Vector3(0, 1.6, 0)
	camera.near = 0.01
	camera.far = 60.0
	origin.add_child(camera)

	content = Node3D.new()
	content.name = "Content"
	origin.add_child(content)

	for hand in ["left", "right"]:
		var c := Ctrl.new()
		c.hand = hand
		c.node = XRController3D.new()
		c.node.name = hand.capitalize() + "Hand"
		c.node.tracker = &"left_hand" if hand == "left" else &"right_hand"
		c.node.pose = &"aim"
		origin.add_child(c.node)
		c.ray = MeshInstance3D.new()
		c.ray.mesh = _lines_mesh(PackedVector3Array([Vector3.ZERO, Vector3(0, 0, -1)]))
		c.ray.material_override = _unlit(Color(1, 1, 1, 0.5))
		c.node.add_child(c.ray)
		c.reticle = MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.008
		tm.outer_radius = 0.014
		tm.rings = 24
		tm.ring_segments = 4
		c.reticle.mesh = tm
		c.reticle.material_override = _unlit(C_CYAN, true)
		c.reticle.visible = false
		content.add_child(c.reticle)
		ctrls.append(c)

	# Meta scene understanding (walls, floor, tables, room mesh from Space Setup) and spatial anchors.
	if ClassDB.class_exists("OpenXRFbSceneManager"):
		scene_mgr = ClassDB.instantiate("OpenXRFbSceneManager")
		scene_mgr.name = "SceneManager"
		scene_mgr.set("default_scene", SceneAnchorScene)
		scene_mgr.set("auto_create", true)
		origin.add_child(scene_mgr)
		scene_mgr.connect("openxr_fb_scene_data_missing", _on_scene_data_missing)
		scene_mgr.connect("openxr_fb_scene_capture_completed", _on_scene_capture_completed)
	if ClassDB.class_exists("OpenXRFbSpatialAnchorManager"):
		anchor_mgr = ClassDB.instantiate("OpenXRFbSpatialAnchorManager")
		anchor_mgr.name = "AnchorManager"
		origin.add_child(anchor_mgr)
		anchor_mgr.connect("openxr_fb_spatial_anchor_tracked", _on_anchor_tracked)
		anchor_mgr.connect("openxr_fb_spatial_anchor_create_failed", _on_anchor_create_failed)
		anchor_mgr.connect("openxr_fb_spatial_anchor_load_failed", _on_anchor_load_failed)

	menu = UIPanel.new()
	menu.name = "Menu"
	add_child(menu)
	palette = UIPanel.new()
	palette.name = "Palette"
	add_child(palette)
	ctx = UIPanel.new()
	ctx.name = "Context"
	add_child(ctx)

	grid_patch = MeshInstance3D.new()
	grid_patch.material_override = _unlit(Color(0, 0.9, 1, 0.35))
	grid_patch.visible = false
	content.add_child(grid_patch)

	preview = MeshInstance3D.new()
	preview.material_override = mat_measure
	preview.visible = false
	content.add_child(preview)
	preview_label = make_label(C_YELLOW)
	preview_label.visible = false
	content.add_child(preview_label)


# ================================================================ formatting
func L(m: float) -> String:
	if units == "metric":
		return ("%.1f cm" % (m * 100.0)) if m < 1.0 else ("%.3f m" % m)
	var inch := m / 0.0254
	if inch < 36.0:
		return "%.2f in" % inch
	var ft := floori(inch / 12.0)
	return "%d ft %.1f in" % [ft, inch - ft * 12.0]


func VOL(m3: float) -> String:
	if units == "metric":
		return ("%.2f L" % (m3 * 1000.0)) if m3 < 1.0 else ("%.3f m³" % m3)
	return "%.3f ft³ (%.2f gal)" % [m3 * 35.3147, m3 * 264.172]


func AREA(m2: float) -> String:
	return ("%.2f m²" % m2) if units == "metric" else ("%.1f ft²" % (m2 * 10.7639))


# ================================================================ labels
func make_label(accent: Color) -> Node3D:
	var n := Node3D.new()
	for i in 3:
		var l := Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.render_priority = 20
		l.fixed_size = false
		l.pixel_size = 0.0005
		l.font_size = 40 if i == 0 else 32
		l.outline_size = 10
		l.outline_modulate = Color(0, 0, 0, 0.85)
		l.modulate = accent if i == 0 else Color.WHITE
		l.position = Vector3(0, -i * 0.019, 0)
		n.add_child(l)
	return n


func set_label(n: Node3D, lines: Array, accent = null) -> void:
	for i in n.get_child_count():
		var l: Label3D = n.get_child(i)
		l.text = lines[i] if i < lines.size() else ""
		if i == 0 and accent != null:
			l.modulate = accent


func make_room_label(label_name: String, size: Vector2) -> Label3D:
	var l := Label3D.new()
	l.text = "%s\n%s × %s · %s" % [label_name.capitalize(), L(size.x), L(size.y), AREA(size.x * size.y)]
	l.pixel_size = 0.0006
	l.font_size = 36
	l.modulate = C_CYAN
	l.outline_size = 8
	l.double_sided = true
	l.no_depth_test = false
	return l


func register_surface(n: Node3D) -> void:
	surfaces.append(n)


func _on_scene_data_missing() -> void:
	set_status("No Space Setup found. Open the menu > Scan room to map walls and tables.")


func _on_scene_capture_completed(_ok: bool) -> void:
	if scene_mgr:
		scene_mgr.call("remove_scene_anchors")
		surfaces.clear()
		scene_mgr.call("create_scene_anchors")
	set_status("Room scan finished.")


# ================================================================ shapes
func scale_of(type: String, d: Dictionary) -> Vector3:
	if type == "box":
		return Vector3(d.x, d.y, d.z)
	if type == "sphere":
		return Vector3.ONE * 2.0 * d.r
	return Vector3(2.0 * d.r, d.h, 2.0 * d.r)


func half_height(s: Shape) -> float:
	return scale_of(s.type, s.dims).y / 2.0


func volume_of(type: String, d: Dictionary) -> float:
	match type:
		"box": return d.x * d.y * d.z
		"sphere": return 4.0 / 3.0 * PI * pow(d.r, 3)
		"cylinder": return PI * d.r * d.r * d.h
		"cone": return PI * d.r * d.r * d.h / 3.0
	return 0.0


func shape_lines(type: String, sname: String, d: Dictionary) -> Array:
	var v := "Vol " + VOL(volume_of(type, d))
	match type:
		"box": return [sname, "W %s × H %s × D %s" % [L(d.x), L(d.y), L(d.z)], v]
		"sphere": return [sname, "r %s · Ø %s" % [L(d.r), L(2 * d.r)], v]
		"cylinder": return [sname, "r %s · Ø %s · H %s" % [L(d.r), L(2 * d.r), L(d.h)], v]
		"cone": return [sname, "r %s · H %s · slant %s" % [L(d.r), L(d.h), L(Vector2(d.r, d.h).length())], v]
	return [sname]


func dims_text(s: Shape) -> String:
	return shape_lines(s.type, s.name, s.dims)[1]


func handle_defs(type: String) -> Array:
	match type:
		"box":
			var out := []
			for a in [[Vector3.RIGHT, "x"], [Vector3.LEFT, "x"], [Vector3.UP, "y"], [Vector3.DOWN, "y"], [Vector3.BACK, "z"], [Vector3.FORWARD, "z"]]:
				out.append({"axis": a[0], "key": a[1], "mode": "face"})
			return out
		"sphere":
			return [{"axis": Vector3.RIGHT, "key": "r", "mode": "radius"}, {"axis": Vector3.UP, "key": "r", "mode": "radius"}]
	return [{"axis": Vector3.RIGHT, "key": "r", "mode": "radius"}, {"axis": Vector3.BACK, "key": "r", "mode": "radius"},
		{"axis": Vector3.UP, "key": "h", "mode": "face"}, {"axis": Vector3.DOWN, "key": "h", "mode": "face"}]


func make_shape(type: String, dims: Dictionary, pos: Vector3, rot := Quaternion.IDENTITY, sname := "", outline = null) -> Shape:
	var s := Shape.new()
	s.type = type
	s.dims = dims.duplicate()
	s.color = COLORS[type]
	if sname == "":
		counters[type] += 1
		sname = "%s %d" % [NAMES[type], counters[type]]
	s.name = sname
	s.node = Node3D.new()
	s.node.position = pos
	s.node.quaternion = rot
	s.wire = MeshInstance3D.new()
	if type == "box" and outline is Dictionary and outline.has("pts"):
		s.outline = outline
		s.wire.mesh = outline_mesh(outline)
	else:
		s.wire.mesh = unit_wire[type]
	s.wire_mat = _unlit(s.color)
	s.wire.material_override = s.wire_mat
	s.fill = MeshInstance3D.new()
	s.fill.mesh = unit_fill[type]
	s.fill_mat = _unlit(Color(s.color, 0.06), false, true)
	s.fill_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	s.fill_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	s.fill.material_override = s.fill_mat
	s.body = StaticBody3D.new()
	s.body.collision_layer = LAYER_SHAPE
	s.body.collision_mask = 0
	s.body.set_meta("shape", s)
	s.col = CollisionShape3D.new()
	s.body.add_child(s.col)
	s.label = make_label(s.color)
	s.node.add_child(s.wire)
	s.node.add_child(s.fill)
	s.node.add_child(s.body)
	s.node.add_child(s.label)
	content.add_child(s.node)
	shapes.append(s)
	refresh_shape(s)
	return s


func refresh_shape(s: Shape) -> void:
	var sc := scale_of(s.type, s.dims)
	s.wire.scale = sc
	s.fill.scale = sc
	match s.type:
		"box":
			var bs := s.col.shape as BoxShape3D
			if bs == null:
				bs = BoxShape3D.new()
				s.col.shape = bs
			bs.size = sc
		"sphere":
			var ss := s.col.shape as SphereShape3D
			if ss == null:
				ss = SphereShape3D.new()
				s.col.shape = ss
			ss.radius = s.dims.r
		"cylinder":
			var cs := s.col.shape as CylinderShape3D
			if cs == null:
				cs = CylinderShape3D.new()
				s.col.shape = cs
			cs.radius = s.dims.r
			cs.height = s.dims.h
		"cone":
			var pts := PackedVector3Array([Vector3(0, s.dims.h / 2.0, 0)])
			for k in 16:
				var t := float(k) / 16 * TAU
				pts.append(Vector3(cos(t) * s.dims.r, -s.dims.h / 2.0, sin(t) * s.dims.r))
			var cv := ConvexPolygonShape3D.new()
			cv.points = pts
			s.col.shape = cv
	s.label.position = Vector3(0, sc.y / 2.0 + 0.09, 0)
	set_label(s.label, shape_lines(s.type, s.name, s.dims))
	for h in s.handles:
		var hd: Dictionary = h.get_meta("hd")
		var e: float = s.dims.r if hd.mode == "radius" else extent(s, hd.key) / 2.0
		h.position = hd.axis * (e + 0.015)


func extent(s: Shape, key: String) -> float:
	return s.dims[key]


func remove_shape(s: Shape) -> void:
	if selected == s:
		select(null)
	if s.node.get_parent():
		content.remove_child(s.node)
	shapes.erase(s)


func restore_shape(s: Shape) -> void:
	if not shapes.has(s):
		content.add_child(s.node)
		shapes.append(s)


func snapshot(s: Shape) -> Dictionary:
	return {"dims": s.dims.duplicate(), "pos": s.node.position, "rot": s.node.quaternion}


func apply_snapshot(s: Shape, sn: Dictionary) -> void:
	s.dims = sn.dims.duplicate()
	s.node.position = sn.pos
	s.node.quaternion = sn.rot
	refresh_shape(s)


func select(s: Shape) -> void:
	var prev := selected
	if prev:
		prev.wire_mat.albedo_color = prev.color
		prev.fill_mat.albedo_color = Color(prev.color, 0.06)
		for h in prev.handles:
			h.queue_free()
		prev.handles = []
	selected = s
	if s:
		s.wire_mat.albedo_color = Color.WHITE
		s.fill_mat.albedo_color = Color(s.color, 0.14)
		for hd in handle_defs(s.type):
			var h := MeshInstance3D.new()
			h.mesh = mesh_handle
			h.material_override = mat_handle[hd.mode]
			hd["shape"] = s
			h.set_meta("hd", hd)
			var hb := StaticBody3D.new()
			hb.collision_layer = LAYER_HANDLE
			hb.collision_mask = 0
			hb.set_meta("handle", h)
			var hc := CollisionShape3D.new()
			var hs := BoxShape3D.new()
			hs.size = Vector3(0.04, 0.04, 0.04)
			hc.shape = hs
			hb.add_child(hc)
			h.add_child(hb)
			s.node.add_child(h)
			s.handles.append(h)
		refresh_shape(s)
	menu_dirty = true


# ================================================================ measurements
func circle_from_3(a: Vector3, b: Vector3, c: Vector3):
	var ab := b - a
	var ac := c - a
	var n := ab.cross(ac)
	var n2 := n.length_squared()
	if n2 < 1e-8:
		return null
	var center := a + (n.cross(ab) * ac.length_squared() + ac.cross(n) * ab.length_squared()) / (2.0 * n2)
	return {"center": center, "normal": n.normalized(), "r": center.distance_to(a)}


func measure_lines(m: Measure) -> Array:
	if m.type == "line":
		var dv: Vector3 = m.points[1] - m.points[0]
		return ["%s  %s" % [m.name, L(dv.length())], "vert %s · horiz %s" % [L(absf(dv.y)), L(Vector2(dv.x, dv.z).length())]]
	return ["%s  Ø %s" % [m.name, L(2 * m.r)], "r %s · circ %s" % [L(m.r), L(TAU * m.r)]]


func _dot(p: Vector3) -> MeshInstance3D:
	var d := MeshInstance3D.new()
	d.mesh = mesh_dot
	d.material_override = mat_dot
	d.position = p
	return d


func create_measure(type: String, points: Array, mname := "") -> Measure:
	var m := Measure.new()
	m.type = type
	m.points = points.duplicate()
	if mname == "":
		counters.m += 1
		mname = "M%d" % counters.m
	m.name = mname
	m.node = Node3D.new()
	var label_pos: Vector3
	for p in m.points:
		m.node.add_child(_dot(p))
	var li := MeshInstance3D.new()
	li.material_override = mat_measure
	if type == "line":
		li.mesh = _lines_mesh(PackedVector3Array(m.points))
		label_pos = (m.points[0] + m.points[1]) / 2.0
	else:
		var c = circle_from_3(m.points[0], m.points[1], m.points[2])
		if c == null:
			return null
		m.center = c.center
		m.normal = c.normal
		m.r = c.r
		var u: Vector3 = (m.points[0] - m.center).normalized()
		var v: Vector3 = m.normal.cross(u)
		var pts := PackedVector3Array()
		for i in 65:
			var t := float(i) / 64 * TAU
			pts.append(m.center + u * cos(t) * m.r + v * sin(t) * m.r)
		li.mesh = _lines_mesh(pts, true)
		m.node.add_child(_dot(m.center))
		label_pos = m.center
	m.node.add_child(li)
	var lbl := make_label(C_YELLOW)
	lbl.position = label_pos + Vector3(0, 0.05, 0)
	set_label(lbl, measure_lines(m))
	lbl.name = "Label"
	m.node.add_child(lbl)
	content.add_child(m.node)
	measures.append(m)
	return m


func refresh_measure_label(m: Measure) -> void:
	var lbl = m.node.get_node_or_null("Label")
	if lbl:
		set_label(lbl, measure_lines(m))


func remove_measure(m: Measure) -> void:
	if m.node.get_parent():
		content.remove_child(m.node)
	measures.erase(m)


func restore_measure(m: Measure) -> void:
	if not measures.has(m):
		content.add_child(m.node)
		measures.append(m)


func clear_pending() -> void:
	for d in pending_dots:
		d.queue_free()
	pending = []
	pending_dots = []
	preview.visible = false
	preview_label.visible = false


func add_pending_point(p: Vector3) -> void:
	pending.append(p)
	var dot := _dot(p)
	content.add_child(dot)
	pending_dots.append(dot)
	var need := 2 if mode == "tape" else 3
	if pending.size() < need:
		set_status("Now point at the second end." if mode == "tape" else "Point %d of 3 on the round edge." % (pending.size() + 1))
		return
	var m := create_measure("line" if mode == "tape" else "circle", pending)
	clear_pending()
	if m == null:
		set_status("Those 3 points are in a line. Try again, spread them out.")
		return
	push_history(func(): remove_measure(m))
	set_status("%s: %s" % [m.name, measure_lines(m)[0].replace(m.name, "").strip_edges()])
	persist()


# ================================================================ history / clipboard
func push_history(undo_fn: Callable) -> void:
	history.append(undo_fn)
	if history.size() > 60:
		history.pop_front()


func undo() -> void:
	if pending.size():
		clear_pending()
		set_status("Cancelled the measurement in progress.")
		return
	if history.is_empty():
		set_status("Nothing to undo.")
		return
	var fn: Callable = history.pop_back()
	fn.call()
	set_status("Undone.")
	persist()


func clip_item(s: Shape) -> Dictionary:
	return {"type": s.type, "dims": s.dims.duplicate(), "rot": s.node.quaternion, "name": s.name, "outline": s.outline}


func copy_selected(cut: bool) -> void:
	var s := selected
	if s == null:
		set_status("Select a shape first.")
		return
	clipboard.push_front(clip_item(s))
	if clipboard.size() > CLIP_MAX:
		clipboard.pop_back()
	clip_index = 0
	if cut:
		remove_shape(s)
		push_history(func(): restore_shape(s))
		set_status("Cut %s. Point somewhere and Paste." % s.name)
		persist()
	else:
		set_status("Copied %s. Point somewhere and Paste." % s.name)


func paste_at(point: Vector3, it = null, offset = null) -> void:
	if it == null:
		it = clipboard[clip_index] if clipboard.size() else null
	if it == null:
		set_status("Clipboard is empty. Copy or Cut a shape first.")
		return
	var s := make_shape(it.type, it.dims, point, it.rot, "", it.get("outline"))
	if offset != null:
		s.node.position += offset
	else:
		s.node.position.y += half_height(s)
	settle(s)
	select(s)
	push_history(func(): remove_shape(s))
	set_status("Pasted %s (copy of %s)." % [s.name, it.name])
	persist()


func set_status(t: String) -> void:
	status = t
	menu_dirty = true
	if selftest:
		print("status: ", t)


# ================================================================ grid, support, settling
func snap_grid(v: float) -> float:
	return roundf(v / grid) * grid if grid > 0.0 else v


func yaw_of_quat(q: Quaternion) -> float:
	return Basis(q).get_euler(EULER_ORDER_YXZ).y


func snap_yaw_quat(q: Quaternion) -> Quaternion:
	var step := PI / 4.0
	return Quaternion(Vector3.UP, roundf(yaw_of_quat(q) / step) * step)


## Highest surface under content-local (x, z) at or below max_y: a real surface from Space Setup,
## the top of another shape, or the floor.
func support_below(x: float, z: float, max_y: float, exclude: Shape) -> float:
	var from_w := content.to_global(Vector3(x, max_y + 0.01, z))
	var floor_y := content.to_local(Vector3(from_w.x, 0.0, from_w.z)).y
	var best := floor_y
	if not is_inside_tree():
		return best
	var space := get_world_3d().direct_space_state
	var ex: Array[RID] = []
	if exclude:
		ex.append(exclude.body.get_rid())
	for f in falling:
		ex.append(f.shape.body.get_rid())
	for i in 6:
		var q := PhysicsRayQueryParameters3D.create(from_w, from_w + Vector3.DOWN * 30.0, LAYER_ROOM | LAYER_SHAPE, ex)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			break
		if hit.normal.y > 0.7:
			best = maxf(best, content.to_local(hit.position).y)
			break
		ex.append(hit.rid)
	# Shapes' tops, done directly too (physics broadphase can lag a frame behind moved shapes).
	for s in shapes:
		if s == exclude or _is_falling(s):
			continue
		var top = _shape_top_at(s, x, z)
		if top != null and top <= max_y + 0.01 and top > best:
			best = top
	return best


func _is_falling(s: Shape) -> bool:
	for f in falling:
		if f.shape == s:
			return true
	return false


## Top of a shape's axis-aligned bounds at (x, z), or null when (x, z) is outside it.
func _shape_top_at(s: Shape, x: float, z: float):
	var sc := scale_of(s.type, s.dims) / 2.0
	var b := Basis(s.node.quaternion)
	var ext := Vector3.ZERO
	for i in 3:
		var axis: Vector3 = b[i] * sc[i]
		ext += axis.abs()
	var p := s.node.position
	if x >= p.x - ext.x and x <= p.x + ext.x and z >= p.z - ext.z and z <= p.z + ext.z:
		return p.y + ext.y
	return null


## Square the shape to the grid (yaw in 45° steps, X/Z on grid points) and let it fall onto what is below.
func settle(s: Shape) -> void:
	s.node.quaternion = snap_yaw_quat(s.node.quaternion)
	s.node.position.x = snap_grid(s.node.position.x)
	s.node.position.z = snap_grid(s.node.position.z)
	refresh_shape(s)
	var hh := half_height(s)
	var bottom := s.node.position.y - hh
	var sup := support_below(s.node.position.x, s.node.position.z, bottom + 0.02, s)
	falling = falling.filter(func(f): return f.shape != s)
	if bottom - sup > 0.005 and not selftest:
		falling.append({"shape": s, "from": s.node.position.y, "to": sup + hh, "t0": Time.get_ticks_msec()})
	else:
		s.node.position.y = sup + hh
	refresh_shape(s)


func update_falling() -> void:
	var now := Time.get_ticks_msec()
	var keep := []
	for f in falling:
		var t: float = (now - f.t0) / 1000.0
		var y: float = f.from - 4.9 * t * t
		if y <= f.to:
			f.shape.node.position.y = f.to
			persist()
		else:
			f.shape.node.position.y = y
			keep.append(f)
	falling = keep


func show_grid_patch(x: float, y: float, z: float) -> void:
	if grid <= 0.0:
		grid_patch.visible = false
		return
	if grid_patch_size != grid:
		var n := roundi(1.0 / grid)
		var pts := PackedVector3Array()
		for i in n + 1:
			var t := -0.5 + float(i) / n
			pts.append_array([Vector3(t, 0, -0.5), Vector3(t, 0, 0.5), Vector3(-0.5, 0, t), Vector3(0.5, 0, t)])
		grid_patch.mesh = _lines_mesh(pts)
		grid_patch_size = grid
	grid_patch.position = Vector3(snap_grid(x), y + 0.002, snap_grid(z))
	grid_patch.visible = true


# ================================================================ main menu (stick click)
func button_text(id: String) -> String:
	match id:
		"box": return "+ Box"
		"sphere": return "+ Sphere"
		"cylinder": return "+ Cylinder"
		"cone": return "+ Cone"
		"tape": return "Tape"
		"circle": return "Circle 3-pt"
		"select": return "Move/Size"
		"units": return "Units: cm" if units == "metric" else "Units: in"
		"copy": return "Copy"
		"cut": return "Cut"
		"paste": return "Paste"
		"nextclip": return "Next clip"
		"duplicate": return "Duplicate"
		"drop": return "Drop"
		"delete": return "Delete"
		"undo": return "Undo"
		"grid": return ("Grid: %d cm" % roundi(grid * 100)) if grid > 0 else "Grid: off"
		"roomvis": return "Room lines: on" if room_visible else "Room lines: off"
		"scan": return "Scan room"
		"clear": return "Clear all"
		"save": return "Save room"
		"rooms": return "Rooms..."
		"export": return "Export"
		"quit": return "Quit app"
	return id


func button_enabled(id: String) -> bool:
	if id in ["copy", "cut", "duplicate", "drop", "delete"]:
		return selected != null
	if id in ["paste", "nextclip"]:
		return clipboard.size() > 0
	return true


func menu_items() -> Array:
	var out := []
	if menu_page == "rooms":
		out.append({"id": "back", "label": "< Back"})
		out.append({"id": "newroom", "label": "New room", "color": C_CYAN})
		out.append({"id": "save", "label": "Save room"})
		out.append({"id": "delroom", "label": "Delete this room", "color": Color("ff6b6b")})
		out.append({"id": "placehere", "label": "Place room here", "sub": "where you stand, facing your way"})
		out.append({"id": "placement", "label": "Placement: where I stand" if placement == "stand" else "Placement: anchor",
			"sub": "recenter to line up" if placement == "stand" else "pinned to this spot"})
		for r in list_rooms():
			out.append({"id": "room:" + r.id, "label": r.name, "sub": "%d shapes · %s" % [r.count, r.updated], "active": r.id == room.get("id", "")})
		return out
	for id in MENU_MAIN:
		out.append({"id": id, "label": button_text(id), "enabled": button_enabled(id),
			"active": (id == mode), "color": Color("ff6b6b") if id == "quit" else Color.WHITE})
	return out


func menu_header() -> Array:
	var clip = clipboard[clip_index] if clipboard.size() else null
	var mode_name: String = {"select": "Move/Size", "tape": "Tape", "circle": "Circle 3-pt"}[mode]
	var anchor_txt: String = "placed where you stood" if placement == "stand" else {"none": "not anchored", "creating": "anchoring...", "loading": "finding anchor...", "tracked": "anchored", "failed": "anchor not found"}[anchor_state]
	return [
		[status, Color.WHITE],
		["Mode: %s   ·   %s (%s)" % [mode_name, room.get("name", "-"), anchor_txt], Color(0.6, 0.65, 0.7)],
		["Clipboard %d/%d: %s" % [clip_index + 1, clipboard.size(), clip.name] if clip else "Clipboard: empty", C_YELLOW],
	]


func rebuild_menu() -> void:
	menu.build("FRAMESPACE  " + BUILD if menu_page == "main" else "ROOMS", menu_header(), menu_items(), 4, 0.085)
	menu_dirty = false


func open_menu(c: Ctrl, fixed: bool) -> void:
	menu_page = "main"
	menu_attach = null if fixed else c
	rebuild_menu()
	var head := camera.global_position
	var pos: Vector3
	if fixed:
		var fwd := -camera.global_basis.z
		fwd.y = 0
		fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
		pos = head + fwd * 0.55 + Vector3(0, -0.15, 0)
	else:
		pos = _menu_hand_pos(c)
	menu.open_at(pos, head)
	haptic(c, 0.4, 0.03)


func _menu_hand_pos(c: Ctrl) -> Vector3:
	# Just above the controller, nudged toward the other hand so it doesn't hide the holding hand.
	var p := c.node.global_position
	var head := camera.global_position
	var to_head := head - p
	to_head.y = 0
	var side := Vector3.UP.cross(to_head.normalized()) * (0.08 if c.hand == "left" else -0.08)
	return p + Vector3(0, 0.17, 0) + side


func close_menu() -> void:
	menu.close()
	menu_attach = null


func on_button(id: String, c: Ctrl = null) -> void:
	if not button_enabled(id):
		set_status("Clipboard is empty." if id in ["paste", "nextclip"] else "Select a shape first (Move/Size mode, point and trigger).")
		return
	if id.begins_with("room:"):
		load_room(id.substr(5))
		menu_page = "main"
		menu_dirty = true
		return
	match id:
		"box", "sphere", "cylinder", "cone":
			var p := spawn_point()
			var s := make_shape(id, DEFAULT_DIMS[id], p)
			s.node.position.y += half_height(s)
			settle(s)
			mode = "select"
			clear_pending()
			select(s)
			push_history(func(): remove_shape(s))
			set_status("Added %s. Grab to move, drag yellow cubes to resize." % s.name)
			persist()
		"tape":
			mode = "tape"
			clear_pending()
			select(null)
			set_status("Tape: point at the first end and press trigger.")
		"circle":
			mode = "circle"
			clear_pending()
			select(null)
			set_status("Circle: tap 3 points around a round edge.")
		"select":
			mode = "select"
			clear_pending()
			set_status("Move/Size: point at a shape and trigger to select it.")
		"units":
			units = "imperial" if units == "metric" else "metric"
			for s in shapes:
				refresh_shape(s)
			for m in measures:
				refresh_measure_label(m)
			set_status("Units: %s." % units)
			persist()
		"copy": copy_selected(false)
		"cut": copy_selected(true)
		"paste":
			var other = _other_target(c)
			paste_at(other if other != null else spawn_point())
		"nextclip":
			clip_index = (clip_index + 1) % clipboard.size()
			set_status("Next clipboard item. Press Paste to place it.")
		"duplicate":
			var s := selected
			var dx: Vector3 = (s.node.quaternion * Vector3.RIGHT) * (scale_of(s.type, s.dims).x + 0.05)
			paste_at(s.node.position, clip_item(s), dx)
		"drop":
			var s := selected
			var sn := snapshot(s)
			push_history(func(): apply_snapshot(s, sn))
			settle(s)
			set_status("Dropped %s onto the surface below." % s.name)
			persist()
		"delete":
			var s := selected
			remove_shape(s)
			push_history(func(): restore_shape(s))
			set_status("Deleted %s. Undo brings it back." % s.name)
			persist()
		"undo": undo()
		"roomvis":
			room_visible = not room_visible
			if scene_mgr:
				scene_mgr.set("visible", room_visible)
		"scan":
			if scene_mgr and scene_mgr.call("is_scene_capture_supported"):
				scene_mgr.call("request_scene_capture")
				set_status("Opening Space Setup...")
			else:
				set_status("Room scan isn't available here.")
		"clear":
			var ss := shapes.duplicate()
			var ms := measures.duplicate()
			for s in ss:
				remove_shape(s)
			for m in ms:
				remove_measure(m)
			clear_pending()
			push_history(_restore_all.bind(ss, ms))
			set_status("Cleared. Undo brings everything back.")
			persist()
		"grid":
			var opts := [0.05, 0.1, 0.01, 0.0]
			var i := 0
			for k in opts.size():
				if is_equal_approx(opts[k], grid):
					i = k
			grid = opts[(i + 1) % opts.size()]
			set_status(("Grid %d cm" % roundi(grid * 100)) if grid > 0 else "Grid off")
			persist()
		"save":
			save_room_now()
			set_status("Saved %s." % room.get("name", "room"))
		"rooms":
			menu_page = "rooms"
		"back":
			menu_page = "main"
		"newroom":
			new_room()
			menu_page = "main"
		"delroom":
			delete_current_room()
			menu_page = "main"
		"placehere":
			place_here()
			set_status("%s placed where you stand, facing where you face." % room.get("name", "Room"))
		"placement":
			set_placement("anchor" if placement == "stand" else "stand")
		"export":
			export_all()
		"quit":
			save_room_now()
			get_tree().quit()
	menu_dirty = true


func _restore_all(ss: Array, ms: Array) -> void:
	for s in ss:
		restore_shape(s)
	for m in ms:
		restore_measure(m)


func _other_target(c: Ctrl):
	for o in ctrls:
		if o != c and o.target != null:
			return o.target.point
	return null


func spawn_point() -> Vector3:
	var c := last_ctrl
	if c and c.target != null:
		return c.target.point
	var head := content.to_local(camera.global_position)
	var fwd := content.global_basis.inverse() * -camera.global_basis.z
	fwd.y = 0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var p := head + fwd * 0.7
	p.y = maxf(0.0, head.y - 0.6)
	return p


# ================================================================ palette (hold X) and context menu (hold A)
func short_dims(type: String, d: Dictionary) -> String:
	var metric := units == "metric"
	var k := 100.0 if metric else 1.0 / 0.0254
	var unit := "cm" if metric else "in"
	var n := func(v): return ("%d" % roundi(v * k)) if metric else ("%.1f" % (v * k))
	if type == "box":
		return "%s×%s×%s %s" % [n.call(d.x), n.call(d.y), n.call(d.z), unit]
	if type == "sphere":
		return "Ø %s %s" % [n.call(2 * d.r), unit]
	return "Ø %s × %s %s" % [n.call(2 * d.r), n.call(d.h), unit]


func open_palette(c: Ctrl) -> void:
	var items := []
	for i in PALETTE.size():
		var p: Dictionary = PALETTE[i]
		items.append({"id": "p%d" % i, "label": p.label, "sub": short_dims(p.type, p.dims), "color": COLORS[p.type], "index": i})
	palette.build("Objects", [], items, 6, 0.07)
	var head := camera.global_position
	var pos := c.node.global_position
	var away := pos - head
	away.y = 0
	away = away.normalized() if away.length() > 0.001 else -camera.global_basis.z
	palette.open_at(pos + away * 0.12 + Vector3(0, 0.12, 0), head)
	haptic(c, 0.3, 0.02)


func spawn_from_palette(c: Ctrl, id: String, point_w: Vector3) -> void:
	var it = palette.item(id)
	if it == null:
		return
	var p: Dictionary = PALETTE[it.index]
	label_counts[p.label] = int(label_counts.get(p.label, 0)) + 1
	var s := make_shape(p.type, p.dims, content.to_local(point_w), Quaternion.IDENTITY, "%s %d" % [p.label, label_counts[p.label]], p.get("outline"))
	push_history(func(): remove_shape(s))
	select(s)
	start_free(c, s, false)
	haptic(c, 0.5, 0.04)
	set_status("Placing %s" % s.name)
	persist()


func open_context(c: Ctrl) -> void:
	var s = c.shape_hit.shape if c.shape_hit != null else null
	var head := camera.global_position
	var anchor_l: Vector3
	if s:
		select(s)
		anchor_l = c.shape_hit.point
		ctx.build(s.name, [], [{"id": "cut", "label": "Cut"}, {"id": "copy", "label": "Copy"},
			{"id": "delete", "label": "Delete", "color": Color("ff6b6b")}, {"id": "duplicate", "label": "Duplicate"}], 2, 0.09)
	else:
		anchor_l = c.target.point if c.target != null else c.o + c.d * 0.8
		var clip = clipboard[clip_index] if clipboard.size() else null
		ctx.build(("Clipboard %d/%d: %s" % [clip_index + 1, clipboard.size(), clip.name]) if clip else "Clipboard empty", [],
			[{"id": "paste", "label": "Paste", "enabled": clip != null}, {"id": "nextclip", "label": "Next clip", "enabled": clipboard.size() > 1}], 2, 0.09)
	ctx.target = s
	ctx.point = anchor_l
	var aw := content.to_global(anchor_l)
	var pos := aw + (head - aw).normalized() * minf(0.3, aw.distance_to(head) * 0.4) + Vector3(0, 0.08, 0)
	ctx.open_at(pos, head)
	haptic(c, 0.4, 0.03)


func run_context(id: String) -> void:
	var s = ctx.target
	var p: Vector3 = ctx.point
	ctx.close()
	match id:
		"cut":
			if s:
				select(s)
				copy_selected(true)
		"copy":
			if s:
				select(s)
				copy_selected(false)
		"delete":
			if s:
				remove_shape(s)
				push_history(func(): restore_shape(s))
				set_status("Deleted %s" % s.name)
				persist()
		"duplicate":
			if s:
				select(s)
				on_button("duplicate")
		"paste": paste_at(p)
		"nextclip":
			clip_index = (clip_index + 1) % clipboard.size()
			set_status("Next clipboard item")
	menu_dirty = true


# ================================================================ pointers
func haptic(c: Ctrl, strength := 0.3, sec := 0.025) -> void:
	if c and xr_active:
		c.node.trigger_haptic_pulse(&"haptic", 0.0, strength, sec, 0.0)


func snap_point(p: Vector3):
	var best = null
	var best_d := SNAP_POINT
	var cands: Array = pending.duplicate()
	for m in measures:
		cands.append_array(m.points)
	for s: Shape in shapes:
		var h := scale_of(s.type, s.dims) / 2.0
		var t := s.node.transform
		if s.type == "box":
			for sx in [-1, 1]:
				for sy in [-1, 1]:
					for sz in [-1, 1]:
						cands.append(t * Vector3(sx * h.x, sy * h.y, sz * h.z))
		else:
			cands.append(t * Vector3(0, h.y, 0))
			cands.append(t * Vector3(0, -h.y, 0))
	for q in cands:
		var dd: float = q.distance_to(p)
		if dd < best_d:
			best_d = dd
			best = q
	return best


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, mask: int, ex: Array[RID] = []) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to, mask, ex)
	q.collide_with_areas = false
	return space.intersect_ray(q)


func update_pointer(c: Ctrl, space: PhysicsDirectSpaceState3D) -> void:
	c.ui = null
	c.handle_hit = null
	c.shape_hit = null
	c.target = null
	if not c.node.get_is_active():
		c.ray.visible = false
		c.reticle.visible = false
		return
	c.ray.visible = true
	var ow := c.node.global_position
	var dw := -c.node.global_basis.z.normalized()
	var inv := content.global_basis.inverse()
	c.o = content.to_local(ow)
	c.d = (inv * dw).normalized()
	var far := ow + dw * 20.0

	# UI first: pop-ups win over the main menu; the menu's holding hand can't click its own menu.
	var ex_ui: Array[RID] = []
	for i in 4:
		var h := _ray(space, ow, far, LAYER_UI, ex_ui)
		if h.is_empty():
			break
		var col: Object = h.collider
		var pnl = col.get_meta("panel") if col.has_meta("panel") else null
		if pnl == null or not pnl.is_open or (pnl == menu and menu_attach == c):
			ex_ui.append(h.rid)
			continue
		c.ui = {"panel": pnl, "id": String(col.get_meta("item")), "dist": ow.distance_to(h.position), "point": h.position}
		break
	if c.ui != null:
		c.reticle.visible = false
		c.ray.scale = Vector3(1, 1, c.ui.dist)
		return

	# Real surfaces (Space Setup) or the floor.
	var real = null
	var hr := _ray(space, ow, far, LAYER_ROOM)
	if not hr.is_empty():
		real = {"point": content.to_local(hr.position), "normal": (inv * hr.normal).normalized(), "dist": ow.distance_to(hr.position), "kind": "surface"}
	elif dw.y < -0.05:
		var t := -ow.y / dw.y
		if t > 0.05 and t < 10.0:
			real = {"point": content.to_local(ow + dw * t), "normal": inv * Vector3.UP, "dist": t, "kind": "surface"}

	# Shapes and the selected shape's resize handles (not the shape being dragged by this hand).
	var ex: Array[RID] = []
	if c.drag != null and c.drag.has("shape"):
		ex.append(c.drag.shape.body.get_rid())
	var hs := _ray(space, ow, far, LAYER_SHAPE, ex)
	var hh := _ray(space, ow, far, LAYER_HANDLE)
	var sd := ow.distance_to(hs.position) if not hs.is_empty() else INF
	if not hh.is_empty() and ow.distance_to(hh.position) < sd + 0.05:
		c.handle_hit = hh.collider.get_meta("handle")
	if not hs.is_empty():
		var n: Vector3 = (inv * hs.normal).normalized()
		c.shape_hit = {"shape": hs.collider.get_meta("shape"), "point": content.to_local(hs.position), "normal": n, "dist": sd}

	var best = real
	if c.shape_hit != null and (best == null or c.shape_hit.dist < best.dist):
		best = {"point": c.shape_hit.point, "normal": c.shape_hit.normal, "dist": c.shape_hit.dist, "kind": "shape"}
	if best != null and mode != "select":
		var sp = snap_point(best.point)
		if sp != null:
			best.point = sp
			best.kind = "snap"
	c.target = best

	if best != null and c.drag == null:
		c.reticle.visible = true
		var n: Vector3 = best.normal
		# TorusMesh lies in XZ: build a basis whose Y axis is the surface normal.
		var bx := n.cross(Vector3.FORWARD if absf(n.z) < 0.9 else Vector3.RIGHT).normalized()
		c.reticle.transform = Transform3D(Basis(bx, n, bx.cross(n)), best.point)
		(c.reticle.material_override as StandardMaterial3D).albedo_color = C_YELLOW if best.kind == "snap" else (Color("ff5ad1") if best.kind == "shape" else C_CYAN)
		c.ray.scale = Vector3(1, 1, best.dist)
	else:
		c.reticle.visible = false
		c.ray.scale = Vector3(1, 1, best.dist if best != null else 3.0)


func update_hovers() -> void:
	var hov := {menu: "", palette: "", ctx: ""}
	for c in ctrls:
		if c.ui != null and hov.has(c.ui.panel):
			hov[c.ui.panel] = c.ui.id
	for p in hov:
		if p.is_open:
			p.set_hover(hov[p])


# ================================================================ controller input
# Trigger: select / press. Grip: scale (alone) or move (with trigger). B (right) while moving: free pick-up.
# Stick while holding: up/down = scale ±5%, left = 45° clockwise, right = 45° counter-clockwise.
# Stick click: main menu on that hand (both sticks: menu fixed in front of you).
# Hold A (right): context menu. Hold X (left): shape palette.
func read_buttons(c: Ctrl) -> Dictionary:
	var n := c.node
	if not n.get_is_active():
		return {}
	var prev := c.btn
	var trig := n.get_float(&"trigger")
	var grip := n.get_float(&"grip")
	var stick := n.get_vector2(&"primary")
	return {
		"trigger": trig > (0.35 if prev.get("trigger", false) else 0.6),
		"grip": grip > (0.35 if prev.get("grip", false) else 0.6),
		"low": n.is_button_pressed(&"ax_button"),
		"high": n.is_button_pressed(&"by_button"),
		"stick": n.is_button_pressed(&"primary_click"),
		"sx": stick.x, "sy": stick.y,
	}


func b_held() -> bool:
	for c in ctrls:
		if c.hand == "right":
			return c.btn.get("high", false)
	return false


func process_input(c: Ctrl, b: Dictionary) -> void:
	var prev := c.btn
	c.btn = b
	if b.is_empty():
		if c.drag != null:
			on_drag_release(c)
		return
	var now := Time.get_ticks_msec() / 1000.0
	var down := func(k): return b.get(k, false) and not prev.get(k, false)
	var up := func(k): return not b.get(k, false) and prev.get(k, false)

	# Stick click: main menu.
	if down.call("stick") and c.drag == null:
		var other: Ctrl = ctrls[0] if c == ctrls[1] else ctrls[1]
		if menu.is_open and menu_attach == other and now - other.stick_down_at < 0.4:
			open_menu(c, true)             # both sticks: pin it in front of you
		elif menu.is_open:
			close_menu()
		else:
			open_menu(c, false)
		c.stick_down_at = now

	if c.hand == "right":
		if down.call("low"):
			c.a_down_at = now
			if ctx.is_open:
				ctx.close()
				c.a_down_at = -1.0
		if b.low and c.a_down_at >= 0.0 and now - c.a_down_at > 0.25:
			c.a_down_at = -1.0
			open_context(c)
		if up.call("low"):
			c.a_down_at = -1.0
	else:
		if down.call("low"):
			open_palette(c)
		if up.call("low"):
			palette.close()

	if c.drag != null and c.drag.type == "move" and b_held():
		convert_to_free(c)
	if down.call("trigger"):
		on_trigger_down(c, b)
	if down.call("grip"):
		on_grip_down(c, b)
	if up.call("trigger"):
		c.press_shape = null
	var t = c.drag.type if c.drag != null else ""
	if (t == "handle" and up.call("trigger")) or (t == "scale" and up.call("grip")) or ((t == "move" or t == "free") and (up.call("trigger") or up.call("grip"))):
		on_drag_release(c)
	if c.drag != null and (c.drag.type == "move" or c.drag.type == "free"):
		if absf(b.sx) < 0.3:
			c.latch_x = false
		if absf(b.sy) < 0.3:
			c.latch_y = false
		if not c.latch_x and absf(b.sx) > 0.7:
			c.latch_x = true
			rotate_held(c, -PI / 4 if b.sx < 0 else PI / 4)
			haptic(c, 0.3, 0.02)
		if not c.latch_y and absf(b.sy) > 0.7:
			c.latch_y = true
			scale_held(c, 1.05 if b.sy > 0 else 0.95)
			haptic(c, 0.3, 0.02)
	else:
		c.latch_x = true     # stick must return to centre after a grab starts
		c.latch_y = true


func on_trigger_down(c: Ctrl, b: Dictionary) -> void:
	last_ctrl = c
	if c.ui != null:
		var pnl = c.ui.panel
		var id: String = c.ui.id
		if pnl == menu:
			var it = menu.item(id)
			if it != null and it.get("enabled", true):
				haptic(c, 0.4, 0.03)
				on_button(id, c)
		elif pnl == palette:
			spawn_from_palette(c, id, c.ui.point)
		elif pnl == ctx:
			var it2 = ctx.item(id)
			if it2 != null and it2.get("enabled", true):
				haptic(c, 0.4, 0.03)
				run_context(id)
		return
	if ctx.is_open:
		ctx.close()
		return
	if c.drag != null and c.drag.type == "scale":
		var s: Shape = c.drag.shape
		c.drag = null
		start_move(c, s)
		return
	if c.handle_hit != null:
		start_handle(c, c.handle_hit)
		haptic(c)
		return
	if mode != "select":
		var p: Vector3 = c.target.point if c.target != null else c.o + c.d * 0.8
		if c.target == null:
			set_status("No surface there: used a point 80 cm along the ray.")
		haptic(c)
		add_pending_point(p)
		return
	if c.shape_hit != null:
		var s: Shape = c.shape_hit.shape
		select(s)
		c.press_shape = s
		haptic(c, 0.2, 0.015)
		if b.get("grip", false):
			start_move(c, s)
		return
	if selected:
		select(null)


func on_grip_down(c: Ctrl, b: Dictionary) -> void:
	last_ctrl = c
	if c.ui != null and c.ui.panel == palette:
		spawn_from_palette(c, c.ui.id, c.ui.point)
		return
	if c.ui != null or mode != "select" or c.drag != null:
		return
	var s = c.press_shape if (b.get("trigger", false) and c.press_shape != null) else (c.shape_hit.shape if c.shape_hit != null else null)
	if s == null:
		return
	select(s)
	if b.get("trigger", false):
		start_move(c, s)
	else:
		start_scale(c, s)
	haptic(c)


func on_drag_release(c: Ctrl) -> void:
	var dr = c.drag
	if dr == null:
		return
	c.drag = null
	if dr.type == "move" or dr.type == "free":
		settle(dr.shape)
		grid_patch.visible = false
		set_status("%s placed" % dr.shape.name)
	persist()
	menu_dirty = true


func _snap_undo(s: Shape) -> Callable:
	var sn := snapshot(s)
	return func(): apply_snapshot(s, sn)


func yaw_of_dir(d: Vector3) -> float:
	return atan2(-d.x, -d.z)


func start_move(c: Ctrl, s: Shape) -> void:
	if b_held():
		start_free(c, s, true)
		return
	push_history(_snap_undo(s))
	falling = falling.filter(func(f): return f.shape != s)
	c.drag = {"type": "move", "shape": s, "c0": c.o, "yaw0": yaw_of_dir(c.d), "p0": s.node.position, "base_y": s.node.position.y}
	set_status("Moving %s" % s.name)


func update_move(c: Ctrl, dr: Dictionary) -> void:
	var qy := Quaternion(Vector3.UP, yaw_of_dir(c.d) - dr.yaw0)
	var p: Vector3 = c.o + qy * (dr.p0 - dr.c0)
	var s: Shape = dr.shape
	s.node.position = Vector3(snap_grid(p.x), dr.base_y, snap_grid(p.z))
	refresh_shape(s)
	show_grid_patch(s.node.position.x, dr.base_y - half_height(s), s.node.position.z)


func _ctrl_local_xform(c: Ctrl) -> Transform3D:
	return content.global_transform.affine_inverse() * c.node.global_transform


func start_free(c: Ctrl, s: Shape, push_undo: bool) -> void:
	if push_undo:
		push_history(_snap_undo(s))
	falling = falling.filter(func(f): return f.shape != s)
	c.drag = {"type": "free", "shape": s, "rel": _ctrl_local_xform(c).affine_inverse() * s.node.transform}
	set_status("Carrying %s" % s.name)


func convert_to_free(c: Ctrl) -> void:
	start_free(c, c.drag.shape, false)
	haptic(c, 0.5, 0.04)


func update_free(c: Ctrl, dr: Dictionary) -> void:
	var s: Shape = dr.shape
	var t: Transform3D = _ctrl_local_xform(c) * dr.rel
	s.node.transform = t.orthonormalized()
	refresh_shape(s)
	show_grid_patch(s.node.position.x, support_below(s.node.position.x, s.node.position.z, s.node.position.y, s), s.node.position.z)


func rotate_held(c: Ctrl, ang: float) -> void:
	var dr: Dictionary = c.drag
	var s: Shape = dr.shape
	var qy := Quaternion(Vector3.UP, ang)
	if dr.type == "move":
		s.node.quaternion = snap_yaw_quat(qy * s.node.quaternion)
	else:
		s.node.quaternion = qy * s.node.quaternion
		dr.rel = _ctrl_local_xform(c).affine_inverse() * s.node.transform
	refresh_shape(s)
	set_status("%s: rotated 45° %s" % [s.name, "clockwise" if ang < 0 else "counter-clockwise"])


func scale_held(c: Ctrl, f: float) -> void:
	var dr: Dictionary = c.drag
	var s: Shape = dr.shape
	var bottom := s.node.position.y - half_height(s)
	for k in s.dims.keys():
		s.dims[k] = maxf(MIN_SIZE, roundf(s.dims[k] * f * 1000.0) / 1000.0)
	if dr.type == "move":
		dr.base_y = bottom + half_height(s)
		s.node.position.y = dr.base_y
	refresh_shape(s)
	set_status("%s: %s" % [s.name, dims_text(s)])


# Grip alone on a shape: push the controller forward to grow, pull back to shrink (x2 per 20 cm).
func start_scale(c: Ctrl, s: Shape) -> void:
	push_history(_snap_undo(s))
	var bottom := s.node.position.y - half_height(s)
	var resting := absf(bottom - support_below(s.node.position.x, s.node.position.z, bottom + 0.02, s)) < 0.01
	c.drag = {"type": "scale", "shape": s, "o0": c.o, "d0": c.d, "dims0": s.dims.duplicate(), "bottom": bottom, "resting": resting}
	set_status("Scaling %s: push to grow, pull to shrink" % s.name)


func update_scale(c: Ctrl, dr: Dictionary) -> void:
	var ratio := clampf(pow(2.0, (c.o - dr.o0).dot(dr.d0) / 0.2), 0.05, 20.0)
	var s: Shape = dr.shape
	for k in s.dims.keys():
		s.dims[k] = maxf(MIN_SIZE, roundf(dr.dims0[k] * ratio * 1000.0) / 1000.0)
	if dr.resting:
		s.node.position.y = dr.bottom + half_height(s)
	refresh_shape(s)
	set_status("%s: %s" % [s.name, dims_text(s)])


## Closest point on line p0 + dir*t to the ray o + r*u. Returns t, or null when parallel.
func closest_t(p0: Vector3, dir: Vector3, o: Vector3, r: Vector3):
	var w := p0 - o
	var b := dir.dot(r)
	var dd := dir.dot(w)
	var e := r.dot(w)
	var denom := 1.0 - b * b
	if denom < 1e-5:
		return null
	return (b * e - dd) / denom


func start_handle(c: Ctrl, handle: Node3D) -> void:
	var hd: Dictionary = handle.get_meta("hd")
	var s: Shape = hd.shape
	push_history(_snap_undo(s))
	var axis_w: Vector3 = (s.node.quaternion * hd.axis).normalized()
	var fixed_w: Vector3 = s.node.position - axis_w * extent(s, hd.key) / 2.0 if hd.mode == "face" else s.node.position
	c.drag = {"type": "handle", "shape": s, "hd": hd, "axis": axis_w, "fixed": fixed_w}
	set_status("Resizing %s" % s.name)


func update_handle(c: Ctrl, dr: Dictionary) -> void:
	var t = closest_t(dr.fixed, dr.axis, c.o, c.d)
	if t == null:
		return
	var v := roundf(maxf(MIN_SIZE, t) * 1000.0) / 1000.0   # 1 mm steps
	var s: Shape = dr.shape
	if dr.hd.mode == "face":
		s.dims[dr.hd.key] = v
		s.node.position = dr.fixed + dr.axis * v / 2.0
	else:
		s.dims.r = v
	refresh_shape(s)
	set_status("%s: %s" % [s.name, dims_text(s)])


func update_preview() -> void:
	var c := last_ctrl
	if pending.is_empty() or c == null or c.target == null:
		preview.visible = false
		preview_label.visible = false
		return
	var p: Vector3 = c.target.point
	var pts := PackedVector3Array(pending)
	pts.append(p)
	preview.mesh = _lines_mesh(pts, true)
	preview.visible = true
	if mode == "tape":
		var a: Vector3 = pending[0]
		var dv := p - a
		set_label(preview_label, [L(dv.length()), "vert %s · horiz %s" % [L(absf(dv.y)), L(Vector2(dv.x, dv.z).length())]])
		preview_label.position = (a + p) / 2.0 + Vector3(0, 0.05, 0)
		preview_label.visible = true
	elif pending.size() == 2:
		var circ = circle_from_3(pending[0], pending[1], p)
		if circ != null:
			set_label(preview_label, ["Ø " + L(2 * circ.r), "r " + L(circ.r)])
			preview_label.position = circ.center + Vector3(0, 0.05, 0)
			preview_label.visible = true
	else:
		preview_label.visible = false


# ================================================================ main loop
func _process(delta: float) -> void:
	_follow_anchor(delta)
	var space := get_world_3d().direct_space_state
	for c in ctrls:
		update_pointer(c, space)
		process_input(c, read_buttons(c))
		var dr = c.drag
		if dr != null:
			match dr.type:
				"move": update_move(c, dr)
				"free": update_free(c, dr)
				"scale": update_scale(c, dr)
				"handle": update_handle(c, dr)
	update_hovers()
	update_falling()
	update_preview()
	if menu.is_open:
		if menu_dirty:
			rebuild_menu()
		if menu_attach != null:
			menu.global_position = _menu_hand_pos(menu_attach)
			menu.face(camera.global_position)
	if save_dirty:
		save_timer -= delta
		if save_timer <= 0.0:
			save_room_now()


# ================================================================ rooms + anchors
func rooms_dir() -> String:
	return "user://rooms"


func room_path(id: String) -> String:
	return "%s/%s.json" % [rooms_dir(), id]


func load_settings() -> void:
	DirAccess.make_dir_recursive_absolute(rooms_dir())
	var f := FileAccess.open("user://settings.json", FileAccess.READ)
	if f:
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			room["id"] = d.get("current_room", "")
			placement = "anchor" if d.get("placement", "stand") == "anchor" else "stand"


func save_settings() -> void:
	var f := FileAccess.open("user://settings.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"current_room": room.get("id", ""), "placement": placement}))


func list_rooms() -> Array:
	var out := []
	var dir := DirAccess.open(rooms_dir())
	if dir == null:
		return out
	for fn in dir.get_files():
		if not fn.ends_with(".json"):
			continue
		var f := FileAccess.open(rooms_dir() + "/" + fn, FileAccess.READ)
		if f == null:
			continue
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			out.append({"id": d.get("id", fn.get_basename()), "name": d.get("name", fn.get_basename()),
				"count": d.get("shapes", []).size(), "updated": String(d.get("updated", "")).substr(0, 16).replace("T", " "),
				"sort": String(d.get("updated", ""))})
	out.sort_custom(func(a, b): return a.sort > b.sort)
	return out


func persist() -> void:
	save_dirty = true
	save_timer = 0.5


func start_rooms() -> void:
	var id: String = room.get("id", "")
	if id != "" and FileAccess.file_exists(room_path(id)):
		load_room(id)
	else:
		new_room()


func _now_iso() -> String:
	return Time.get_datetime_string_from_system(false, true)


func new_room() -> void:
	if room.get("id", "") != "" and (shapes.size() or measures.size()):
		save_room_now()
	_clear_content()
	var n := list_rooms().size() + 1
	room = {"id": "room-%d-%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec() % 100000], "name": "Room %d" % n, "anchor": "", "created": _now_iso()}
	anchor_node = null
	anchor_state = "none"
	# The room's origin is the spot you're standing on, facing the way you look. The grid lines up with it.
	content.transform = stand_frame()
	if placement == "anchor":
		_create_room_anchor()
	save_room_now()
	set_status("New room: %s, starting where you stand. Everything you add is saved to it." % room.name)


## Where you are standing: the floor under your head, turned to face the way you look (yaw only).
## In tracking space (origin-local), which is what `content.transform` is in.
func stand_frame() -> Transform3D:
	var t := camera.transform
	var fwd := -t.basis.z
	fwd.y = 0
	if fwd.length() < 0.2:
		# Looking almost straight up or down: the top of the headset points the way you face (or away, looking up).
		fwd = t.basis.y * (1.0 if t.basis.z.y > 0 else -1.0)
		fwd.y = 0
	var yaw := yaw_of_dir(fwd) if fwd.length() > 0.001 else 0.0
	return Transform3D(Basis(Vector3.UP, yaw), Vector3(t.origin.x, 0, t.origin.z))


## Move the whole room so its origin is where you are standing now, facing the way you look.
func place_here() -> void:
	content.transform = stand_frame()
	content.visible = true
	if placement == "anchor":
		_repin_anchor()


func _on_recentered() -> void:
	if placement != "stand":
		return   # an anchored room keeps its real-world spot by itself
	# Let the new head pose arrive before reading it.
	await get_tree().create_timer(0.3).timeout
	place_here()
	set_status("Recentered: %s is placed where you stand, facing where you face." % room.get("name", "room"))


func set_placement(p: String) -> void:
	placement = p
	if p == "stand":
		# Keep everything exactly where it is now; just stop following the anchor.
		anchor_node = null
		anchor_state = "none"
		content.visible = true
		set_status("Placement: where you stand. To line a room up, stand on your spot, face your way and recenter.")
	else:
		_repin_anchor()
		set_status("Placement: spatial anchor. The room is pinned to this spot and reappears here on its own.")
	save_settings()


## Drop the room's old anchor (if any) and pin it to a new one where it is now.
func _repin_anchor() -> void:
	var uuid: String = room.get("anchor", "")
	if uuid != "" and anchor_mgr != null and xr_active:
		anchor_mgr.call("untrack_anchor", StringName(uuid))
	room.anchor = ""
	anchor_node = null
	_create_room_anchor()


func _create_room_anchor() -> void:
	if anchor_mgr == null or not xr_active:
		anchor_state = "none"
		return
	# Anchor at the room's current origin (on the floor where you stood), so nothing moves when it's created.
	anchor_state = "creating"
	anchor_mgr.call("create_anchor", content.global_transform, {"room": room.id})


func _on_anchor_tracked(node: Node3D, entity: Object, is_new: bool) -> void:
	if placement != "anchor":
		return
	var data: Dictionary = entity.get("custom_data")
	var uuid := String(entity.get("uuid"))
	if data.get("room", "") != room.get("id", "") and uuid != room.get("anchor", ""):
		return
	var old := content.global_transform
	anchor_node = node
	anchor_state = "tracked"
	if is_new:
		room.anchor = uuid
		# Keep anything placed before the anchor existed exactly where it is.
		_rebase(old, node.global_transform)
		save_room_now()
	set_status("%s anchored." % room.name if is_new else "Found %s. Everything is back in place." % room.name)


func _on_anchor_create_failed(_t, _data) -> void:
	anchor_state = "failed"
	set_status("Couldn't create a room anchor. Shapes are saved relative to where you started.")


func _on_anchor_load_failed(_uuid, _data, _loc) -> void:
	anchor_state = "failed"
	content.transform = stand_frame()
	content.visible = true
	set_status("Couldn't find this room's anchor (different place, or Space was cleared). Placed where you stand.")


func _follow_anchor(delta: float) -> void:
	if anchor_node and is_instance_valid(anchor_node) and anchor_state == "tracked":
		content.global_transform = anchor_node.global_transform
		content.visible = true
	elif anchor_state == "loading":
		anchor_wait += delta
		if anchor_wait > 8.0:
			_on_anchor_load_failed(null, null, null)


## Re-express shapes/measures that sit under `content` so they keep their world pose when content moves.
func _rebase(old_t: Transform3D, new_t: Transform3D) -> void:
	var m := new_t.affine_inverse() * old_t
	content.global_transform = new_t
	for s in shapes:
		s.node.transform = (m * s.node.transform).orthonormalized()
	var old_measures := measures.duplicate()
	for ms in old_measures:
		var pts := []
		for p in ms.points:
			pts.append(m * p)
		remove_measure(ms)
		ms.node.queue_free()
		create_measure(ms.type, pts, ms.name)


func _clear_content() -> void:
	select(null)
	clear_pending()
	for s in shapes:
		s.node.queue_free()
	for ms in measures:
		ms.node.queue_free()
	shapes = []
	measures = []
	falling = []
	history = []
	counters = {"box": 0, "sphere": 0, "cylinder": 0, "cone": 0, "m": 0}


func room_data() -> Dictionary:
	var ss := []
	for s: Shape in shapes:
		var p := s.node.position
		var q := s.node.quaternion
		ss.append({"name": s.name, "type": s.type, "dims": s.dims, "volume_m3": volume_of(s.type, s.dims),
			"position": [p.x, p.y, p.z], "quaternion": [q.x, q.y, q.z, q.w], "outline": s.outline})
	var ms := []
	for m in measures:
		var pts := []
		for p in m.points:
			pts.append([p.x, p.y, p.z])
		var base := {"name": m.name, "type": m.type, "points": pts}
		if m.type == "line":
			var dv: Vector3 = m.points[1] - m.points[0]
			base.merge({"distance_m": dv.length(), "vertical_m": absf(dv.y), "horizontal_m": Vector2(dv.x, dv.z).length()})
		else:
			base.merge({"radius_m": m.r, "diameter_m": 2 * m.r, "circumference_m": TAU * m.r, "center": [m.center.x, m.center.y, m.center.z]})
		ms.append(base)
	var surf := []
	for n in surfaces:
		if is_instance_valid(n) and n.size_2d != Vector2.ZERO:
			surf.append({"label": n.label_name, "width_m": n.size_2d.x, "depth_m": n.size_2d.y, "area_m2": n.size_2d.x * n.size_2d.y})
	return {"app": "Framespace", "build": BUILD, "id": room.get("id", ""), "name": room.get("name", ""),
		"anchor": room.get("anchor", ""), "created": room.get("created", ""), "updated": _now_iso(),
		"units": units, "grid": grid, "counters": counters, "clipboard": _clip_data(),
		"shapes": ss, "measurements": ms, "room": surf}


func _clip_data() -> Array:
	var out := []
	for it in clipboard:
		var q: Quaternion = it.rot
		out.append({"type": it.type, "dims": it.dims, "name": it.name, "quaternion": [q.x, q.y, q.z, q.w], "outline": it.get("outline", {})})
	return out


func save_room_now() -> void:
	save_dirty = false
	if room.get("id", "") == "":
		return
	DirAccess.make_dir_recursive_absolute(rooms_dir())
	var f := FileAccess.open(room_path(room.id), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(room_data(), "  "))
		f.close()
	save_settings()


func _v3(a) -> Vector3:
	return Vector3(a[0], a[1], a[2])


func _q(a) -> Quaternion:
	return Quaternion(a[0], a[1], a[2], a[3]).normalized()


func load_room(id: String) -> void:
	if room.get("id", "") != "" and room.id != id:
		save_room_now()
	var f := FileAccess.open(room_path(id), FileAccess.READ)
	if f == null:
		set_status("Couldn't open that room.")
		return
	var d = JSON.parse_string(f.get_as_text())
	if not (d is Dictionary):
		set_status("That room file is damaged.")
		return
	_clear_content()
	room = {"id": d.get("id", id), "name": d.get("name", id), "anchor": d.get("anchor", ""), "created": d.get("created", "")}
	units = d.get("units", units)
	grid = d.get("grid", grid)
	for s in d.get("shapes", []):
		make_shape(s.type, s.dims, _v3(s.position), _q(s.quaternion), s.name, s.get("outline"))
	for m in d.get("measurements", []):
		var pts := []
		for p in m.points:
			pts.append(_v3(p))
		create_measure(m.type, pts, m.name)
	var cn = d.get("counters", {})
	for k in counters.keys():
		counters[k] = int(cn.get(k, counters[k]))
	clipboard = []
	for it in d.get("clipboard", []):
		clipboard.append({"type": it.type, "dims": it.dims, "name": it.name, "rot": _q(it.quaternion), "outline": it.get("outline", {})})
	clip_index = 0
	anchor_node = null
	anchor_state = "none"
	content.transform = stand_frame()
	content.visible = true
	var uuid: String = room.anchor
	if placement == "stand":
		pass   # placed where you stand; recentering lines it up exactly
	elif uuid != "" and anchor_mgr != null and xr_active:
		var existing = anchor_mgr.call("get_anchor_node", StringName(uuid))
		if existing:
			anchor_node = existing
			anchor_state = "tracked"
		else:
			anchor_state = "loading"
			anchor_wait = 0.0
			content.visible = false     # don't flash it in the wrong place while the headset finds the anchor
			anchor_mgr.call("load_anchor", StringName(uuid), {"room": room.id})
	elif uuid == "" and anchor_mgr != null and xr_active:
		_create_room_anchor()
	save_settings()
	if placement == "stand":
		set_status("Loaded %s (%d shapes, %d measurements) where you stand. On your usual spot? Face your usual way and recenter." % [room.name, shapes.size(), measures.size()])
	else:
		set_status("Loaded %s (%d shapes, %d measurements)." % [room.name, shapes.size(), measures.size()])


func delete_current_room() -> void:
	var id: String = room.get("id", "")
	if id == "":
		return
	var uuid: String = room.get("anchor", "")
	if uuid != "" and anchor_mgr != null and xr_active:
		anchor_mgr.call("untrack_anchor", StringName(uuid))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(room_path(id)))
	var gone: String = room.get("name", "room")
	room = {}
	var rest := list_rooms()
	if rest.size():
		load_room(rest[0].id)
	else:
		new_room()
	set_status("Deleted %s." % gone)


# ================================================================ export
func to_csv(data: Dictionary) -> String:
	var rows := [["kind", "name", "type", "length_m", "width_m", "height_m", "depth_m", "radius_m", "diameter_m", "volume_m3", "area_m2", "distance_m", "vertical_m", "horizontal_m", "circumference_m"]]
	var f := func(v): return "" if v == null else "%.4f" % float(v)
	for m in data.measurements:
		if m.type == "line":
			rows.append(["measurement", m.name, "tape", "", "", "", "", "", "", "", "", f.call(m.distance_m), f.call(m.vertical_m), f.call(m.horizontal_m), ""])
		else:
			rows.append(["measurement", m.name, "circle", "", "", "", "", f.call(m.radius_m), f.call(m.diameter_m), "", "", "", "", "", f.call(m.circumference_m)])
	for s in data.shapes:
		var d: Dictionary = s.dims
		if s.type == "box":
			rows.append(["shape", s.name, s.type, "", f.call(d.x), f.call(d.y), f.call(d.z), "", "", f.call(s.volume_m3), "", "", "", "", ""])
		elif s.type == "sphere":
			rows.append(["shape", s.name, s.type, "", "", "", "", f.call(d.r), f.call(2 * d.r), f.call(s.volume_m3), "", "", "", "", ""])
		else:
			rows.append(["shape", s.name, s.type, "", "", f.call(d.h), "", f.call(d.r), f.call(2 * d.r), f.call(s.volume_m3), "", "", "", "", ""])
	for p in data.room:
		rows.append(["room", p.label, "plane", f.call(p.width_m), f.call(p.depth_m), "", "", "", "", "", f.call(p.area_m2), "", "", "", ""])
	var lines := []
	for r in rows:
		var cells := []
		for c in r:
			var cs := String(c)
			if cs.contains(",") or cs.contains("\"") or cs.contains("\n"):
				cs = "\"" + cs.replace("\"", "\"\"") + "\""
			cells.append(cs)
		lines.append(",".join(cells))
	return "\n".join(lines)


func export_dir() -> String:
	# Shared Download folder first (visible over USB / in Meta Quest Developer Hub's file browser),
	# app storage as a fallback.
	var dl := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	if dl != "":
		var d := dl.path_join("Framespace")
		if DirAccess.make_dir_recursive_absolute(d) == OK and _writable(d):
			return d
	var u := ProjectSettings.globalize_path("user://exports")
	DirAccess.make_dir_recursive_absolute(u)
	return u


func _writable(dir: String) -> bool:
	var p := dir.path_join(".probe")
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f == null:
		return false
	f.close()
	DirAccess.remove_absolute(p)
	return true


func export_all() -> Dictionary:
	save_room_now()
	var data := room_data()
	var dir := export_dir()
	var stamp := _now_iso().substr(0, 16).replace(":", "-").replace("T", "-")
	var base := dir.path_join("framespace-%s-%s" % [String(data.name).replace(" ", "-").to_lower(), stamp])
	var csv := to_csv(data)
	var ok := true
	var fc := FileAccess.open(base + ".csv", FileAccess.WRITE)
	if fc:
		fc.store_string(csv)
		fc.close()
	else:
		ok = false
	var fj := FileAccess.open(base + ".json", FileAccess.WRITE)
	if fj:
		fj.store_string(JSON.stringify(data, "  "))
		fj.close()
	else:
		ok = false
	var glb_ok := export_glb(data, base + ".glb")
	DisplayServer.clipboard_set(csv)
	set_status(("Exported CSV, JSON%s to %s (CSV also copied)." % [", GLB" if glb_ok else "", dir]) if ok else "Export failed: can't write to %s" % dir)
	return {"base": base, "ok": ok, "glb": glb_ok}


func export_glb(data: Dictionary, path: String) -> bool:
	var root := Node3D.new()
	root.name = "Framespace"
	for s in data.shapes:
		var mi := MeshInstance3D.new()
		mi.name = String(s.name).replace(" ", "_")
		mi.mesh = unit_fill[s.type]
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(COLORS[s.type], 0.5)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mi.material_override = mat
		var t := Transform3D(Basis(_q(s.quaternion)), _v3(s.position))
		mi.transform = t * Transform3D(Basis.from_scale(scale_of(s.type, s.dims)), Vector3.ZERO)
		mi.set_meta("extras", {"type": s.type, "dims_m": s.dims, "volume_m3": s.volume_m3})
		root.add_child(mi)
	for m in data.measurements:
		var pts := PackedVector3Array()
		for p in m.points:
			pts.append(_v3(p))
		if m.type != "line":
			pts.append(pts[0])
		var li := MeshInstance3D.new()
		li.name = String(m.name)
		li.mesh = _lines_mesh(pts, true)
		root.add_child(li)
	add_child(root)
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_scene(root, st)
	if err == OK:
		err = doc.write_to_filesystem(st, path)
	root.queue_free()
	return err == OK
