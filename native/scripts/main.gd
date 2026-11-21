extends Node3D
## Framespace native (Meta Quest 3): wireframe design + measuring over passthrough, saved rooms.
## Port of the WebXR prototype (../app.js). Everything is built in code so the scene file stays tiny.
##
## Coordinates: shapes and measurements live under `content`, which is placed on the floor where you
## stand, facing the way you look (on load, on recenter, or with Place room here). All shape/measure maths
## is done in content-local space; the grid is content-local X/Z, so it lines up with the room.

const UIPanel := preload("res://scripts/ui_panel.gd")
const SceneAnchorScene := preload("res://scene_anchor.tscn")

const BUILD := "0.5.0-native"
const MIN_SIZE := 0.01        # 1 cm smallest dimension
const SNAP_POINT := 0.025     # tape points snap to corners/points within 2.5 cm
const CLIP_MAX := 5
const SCALE_STEP := 1.05      # stick up / down: +5% / -5% (reversible)

const LAYER_ROOM := 2
const LAYER_SHAPE := 4
const LAYER_HANDLE := 8
const LAYER_UI := 16

const COLORS := {"box": Color("00e5ff"), "sphere": Color("7cff6b"), "cylinder": Color("ffb020"), "cone": Color("ff5ad1")}
const NAMES := {"box": "Box", "sphere": "Sphere", "cylinder": "Cylinder", "cone": "Cone"}
const DEFAULT_DIMS := {"box": {"x": 0.3, "y": 0.3, "z": 0.3}, "sphere": {"r": 0.15}, "cylinder": {"r": 0.12, "h": 0.3}, "cone": {"r": 0.12, "h": 0.3}}
const C_YELLOW := Color("ffe14d")
const C_CYAN := Color("00e5ff")

# Object tray (stick-click menu). Loaded at startup from res://objects.txt, which CI copies from the repo's objects.csv
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

# Stick-click menu: a 4×8 sidebar with every tool and setting; the object tray (objects.csv) sits to its
# right while the tool is Move/Scale.
const MENU_MAIN := [
	"select", "cut", "copy", "paste",
	"duplicate", "delete", "reset", "drop",
	"pin", "nextclip", "undo", "units",
	"tape", "circle", "rect", "height",
	"angle", "path", "area", "grid",
	"roomvis", "scan", "save", "rooms",
	"export", "clear", "scale", "quit",
	"turnl5", "turnl1", "turnr1", "turnr5",
	"accuracy", "roominfo", "fitcheck",
]
# Accuracy test references: things with a known true size. True sizes in mm.
const ACC_REFS := [
	{"id": "a4l", "label": "A4 sheet, long side", "mm": 297.0},
	{"id": "a4s", "label": "A4 sheet, short side", "mm": 210.0},
	{"id": "card", "label": "Bank card, long side", "mm": 85.6},
	{"id": "door", "label": "Door leaf height", "mm": 2040.0},
	{"id": "doorw", "label": "Door leaf width (820)", "mm": 820.0},
]
const FIT_MARGIN := 0.02        # overlaps under 2 cm (scan noise, flush contact) don't count as "doesn't fit"
const FIT_EVERY := 0.2          # seconds between fit checks
const C_RED := Color("ff4d4d")
# Press X or A: tool menu. The picked tool is what trigger does on an object.
const TOOLS_MENU := ["select", "scale", "cut", "copy", "paste", "duplicate", "delete", "reset", "drop", "pin", "nextclip"]
const MEASURE_TOOLS := ["tape", "circle", "rect", "height", "angle", "path", "area", "acctest"]
const EDIT_TOOLS := ["scale", "cut", "copy", "paste", "duplicate", "delete", "reset", "drop", "pin"]
const MODE_NAMES := {"select": "Rotate/Move", "tape": "Tape", "circle": "Circle 3-pt", "rect": "Rect 3-pt",
	"height": "Height", "angle": "Angle 3-pt", "path": "Path", "area": "Area",
	"cut": "Cut", "copy": "Copy", "paste": "Paste", "duplicate": "Duplicate", "delete": "Delete",
	"reset": "Reset size", "scale": "Scale", "drop": "Drop", "pin": "Pin/Unpin", "acctest": "Accuracy test"}
const HOLD_UNDO := 0.5          # seconds holding B or Y
const YAW_STEP_DEG := 15.0      # placed shapes square up to 15° steps
const ROT_SPEED := 120.0        # degrees/s at full stick left/right while holding
const PUSH_SPEED := 1.5         # m/s at full stick forward/back while holding
const SNAP_TOUCH := 0.03        # carried shape snaps onto a surface when its bottom is within 3 cm
const TAP_SEC := 0.25           # a trigger tap shorter than this (and not moved) only selects


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
	var pinned := false
	var orig_dims: Dictionary = {}   # size it was created with (Reset size)
	var fit_hits: Array = []         # names of walls / furniture / shapes it overlaps (Fit check)


class Measure:
	var type: String          # line | circle | rect | height | angle | path | area
	var name: String
	var points: Array = []    # content-local Vector3
	var node: Node3D
	var center := Vector3.ZERO
	var normal := Vector3.UP
	var r := 0.0
	var w := 0.0              # rect width / depth
	var dp := 0.0


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
	var high_at := INF              # when B / Y went down (tap = menu, hold = undo); INF = not held
	var high_used := false          # this press already did something (undo, or cancelled by a grab)
	var last_t := -1.0              # last input time (stick speeds)
	var stick_down_at := -10.0
	var latch_x := true
	var latch_y := true
	var press_shape = null


# ---------------------------------------------------------------- state
var units := "metric"
var mode := "select"           # select | a MEASURE_TOOLS entry | an EDIT_TOOLS entry
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

var room := {}                 # {id, name, created}
# A room loads on the floor where you are standing, facing the way you look. Stand on your usual spot,
# face your usual way and recenter (hold the Meta button): the room snaps back into place.
var room_turn := 0.0           # degrees turned with Turn room since the room was last placed
var surfaces: Array = []       # scene_anchor nodes
var save_dirty := false
var save_timer := 0.0
var menu_page := "main"
var menu_attach: Ctrl = null   # null = fixed in place
var menu_anchor := Vector3.ZERO
var ctx_attach: Ctrl = null    # hand the tool menu is stuck to
var menu_dirty := true
var selftest := false

var fit_check := true          # shapes overlapping walls, furniture or each other turn red
var fit_timer := 0.0
var fit_ignore: Array[RID] = []   # floor + whole-room mesh: never count as "doesn't fit"
var acc_ref := {}              # current accuracy reference {id, label, mm}
var acc_custom_mm := 1000.0
var acc_trials: Array = []     # [{time, ref, true_mm, measured_mm, error_mm, error_pct, distance_m}]
var acc_line: Node3D = null    # the last accuracy trial, drawn until the next one

var xr_interface: XRInterface
var xr_active := false
var origin: XROrigin3D
var camera: XRCamera3D
var content: Node3D
var ctrls: Array = []
var scene_mgr: Node = null
var menu: Node3D
var ctx: Node3D                # X / A tool menu
var tray: Node3D               # object tray beside the stick-click menu
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
	load_accuracy()
	if not xr_active:
		# Desktop / CI: no headset, so start the room straight away.
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
	# Give tracking a moment to settle before placing the room where you stand.
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

	# Meta scene understanding (walls, floor, tables, room mesh from Space Setup).
	if ClassDB.class_exists("OpenXRFbSceneManager"):
		scene_mgr = ClassDB.instantiate("OpenXRFbSceneManager")
		scene_mgr.name = "SceneManager"
		scene_mgr.set("default_scene", SceneAnchorScene)
		scene_mgr.set("auto_create", true)
		origin.add_child(scene_mgr)
		scene_mgr.connect("openxr_fb_scene_data_missing", _on_scene_data_missing)
		scene_mgr.connect("openxr_fb_scene_capture_completed", _on_scene_capture_completed)

	menu = UIPanel.new()
	menu.name = "Menu"
	add_child(menu)
	ctx = UIPanel.new()
	ctx.name = "Tools"
	add_child(ctx)
	tray = UIPanel.new()
	tray.name = "Tray"
	add_child(tray)

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
func make_label(accent: Color, lines := 3) -> Node3D:
	var n := Node3D.new()
	for i in lines:
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
	menu_dirty = true


