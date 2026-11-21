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
	check("Palette loaded from objects.csv (39 objects)", main.PALETTE.size() == 39, str(main.PALETTE.size()))
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
	check("Bigger 5% scales +5%", absf(box.dims.x - 0.315) < 0.0005, str(box.dims))
	check("Scaled box stays on the floor", absf(box.node.position.y - box.dims.y / 2.0) < 0.002, str(box.node.position))
	main.rotate_held(c, -PI / 4)
	check("Stick left rotates 45° clockwise", absf(main.yaw_of_quat(box.node.quaternion) + PI / 4) < 0.01, str(main.yaw_of_quat(box.node.quaternion)))
	main.scale_held(c, 1.0 / main.SCALE_STEP)
	check("Smaller 5% undoes it exactly (-5%)", absf(box.dims.x - 0.3) < 0.0005, str(box.dims))
	main.scale_held(c, main.SCALE_STEP)
	# Stick forward / back on a held shape: continuous push away / pull in along the floor.
	box.node.position = Vector3(0, box.node.position.y, -1.0)
	c.drag = {"type": "move", "shape": box, "c0": Vector3.ZERO, "yaw0": 0.0, "p0": box.node.position, "base_y": box.node.position.y}
	main.push_held(c, 0.5)
	check("Stick forward pushes a held shape away", absf(c.drag.p0.z + 1.5) < 0.001 and absf(c.drag.p0.y - box.node.position.y) < 0.001, str(c.drag.p0))
	main.push_held(c, -0.7)
	check("Stick back pulls it in", absf(c.drag.p0.z + 0.8) < 0.001, str(c.drag.p0))
	main.push_held(c, -5.0)
	check("Pulling stops just short of the controller", absf(c.drag.p0.z + main.PUSH_MIN) < 0.001, str(c.drag.p0))
	var dims_push: Dictionary = box.dims.duplicate()
	main.push_held(c, 1.0)
	check("Push/pull never changes size", box.dims == dims_push, str(box.dims))
	c.drag = {"type": "free", "shape": box, "off": Vector3(0, 0, -0.5), "rot": box.node.quaternion}
	main.push_held(c, 0.25)
	check("Stick forward pushes a carried shape away", absf(c.drag.off.z + 0.75) < 0.001, str(c.drag.off))
	c.drag = null

	# Grabbing never changes size or (in a free carry) rotation; only the stick does.
	var dims_before: Dictionary = box.dims.duplicate()
	c.shape_hit = {"shape": box, "point": box.node.position, "normal": Vector3.UP, "dist": 1.0}
	main.on_grip_down(c, {"grip": true})
	check("Grip alone grabs to move (not scale)", c.drag != null and c.drag.type == "move", str(c.drag.type if c.drag else null))
	c.node.position += Vector3(0, 0, -0.4)   # push the hand forward, like the old push-to-grow
	c.o += Vector3(0, 0, -0.4)
	main.update_move(c, c.drag)
	check("Pushing the hand while holding doesn't change size", box.dims == dims_before, str(box.dims))
	main.convert_to_free(c)
	var q_before: Quaternion = box.node.quaternion
	c.node.rotate_object_local(Vector3.FORWARD, 0.7)    # twist the wrist
	c.node.rotate_object_local(Vector3.RIGHT, 0.4)
	main.update_free(c, c.drag)
	check("Twisting the wrist while carrying doesn't rotate it", box.node.quaternion.is_equal_approx(q_before) and box.dims == dims_before, str(box.node.quaternion))
	c.node.transform = Transform3D.IDENTITY
	main.on_drag_release(c)
	box.node.position = Vector3(0, half_y(box), -1.0)
	box.node.quaternion = Quaternion.IDENTITY

	# Trigger alone on a shape: hold it like a brush, wrist twist turns it. Adding grip lifts it.
	main.on_trigger_down(c, {"trigger": true})
	check("Trigger alone on a shape picks it up in your hand", c.drag != null and c.drag.type == "wrist", str(c.drag.type if c.drag else null))
	c.node.rotate_y(0.5)
	main.update_wrist(c, c.drag)
	check("Wrist twist turns the held shape", absf(main.yaw_of_quat(box.node.quaternion)) > 0.3 and box.dims == dims_before, str(main.yaw_of_quat(box.node.quaternion)))
	main.on_drag_release(c)
	check("Release squares it to 45° steps", absf(fmod(absf(main.yaw_of_quat(box.node.quaternion)) + 0.0001, PI / 4)) < 0.01, str(main.yaw_of_quat(box.node.quaternion)))
	c.node.transform = Transform3D.IDENTITY
	main.on_trigger_down(c, {"trigger": true})
	main.on_grip_down(c, {"grip": true, "trigger": true})
	check("Trigger then grip lifts it", c.drag != null and c.drag.type == "free", str(c.drag.type if c.drag else null))
	main.on_drag_release(c)
	main.on_grip_down(c, {"grip": true})
	main.on_trigger_down(c, {"grip": true, "trigger": true})
	check("Grip then trigger lifts it", c.drag != null and c.drag.type == "free", str(c.drag.type if c.drag else null))
	main.on_drag_release(c)
	c.shape_hit = null
	box.node.position = Vector3(0, half_y(box), -1.0)
	box.node.quaternion = Quaternion(Vector3.UP, -PI / 4)

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

	# Pin: context menu Pin/Unpin; a pinned shape can't be grabbed, resized or dropped.
	var cp = main.ctrls[1]
	cp.o = Vector3(0, 1.2, 0)
	cp.d = (box.node.position - cp.o).normalized()
	cp.shape_hit = {"shape": box, "point": box.node.position, "normal": Vector3.UP, "dist": 1.0}
	main.open_context(cp)
	check("Hold-A menu on a shape offers Pin", main.ctx.is_open and main.ctx.item("pin") != null and main.ctx.item("pin").label == "Pin")
	var ctx_pos: Vector3 = main.ctx.global_position
	check("Context menu opens near the hand, not at the object", ctx_pos.distance_to(main.content.to_global(cp.o)) < 0.5, str(ctx_pos))
	check("...linked to the object by a dotted line", main.ctx_link.visible)
	main.run_context("pin")
	check("Pin pins it (no resize cubes)", box.pinned and box.handles.size() == 0)
	var pos_pinned: Vector3 = box.node.position
	main.on_grip_down(cp, {"grip": true})
	check("A pinned shape can't be grabbed", cp.drag == null and box.node.position == pos_pinned, main.status)
	main.on_trigger_down(cp, {"trigger": true, "grip": true})
	check("...not even with grip + trigger", cp.drag == null)
	check("Drop is disabled while pinned", not main.button_enabled("drop"))
	check("Pinned flag is saved", main.room_data().shapes[0].pinned == true)
	main.open_context(cp)
	check("Pinned shape offers Unpin", main.ctx.item("pin").label == "Unpin")
	main.run_context("pin")
	main.on_grip_down(cp, {"grip": true})
	check("Unpin makes it grabbable again", not box.pinned and cp.drag != null and cp.drag.type == "move")
	main.on_drag_release(cp)
	# Buttons: Y / B toggle the clipboard menu, X / A hold the objects palette.
	if main.ctx.is_open:
		main.ctx.close()
	cp.btn = {"high": false, "low": false}
	main.process_input(cp, {"high": true, "low": false, "trigger": false, "grip": false, "stick": false, "sx": 0.0, "sy": 0.0})
	check("B opens the clipboard menu", main.ctx.is_open)
	main.process_input(cp, {"high": false, "low": false, "trigger": false, "grip": false, "stick": false, "sx": 0.0, "sy": 0.0})
	main.process_input(cp, {"high": true, "low": false, "trigger": false, "grip": false, "stick": false, "sx": 0.0, "sy": 0.0})
	check("B again closes it", not main.ctx.is_open)
	main.process_input(cp, {"high": false, "low": true, "trigger": false, "grip": false, "stick": false, "sx": 0.0, "sy": 0.0})
	check("A (right hand) opens the objects palette", main.palette.is_open)
	main.process_input(cp, {"high": false, "low": false, "trigger": false, "grip": false, "stick": false, "sx": 0.0, "sy": 0.0})
	check("Letting go of A closes it", not main.palette.is_open)
	var cl = main.ctrls[0]
	cl.btn = {}
	main.process_input(cl, {"high": true, "low": false, "trigger": false, "grip": false, "stick": false, "sx": 0.0, "sy": 0.0})
	check("Y (left hand) opens the clipboard menu too", main.ctx.is_open)
	main.ctx.close()
	cl.btn = {}
	check("Context link hides when the menu closes", (func(): main._process(0.0); return not main.ctx_link.visible).call())

	# Resize cubes can never fire while grabbing (the accidental-scaling bug).
	main.select(box)
	var dims0: Dictionary = box.dims.duplicate()
	cp.handle_hit = box.handles[0]
	main.on_trigger_down(cp, {"trigger": true, "grip": true})
	check("Trigger on a resize cube while gripping doesn't start a resize", cp.drag == null or cp.drag.type != "handle")
	cp.drag = null
	main.on_trigger_down(cp, {"trigger": true})
	check("Trigger alone on a resize cube still resizes", cp.drag != null and cp.drag.type == "handle")
	main.on_grip_down(cp, {"grip": true, "trigger": true})
	check("Grip during a resize switches to moving, size unchanged", cp.drag != null and cp.drag.type == "move" and box.dims == dims0, str(box.dims))
	main.on_drag_release(cp)
	cp.handle_hit = null
	cp.shape_hit = null
	box.node.position = pos_pinned

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
	check("Main menu opens with 28 buttons", main.menu.is_open and main.menu.items.size() == 28, str(main.menu.items.size()))
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
	check("...and its measurements", main.measures.size() == 2)
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
