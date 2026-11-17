extends Node
## Headless self-test, run in CI with:  godot --headless --path native -- --selftest
## Drives the app's own functions (no headset) and exits with code 0 if every check passes.

var main
var passed := 0
var failed := 0


func check(name: String, ok: bool, info := "") -> void:
	if ok:
		passed += 1
	else:
		failed += 1
	print("%s  %s%s" % ["PASS" if ok else "FAIL", name, ("  -- " + info) if info != "" else ""])


func run(m) -> void:
	main = m
	await get_tree().process_frame
	await get_tree().process_frame

	# Fresh room on first start.
	check("A room exists on start", main.room.get("id", "") != "", str(main.room))

	# Shapes from the menu.
	# Spawn each where a (fake) controller points, 50 cm apart on the floor.
	var pc = main.ctrls[0]
	main.last_ctrl = pc
	var types := ["box", "sphere", "cylinder", "cone"]
	for i in types.size():
		pc.target = {"point": Vector3(i * 0.5, 0, -1.0), "normal": Vector3.UP, "dist": 1.0, "kind": "surface"}
		main.on_button(types[i])
	pc.target = null
	check("Menu adds 4 shapes", main.shapes.size() == 4, str(main.shapes.size()))
	var box = main.shapes[0]
	check("New box rests on the floor", absf(box.node.position.y - 0.15) < 0.002, str(box.node.position))
	check("New box sits on the 5 cm grid", is_equal_approx(box.node.position.x, 0.0) and is_equal_approx(box.node.position.z, -1.0), str(box.node.position))
	check("Label shows volume", main.shape_lines(box.type, box.name, box.dims)[2].begins_with("Vol 27.00 L"), main.shape_lines(box.type, box.name, box.dims)[2])

	# Containers in the palette.
	var labels := []
	for p in main.PALETTE:
		labels.append(p.label)
	check("Palette has 20ft / 40ft / 40ft HC containers", labels.has("20ft container") and labels.has("40ft container") and labels.has("40ft high cube"))
	var c20 = main.PALETTE[labels.find("20ft container")]
	check("20ft container interior volume ~33.2 m3", absf(main.volume_of("box", c20.dims) - 33.2) < 0.1, str(main.volume_of("box", c20.dims)))

	# Stick scale / rotate on a held shape (move drag, no headset: fake the drag dict).
	var c = main.ctrls[1]
	main.select(box)
	c.drag = {"type": "move", "shape": box, "c0": Vector3.ZERO, "yaw0": 0.0, "p0": box.node.position, "base_y": box.node.position.y}
	main.scale_held(c, 1.05)
	check("Stick up scales +5%", absf(box.dims.x - 0.315) < 0.0005, str(box.dims))
	check("Scaled box stays on the floor", absf(box.node.position.y - box.dims.y / 2.0) < 0.002, str(box.node.position))
	main.rotate_held(c, -PI / 4)
	check("Stick left rotates 45° clockwise", absf(main.yaw_of_quat(box.node.quaternion) + PI / 4) < 0.01, str(main.yaw_of_quat(box.node.quaternion)))
	c.drag = null

	# Clipboard.
	main.select(box)
	main.copy_selected(false)
	main.paste_at(Vector3(1.0, 0, 1.0))
	check("Copy + paste makes a 5th shape", main.shapes.size() == 5)
	main.select(main.shapes[4])
	main.on_button("delete")
	check("Delete removes it", main.shapes.size() == 4)
	main.undo()
	check("Undo restores it", main.shapes.size() == 5)

	# Stacking: drop a box on top of another.
	main.select(box)
	var top = main.make_shape("box", {"x": 0.1, "y": 0.1, "z": 0.1}, box.node.position + Vector3(0, 1.0, 0))
	main.settle(top)
	check("Dropped shape lands on the shape below", absf(top.node.position.y - (box.dims.y + 0.05)) < 0.003, str(top.node.position))

	# Tape + circle.
	main.on_button("tape")
	main.add_pending_point(Vector3(0, 0, 0))
	main.add_pending_point(Vector3(3, 4, 0))
	check("Tape measures 5 m", main.measures.size() == 1 and main.measure_lines(main.measures[0])[0].ends_with("5.000 m"), str(main.measure_lines(main.measures[0])))
	main.on_button("circle")
	main.add_pending_point(Vector3(1, 1, 0))
	main.add_pending_point(Vector3(-1, 1, 0))
	main.add_pending_point(Vector3(0, 1, 1))
	check("Circle 3-pt radius 1 m", main.measures.size() == 2 and absf(main.measures[1].r - 1.0) < 0.001)
	main.on_button("units")
	check("Units toggle to inches", main.L(1.0) == "3 ft 3.4 in", main.L(1.0))
	main.on_button("units")

	# Menu builds (main page + rooms page).
	main.open_menu(main.ctrls[0], true)
	check("Main menu opens with 24 buttons", main.menu.is_open and main.menu.items.size() == 24, str(main.menu.items.size()))
	main.on_button("rooms")
	main.rebuild_menu()
	check("Rooms page lists the current room", main.menu.item("room:" + main.room.id) != null)
	main.on_button("back")
	main.close_menu()

	# Save, new room, reload.
	var first_id: String = main.room.id
	var n_shapes: int = main.shapes.size()
	main.save_room_now()
	main.new_room()
	check("New room starts empty", main.shapes.size() == 0 and main.room.id != first_id)
	main.on_button("box")
	main.save_room_now()
	main.load_room(first_id)
	check("Loading the first room brings its shapes back", main.shapes.size() == n_shapes, "%d vs %d" % [main.shapes.size(), n_shapes])
	check("...and its measurements", main.measures.size() == 2)
	check("Rooms list has 2 rooms", main.list_rooms().size() == 2)

	# Export.
	var res: Dictionary = main.export_all()
	check("CSV export written", FileAccess.file_exists(res.base + ".csv"), res.base)
	check("JSON export written", FileAccess.file_exists(res.base + ".json"))
	check("GLB export written", res.glb and FileAccess.file_exists(res.base + ".glb"))
	var csv := FileAccess.get_file_as_string(res.base + ".csv")
	check("CSV has header + rows", csv.begins_with("kind,name,type") and csv.split("\n").size() >= 8, str(csv.split("\n").size()))

	# Delete room.
	main.delete_current_room()
	check("Delete room leaves 1 room", main.list_rooms().size() == 1)

	print("\n%d/%d checks passed" % [passed, passed + failed])
	get_tree().quit(0 if failed == 0 else 1)