## Floor and the whole-room mesh: things always touch them, so they never count for Fit check.
func ignore_for_fit(rid: RID) -> void:
	fit_ignore.append(rid)


func _on_scene_data_missing() -> void:
	set_status("No Space Setup found. Open the menu > Scan room to map walls and tables.")


func _on_scene_capture_completed(_ok: bool) -> void:
	if scene_mgr:
		scene_mgr.call("remove_scene_anchors")
		surfaces.clear()
		fit_ignore.clear()
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


func make_shape(type: String, dims: Dictionary, pos: Vector3, rot := Quaternion.IDENTITY, sname := "", outline = null, orig = null) -> Shape:
	var s := Shape.new()
	s.type = type
	s.dims = dims.duplicate()
	s.orig_dims = (orig if orig is Dictionary and not orig.is_empty() else dims).duplicate()
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
	s.label = make_label(s.color, 4)   # 4th line: Fit check warning
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
	var lines := shape_lines(s.type, ("%s (pinned)" % s.name) if s.pinned else s.name, s.dims)
	if s.fit_hits.size():
		lines.append("DOESN'T FIT: hits " + ", ".join(s.fit_hits))
	set_label(s.label, lines)
	if s.label.get_child_count() > 3:
		(s.label.get_child(3) as Label3D).modulate = C_RED
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
	selected = s
	if prev:
		apply_shape_colors(prev)
		for h in prev.handles:
			h.queue_free()
		prev.handles = []
	if s:
		apply_shape_colors(s)
		# Resize cubes only in the Scale tool, and never on a pinned shape.
		for hd in ([] if s.pinned or mode != "scale" else handle_defs(s.type)):
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


## Tool type -> stored measure type (tape is saved as "line" for older rooms).
func measure_type(tool: String) -> String:
	return "line" if tool == "tape" else tool


func newell(pts: Array) -> Vector3:
	var n := Vector3.ZERO
	for i in pts.size():
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[(i + 1) % pts.size()]
		n += Vector3((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y))
	return n


func poly_area(pts: Array) -> float:
	return newell(pts).length() / 2.0 if pts.size() >= 3 else 0.0


func path_len(pts: Array, closed := false) -> float:
	var t := 0.0
	for i in pts.size() - 1:
		t += (pts[i] as Vector3).distance_to(pts[i + 1])
	if closed and pts.size() > 2:
		t += (pts[-1] as Vector3).distance_to(pts[0])
	return t


## Rect 3-pt: A-B is one edge, C sets the depth (squared off to A-B). Returns 4 corners, width, depth.
func rect_from_3(a: Vector3, b: Vector3, c: Vector3):
	var ab := b - a
	if ab.length() < 1e-4:
		return null
	var u := ab.normalized()
	var ac := c - a
	var dv := ac - u * ac.dot(u)
	if dv.length() < 1e-4:
		return null
	return {"corners": [a, b, b + dv, a + dv], "w": ab.length(), "d": dv.length()}


func floor_foot(p: Vector3) -> Vector3:
	return Vector3(p.x, 0.0, p.z)


func angle_deg(a: Vector3, v: Vector3, b: Vector3) -> float:
	return rad_to_deg((a - v).angle_to(b - v))


## The polyline drawn for a measurement: {pts, closed}.
func measure_poly(type: String, points: Array) -> Dictionary:
	match type:
		"rect":
			var r = rect_from_3(points[0], points[1], points[2])
			return {"pts": r.corners if r else points, "closed": true}
		"height": return {"pts": [points[0], floor_foot(points[0])], "closed": false}
		"area": return {"pts": points, "closed": true}
	return {"pts": points, "closed": false}


func measure_lines(m: Measure) -> Array:
	match m.type:
		"line":
			var dv: Vector3 = m.points[1] - m.points[0]
			return ["%s  %s" % [m.name, L(dv.length())], "vert %s · horiz %s" % [L(absf(dv.y)), L(Vector2(dv.x, dv.z).length())]]
		"circle":
			return ["%s  Ø %s" % [m.name, L(2 * m.r)], "r %s · circ %s" % [L(m.r), L(TAU * m.r)]]
		"rect":
			return ["%s  %s × %s" % [m.name, L(m.w), L(m.dp)], "area %s · perim %s" % [AREA(m.w * m.dp), L(2 * (m.w + m.dp))]]
		"height":
			return ["%s  H %s" % [m.name, L(m.points[0].y)], "above the floor"]
		"angle":
			return ["%s  %.1f°" % [m.name, angle_deg(m.points[0], m.points[1], m.points[2])], "at the middle point"]
		"path":
			return ["%s  %s" % [m.name, L(path_len(m.points))], "%d segments" % (m.points.size() - 1)]
		"area":
			return ["%s  %s" % [m.name, AREA(poly_area(m.points))], "perim %s · %d sides" % [L(path_len(m.points, true)), m.points.size()]]
	return [m.name]


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
	var label_pos: Vector3 = Vector3.ZERO
	for p in m.points:
		label_pos += p
	label_pos /= maxf(1.0, m.points.size())
	var li := MeshInstance3D.new()
	li.material_override = mat_measure
	if type == "circle":
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
		label_pos = m.center
	else:
		if type == "rect":
			var r = rect_from_3(m.points[0], m.points[1], m.points[2])
			if r == null:
				return null
			m.w = r.w
			m.dp = r.d
			label_pos = (r.corners[0] + r.corners[2]) / 2.0
		elif type == "angle" and ((m.points[0] - m.points[1]).length() < 1e-4 or (m.points[2] - m.points[1]).length() < 1e-4):
			return null
		elif type == "area" and poly_area(m.points) < 1e-6:
			return null
		elif type == "height":
			label_pos = (m.points[0] + floor_foot(m.points[0])) / 2.0
		var mp := measure_poly(type, m.points)
		var pts := PackedVector3Array(mp.pts)
		if mp.closed:
			pts.append(mp.pts[0])
		li.mesh = _lines_mesh(pts, true)
	if mname == "":
		counters.m += 1
		mname = "M%d" % counters.m
	m.name = mname
	m.node = Node3D.new()
	for p in m.points:
		m.node.add_child(_dot(p))
	if type == "circle":
		m.node.add_child(_dot(m.center))
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


const TOOL_POINTS := {"tape": 2, "circle": 3, "rect": 3, "angle": 3, "height": 1, "acctest": 2}

func tool_hint(t: String, n: int) -> String:
	match t:
		"tape": return "Tape: point at the first end and press trigger." if n == 0 else "Now point at the second end."
		"circle": return "Circle: tap 3 points around a round edge." if n == 0 else "Point %d of 3 on the round edge." % (n + 1)
		"rect": return ["Rect: tap one corner.", "Tap the next corner along the same edge.", "Tap anywhere on the opposite edge."][mini(n, 2)]
		"height": return "Height: tap a point. Shows its height above the floor."
		"angle": return ["Angle: tap a point on the first arm.", "Tap the corner (vertex).", "Tap a point on the second arm."][mini(n, 2)]
		"path": return "Path: tap points along the route. Tap the last point again to finish." if n < 2 else "Path: keep tapping. Tap the last point again to finish."
		"area": return "Area: tap the corners of the outline. Tap the first point again to close it." if n < 3 else "Area: keep tapping, or tap the first point to close."
		"acctest":
			var lbl: String = acc_ref.get("label", "reference")
			return ("Accuracy: tap one end of the %s (true %.1f mm)." % [lbl, acc_ref.get("mm", 0.0)]) if n == 0 else "Now tap the other end of the %s." % lbl
	return ""


