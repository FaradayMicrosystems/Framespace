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


func half_y(s) -> float:
	return main.half_height(s)


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
	check("Palette loaded from objects.csv (54 objects incl. 15 building blocks)", main.PALETTE.size() == 54 and labels.has("Brick 2x1") and labels.has("Slab 100"), str(main.PALETTE.size()))
	var pallet = main.PALETTE[labels.find("AU pallet")] if labels.has("AU pallet") else null
	var van = main.PALETTE[labels.find("Farizon V7E open cargo")] if labels.has("Farizon V7E open cargo") else null
	check("V7E open cargo: whole van with load box and wheels", van != null and van.has("outline") and van.outline.inner.size() == 1 and van.outline.wheels.size() == 2, str(van))
	if van != null:
		var vs = main.make_shape(van.type, van.dims, Vector3(3, 0, 3), Quaternion.IDENTITY, "Van test", van.outline)
		check("V7E spawns with its van wireframe", vs.wire.mesh != main.unit_wire["box"] and vs.wire.mesh.get_surface_count() == 1)
		main.remove_shape(vs)
		vs.node.queue_free()
	check("AU pallet is 1165 x 1165 mm", pallet != null and is_equal_approx(pallet.dims.x, 1.165) and is_equal_approx(pallet.dims.z, 1.165), str(pallet))

	# Stick scale / rotate on a held shape (move drag, no headset: fake the drag dict).
	var c = main.ctrls[1]
	main.select(box)
	c.drag = {"type": "move", "shape": box, "c0": Vector3.ZERO, "yaw0": 0.0, "p0": box.node.position, "base_y": box.node.position.y}
	main.scale_held(c, main.SCALE_STEP)
	check("Stick up scales +5%", absf(box.dims.x - 0.315) < 0.0005, str(box.dims))
	check("Scaled box stays on the floor", absf(box.node.position.y - box.dims.y / 2.0) < 0.002, str(box.node.position))
	main.rotate_held(c, -PI / 4)
	check("Stick left rotates 45° clockwise", absf(main.yaw_of_quat(box.node.quaternion) + PI / 4) < 0.01, str(main.yaw_of_quat(box.node.quaternion)))
	main.scale_held(c, 1.0 / main.SCALE_STEP)
	check("Stick down undoes it exactly (-5%)", absf(box.dims.x - 0.3) < 0.0005, str(box.dims))
	main.scale_held(c, main.SCALE_STEP)
	c.drag = null

	# Grip slides on the grid (never resizes); trigger picks it up, wrist twist turns it, surfaces snap.
	var dims_before: Dictionary = box.dims.duplicate()
	c.shape_hit = {"shape": box, "point": box.node.position, "normal": Vector3.UP, "dist": 1.0}
	main.on_grip_down(c, {"grip": true})
	check("Grip alone grabs to slide (not scale)", c.drag != null and c.drag.type == "move" and c.drag.release == "grip", str(c.drag))
	c.o += Vector3(0, 0, -0.4)
	main.update_move(c, c.drag)
	check("Sliding doesn't change size or height", box.dims == dims_before and absf(box.node.position.y - box.dims.y / 2.0) < 0.002, str(box.dims))
	main.on_drag_release(c)
	box.node.position = Vector3(0, half_y(box), -1.0)
	box.node.quaternion = Quaternion.IDENTITY
	main.refresh_shape(box)

	# Trigger carry: aim from above, so the ray points down at the box.
	c.node.transform = Transform3D(Basis(Vector3.RIGHT, -PI / 2), Vector3(0, 1.5, -1.0))
	c.o = Vector3(0, 1.5, -1.0)
	c.d = Vector3.DOWN
	c.shape_hit = {"shape": box, "point": Vector3(0, box.dims.y, -1.0), "normal": Vector3.UP, "dist": 1.0}
	var hist0: int = main.history.size()
	main.on_trigger_down(c, {"trigger": true})
	check("Trigger on an object picks it up", c.drag != null and c.drag.type == "free" and c.drag.release == "trigger")
	main.on_drag_release(c)
	check("A quick trigger tap only selects (no move, no undo step)", box.node.position.is_equal_approx(Vector3(0, half_y(box), -1.0)) and main.history.size() == hist0 and main.selected == box)
	main.on_trigger_down(c, {"trigger": true})
	c.drag.t0 -= 1.0
	c.o = Vector3(-0.52, 1.8, -1.0)         # lift the hand 30 cm and move it 52 cm left (clear floor)
	main.update_free(c, c.drag)
	check("Lifted clear of the floor: carried freely, not snapped", not c.drag.snapped and box.node.position.y > 0.3, str(box.node.position))
	c.node.rotate_object_local(Vector3.BACK, deg_to_rad(40))   # twist the wrist 40°
	main.update_free(c, c.drag)
	check("Twisting the wrist turns it (free: follows the hand)", absf(rad_to_deg(main.yaw_of_quat(box.node.quaternion)) - 40.0) < 1.0, str(rad_to_deg(main.yaw_of_quat(box.node.quaternion))))
	check("Carrying keeps it upright and the same size", absf(box.node.quaternion.get_euler().x) < 0.001 and box.dims == dims_before)
	c.o = Vector3(-0.52, 1.51, -1.0)        # lower it to the floor
	main.update_free(c, c.drag)
	check("Touching the floor snaps it to the grid on top of it", c.drag.snapped and absf(box.node.position.y - half_y(box)) < 0.002 and is_equal_approx(box.node.position.x, -0.5), str(box.node.position))
	check("...and squares the turn to 15° steps", absf(rad_to_deg(main.yaw_of_quat(box.node.quaternion)) - 45.0) < 0.01, str(rad_to_deg(main.yaw_of_quat(box.node.quaternion))))
	main.on_drag_release(c)
	check("Releasing keeps it where it snapped", box.node.position.is_equal_approx(Vector3(-0.5, half_y(box), -1.0)))
	main.undo()
	check("Undo puts a carried object back", box.node.position.is_equal_approx(Vector3(0, half_y(box), -1.0)), str(box.node.position))
	c.node.transform = Transform3D.IDENTITY
	c.shape_hit = null
	box.node.quaternion = Quaternion(Vector3.UP, -PI / 4)

	# Reset size.
	main.select(box)
	c.drag = {"type": "move", "shape": box, "c0": Vector3.ZERO, "yaw0": 0.0, "p0": box.node.position, "base_y": box.node.position.y}
	main.scale_held(c, main.SCALE_STEP)
	main.scale_held(c, main.SCALE_STEP)
	c.drag = null
	main.set_tool("reset")
	main.apply_tool(c, box)
	check("Reset size puts it back to its original size, still on the floor", box.dims == box.orig_dims and absf(box.dims.x - 0.3) < 0.0005 and absf(box.node.position.y - 0.15) < 0.002, str(box.dims))
	main.set_tool("select")

	# Stick while holding: right = turn clockwise smoothly, forward = push away.
	c.drag = null
	c.node.transform = Transform3D.IDENTITY
	c.o = Vector3(0, 1.2, 0)
	c.d = (Vector3(0, 0.6, -1.0) - c.o).normalized()
	var yaw_s: float = main.yaw_of_quat(box.node.quaternion)
	main.start_free(c, box, true, box.node.position)
	var d0: float = c.drag.dist
	main.stick_held(c, 1.0, 0.0, 0.25)
	check("Stick right while holding turns it clockwise, smoothly (30° in ¼ s)", absf(c.drag.yaw0 - (yaw_s - deg_to_rad(30))) < 0.001, str(rad_to_deg(c.drag.yaw0 - yaw_s)))
	main.stick_held(c, 0.0, 1.0, 0.2)
	check("Stick forward pushes it away (30 cm in 0.2 s)", absf(c.drag.dist - (d0 + 0.3)) < 0.001, str(c.drag.dist - d0))
	main.stick_held(c, 0.0, -0.3, 0.5)
	check("Light pull back is slow, for fine control", c.drag.dist < d0 + 0.3 and c.drag.dist > d0 + 0.28, str(c.drag.dist - d0))
	main.on_drag_release(c)
	main.undo()
	box.node.quaternion = Quaternion(Vector3.UP, -PI / 4)

	# Clipboard.
	main.select(box)
	main.copy_selected(false)
	main.paste_at(Vector3(1.0, 0, 1.0))
	check("Copy + paste makes a 5th shape", main.shapes.size() == 5)
	main.set_tool("delete")
	main.apply_tool(c, main.shapes[4])
	check("Delete tool removes it", main.shapes.size() == 4)
	var cu = main.ctrls[0]
	cu.drag = null
	main.process_input(cu, {"high": true})
	cu.high_at -= 1.0
	main.process_input(cu, {"high": true})
	main.process_input(cu, {})
	cu.btn = {}
	check("Hold Y undoes (restores it)", main.shapes.size() == 5)
	main.process_input(cu, {"high": false})
	check("...and a hold doesn't open the menu", not main.menu.is_open)
	main.process_input(cu, {"high": true})
	main.process_input(cu, {"high": false})
	check("Tap Y opens the main menu stuck to the left hand", main.menu.is_open and main.menu_attach == cu)
	check("...just above the hand", main.menu.global_position.distance_to(cu.node.global_position) < 0.4, str(main.menu.global_position))
	cu.node.position += Vector3(0.3, 0.1, -0.2)
	main._process(0.0)
	check("...and follows the hand", main.menu.global_position.distance_to(cu.node.global_position) < 0.4)
	cu.node.position = Vector3.ZERO
	main.process_input(cu, {"high": true})
	main.process_input(cu, {"high": false})
	check("Tap Y again closes it", not main.menu.is_open)
	cu.btn = {}

	# X / A tool menu: cut -> paste via trigger.
	var ct = main.ctrls[1]
	main.open_tools(ct)
	check("X / A opens the tool menu with 11 tools", main.ctx.is_open and main.ctx.items.size() == 11, str(main.ctx.items.size()))
	check("...stuck to that hand", main.ctx_attach == ct and main.ctx.global_position.distance_to(ct.node.global_position) < 0.4)
	check("...first tool is Rotate/Move", main.ctx.items[0].label == "Rotate/Move")
	main.run_tool("cut")
	check("Picking Cut sets the tool and closes the menu", main.mode == "cut" and not main.ctx.is_open)
	var victim = main.shapes[4]
	ct.ui = null
	ct.shape_hit = {"shape": victim, "point": victim.node.position, "normal": Vector3.UP, "dist": 1.0}
	main.on_trigger_down(ct, {"trigger": true})
	check("Trigger in Cut mode cuts the object, then switches to Paste", main.shapes.size() == 4 and main.mode == "paste" and main.clipboard[0].name == victim.name)
	ct.shape_hit = null
	ct.target = {"point": Vector3(2, 0, 2), "normal": Vector3.UP, "dist": 1.0, "kind": "surface"}
	main.on_trigger_down(ct, {"trigger": true})
	check("Trigger in Paste mode pastes where you point", main.shapes.size() == 5 and Vector2(main.shapes[4].node.position.x, main.shapes[4].node.position.z).is_equal_approx(Vector2(2, 2)))
	ct.target = null
	main.set_tool("duplicate")
	main.apply_tool(ct, main.shapes[4])
	check("Duplicate tool makes a copy", main.shapes.size() == 6)
	main.undo()
	main.set_tool("select")

	# Pin tool; a pinned shape can't be grabbed, resized or dropped.
	var cp = main.ctrls[1]
	cp.o = Vector3(0, 1.2, 0)
	cp.d = (box.node.position - cp.o).normalized()
	main.open_tools(cp)
	check("Tool menu offers Pin", main.ctx.item("pin") != null)
	main.run_tool("pin")
	main.apply_tool(cp, box)
	main.set_tool("select")
	main.select(box)
	check("Pin pins it (no resize cubes)", box.pinned and box.handles.size() == 0)
	var pos_pinned: Vector3 = box.node.position
	cp.shape_hit = {"shape": box, "point": box.node.position, "normal": Vector3.UP, "dist": 1.0}
	main.on_grip_down(cp, {"grip": true})
	check("A pinned shape can't be slid", cp.drag == null and box.node.position == pos_pinned, main.status)
	main.on_trigger_down(cp, {"trigger": true})
	check("...or picked up", cp.drag == null)
	check("Pinned flag is saved", main.room_data().shapes[0].pinned == true)
	main.set_tool("pin")
	main.apply_tool(cp, box)
	main.set_tool("select")
	main.on_grip_down(cp, {"grip": true})
	check("Unpin makes it grabbable again", not box.pinned and cp.drag != null and cp.drag.type == "move")
	main.on_drag_release(cp)

	# Resize cubes live in the Scale tool only, and never fire while grabbing (the accidental-scaling bug).
	main.select(box)
	check("Rotate/Move shows no resize cubes (scaling lives in the Scale tool)", box.handles.size() == 0)
	main.set_tool("scale")
	main.select(box)
	check("Scale tool shows the resize cubes", box.handles.size() > 0)
	var dims0: Dictionary = box.dims.duplicate()
	cp.handle_hit = box.handles[0]
	main.on_trigger_down(cp, {"trigger": true, "grip": true})
	check("Trigger on a resize cube while gripping doesn't start a resize", cp.drag == null or cp.drag.type != "handle")
	cp.drag = null
	main.on_trigger_down(cp, {"trigger": true})
	check("Trigger alone on a resize cube resizes (Scale tool)", cp.drag != null and cp.drag.type == "handle")
	main.on_grip_down(cp, {"grip": true, "trigger": true})
	check("Grip during a resize switches to sliding, size unchanged", cp.drag != null and cp.drag.type == "move" and box.dims == dims0, str(box.dims))
	main.on_drag_release(cp)
	cp.handle_hit = null
	cp.shape_hit = null
	box.node.position = pos_pinned
	main.set_tool("select")

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
	main.on_button("rect")
	for q in [Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(1.5, 0, 1)]:
		main.add_pending_point(q)
	check("Rect 3-pt: 2 m × 1 m = 2 m²", main.measures.size() == 3 and absf(main.measures[2].w - 2.0) < 0.001 and absf(main.measures[2].dp - 1.0) < 0.001, str(main.measure_lines(main.measures[-1])))
	main.on_button("height")
	main.add_pending_point(Vector3(0.3, 1.5, 0.2))
	check("Height: 1.5 m above the floor", main.measures.size() == 4 and main.measure_lines(main.measures[3])[0].ends_with("1.500 m"), str(main.measure_lines(main.measures[-1])))
	main.on_button("angle")
	for q in [Vector3(1, 0, 0), Vector3(0, 0, 0), Vector3(0, 0, 1)]:
		main.add_pending_point(q)
	check("Angle 3-pt: 90°", main.measures.size() == 5 and main.measure_lines(main.measures[4])[0].ends_with("90.0°"), str(main.measure_lines(main.measures[-1])))
	main.on_button("path")
	for q in [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1)]:
		main.add_pending_point(q)
	check("Path keeps going until you tap the last point again", main.measures.size() == 5 and main.pending.size() == 3)
	main.add_pending_point(Vector3(1, 0, 1))
	check("Path: 2 m over 2 segments", main.measures.size() == 6 and absf(main.path_len(main.measures[5].points) - 2.0) < 0.001)
	main.on_button("area")
	for q in [Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(2, 0, 1.5), Vector3(0, 0, 1.5)]:
		main.add_pending_point(q)
	main.add_pending_point(Vector3(0.005, 0, 0))     # tap the first point again
	check("Area: closing the outline gives 3 m²", main.measures.size() == 7 and absf(main.poly_area(main.measures[6].points) - 3.0) < 0.001, str(main.measures.size()))
	main.set_tool("select")
	main.on_button("units")
	check("Units toggle to inches", main.L(1.0) == "3 ft 3.4 in", main.L(1.0))
	main.on_button("units")

	# Menu builds (main page + rooms page).
	main.open_menu(main.ctrls[0], true)
	check("Y/B menu: 4×8 sidebar of tools", main.menu.is_open and main.menu.items.size() == 32, str(main.menu.items.size()))
	check("...with the object tray beside it in Rotate/Move", main.tray.is_open and main.tray.items.size() == main.PALETTE.size())
	check("...tray to the right of the sidebar, not overlapping", main.menu.to_local(main.tray.global_position).x > (main.menu.size.x + main.tray.size.x) / 2.0)
	main.on_button("tape")
	main.rebuild_menu()
	check("Tray hides in other tools", not main.tray.is_open)
	main.on_button("select")
	main.rebuild_menu()
	var n0: int = main.shapes.size()
	var cg = main.ctrls[1]
	cg.ui = {"panel": main.tray, "id": "obj:0", "dist": 0.5, "point": main.tray.global_position}
	main.on_trigger_down(cg, {"trigger": true})
	check("Trigger on a tray object puts it in your hand and closes the menu", main.shapes.size() == n0 + 1 and cg.drag != null and cg.drag.type == "free" and not main.menu.is_open)
	cg.ui = null
	main.on_drag_release(cg)
	main.undo()
	main.open_menu(main.ctrls[0], true)
	main.on_button("rooms")
	main.rebuild_menu()
	check("Rooms page lists the current room", main.menu.item("room:" + main.room.id) != null)
	main.on_button("back")
	main.close_menu()

	# Save, new room, reload.
	var first_id: String = main.room.id
	var n_shapes: int = main.shapes.size()
	main.set_pinned(box, true)
	main.save_room_now()
	main.new_room()
	check("New room starts empty", main.shapes.size() == 0 and main.room.id != first_id)
	main.on_button("box")
	main.save_room_now()
	main.load_room(first_id)
	check("Loading the first room brings its shapes back", main.shapes.size() == n_shapes, "%d vs %d" % [main.shapes.size(), n_shapes])
	check("...and its measurements (all 7 kinds)", main.measures.size() == 7, str(main.measures.size()))
	check("...and pinned shapes stay pinned", main.shapes[0].pinned)
	check("Rooms list has 2 rooms", main.list_rooms().size() == 2)

	# Placement: rooms drop where you stand, facing the way you look; recentering re-places them.
	var cam0: Transform3D = main.camera.transform
	main.camera.transform = Transform3D(Basis(Vector3.UP, PI / 2), Vector3(2, 1.6, -1))
	var sf: Transform3D = main.stand_frame()
	check("Stand frame is on the floor under your head", sf.origin.is_equal_approx(Vector3(2, 0, -1)), str(sf.origin))
	check("Stand frame faces the way you look", absf(main.yaw_of_quat(sf.basis.get_rotation_quaternion()) - PI / 2) < 0.001)
	main.camera.transform = Transform3D(Basis(Vector3.UP, PI / 2) * Basis(Vector3.RIGHT, -PI / 2 + 0.01), Vector3(2, 1.6, -1))
	check("Looking straight down still keeps your heading", absf(main.yaw_of_quat(main.stand_frame().basis.get_rotation_quaternion()) - PI / 2) < 0.01)
	main.camera.transform = Transform3D(Basis(Vector3.UP, PI / 2), Vector3(2, 1.6, -1))
	var s0 = main.shapes[0]
	var local0: Vector3 = s0.node.position
	main.place_here()
	check("Place here moves the room to where you stand", s0.node.global_position.is_equal_approx(sf * local0), "%s vs %s" % [s0.node.global_position, sf * local0])
	check("...without changing its saved layout", s0.node.position.is_equal_approx(local0))
	main.camera.transform = Transform3D(Basis(Vector3.UP, -PI / 2), Vector3(-3, 1.6, 4))
	main.save_room_now()
	main.load_room(main.room.id)
	check("Loading a room drops it where you stand", main.content.transform.origin.is_equal_approx(Vector3(-3, 0, 4)) and absf(main.yaw_of_quat(main.content.quaternion) + PI / 2) < 0.001, str(main.content.transform))
	main.camera.transform = cam0
	main.place_here()
	check("Back at the spot you started, facing the same way, it lines up exactly", main.shapes[0].node.global_position.is_equal_approx(local0), str(main.shapes[0].node.global_position))
	# Turn room: fine heading fix after a recenter, around where you stand.
	main.camera.transform = Transform3D(Basis.IDENTITY, Vector3(1, 1.6, 0))
	var before: Vector3 = main.shapes[0].node.global_position
	main.on_button("turnl5")
	main.on_button("turnr1")
	check("Turn room 5° left then 1° right = 4° left", absf(main.yaw_of_quat(main.content.quaternion) - deg_to_rad(4)) < 0.0001, str(rad_to_deg(main.yaw_of_quat(main.content.quaternion))))
	var pivot := Vector3(1, 0, 0)
	var expect: Vector3 = pivot + (before - pivot).rotated(Vector3.UP, deg_to_rad(4))
	check("...turned around where you stand", main.shapes[0].node.global_position.is_equal_approx(expect), "%s vs %s" % [main.shapes[0].node.global_position, expect])
	check("...without changing the saved layout", main.shapes[0].node.position.is_equal_approx(local0))
	main.camera.transform = cam0
	main.place_here()
	main.open_menu(main.ctrls[0], true)
	main.on_button("rooms")
	main.rebuild_menu()
	check("Rooms page has Place room here", main.menu.item("placehere") != null)
	main.on_button("back")
	main.close_menu()

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
