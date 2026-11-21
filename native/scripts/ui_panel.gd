extends Node3D
## A flat panel of tiles in 3D: a title, a few header lines and a grid of buttons.
## Used for the stick-click main menu, the hold-X / A objects palette and the Y / B clipboard menu.
## Each tile has a thin StaticBody3D on the UI collision layer, tagged with meta "item" = tile id,
## so a controller ray can find which tile it points at.

const LAYER_UI := 16

const C_BG := Color(0.047, 0.059, 0.078, 0.92)
const C_TILE := Color(0.137, 0.165, 0.204, 1.0)
const C_HOVER := Color(0.227, 0.267, 0.322, 1.0)
const C_ACTIVE := Color(0.0, 0.898, 1.0, 1.0)
const C_ACCENT := Color(0.0, 0.898, 1.0, 1.0)
const C_DIM := Color(0.36, 0.4, 0.45, 1.0)

var items: Array = []          # [{id, label, sub, color, enabled, active}]
var cols := 3
var tile_w := 0.085
var tile_h := 0.06
var hover := ""
var is_open := false
var target = null              # free slot for the owner (e.g. the shape a context menu is about)
var point := Vector3.ZERO      # free slot for the owner (e.g. where to paste)

var _tiles := {}               # id -> {mat, label, sub_label, item}
var _title: Label3D
var _header: Array = []


func _ready() -> void:
	visible = false


static func _mat(color: Color, priority: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true
	m.render_priority = priority
	m.albedo_color = color
	return m


static func make_text(size: int, color: Color, priority: int) -> Label3D:
	var l := Label3D.new()
	l.font_size = size
	l.pixel_size = 0.0004
	l.modulate = color
	l.outline_size = 0
	l.no_depth_test = true
	l.render_priority = priority
	l.double_sided = true
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


## Rebuild the panel. header_lines: [[text, Color], ...] shown under the title.
func build(title: String, header_lines: Array, new_items: Array, new_cols: int, new_tile_w: float = 0.085) -> void:
	for ch in get_children():
		ch.queue_free()
	_tiles.clear()
	_header.clear()
	items = new_items
	cols = new_cols
	tile_w = new_tile_w
	tile_h = tile_w * 0.62
	hover = ""
	var rows := int(ceil(float(items.size()) / cols))
	var line_h := 0.022
	var head_h := 0.035 + header_lines.size() * line_h
	var w := cols * tile_w + 0.01
	var h := head_h + rows * tile_h + 0.01

	var bg := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	bg.mesh = q
	bg.material_override = _mat(C_BG, 10)
	add_child(bg)

	_title = make_text(40, C_ACCENT, 13)
	_title.text = title
	_title.position = Vector3(0, h / 2 - 0.02, 0.001)
	_title.width = (w - 0.02) / _title.pixel_size
	_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	add_child(_title)
	for i in header_lines.size():
		var hl := make_text(26, header_lines[i][1], 13)
		hl.text = header_lines[i][0]
		hl.position = Vector3(0, h / 2 - 0.035 - (i + 0.5) * line_h, 0.001)
		add_child(hl)
		_header.append(hl)

	for i in items.size():
		var it: Dictionary = items[i]
		var cx := -w / 2 + 0.005 + (i % cols + 0.5) * tile_w
		var cy := h / 2 - head_h - (i / cols + 0.5) * tile_h
		var tile := Node3D.new()
		tile.position = Vector3(cx, cy, 0.0005)
		add_child(tile)
		var mi := MeshInstance3D.new()
		var tq := QuadMesh.new()
		tq.size = Vector2(tile_w - 0.006, tile_h - 0.006)
		mi.mesh = tq
		var m := _mat(C_TILE, 11)
		mi.material_override = m
		tile.add_child(mi)
		var lab := make_text(30, Color.WHITE, 12)
		lab.text = it.get("label", "")
		lab.position = Vector3(0, 0.008 if it.get("sub", "") != "" else 0.0, 0.001)
		tile.add_child(lab)
		var sub: Label3D = null
		if it.get("sub", "") != "":
			sub = make_text(22, Color(0.6, 0.65, 0.7), 12)
			sub.text = it.sub
			sub.position = Vector3(0, -0.011, 0.001)
			tile.add_child(sub)
		_fit(lab, tile_w - 0.012)
		if sub:
			_fit(sub, tile_w - 0.01)
		var body := StaticBody3D.new()
		body.collision_layer = LAYER_UI
		body.collision_mask = 0
		body.set_meta("item", String(it.id))
		body.set_meta("panel", self)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(tile_w, tile_h, 0.004)
		cs.shape = bs
		body.add_child(cs)
		tile.add_child(body)
		_tiles[String(it.id)] = {"mat": m, "label": lab, "item": it}
		_paint(String(it.id))


## Shrink a label's font until its text fits the given width (rough estimate: 0.55 em per char).
func _fit(l: Label3D, max_w: float) -> void:
	var size := l.font_size
	while size > 12 and l.text.length() * size * 0.55 * l.pixel_size > max_w:
		size -= 2
	l.font_size = size


func set_header(i: int, text: String) -> void:
	if i < _header.size():
		_header[i].text = text


func _paint(id: String) -> void:
	var t = _tiles.get(id)
	if t == null:
		return
	var it: Dictionary = t.item
	var en: bool = it.get("enabled", true)
	var act: bool = it.get("active", false)
	t.mat.albedo_color = C_ACTIVE if act else (C_HOVER if hover == id and en else C_TILE)
	var col: Color = it.get("color", Color.WHITE)
	t.label.modulate = Color(0.0, 0.06, 0.08) if act else (col if en else C_DIM)


func set_hover(id: String) -> void:
	if id == hover:
		return
	var old := hover
	hover = id
	_paint(old)
	_paint(id)


func item(id: String):
	var t = _tiles.get(id)
	return t.item if t else null


func open_at(pos: Vector3, face_toward: Vector3) -> void:
	global_position = pos
	face(face_toward)
	visible = true
	is_open = true


## Turn so the panel's front (+Z) faces the given world point, staying upright.
func face(world_point: Vector3) -> void:
	var away := global_position * 2.0 - world_point
	if global_position.distance_to(world_point) > 0.001:
		look_at(away, Vector3.UP)


func close() -> void:
	visible = false
	is_open = false
	hover = ""
	target = null