func add_pending_point(p: Vector3) -> void:
	var finish := false
	if mode == "path" and pending.size() >= 2 and p.distance_to(pending[-1]) < 0.01:
		finish = true
	elif mode == "area" and pending.size() >= 3 and p.distance_to(pending[0]) < SNAP_POINT:
		finish = true
	if not finish:
		if mode in ["path", "area"] and pending.size() and p.distance_to(pending[-1]) < 0.01:
			return     # double tap on the same spot too early: ignore
		pending.append(p)
		var dot := _dot(p)
		content.add_child(dot)
		pending_dots.append(dot)
		var need: int = TOOL_POINTS.get(mode, 1 << 20)
		if pending.size() < need:
			set_status(tool_hint(mode, pending.size()))
			return
	if mode == "acctest":
		var a: Vector3 = pending[0]
		var b: Vector3 = pending[1]
		clear_pending()
		record_trial(a, b)
		return
	var m := create_measure(measure_type(mode), pending)
	clear_pending()
	if m == null:
		set_status("Those points don't make a shape (in a line or on top of each other). Try again, spread them out.")
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
	return {"type": s.type, "dims": s.dims.duplicate(), "rot": s.node.quaternion, "name": s.name, "outline": s.outline, "orig": s.orig_dims.duplicate()}


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
	var s := make_shape(it.type, it.dims, point, it.rot, "", it.get("outline"), it.get("orig"))
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
	var step := deg_to_rad(YAW_STEP_DEG)
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
		"rect": return "Rect 3-pt"
		"height": return "Height"
		"angle": return "Angle 3-pt"
		"path": return "Path"
		"area": return "Area"
		"settings": return "Settings..."
		"reset": return "Reset size"
		"scale": return "Scale"
		"pin": return "Pin / Unpin"
		"select": return "Rotate/Move"
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
		"turnl5": return "Turn room 5° left"
		"turnl1": return "Turn room 1° left"
		"turnr1": return "Turn room 1° right"
		"turnr5": return "Turn room 5° right"
		"accuracy": return "Accuracy test..."
		"roominfo": return "Room info..."
		"fitcheck": return "Fit check: on" if fit_check else "Fit check: off"
		"accexport": return "Export results"
		"accclear": return "Clear results"
	return id


func button_enabled(id: String) -> bool:
	if id == "paste":
		return clipboard.size() > 0
	if id == "nextclip":
		return clipboard.size() > 1
	return true


func menu_items() -> Array:
	var out := []
	if menu_page == "rooms":
		out.append({"id": "back", "label": "< Back"})
		out.append({"id": "newroom", "label": "New room", "color": C_CYAN})
		out.append({"id": "save", "label": "Save room"})
		out.append({"id": "delroom", "label": "Delete this room", "color": Color("ff6b6b")})
		out.append({"id": "placehere", "label": "Place room here", "sub": "where you stand, facing your way"})
		for r in list_rooms():
			out.append({"id": "room:" + r.id, "label": r.name, "sub": "%d shapes · %s" % [r.count, r.updated], "active": r.id == room.get("id", "")})
		return out
	if menu_page == "accuracy":
		return accuracy_items()
	if menu_page == "roominfo":
		return [
			{"id": "back", "label": "< Back"},
			{"id": "scan", "label": button_text("scan"), "sub": "Meta Space Setup"},
			{"id": "fitcheck", "label": button_text("fitcheck"), "sub": "red = overlaps", "active": fit_check},
			{"id": "roomvis", "label": button_text("roomvis")},
		]
	for id in MENU_MAIN:
		var col := Color.WHITE
		if id in MEASURE_TOOLS:
			col = C_YELLOW
		elif id in ["quit", "delete", "clear"]:
			col = Color("ff6b6b")
		elif id.begins_with("turn") or id == "placehere":
			col = Color(0.6, 0.8, 1.0)
		out.append({"id": id, "label": button_text(id), "active": id == mode, "enabled": button_enabled(id), "color": col})
	return out


func tray_items() -> Array:
	var out := []
	for i in PALETTE.size():
		var p: Dictionary = PALETTE[i]
		out.append({"id": "obj:%d" % i, "label": p.label, "sub": short_dims(p.type, p.dims), "color": COLORS[p.type]})
	return out


func menu_header() -> Array:
	if menu_page == "accuracy":
		var last = acc_trials[-1] if acc_trials.size() else null
		return [
			[status, Color.WHITE],
			[accuracy_summary(), C_YELLOW],
			[("Last: %s  %.1f mm (true %.1f, error %+.1f)" % [last.ref, last.measured_mm, last.true_mm, last.error_mm]) if last else "Pick a reference, then tap its two ends with the trigger.", Color(0.6, 0.65, 0.7)],
		]
	if menu_page == "roominfo":
		var out := [[status, Color.WHITE]]
		for l in room_info_lines():
			out.append([l, C_CYAN])
		return out
	var clip = clipboard[clip_index] if clipboard.size() else null
	return [
		[status, Color.WHITE],
		["Tool: %s   ·   %s" % [MODE_NAMES.get(mode, mode), room.get("name", "-")], Color(0.6, 0.65, 0.7)],
		["Clipboard %d/%d: %s" % [clip_index + 1, clipboard.size(), clip.name] if clip else "Clipboard: empty", C_YELLOW],
	]


func tray_wanted() -> bool:
	return menu.is_open and menu_page == "main" and mode == "select"


func rebuild_menu() -> void:
	var title: String = {"rooms": "ROOMS", "accuracy": "ACCURACY TEST", "roominfo": "ROOM INFO"}.get(menu_page, "FRAMESPACE  " + BUILD)
	menu.build(title, menu_header(), menu_items(), 4, 0.075)
	menu_dirty = false
	var want := tray_wanted()
	if want and not tray.is_open:
		tray.build("OBJECTS  ·  trigger or grip one to grab it", [], tray_items(), 6, 0.07)
		tray.is_open = true
		tray.visible = true
	elif not want and tray.is_open:
		tray.close()
	layout_menu()


## Y / B tap: the menu (sidebar + tray) stuck to that hand. Point with the other hand.
func open_menu(c: Ctrl, _fixed := true) -> void:
	if ctx_attach == c:
		close_tools()
	menu_page = "main"
	menu_attach = c
	menu.is_open = true       # so rebuild_menu knows the tray is wanted
	rebuild_menu()
	menu.open_at(_hand_top(c, menu.size.y), camera.global_position)
	layout_menu()
	haptic(c, 0.4, 0.03)


## Where a panel of height h sits: just above the controller, its bottom edge 6 cm over the hand.
func _hand_top(c: Ctrl, h: float) -> Vector3:
	return c.node.global_position + Vector3(0, 0.06 + h / 2.0, 0)


## Sidebar over the hand, tray beside it on the inside (toward the other hand), tops aligned.
func layout_menu() -> void:
	if not menu.is_open:
		return
	var head := camera.global_position
	if menu_attach != null:
		menu_anchor = _hand_top(menu_attach, menu.size.y)
	menu.global_position = menu_anchor
	menu.face(head)
	if not tray.is_open:
		return
	var right: Vector3 = menu.global_basis.x
	var up: Vector3 = menu.global_basis.y
	var side := -1.0 if menu_attach != null and menu_attach.hand == "right" else 1.0
	tray.global_transform = menu.global_transform
	tray.global_position = menu.global_position + right * side * (menu.size.x / 2.0 + 0.015 + tray.size.x / 2.0) + up * (menu.size.y - tray.size.y) / 2.0


func close_menu() -> void:
	menu.close()
	tray.close()
	menu_attach = null


func on_button(id: String, c: Ctrl = null) -> void:
	if id.begins_with("obj:"):
		spawn_object(int(id.substr(4)))
		return
	if id in MEASURE_TOOLS or id in EDIT_TOOLS or id == "select":
		set_tool(id)
		return
	if id == "nextclip":
		run_tool("nextclip")
		menu_dirty = true
		return
	if not button_enabled(id):
		set_status("Clipboard is empty." if id in ["paste", "nextclip"] else "Select a shape first (Move/Size mode, point and trigger).")
		return
	if id.begins_with("room:"):
		load_room(id.substr(5))
		menu_page = "main"
		menu_dirty = true
		return
	if id.begins_with("acc:"):
		start_accuracy(id.substr(4))
		close_menu()
		return
	if id.begins_with("accu:"):
		acc_custom_mm = maxf(1.0, acc_custom_mm + float(id.substr(5)))
		if acc_ref.get("id", "") == "custom":
			acc_ref.mm = acc_custom_mm
		save_accuracy()
		set_status("Custom true length: %.0f mm. Tape-measure the real thing first, then set it here." % acc_custom_mm)
		menu_dirty = true
		return
	match id:
		"accuracy":
			menu_page = "accuracy"
			set_status("Accuracy test: measure things whose true size you know.")
		"roominfo":
			menu_page = "roominfo"
			set_status("From your Space Setup scan." if surfaces.size() else "No Space Setup yet: press Scan room.")
		"fitcheck":
			set_fit_check(not fit_check)
			set_status("Fit check on: objects that hit walls, furniture or each other turn red." if fit_check else "Fit check off.")
		"accexport":
			export_accuracy()
		"accclear":
			var old := acc_trials.duplicate()
			acc_trials.clear()
			_clear_acc_line()
			save_accuracy()
			push_history(func():
				acc_trials = old
				save_accuracy())
			set_status("Accuracy results cleared. Undo brings them back.")
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
		"units":
			units = "imperial" if units == "metric" else "metric"
			for s in shapes:
				refresh_shape(s)
			for m in measures:
				refresh_measure_label(m)
			set_status("Units: %s." % units)
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
		"settings":
			menu_page = "settings"
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
		"export":
			export_all()
		"quit":
			save_room_now()
			get_tree().quit()
		"turnl5": turn_room(5.0)
		"turnl1": turn_room(1.0)
		"turnr1": turn_room(-1.0)
		"turnr5": turn_room(-5.0)
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


# ================================================================ objects (stick-click menu) and tool menu (X / A)
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


## Spawn object i from objects.csv. With a controller + point it starts in that hand (carry until
## trigger/grip release); without, it lands where you point and settles.
func spawn_object(i: int, c: Ctrl = null, point_w = null) -> Shape:
	if i < 0 or i >= PALETTE.size():
		return null
	var p: Dictionary = PALETTE[i]
	label_counts[p.label] = int(label_counts.get(p.label, 0)) + 1
	var pos: Vector3 = content.to_local(point_w) if point_w != null else spawn_point()
	var s := make_shape(p.type, p.dims, pos, Quaternion.IDENTITY, "%s %d" % [p.label, label_counts[p.label]], p.get("outline"))
	push_history(func(): remove_shape(s))
	if mode in MEASURE_TOOLS:
		set_tool("select", false)
	select(s)
	if c != null:
		start_free(c, s, false)
		haptic(c, 0.5, 0.04)
		set_status("Placing %s" % s.name)
	else:
		s.node.position.y += half_height(s)
		settle(s)
		set_status("Added %s." % s.name)
	persist()
	return s


func set_tool(t: String, announce := true) -> void:
	mode = t
	clear_pending()
	select(selected if t in ["select", "scale"] else null)
	menu_dirty = true
	if not announce:
		return
	if t in MEASURE_TOOLS:
		set_status(tool_hint(t, 0))
		return
	var clip = clipboard[clip_index] if clipboard.size() else null
	set_status({
		"select": "Rotate/Move: trigger picks up (twist your wrist to turn it), grip slides. While holding: stick left/right turns, forward/back pushes/pulls.",
		"scale": "Scale: trigger an object to select it, then drag its yellow cubes.",
		"cut": "Cut: trigger on an object.",
		"copy": "Copy: trigger on an object.",
		"paste": ("Paste: trigger where you want %s." % clip.name) if clip else "Paste: clipboard is empty. Cut or Copy something first.",
		"duplicate": "Duplicate: trigger on an object.",
		"delete": "Delete: trigger on an object.",
		"reset": "Reset size: trigger on an object to put it back to its original size.",
		"drop": "Drop: trigger on an object to drop it onto what's below.",
		"pin": "Pin: trigger on an object to pin or unpin it.",
	}.get(t, ""))


func tool_items() -> Array:
	var out := []
	for id in TOOLS_MENU:
		var en := true
		if id in ["paste", "nextclip"]:
			en = clipboard.size() > (1 if id == "nextclip" else 0)
		out.append({"id": id, "label": button_text(id), "active": id == mode, "enabled": en,
			"color": Color("ff6b6b") if id == "delete" else (C_YELLOW if id == "pin" else Color.WHITE)})
	return out


## X / A: the tool menu, in front of that hand. Pick a tool; trigger then does it on whatever you point at.
func open_tools(c: Ctrl) -> void:
	var clip = clipboard[clip_index] if clipboard.size() else null
	ctx.build("TOOL: " + String(MODE_NAMES.get(mode, mode)).to_upper(),
		[[("Clipboard %d/%d: %s" % [clip_index + 1, clipboard.size(), clip.name]) if clip else "Clipboard empty", C_YELLOW]],
		tool_items(), 4, 0.085)
	if menu_attach == c:
		close_menu()
	ctx_attach = c
	ctx.open_at(_hand_top(c, ctx.size.y), camera.global_position)
	haptic(c, 0.4, 0.03)


func close_tools() -> void:
	ctx.close()
	ctx_attach = null


func run_tool(id: String) -> void:
	close_tools()
	if id == "nextclip":
		if clipboard.size():
			clip_index = (clip_index + 1) % clipboard.size()
			set_tool("paste", false)
			set_status("Paste: %s. Trigger where you want it." % clipboard[clip_index].name)
		return
	set_tool(id)


## What trigger does on a shape in an edit tool.
func apply_tool(c: Ctrl, s: Shape) -> void:
	haptic(c, 0.4, 0.03)
	match mode:
		"cut", "copy":
			select(s)
			copy_selected(mode == "cut")
			set_tool("paste", false)
		"duplicate":
			var dx: Vector3 = (s.node.quaternion * Vector3.RIGHT) * (scale_of(s.type, s.dims).x + 0.05)
			paste_at(s.node.position, clip_item(s), dx)
		"delete":
			remove_shape(s)
			push_history(func(): restore_shape(s))
			set_status("Deleted %s. Hold B to undo." % s.name)
			persist()
		"reset":
			reset_size(s)
		"scale":
			select(s)
		"drop":
			if refuse_pinned(c, s):
				return
			push_history(_snap_undo(s))
			settle(s)
			set_status("Dropped %s onto the surface below." % s.name)
			persist()
		"pin":
			set_pinned(s, not s.pinned)
			push_history(func(): set_pinned(s, not s.pinned))
			set_status(("%s pinned. It can't be grabbed until you unpin it." % s.name) if s.pinned else ("%s unpinned." % s.name))
			persist()
	menu_dirty = true


## Back to the size it was created with, still standing on the same spot.
func reset_size(s: Shape) -> void:
	if s.orig_dims.is_empty() or s.orig_dims == s.dims:
		set_status("%s is already its original size." % s.name)
		return
	push_history(_snap_undo(s))
	var bottom := s.node.position.y - half_height(s)
	s.dims = s.orig_dims.duplicate()
	s.node.position.y = bottom + half_height(s)
	refresh_shape(s)
	set_status("%s reset: %s" % [s.name, dims_text(s)])
	persist()


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
		if pnl == null or not pnl.is_open or ((pnl == menu or pnl == tray) and menu_attach == c) or (pnl == ctx and ctx_attach == c):
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
	if best != null and mode in MEASURE_TOOLS:
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
	var hov := {menu: "", tray: "", ctx: ""}
	for c in ctrls:
		if c.ui != null and hov.has(c.ui.panel):
			hov[c.ui.panel] = c.ui.id
	for p in hov:
		if p.is_open:
			p.set_hover(hov[p])


# ================================================================ controller input
# Like a brush on a canvas:
#   Trigger on an object (Move/Scale): pick it up. Twist your wrist to turn it. Touch a surface and it
#     snaps to the grid on top of it. Let go to place it (in mid-air it falls onto what's below).
#     A quick tap only selects it. Trigger on a yellow cube: resize.
#   Grip on an object: slide it around on the grid, staying on its surface.
#   Stick while holding: left/right = turn smoothly, forward/back = push away / pull in.
#   Y or B tap: main menu (tools sidebar + object tray) stuck to that hand. Hold ½ s: undo.
#   X or A: tool menu stuck to that hand. Point and trigger with the other hand.
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

	var dt := clampf(now - c.last_t, 0.0, 0.1) if c.last_t >= 0.0 else 0.0
	c.last_t = now

	# X / A: tool menu on that hand (toggle).
	if down.call("low"):
		if ctx.is_open and ctx_attach == c:
			close_tools()
		else:
			open_tools(c)

	# Y / B: tap = main menu on that hand (toggle, on release); hold ½ s = undo.
	if down.call("high"):
		c.high_at = now
		c.high_used = c.drag != null
	if b.get("high", false):
		if c.drag != null:
			c.high_used = true
		elif not c.high_used and now - c.high_at >= HOLD_UNDO:
			c.high_used = true
			undo()
			haptic(c, 0.5, 0.05)
	if up.call("high"):
		if not c.high_used:
			if menu.is_open and menu_attach == c:
				close_menu()
			else:
				open_menu(c)
		c.high_at = INF

	if down.call("trigger"):
		on_trigger_down(c, b)
	if down.call("grip"):
		on_grip_down(c, b)
	if up.call("trigger"):
		c.press_shape = null
	if c.drag != null:
		var rel: String = c.drag.get("release", "trigger")
		if up.call(rel):
			on_drag_release(c)
	if c.drag != null and (c.drag.type == "move" or c.drag.type == "free"):
		# Stick while holding: left/right turns smoothly, forward/back pushes away / pulls in.
		# The stick must come back to centre after a grab starts (no surprise spin).
		var sx: float = b.get("sx", 0.0)
		var sy: float = b.get("sy", 0.0)
		if Vector2(sx, sy).length() < 0.2:
			c.latch_x = false
		if not c.latch_x:
			stick_held(c, sx, sy, dt)
	else:
		c.latch_x = true


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
				# Picking a tool other than Move/Scale gets the menu out of your way.
				if (id in MEASURE_TOOLS or id in EDIT_TOOLS) and menu.is_open:
					close_menu()
		elif pnl == tray:
			grab_from_tray(c, id, "trigger")
		elif pnl == ctx:
			var it2 = ctx.item(id)
			if it2 != null and it2.get("enabled", true):
				haptic(c, 0.4, 0.03)
				run_tool(id)
		return
	if ctx.is_open:
		close_tools()
		return
	if mode in MEASURE_TOOLS:
		var p: Vector3 = c.target.point if c.target != null else c.o + c.d * 0.8
		if c.target == null:
			set_status("No surface there: used a point 80 cm along the ray.")
		haptic(c)
		add_pending_point(p)
		return
	if mode == "paste":
		var pp: Vector3 = c.target.point if c.target != null else c.o + c.d * 0.8
		haptic(c, 0.4, 0.03)
		paste_at(pp)
		return
	if mode == "scale":
		if c.handle_hit != null and not b.get("grip", false) and not _anyone_carrying():
			start_handle(c, c.handle_hit)
			haptic(c)
		elif c.shape_hit != null:
			select(c.shape_hit.shape)
			haptic(c, 0.2, 0.015)
			set_status(("%s is pinned: unpin it to resize." if selected.pinned else "Scale %s: drag a yellow cube.") % selected.name)
		elif selected:
			select(null)
		return
	if mode in EDIT_TOOLS:
		if c.shape_hit != null:
			apply_tool(c, c.shape_hit.shape)
		else:
			set_status("%s: point at an object." % MODE_NAMES[mode])
		return
	# Rotate/Move.
	if c.drag != null:
		return
	if c.shape_hit != null:
		var s: Shape = c.shape_hit.shape
		select(s)
		c.press_shape = s
		haptic(c, 0.2, 0.015)
		if not refuse_pinned(c, s, false):
			start_free(c, s, true, c.shape_hit.point)
		return
	if selected:
		select(null)


func grab_from_tray(c: Ctrl, id: String, release: String) -> void:
	if not id.begins_with("obj:"):
		return
	var s := spawn_object(int(id.substr(4)), c, c.ui.point)
	if s and c.drag != null:
		c.drag["release"] = release
	close_menu()


func on_grip_down(c: Ctrl, b: Dictionary) -> void:
	last_ctrl = c
	if c.ui != null and c.ui.panel == tray:
		grab_from_tray(c, c.ui.id, "grip")
		return
	if c.drag != null and c.drag.type == "handle":
		# Grip during a resize: stop resizing (size stays where it is) and slide it instead.
		var hs: Shape = c.drag.shape
		c.drag = null
		if not refuse_pinned(c, hs):
			start_move(c, hs)
		return
	if c.ui != null or mode in MEASURE_TOOLS or c.drag != null:
		return
	var s = c.shape_hit.shape if c.shape_hit != null else null
	if s == null:
		return
	if mode == "select":
		select(s)
	if refuse_pinned(c, s):
		return
	# Grip slides it on the grid; size and rotation change only with the stick.
	start_move(c, s)
	haptic(c)


func _anyone_carrying() -> bool:
	for k in ctrls:
		if k.drag != null and (k.drag.type == "move" or k.drag.type == "free"):
			return true
	return false


## Pinned shapes stay put: no grabbing, carrying, resizing or dropping until unpinned (Pin tool).
func set_pinned(s: Shape, on: bool) -> void:
	s.pinned = on
	if selected == s:
		select(s)
	else:
		refresh_shape(s)
	menu_dirty = true


func refuse_pinned(c: Ctrl, s: Shape, loud := true) -> bool:
	if s == null or not s.pinned:
		return false
	set_status("%s is pinned. Use the Pin tool (X / A) to unpin it." % s.name)
	if c and loud:
		haptic(c, 0.6, 0.06)
	return true


func on_drag_release(c: Ctrl) -> void:
	var dr = c.drag
	if dr == null:
		return
	c.drag = null
	if dr.type == "free":
		var s: Shape = dr.shape
		var now := Time.get_ticks_msec() / 1000.0
		var moved: float = s.node.position.distance_to(dr.p_start)
		if dr.get("tap_ok", false) and now - dr.t0 < TAP_SEC and moved < 0.03:
			# Just a tap: select, leave it exactly where it was.
			apply_snapshot(s, dr.snap)
			if dr.undo_pushed and history.size():
				history.pop_back()
			set_status("Selected %s. Hold trigger to pick it up, grip to slide it." % s.name)
		else:
			settle(s)
			set_status("%s placed" % s.name)
		grid_patch.visible = false
	elif dr.type == "move":
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
	push_history(_snap_undo(s))
	falling = falling.filter(func(f): return f.shape != s)
	c.drag = {"type": "move", "release": "grip", "shape": s, "c0": c.o, "yaw0": yaw_of_dir(c.d), "p0": s.node.position, "base_y": s.node.position.y}
	set_status("Sliding %s" % s.name)


func update_move(c: Ctrl, dr: Dictionary) -> void:
	var qy := Quaternion(Vector3.UP, yaw_of_dir(c.d) - dr.yaw0)
	var p: Vector3 = c.o + qy * (dr.p0 - dr.c0)
	var flat := Vector3(c.d.x, 0, c.d.z)
	if flat.length() > 0.01:
		p += flat.normalized() * float(dr.get("push", 0.0))
	var s: Shape = dr.shape
	s.node.position = Vector3(snap_grid(p.x), dr.base_y, snap_grid(p.z))
	refresh_shape(s)
	show_grid_patch(s.node.position.x, dr.base_y - half_height(s), s.node.position.z)


func _ctrl_local_quat(c: Ctrl) -> Quaternion:
	return (content.global_basis.inverse() * c.node.global_basis).get_rotation_quaternion()


## Trigger carry. The shape hangs on the ray at the distance you grabbed it (point where you want it,
## like a brush); twisting the wrist turns it; it stays upright.
func start_free(c: Ctrl, s: Shape, push_undo: bool, grab_point = null) -> void:
	var snap := snapshot(s)
	if push_undo:
		push_history(_snap_undo(s))
	falling = falling.filter(func(f): return f.shape != s)
	var gp: Vector3 = grab_point if grab_point != null else s.node.position
	var dist := maxf(0.05, (gp - c.o).dot(c.d))
	c.drag = {"type": "free", "release": "trigger", "shape": s, "dist": dist, "off": s.node.position - (c.o + c.d * dist),
		"yaw0": yaw_of_quat(s.node.quaternion), "q0": _ctrl_local_quat(c), "t0": Time.get_ticks_msec() / 1000.0,
		"p_start": s.node.position, "snap": snap, "undo_pushed": push_undo, "tap_ok": push_undo, "snapped": false}
	set_status("Carrying %s. Touch a surface to snap, twist to turn." % s.name)


## Wrist twist (roll around the controller's pointing axis) since the grab, in radians.
func wrist_twist(c: Ctrl, q0: Quaternion) -> float:
	var rel := q0.inverse() * _ctrl_local_quat(c)
	var a := 2.0 * atan2(rel.z, rel.w)
	return wrapf(a, -PI, PI)


func update_free(c: Ctrl, dr: Dictionary) -> void:
	var s: Shape = dr.shape
	var p: Vector3 = c.o + c.d * dr.dist + dr.off
	var yaw: float = dr.yaw0 + wrist_twist(c, dr.q0)
	var hh := half_height(s)
	var sup := support_below(p.x, p.z, p.y, s)
	dr.snapped = p.y - hh - sup < SNAP_TOUCH
	if dr.snapped:
		var step := deg_to_rad(YAW_STEP_DEG)
		yaw = roundf(yaw / step) * step
		p = Vector3(snap_grid(p.x), sup + hh, snap_grid(p.z))
		show_grid_patch(p.x, sup, p.z)
	else:
		grid_patch.visible = false
	s.node.position = p
	s.node.quaternion = Quaternion(Vector3.UP, yaw)
	refresh_shape(s)


func rotate_held(c: Ctrl, ang: float) -> void:
	var dr: Dictionary = c.drag
	var s: Shape = dr.shape
	var qy := Quaternion(Vector3.UP, ang)
	if dr.type == "move":
		s.node.quaternion = snap_yaw_quat(qy * s.node.quaternion)
	else:
		dr.yaw0 += ang
		s.node.quaternion = qy * s.node.quaternion
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


func _stick_curve(v: float) -> float:
	var a := absf(v)
	if a < 0.2:
		return 0.0
	var t := (a - 0.2) / 0.8
	return signf(v) * t * t       # gentle near the centre for fine control


## Smooth stick while holding: x = turn (right = clockwise), y = push away (+) / pull in (-).
func stick_held(c: Ctrl, sx: float, sy: float, dt: float) -> void:
	var dr: Dictionary = c.drag
	var s: Shape = dr.shape
	var turn := -deg_to_rad(ROT_SPEED) * _stick_curve(sx) * dt
	var push := PUSH_SPEED * _stick_curve(sy) * dt
	if turn != 0.0:
		if dr.type == "free":
			dr.yaw0 += turn
		else:
			s.node.quaternion = Quaternion(Vector3.UP, turn) * s.node.quaternion
			refresh_shape(s)
	if push != 0.0:
		if dr.type == "free":
			dr.dist = clampf(dr.dist + push, 0.1, 15.0)
		else:
			dr["push"] = float(dr.get("push", 0.0)) + push


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
	if c == null or c.target == null or not (mode in MEASURE_TOOLS) or (pending.is_empty() and mode != "height"):
		preview.visible = false
		preview_label.visible = false
		return
	var p: Vector3 = c.target.point
	var pts: Array = pending.duplicate()
	pts.append(p)
	var lines: Array = []
	var at: Vector3 = p
	var draw := PackedVector3Array(pts)
	match mode:
		"acctest":
			var mm: float = (pending[0] as Vector3).distance_to(p) * 1000.0
			lines = ["%.1f mm" % mm, "error %+.1f mm" % (mm - float(acc_ref.get("mm", 0.0)))]
			at = (pending[0] + p) / 2.0
		"tape":
			var dv: Vector3 = p - pending[0]
			lines = [L(dv.length()), "vert %s · horiz %s" % [L(absf(dv.y)), L(Vector2(dv.x, dv.z).length())]]
			at = (pending[0] + p) / 2.0
		"circle":
			if pending.size() == 2:
				var circ = circle_from_3(pending[0], pending[1], p)
				if circ != null:
					lines = ["Ø " + L(2 * circ.r), "r " + L(circ.r)]
					at = circ.center
		"rect":
			if pending.size() == 1:
				lines = [L(pending[0].distance_to(p))]
				at = (pending[0] + p) / 2.0
			else:
				var r = rect_from_3(pending[0], pending[1], p)
				if r != null:
					draw = PackedVector3Array(r.corners + [r.corners[0]])
					lines = ["%s × %s" % [L(r.w), L(r.d)], "area " + AREA(r.w * r.d)]
					at = (r.corners[0] + r.corners[2]) / 2.0
		"height":
			draw = PackedVector3Array([p, floor_foot(p)])
			lines = ["H " + L(p.y)]
			at = (p + floor_foot(p)) / 2.0
		"angle":
			if pending.size() == 2:
				lines = ["%.1f°" % angle_deg(pending[0], pending[1], p)]
				at = pending[1]
			else:
				lines = [L(pending[0].distance_to(p))]
				at = (pending[0] + p) / 2.0
		"path":
			lines = ["total " + L(path_len(pts)), "this leg " + L(pending[-1].distance_to(p))]
		"area":
			if pts.size() >= 3:
				draw.append(pts[0])
				lines = ["area " + AREA(poly_area(pts)), "perim " + L(path_len(pts, true))]
			else:
				lines = [L(pending[0].distance_to(p))]
	preview.mesh = _lines_mesh(draw, true)
	preview.visible = true
	if lines.size():
		set_label(preview_label, lines)
		preview_label.position = at + Vector3(0, 0.05, 0)
		preview_label.visible = true
	else:
		preview_label.visible = false


# ================================================================ main loop
func _process(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	for c in ctrls:
		update_pointer(c, space)
		process_input(c, read_buttons(c))
		var dr = c.drag
		if dr != null:
			match dr.type:
				"move": update_move(c, dr)
				"free": update_free(c, dr)
				"handle": update_handle(c, dr)
	update_hovers()
	update_falling()
	update_preview()
	update_fit(delta)
	if menu.is_open:
		if menu_dirty:
			rebuild_menu()
		else:
			layout_menu()
	if ctx.is_open and ctx_attach != null:
		ctx.global_position = _hand_top(ctx_attach, ctx.size.y)
		ctx.face(camera.global_position)
	if save_dirty:
		save_timer -= delta
		if save_timer <= 0.0:
			save_room_now()


# ================================================================ fit check
## Wire / fill colours: red when it doesn't fit, white wire while selected.
func apply_shape_colors(s: Shape) -> void:
	var base: Color = C_RED if s.fit_hits.size() else s.color
	s.wire_mat.albedo_color = Color.WHITE if s == selected else base
	s.fill_mat.albedo_color = Color(base, (0.14 if s == selected else 0.06) + (0.08 if s.fit_hits.size() else 0.0))


func set_fit_check(on: bool) -> void:
	fit_check = on
	if not on:
		for s in shapes:
			if s.fit_hits.size():
				s.fit_hits = []
				refresh_shape(s)
				apply_shape_colors(s)
	fit_timer = 0.0
	save_settings()
	menu_dirty = true


## The shape's collider shrunk by FIT_MARGIN on every side, so flush contact and scan noise don't count.
func fit_query_shape(s: Shape) -> Shape3D:
	var m := FIT_MARGIN
	match s.type:
		"box":
			var b := BoxShape3D.new()
			b.size = (scale_of(s.type, s.dims) - Vector3.ONE * 2.0 * m).max(Vector3.ONE * 0.005)
			return b
		"sphere":
			var sp := SphereShape3D.new()
			sp.radius = maxf(0.005, s.dims.r - m)
			return sp
		"cylinder":
			var cy := CylinderShape3D.new()
			cy.radius = maxf(0.005, s.dims.r - m)
			cy.height = maxf(0.005, s.dims.h - 2.0 * m)
			return cy
	var r := maxf(0.005, s.dims.r - m)
	var h := maxf(0.005, s.dims.h - 2.0 * m)
	var pts := PackedVector3Array([Vector3(0, h / 2.0, 0)])
	for k in 16:
		var t := float(k) / 16 * TAU
		pts.append(Vector3(cos(t) * r, -h / 2.0, sin(t) * r))
	var cv := ConvexPolygonShape3D.new()
	cv.points = pts
	return cv


## Names of the walls, furniture and other shapes this shape overlaps by more than FIT_MARGIN.
func fit_hits_for(s: Shape, space: PhysicsDirectSpaceState3D) -> Array:
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = fit_query_shape(s)
	q.transform = s.col.global_transform
	q.collision_mask = LAYER_ROOM | LAYER_SHAPE
	var ex: Array[RID] = fit_ignore.duplicate()
	ex.append(s.body.get_rid())
	q.exclude = ex
	var out := []
	for r in space.intersect_shape(q, 16):
		var col: Object = r.collider
		var nm := ""
		if col == null:
			continue
		if col.has_meta("shape"):
			var o = col.get_meta("shape")
			if not shapes.has(o):
				continue
			nm = o.name
		else:
			var a = col.get_parent()
			nm = String(a.label_name) if a != null and "label_name" in a else "room"
		if nm != "" and not out.has(nm):
			out.append(nm)
	out.sort()
	return out


func update_fit(delta: float, force := false) -> void:
	if not fit_check:
		return
	fit_timer -= delta
	if fit_timer > 0.0 and not force:
		return
	fit_timer = FIT_EVERY
	var space := get_world_3d().direct_space_state
	for s in shapes:
		if not s.node.is_inside_tree():
			continue
		var hits := fit_hits_for(s, space)
		if hits != s.fit_hits:
			s.fit_hits = hits
			refresh_shape(s)
			apply_shape_colors(s)


# ================================================================ room info (Space Setup)
func _poly2_area(pts: PackedVector2Array) -> float:
	var a := 0.0
	for i in pts.size():
		var p := pts[i]
		var q := pts[(i + 1) % pts.size()]
		a += p.x * q.y - q.x * p.y
	return absf(a) / 2.0


## Size of the room from the Space Setup scan: floor, ceiling height, walls, doors, windows, furniture.
func room_summary() -> Dictionary:
	var fl = null
	var ce = null
	var walls := []
	var doors := 0
	var windows := 0
	var things := 0
	for n in surfaces:
		if not is_instance_valid(n):
			continue
		var lab := String(n.label_name)
		if lab == "floor":
			fl = n
		elif lab == "ceiling":
			ce = n
		elif lab.contains("wall"):
			walls.append(n.size_2d.x)
		elif lab.contains("door"):
			doors += 1
		elif lab.contains("window"):
			windows += 1
		elif not lab.contains("global mesh"):
			things += 1
	var out := {"scanned": surfaces.size() > 0, "walls": walls.size(), "doors": doors, "windows": windows, "furniture": things}
	var per := 0.0
	for w in walls:
		per += w
	out["perimeter_m"] = per
	if fl != null:
		out["floor_w_m"] = fl.size_2d.x
		out["floor_d_m"] = fl.size_2d.y
		out["floor_area_m2"] = _poly2_area(fl.boundary) if fl.boundary.size() >= 3 else fl.size_2d.x * fl.size_2d.y
		if ce != null:
			out["ceiling_m"] = ce.global_position.y - fl.global_position.y
			out["volume_m3"] = out.floor_area_m2 * out.ceiling_m
	return out


func room_info_lines() -> Array:
	var r := room_summary()
	if not r.scanned:
		return ["No Space Setup data yet.", "Press Scan room to map the walls, floor and furniture."]
	var out := []
	if r.has("floor_area_m2"):
		out.append("Floor %s × %s  ·  area %s" % [L(r.floor_w_m), L(r.floor_d_m), AREA(r.floor_area_m2)])
	else:
		out.append("No floor in the scan.")
	if r.has("ceiling_m"):
		out.append("Ceiling height %s  ·  room volume %s" % [L(r.ceiling_m), VOL(r.volume_m3)])
	out.append("%d walls, perimeter %s" % [r.walls, L(r.perimeter_m)])
	var pl := func(n: int, w: String) -> String: return "%d %s%s" % [n, w, "" if n == 1 else "s"]
	out.append("%s · %s · %s" % [pl.call(r.doors, "door"), pl.call(r.windows, "window"), pl.call(r.furniture, "furniture item")])
	return out


# ================================================================ accuracy test
func accuracy_items() -> Array:
	var cur: String = acc_ref.get("id", "") if mode == "acctest" else ""
	var out := [{"id": "back", "label": "< Back"}]
	for r in ACC_REFS:
		out.append({"id": "acc:" + r.id, "label": r.label, "sub": "%.1f mm" % r.mm, "active": cur == r.id, "color": C_YELLOW})
	out.append({"id": "acc:custom", "label": "Custom length", "sub": "%.0f mm (set below)" % acc_custom_mm, "active": cur == "custom", "color": C_YELLOW})
	out.append({"id": "accexport", "label": button_text("accexport"), "sub": "CSV to Download/Framespace", "enabled": acc_trials.size() > 0})
	for d in ["-100", "-10", "-1", "+1", "+10", "+100"]:
		out.append({"id": "accu:" + d, "label": "%s mm" % d, "sub": "custom length", "color": Color(0.6, 0.8, 1.0)})
	out.append({"id": "accclear", "label": button_text("accclear"), "color": Color("ff6b6b"), "enabled": acc_trials.size() > 0})
	return out


func start_accuracy(ref_id: String) -> void:
	if ref_id == "custom":
		acc_ref = {"id": "custom", "label": "Custom length", "mm": acc_custom_mm}
	else:
		for r in ACC_REFS:
			if r.id == ref_id:
				acc_ref = r.duplicate()
	if acc_ref.is_empty():
		return
	set_tool("acctest")


func _clear_acc_line() -> void:
	if acc_line != null and is_instance_valid(acc_line):
		acc_line.queue_free()
	acc_line = null


func record_trial(a: Vector3, b: Vector3) -> Dictionary:
	var true_mm: float = acc_ref.get("mm", 0.0)
	var meas := a.distance_to(b) * 1000.0
	var err := meas - true_mm
	var head := content.to_local(camera.global_position)
	var t := {
		"time": _now_iso(), "ref": String(acc_ref.get("label", "?")),
		"true_mm": snappedf(true_mm, 0.1), "measured_mm": snappedf(meas, 0.1), "error_mm": snappedf(err, 0.1),
		"error_pct": snappedf(100.0 * err / true_mm, 0.01) if true_mm > 0 else 0.0,
		"distance_m": snappedf(head.distance_to((a + b) / 2.0), 0.01),
	}
	acc_trials.append(t)
	save_accuracy()
	_clear_acc_line()
	acc_line = Node3D.new()
	acc_line.add_child(_dot(a))
	acc_line.add_child(_dot(b))
	var li := MeshInstance3D.new()
	li.material_override = mat_measure
	li.mesh = _lines_mesh(PackedVector3Array([a, b]))
	acc_line.add_child(li)
	var lbl := make_label(C_YELLOW if absf(err) <= 10.0 else C_RED)
	lbl.position = (a + b) / 2.0 + Vector3(0, 0.05, 0)
	set_label(lbl, ["%.1f mm  (%+.1f)" % [meas, err], "true %.1f mm · trial %d" % [true_mm, acc_trials.size()]])
	acc_line.add_child(lbl)
	content.add_child(acc_line)
	push_history(func():
		acc_trials.erase(t)
		save_accuracy()
		_clear_acc_line())
	set_status("%s: %.1f mm, true %.1f, error %+.1f mm. %s. Tap again for another trial." % [t.ref, meas, true_mm, err, accuracy_summary()])
	if last_ctrl:
		haptic(last_ctrl, 0.5, 0.04)
	menu_dirty = true
	return t


func accuracy_stats() -> Dictionary:
	var n := acc_trials.size()
	if n == 0:
		return {"n": 0}
	var sum := 0.0
	var sabs := 0.0
	var sq := 0.0
	var worst := 0.0
	var spct := 0.0
	var sdist := 0.0
	for t in acc_trials:
		var e: float = t.error_mm
		sum += e
		sabs += absf(e)
		sq += e * e
		worst = maxf(worst, absf(e))
		spct += absf(float(t.error_pct))
		sdist += float(t.distance_m)
	return {"n": n, "bias_mm": sum / n, "mean_abs_mm": sabs / n, "rms_mm": sqrt(sq / n), "worst_mm": worst,
		"mean_abs_pct": spct / n, "mean_distance_m": sdist / n}


func accuracy_summary() -> String:
	var st := accuracy_stats()
	if st.n == 0:
		return "No trials yet"
	return "%d trials · avg error ±%.1f mm (%.1f%%) · worst %.1f mm · bias %+.1f mm" % [st.n, st.mean_abs_mm, st.mean_abs_pct, st.worst_mm, st.bias_mm]


func accuracy_csv() -> String:
	var lines := ["time,reference,true_mm,measured_mm,error_mm,error_pct,distance_m"]
	for t in acc_trials:
		lines.append("%s,\"%s\",%.1f,%.1f,%.1f,%.2f,%.2f" % [t.time, String(t.ref).replace("\"", "\"\""), t.true_mm, t.measured_mm, t.error_mm, t.error_pct, t.distance_m])
	var st := accuracy_stats()
	if st.n > 0:
		lines.append("")
		lines.append("trials,mean_abs_error_mm,mean_abs_error_pct,rms_mm,worst_mm,bias_mm,mean_distance_m")
		lines.append("%d,%.1f,%.2f,%.1f,%.1f,%.1f,%.2f" % [st.n, st.mean_abs_mm, st.mean_abs_pct, st.rms_mm, st.worst_mm, st.bias_mm, st.mean_distance_m])
	return "\n".join(lines)


func export_accuracy() -> String:
	var dir := export_dir()
	var stamp := _now_iso().substr(0, 16).replace(":", "-").replace("T", "-")
	var path := dir.path_join("framespace-accuracy-%s.csv" % stamp)
	var csv := accuracy_csv()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		set_status("Export failed: can't write to %s" % dir)
		return ""
	f.store_string(csv)
	f.close()
	DisplayServer.clipboard_set(csv)
	set_status("Exported %d trials to %s (also copied)." % [acc_trials.size(), path])
	return path


func save_accuracy() -> void:
	var f := FileAccess.open("user://accuracy.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"custom_mm": acc_custom_mm, "trials": acc_trials}, "  "))


func load_accuracy() -> void:
	var f := FileAccess.open("user://accuracy.json", FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		acc_custom_mm = float(d.get("custom_mm", 1000.0))
		acc_trials = d.get("trials", []) if d.get("trials") is Array else []


# ================================================================ rooms
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
			fit_check = bool(d.get("fit_check", true))


func save_settings() -> void:
	var f := FileAccess.open("user://settings.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"current_room": room.get("id", ""), "fit_check": fit_check}))


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
	room = {"id": "room-%d-%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec() % 100000], "name": "Room %d" % n, "created": _now_iso()}
	# The room's origin is the spot you're standing on, facing the way you look. The grid lines up with it.
	content.transform = stand_frame()
	room_turn = 0.0
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
	room_turn = 0.0
	content.visible = true


## Turn the whole room (and its grid) around the spot you're standing on. Positive = left (counter-clockwise from above).
## Only moves where the room sits in the real world; the saved layout doesn't change.
func turn_room(deg: float) -> void:
	var head := camera.transform.origin
	var pivot := Vector3(head.x, content.transform.origin.y, head.z)
	var r := Transform3D(Basis(Vector3.UP, deg_to_rad(deg)), Vector3.ZERO)
	content.transform = Transform3D.IDENTITY.translated(pivot) * r * Transform3D.IDENTITY.translated(-pivot) * content.transform
	content.transform = content.transform.orthonormalized()
	room_turn += deg
	set_status("Room turned %d° %s (%+d° since placed)." % [absi(roundi(deg)), "left" if deg > 0 else "right", roundi(room_turn)])


func _on_recentered() -> void:
	# Let the new head pose arrive before reading it.
	await get_tree().create_timer(0.3).timeout
	place_here()
	set_status("Recentered: %s is placed where you stand, facing where you face." % room.get("name", "room"))


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
			"position": [p.x, p.y, p.z], "quaternion": [q.x, q.y, q.z, q.w], "outline": s.outline, "pinned": s.pinned, "orig_dims": s.orig_dims})
	var ms := []
	for m in measures:
		var pts := []
		for p in m.points:
			pts.append([p.x, p.y, p.z])
		var base := {"name": m.name, "type": m.type, "points": pts}
		match m.type:
			"line":
				var dv: Vector3 = m.points[1] - m.points[0]
				base.merge({"distance_m": dv.length(), "vertical_m": absf(dv.y), "horizontal_m": Vector2(dv.x, dv.z).length()})
			"circle":
				base.merge({"radius_m": m.r, "diameter_m": 2 * m.r, "circumference_m": TAU * m.r, "center": [m.center.x, m.center.y, m.center.z]})
			"rect":
				base.merge({"width_m": m.w, "depth_m": m.dp, "area_m2": m.w * m.dp, "perimeter_m": 2 * (m.w + m.dp)})
			"height":
				base.merge({"height_m": m.points[0].y})
			"angle":
				base.merge({"angle_deg": angle_deg(m.points[0], m.points[1], m.points[2])})
			"path":
				base.merge({"distance_m": path_len(m.points)})
			"area":
				base.merge({"area_m2": poly_area(m.points), "perimeter_m": path_len(m.points, true)})
		ms.append(base)
	var surf := []
	for n in surfaces:
		if is_instance_valid(n) and n.size_2d != Vector2.ZERO:
			surf.append({"label": n.label_name, "width_m": n.size_2d.x, "depth_m": n.size_2d.y, "area_m2": n.size_2d.x * n.size_2d.y})
	return {"app": "Framespace", "build": BUILD, "id": room.get("id", ""), "name": room.get("name", ""),
		"created": room.get("created", ""), "updated": _now_iso(),
		"units": units, "grid": grid, "counters": counters, "clipboard": _clip_data(),
		"shapes": ss, "measurements": ms, "room": surf}


func _clip_data() -> Array:
	var out := []
	for it in clipboard:
		var q: Quaternion = it.rot
		out.append({"type": it.type, "dims": it.dims, "name": it.name, "quaternion": [q.x, q.y, q.z, q.w], "outline": it.get("outline", {}), "orig": it.get("orig", {})})
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
	room = {"id": d.get("id", id), "name": d.get("name", id), "created": d.get("created", "")}
	units = d.get("units", units)
	grid = d.get("grid", grid)
	for s in d.get("shapes", []):
		var ns := make_shape(s.type, s.dims, _v3(s.position), _q(s.quaternion), s.name, s.get("outline"), s.get("orig_dims"))
		if s.get("pinned", false):
			set_pinned(ns, true)
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
		clipboard.append({"type": it.type, "dims": it.dims, "name": it.name, "rot": _q(it.quaternion), "outline": it.get("outline", {}), "orig": it.get("orig", {})})
	clip_index = 0
	content.transform = stand_frame()
	room_turn = 0.0
	content.visible = true
	save_settings()
	set_status("Loaded %s (%d shapes, %d measurements) where you stand. On your usual spot? Face your usual way and recenter." % [room.name, shapes.size(), measures.size()])


func delete_current_room() -> void:
	var id: String = room.get("id", "")
	if id == "":
		return
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
	var rows := [["kind", "name", "type", "length_m", "width_m", "height_m", "depth_m", "radius_m", "diameter_m", "volume_m3", "area_m2", "distance_m", "vertical_m", "horizontal_m", "circumference_m", "perimeter_m", "angle_deg"]]
	var f := func(v): return "" if v == null else "%.4f" % float(v)
	var mcols := ["width_m", "height_m", "depth_m", "radius_m", "diameter_m", "volume_m3", "area_m2", "distance_m", "vertical_m", "horizontal_m", "circumference_m", "perimeter_m", "angle_deg"]
	for m in data.measurements:
		var row := ["measurement", m.name, "tape" if m.type == "line" else m.type, ""]
		for k in mcols:
			row.append(f.call(m.get(k)))
		rows.append(row)
	for s in data.shapes:
		var d: Dictionary = s.dims
		if s.type == "box":
			rows.append(["shape", s.name, s.type, "", f.call(d.x), f.call(d.y), f.call(d.z), "", "", f.call(s.volume_m3), "", "", "", "", "", "", ""])
		elif s.type == "sphere":
			rows.append(["shape", s.name, s.type, "", "", "", "", f.call(d.r), f.call(2 * d.r), f.call(s.volume_m3), "", "", "", "", "", "", ""])
		else:
			rows.append(["shape", s.name, s.type, "", "", f.call(d.h), "", f.call(d.r), f.call(2 * d.r), f.call(s.volume_m3), "", "", "", "", "", "", ""])
	for p in data.room:
		rows.append(["room", p.label, "plane", f.call(p.width_m), f.call(p.depth_m), "", "", "", "", "", f.call(p.area_m2), "", "", "", "", "", ""])
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
	data["room_scan"] = room_summary()
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
		var raw := []
		for p in m.points:
			raw.append(_v3(p))
		var mp := measure_poly(m.type, raw)
		var pts := PackedVector3Array(mp.pts)
		if mp.closed or m.type == "circle":
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
