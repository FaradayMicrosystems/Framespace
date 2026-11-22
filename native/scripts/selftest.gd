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
	check("Palette has walk-in 20ft / 40ft containers (no high cube)", labels.has("20ft container") and labels.has("40ft container") and not labels.has("40ft high cube"))
	check("Basic shapes and unused objects are gone", not (labels.has("Cube") or labels.has("Sphere") or labels.has("Rack bay") or labels.has("Brick") or labels.has("Door")))
	check("Motorcycle is in the palette", labels.has("Motorcycle"))
	var c20 = main.PALETTE[labels.find("20ft container")]
	check("20ft container is 6058 x 2438 x 2591 mm outside", is_equal_approx(c20.dims.x, 6.058) and is_equal_approx(c20.dims.y, 2.591), str(c20.dims))
	check("Palette loaded from objects.csv (51 objects)", main.PALETTE.size() == 51, str(main.PALETTE.size()))
	check("AU pallet loaded, Person, Wheelchair turn, Office desk and Car (sedan) are gone", not (labels.has("AU pallet loaded") or labels.has("Person 1.75 m") or labels.has("Wheelchair turn") or labels.has("Office desk") or labels.has("Car (sedan)")))
	var ibc = main.PALETTE[labels.find("IBC 1000 L")] if labels.has("IBC 1000 L") else null
	check("IBC 1000 L is a real wireframe (cage, tank, base), not a plain box", ibc != null and ibc.outline.parts.size() > 60)
	var drm = main.PALETTE[labels.find("Drum 205 L")] if labels.has("Drum 205 L") else null
	check("205 L drum is 584 x 880 with rims and rolling hoops", drm != null and is_equal_approx(drm.dims.x, 0.584) and is_equal_approx(drm.dims.y, 0.88) and drm.outline.parts.size() > 100)
	for nm in ["Kitchen sink bench 900", "Kitchen oven bench 600", "Dishwasher 600", "Kitchen corner 900", "Pantry 600", "Wall cabinet 600", "Island bench 1800", "Bar stool"]:
		check("Kitchen: " + nm, labels.has(nm))
	var wc = main.PALETTE[labels.find("Wall cabinet 600")] if labels.has("Wall cabinet 600") else null
	check("Wall cabinet hangs at 1450 mm and is hollow below (slides over a bench)", wc != null and wc.outline.solids.size() == 1)
	for nm in ["Carton large", "Carton small", "10ft container", "Tandem box trailer", "Pantech truck 4.5 t", "King bed", "Single bed", "Wardrobe 2-door", "Kitchen bench 600", "Dryer",
			"Shelf 5 cm", "Shelf 30 cm", "Shelf spacer 50 cm", "Rack 18RU 1200D", "Rack 24RU 1200D", "Rack 42RU 1200D", "Rack 48RU 1200D"]:
		if not labels.has(nm):
			check("New object " + nm, false)
	var rk = main.PALETTE[labels.find("Rack 42RU 1200D")]
	check("42RU rack: 600 x 1200 x 2067 mm with a detailed wireframe", is_equal_approx(rk.dims.x, 1.2) and is_equal_approx(rk.dims.z, 0.6) and is_equal_approx(rk.dims.y, 2.067) and rk.outline.parts.size() > 80)
	# Stacking: dryer on the washer; shelves stack board-gap by board-gap; spacer panel holds things.
	var wsh = main.PALETTE[labels.find("Washing machine")]
	var dry = main.PALETTE[labels.find("Dryer")]
	var ws = main.make_shape(wsh.type, wsh.dims, Vector3(20, wsh.dims.y / 2.0, 20), Quaternion.IDENTITY, "W", wsh.get("outline"))
	var ds = main.make_shape(dry.type, dry.dims, Vector3(20, 3.0, 20), Quaternion.IDENTITY, "D", dry.get("outline"))
	main.settle(ds)
	check("Dryer dropped on the washer stacks on top (bottom at 850 mm)", absf(ds.node.position.y - dry.dims.y / 2.0 - 0.85) < 0.003, str(ds.node.position))
	var sh30 = main.PALETTE[labels.find("Shelf 30 cm")]
	var sh20 = main.PALETTE[labels.find("Shelf 20 cm")]
	var spc = main.PALETTE[labels.find("Shelf spacer 50 cm")]
	var a1 = main.make_shape("box", spc.dims, Vector3(22, spc.dims.y / 2.0, 22), Quaternion.IDENTITY, "Sp", spc.outline)
	# (Created off to the side, then moved over: a new physics body only moves on the next physics frame.)
	var a2 = main.make_shape("box", sh30.dims, Vector3(26, 3.0, 26), Quaternion.IDENTITY, "S30", sh30.outline)
	a2.node.position = Vector3(22, 3.0, 22)
	main.settle(a2)
	var a3 = main.make_shape("box", sh20.dims, Vector3(27, 4.0, 27), Quaternion.IDENTITY, "S20", sh20.outline)
	a3.node.position = Vector3(22, 4.0, 22)
	main.settle(a3)
	check("Spacer 50 + shelf 30 + shelf 20 stack: top board at 1.0 m", absf(a3.node.position.y + sh20.dims.y / 2.0 - 1.0) < 0.003, str(a3.node.position))
	var cart = main.make_shape("box", {"x": 0.3, "y": 0.2, "z": 0.2}, Vector3(28, 4.0, 28))
	cart.node.position = Vector3(22, 4.0, 22)
	main.settle(cart)
	check("A box dropped on the top shelf sits on its board", absf(cart.node.position.y - 1.1) < 0.003, str(cart.node.position))
	for sx in [ws, ds, a1, a2, a3, cart]:
		main.remove_shape(sx)
		sx.node.queue_free()
	var pt = main.PALETTE[labels.find("Pantech truck 4.5 t")]
	var pts = main.make_shape("box", pt.dims, Vector3(30, pt.dims.y / 2.0, 30), Quaternion.IDENTITY, "Pt", pt.outline)
	var pal_in = main.make_shape("box", {"x": 1.165, "y": 0.15, "z": 1.165}, Vector3(31.5, 2.5, 30))
	main.settle(pal_in)
	check("A pallet dropped into the Pantech lands on its 1 m floor", absf(pal_in.node.position.y - 1.075) < 0.003, str(pal_in.node.position))
	for sx in [pts, pal_in]:
		main.remove_shape(sx)
		sx.node.queue_free()
	var fl = main.PALETTE[labels.find("Forklift 2.5 t")]
	check("Forklift has a detailed wireframe", fl.has("outline") and fl.outline.parts.size() > 15, str(fl.get("outline", {}).get("parts", []).size()))
	# Walk-in container: things land on its floor, not its roof; sliding in steps up onto the floor; stacking on the roof works.
	var ct = main.make_shape("box", c20.dims, Vector3(10, c20.dims.y / 2.0, 10), Quaternion.IDENTITY, "Container test", c20.outline)
	check("Container is hollow (solid floor, walls, roof)", ct.cols.size() == 6 and not ct.fill.visible, str(ct.cols.size()))
	var inside = main.make_shape("box", {"x": 0.3, "y": 0.3, "z": 0.3}, Vector3(10, 1.2, 10))
	main.settle(inside)
	check("A box dropped inside lands on the container floor", absf(inside.node.position.y - 0.30) < 0.003, str(inside.node.position))
	var cm = main.ctrls[1]
	var o_save: Vector3 = cm.o
	var d_save: Vector3 = cm.d
	inside.node.position = Vector3(10, 0.15, 12.5)
	cm.d = Vector3.FORWARD
	cm.drag = {"type": "move", "shape": inside, "c0": Vector3(10, 1.2, 13), "yaw0": 0.0, "p0": inside.node.position, "base_y": 0.15}
	cm.o = Vector3(10, 1.2, 10.5)
	main.update_move(cm, cm.drag)
	check("Sliding a box into the container steps it up onto the floor", absf(inside.node.position.y - 0.30) < 0.003 and absf(inside.node.position.z - 10.0) < 0.03, str(inside.node.position))
	cm.drag = null
	cm.o = o_save
	cm.d = d_save
	inside.node.position = Vector3(10, 4.0, 10)
	main.settle(inside)
	check("A box dropped from above lands on the roof", absf(inside.node.position.y - (2.591 + 0.15)) < 0.003, str(inside.node.position))
	main.remove_shape(ct)
	ct.node.queue_free()
	var tr = main.PALETTE[labels.find("Farizon F3E tray")] if labels.has("Farizon F3E tray") else null
	check("F3E trayback is in the palette", tr != null and tr.outline.solids.size() == 6)
	if tr != null:
		ct = main.make_shape("box", tr.dims, Vector3(10, tr.dims.y / 2.0, 10), Quaternion.IDENTITY, "Tray test", tr.outline)
		inside.node.position = Vector3(10 - 1.0, 3.0, 10)
		main.settle(inside)
		check("A box dropped on the tray lands on the deck", absf(inside.node.position.y - (0.95 + 0.15)) < 0.003, str(inside.node.position))
	main.remove_shape(inside)
	inside.node.queue_free()
	main.remove_shape(ct)
	ct.node.queue_free()
	var pallet = main.PALETTE[labels.find("AU pallet")] if labels.has("AU pallet") else null
	var van = main.PALETTE[labels.find("Farizon V7E open cargo")] if labels.has("Farizon V7E open cargo") else null
	check("V7E open cargo: whole van with load box and wheels", van != null and van.has("outline") and van.outline.inner.size() == 1 and van.outline.wheels.size() == 2, str(van))
	if van != null:
		var vs = main.make_shape(van.type, van.dims, Vector3(3, 0, 3), Quaternion.IDENTITY, "Van test", van.outline)
		check("V7E spawns with its van wireframe", vs.wire.mesh != main.unit_wire["box"] and vs.wire.mesh.get_surface_count() == 1)
		main.remove_shape(vs)
		vs.node.queue_free()
	check("AU pallet is 1165 x 1165 mm", pallet != null and is_equal_approx(pallet.dims.x, 1.165) and is_equal_approx(pallet.dims.z, 1.165), str(pallet))

	# Bigger / Smaller 5% (Y / B menu) on a shape standing on the floor.
	var c = main.ctrls[1]
	main.select(box)
	main.scale_shape(box, main.SCALE_STEP)
	check("Bigger 5% scales +5%", absf(box.dims.x - 0.315) < 0.0005, str(box.dims))
	check("Scaled box stays on the floor", absf(box.node.position.y - box.dims.y / 2.0) < 0.002, str(box.node.position))
	main.scale_shape(box, 1.0 / main.SCALE_STEP)
	check("Smaller 5% undoes it exactly (-5%)", absf(box.dims.x - 0.3) < 0.0005, str(box.dims))
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

	# Reset size (Y / B menu).
	main.select(box)
	main.scale_shape(box, main.SCALE_STEP)
	main.scale_shape(box, main.SCALE_STEP)
	c.shape_hit = {"shape": box, "point": box.node.position, "normal": Vector3.UP, "dist": 1.0}
	main.open_tools(c)
	check("Y / B menu on a shape offers Reset size", main.ctx.item("reset") != null)
	main.run_tool("reset")
	check("Reset size puts it back to its original size, still on the floor", box.dims == box.orig_dims and absf(box.dims.x - 0.3) < 0.0005 and absf(box.node.position.y - 0.15) < 0.002, str(box.dims))
	c.shape_hit = null

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

	# Clipboard (Y / B menu).
	main.select(box)
	main.copy_selected(false)
	main.paste_at(Vector3(1.0, 0, 1.0))
	check("Copy + paste makes a 5th shape", main.shapes.size() == 5)
	var cq = main.ctrls[1]
	cq.shape_hit = {"shape": main.shapes[4], "point": main.shapes[4].node.position, "normal": Vector3.UP, "dist": 1.0}
	main.open_tools(cq)
	check("X / A on a shape: 10 buttons incl. Cut, Pin, Bigger, Undo", main.ctx.is_open and main.ctx.items.size() == 10 and main.ctx.item("cut") != null and main.ctx.item("pin") != null and main.ctx.item("bigger") != null and main.ctx.item("undo") != null, str(main.ctx.items.size()))
	check("...20 cm in front of that controller", main.ctx_attach == cq and absf(main.ctx.global_position.distance_to(cq.node.global_position) - 0.2) < 0.01, str(main.ctx.global_position))
	main.run_tool("delete")
	check("Delete removes it; the palette stays open (tap mode)", main.shapes.size() == 4 and main.ctx.is_open)
	cq.shape_hit = null
	main.open_tools(cq)
	check("X / A on empty space: Paste, Next clip, Undo", main.ctx.items.size() == 3 and main.ctx.item("paste") != null)
	main.run_tool("undo")
	check("Undo brings it back", main.shapes.size() == 5)
	var victim = main.shapes[4]
	cq.shape_hit = {"shape": victim, "point": victim.node.position, "normal": Vector3.UP, "dist": 1.0}
	main.open_tools(cq)
	main.run_tool("cut")
	check("Cut removes it and puts it on the clipboard", main.shapes.size() == 4 and main.clipboard[0].name == victim.name)
	cq.shape_hit = null
	cq.target = {"point": Vector3(2, 0, 2), "normal": Vector3.UP, "dist": 1.0, "kind": "surface"}
	main.open_tools(cq)
	main.run_tool("paste")
	check("Paste puts it where you pointed", main.shapes.size() == 5 and Vector2(main.shapes[4].node.position.x, main.shapes[4].node.position.z).is_equal_approx(Vector2(2, 2)))
	cq.target = null
	cq.shape_hit = {"shape": main.shapes[4], "point": main.shapes[4].node.position, "normal": Vector3.UP, "dist": 1.0}
	main.open_tools(cq)
	main.run_tool("duplicate")
	check("Duplicate makes a copy", main.shapes.size() == 6)
	main.undo()
	cq.shape_hit = null

	# Face buttons: X / A = clipboard menu, Y / B = objects menu. Tap = palette that stays; hold = quick-pick.
	main.close_tools()
	var cu = main.ctrls[0]
	cu.drag = null
	cu.shape_hit = null
	cu.ui = null
	main.face_button(cu, "low", true, false, 10.0)
	main.face_button(cu, "low", false, true, 10.1)
	check("Tap X: clipboard menu opens 20 cm in front of the controller", main.ctx.is_open and main.ctx_attach == cu and absf(main.ctx.global_position.distance_to(cu.node.global_position) - 0.2) < 0.01, str(main.ctx.global_position))
	check("...and stays open after the tap (palette)", main.ctx.is_open and main.ctx_hold == null)
	var ctx_pos: Vector3 = main.ctx.global_position
	cu.node.position += Vector3(0.3, 0.0, 0.0)
	main._process(0.0)
	check("...and stays where it opened when the hand moves", main.ctx.global_position.is_equal_approx(ctx_pos))
	cu.node.position = Vector3.ZERO
	main.face_button(cu, "low", true, false, 11.0)
	check("Tap X again closes it", not main.ctx.is_open)
	main.face_button(cu, "high", true, false, 12.0)
	main.face_button(cu, "high", false, true, 12.1)
	check("Tap Y: objects menu + sidebar (Trace, Box, Custom, Save selected)", main.tray.is_open and main.tray_side.is_open and main.tray.items.size() == main.PALETTE.size() and main.tray_side.item("side:trace") != null and main.tray_side.item("side:box") != null and main.tray_side.item("side:custom") != null and main.tray_side.item("side:save") != null)
	check("...sidebar sits left of the grid", main.tray.to_local(main.tray_side.global_position).x < -(main.tray.size.x + main.tray_side.size.x) / 2.0 + 0.001)
	check("...tapped open, it rides on that wrist (above the hand)", main.tray_follow and main.tray.global_position.y > cu.node.global_position.y + 0.05)
	var tray_p0: Vector3 = main.tray.global_position
	cu.node.position += Vector3(0.3, -0.2, 0.1)
	main._process(0.0)
	var tray_rel: Vector3 = main.tray.global_position - cu.node.global_position
	check("...and follows the hand when it moves", not main.tray.global_position.is_equal_approx(tray_p0) and tray_rel.y > 0.05 and tray_rel.length() < 0.6, str(tray_rel))
	cu.node.position = Vector3.ZERO
	main._process(0.0)
	var n1: int = main.shapes.size()
	var cg2 = main.ctrls[1]
	cg2.ui = {"panel": main.tray, "id": "obj:0", "dist": 0.5, "point": main.tray.global_position}
	main.on_trigger_down(cg2, {"trigger": true})
	check("Picking from the palette puts it in your hand; the menu stays open", main.shapes.size() == n1 + 1 and cg2.drag != null and main.tray.is_open)
	cg2.ui = null
	main.on_drag_release(cg2)
	main.undo()
	main.face_button(cu, "high", true, false, 13.0)
	check("Tap Y again closes it (and its sidebar)", not main.tray.is_open and not main.tray_side.is_open)
	main.face_button(cu, "high", true, false, 14.0)
	cu.ui = {"panel": main.tray, "id": "obj:0", "dist": 0.2, "point": main.tray.global_position}
	var n2: int = main.shapes.size()
	main.face_button(cu, "high", false, true, 14.6)
	check("Hold Y, point with the same hand, let go: it's in your hand and the menu closes", main.shapes.size() == n2 + 1 and cu.drag != null and cu.drag.type == "free" and not main.tray.is_open)
	cu.ui = null
	main.on_drag_release(cu)
	main.undo()
	cu.shape_hit = {"shape": main.shapes[4], "point": main.shapes[4].node.position, "normal": Vector3.UP, "dist": 1.0}
	main.face_button(cu, "low", true, false, 15.0)
	cu.ui = {"panel": main.ctx, "id": "duplicate", "dist": 0.2, "point": main.ctx.global_position}
	var n3: int = main.shapes.size()
	main.face_button(cu, "low", false, true, 15.5)
	check("Hold X on a shape, point at Duplicate, let go: duplicated and closed", main.shapes.size() == n3 + 1 and not main.ctx.is_open)
	main.undo()
	cu.ui = null
	cu.shape_hit = null
	main.face_button(cu, "low", true, false, 16.0)
	main.face_button(cu, "low", false, true, 16.5)
	check("Hold X and let go pointing at nothing: it just closes", not main.ctx.is_open and main.shapes.size() == n3)
	var nb := {"high": false, "low": false, "trigger": false, "grip": false, "stick": false, "menu": false, "sx": 0.0, "sy": 0.0}
	var press := func(k: String) -> void:
		var b2: Dictionary = nb.duplicate()
		b2[k] = true
		main.process_input(cu, b2)
		main.process_input(cu, nb.duplicate())
	cu.btn = nb.duplicate()
	press.call("stick")
	check("Stick click: Tools menu (Rotate/Move, Scale, Edit, Player move, 7 measuring tools, Reset position; no Free draw)", main.menu.is_open and main.menu_kind == "tools" and main.menu.items.size() == 12 and main.menu.item("tape") != null and main.menu.item("freedraw") == null and main.menu.item("playermove") != null and main.menu.item("edit") != null and main.menu.item("units") == null, str(main.menu.items.size()))
	cu.node.position += Vector3(0.3, 0.1, -0.2)
	main._process(0.0)
	check("...stuck to that hand", main.menu.global_position.distance_to(cu.node.global_position) < 0.6)
	cu.node.position = Vector3.ZERO
	cu.stick_down_at = -10.0
	press.call("stick")
	check("Stick click again closes it", not main.menu.is_open)
	press.call("menu")
	check("Left ≡: settings menu (16 buttons, no tools / clipboard)", main.menu.is_open and main.menu_kind == "settings" and main.menu.items.size() == 16 and main.menu.item("units") != null and main.menu.item("tape") == null and main.menu.item("copy") == null, str(main.menu.items.size()))
	press.call("menu")
	check("≡ again closes it", not main.menu.is_open)
	cu.btn = {}

	# Pin (Y / B menu); a pinned shape can't be grabbed, resized or dropped.
	var cp = main.ctrls[1]
	cp.o = Vector3(0, 1.2, 0)
	cp.d = (box.node.position - cp.o).normalized()
	cp.shape_hit = {"shape": box, "point": box.node.position, "normal": Vector3.UP, "dist": 1.0}
	main.open_tools(cp)
	check("Y / B menu offers Pin", main.ctx.item("pin") != null and main.ctx.item("pin").label == "Pin")
	main.run_tool("pin")
	main.select(box)
	check("Pin pins it (no resize cubes)", box.pinned and box.handles.size() == 0)
	var pos_pinned: Vector3 = box.node.position
	main.on_grip_down(cp, {"grip": true})
	check("A pinned shape can't be slid", cp.drag == null and box.node.position == pos_pinned, main.status)
	main.on_trigger_down(cp, {"trigger": true})
	check("...or picked up", cp.drag == null)
	check("Pinned flag is saved", main.room_data().shapes[0].pinned == true)
	main.open_tools(cp)
	check("...and the menu now says Unpin", main.ctx.item("pin").label == "Unpin")
	main.run_tool("pin")
	main.on_grip_down(cp, {"grip": true})
	check("Unpin makes it grabbable again", not box.pinned and cp.drag != null and cp.drag.type == "move")
	main.on_trigger_down(cp, {"grip": true, "trigger": true})
	check("Grip + trigger lifts it", cp.drag != null and cp.drag.type == "free", str(cp.drag.type if cp.drag else null))
	main.on_drag_release(cp)
	box.node.position = pos_pinned
	box.node.quaternion = Quaternion(Vector3.UP, -PI / 4)
	main.refresh_shape(box)

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
	main.close_menu()
	main.open_menu(main.ctrls[0], true)
	main.on_button("rooms")
	main.rebuild_menu()
	check("Rooms page lists the current room", main.menu.item("room:" + main.room.id) != null)
	main.on_button("back")
	main.close_menu()

	# Accuracy test (menu > Accuracy test...).
	main.acc_trials.clear()
	main.open_menu(main.ctrls[0], true)
	main.on_button("accuracy")
	main.rebuild_menu()
	check("Accuracy test page opens from the menu", main.menu_page == "accuracy" and main.menu.item("acc:a4l") != null and main.menu.item("accu:+10") != null)
	main.on_button("acc:a4l")
	check("Picking A4 starts the test and closes the menu", main.mode == "acctest" and not main.menu.is_open and is_equal_approx(main.acc_ref.mm, 297.0))
	var nm0: int = main.measures.size()
	main.add_pending_point(Vector3(10, 0.8, 10))
	main.add_pending_point(Vector3(10.299, 0.8, 10))
	check("Trial 1: A4 measured 299 mm = +2.0 mm", main.acc_trials.size() == 1 and is_equal_approx(main.acc_trials[0].error_mm, 2.0), str(main.acc_trials))
	check("...is not saved as a room measurement", main.measures.size() == nm0)
	main.start_accuracy("a4s")
	main.add_pending_point(Vector3(10, 0.8, 11))
	main.add_pending_point(Vector3(10, 0.8, 11.207))
	var st: Dictionary = main.accuracy_stats()
	check("Stats: 2 trials, avg ±2.5 mm, worst 3.0, bias -0.5", st.n == 2 and is_equal_approx(st.mean_abs_mm, 2.5) and is_equal_approx(st.worst_mm, 3.0) and is_equal_approx(st.bias_mm, -0.5), str(st))
	main.on_button("acc:custom")
	main.on_button("accu:+100")
	main.on_button("accu:-1")
	check("Custom length steps: 1000 +100 -1 = 1099 mm", is_equal_approx(main.acc_ref.mm, 1099.0) and main.mode == "acctest", str(main.acc_ref))
	main.acc_custom_mm = 1000.0
	var ap: String = main.export_accuracy()
	var acsv := FileAccess.get_file_as_string(ap) if ap != "" else ""
	check("Accuracy CSV export: header, 2 trials, summary", acsv.begins_with("time,reference,true_mm") and acsv.contains("A4 sheet, long side") and acsv.contains("\ntrials,mean_abs_error_mm"), ap)
	main.load_accuracy()
	check("Trials survive a restart (accuracy.json)", main.acc_trials.size() == 2)
	main.undo()
	check("Undo removes the last trial", main.acc_trials.size() == 1)
	main.on_button("accclear")
	check("Clear results empties the list", main.acc_trials.is_empty())
	main.set_tool("select")

	# Room info + Fit check against fake Space Setup surfaces.
	var fake := []
	var mk := func(lab: String, pos: Vector3, basis: Basis, size: Vector2, collide: bool):
		var n = main.SceneAnchorScene.instantiate()
		n.label_name = lab
		n.size_2d = size
		n.transform = Transform3D(basis, pos)
		if collide:
			var body := StaticBody3D.new()
			body.collision_layer = main.LAYER_ROOM
			body.collision_mask = 0
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(size.x, size.y, 0.02)
			cs.shape = bs
			body.add_child(cs)
			n.add_child(body)
			if lab == "floor":
				main.ignore_for_fit.call_deferred(body.get_rid())
		main.origin.add_child(n)
		main.register_surface(n)
		fake.append(n)
		return n
	var flo = mk.call("floor", Vector3(20, 0, 0), Basis(Vector3.RIGHT, -PI / 2), Vector2(4, 3), true)
	flo.boundary = PackedVector2Array([Vector2(-2, -1.5), Vector2(2, -1.5), Vector2(2, 1.5), Vector2(-2, 1.5)])
	mk.call("ceiling", Vector3(20, 2.4, 0), Basis(Vector3.RIGHT, PI / 2), Vector2(4, 3), false)
	mk.call("wall face", Vector3(20, 1.2, -1.5), Basis.IDENTITY, Vector2(4, 2.4), true)
	mk.call("wall face", Vector3(20, 1.2, 1.5), Basis(Vector3.UP, PI), Vector2(4, 2.4), false)
	mk.call("wall face", Vector3(18, 1.2, 0), Basis(Vector3.UP, PI / 2), Vector2(3, 2.4), false)
	mk.call("wall face", Vector3(22, 1.2, 0), Basis(Vector3.UP, -PI / 2), Vector2(3, 2.4), false)
	mk.call("door frame", Vector3(18, 1.0, 0), Basis(Vector3.UP, PI / 2), Vector2(0.82, 2.04), false)
	mk.call("table", Vector3(21, 0.75, 0.5), Basis(Vector3.RIGHT, -PI / 2), Vector2(1.2, 0.8), false)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var rs: Dictionary = main.room_summary()
	check("Room info: floor 4 × 3 m = 12 m²", is_equal_approx(rs.floor_area_m2, 12.0) and is_equal_approx(rs.floor_w_m, 4.0), str(rs))
	check("Room info: ceiling 2.4 m, volume 28.8 m³", is_equal_approx(rs.ceiling_m, 2.4) and is_equal_approx(rs.volume_m3, 28.8), str(rs))
	check("Room info: 4 walls, perimeter 14 m, 1 door, 1 furniture", rs.walls == 4 and is_equal_approx(rs.perimeter_m, 14.0) and rs.doors == 1 and rs.furniture == 1, str(rs))
	main.open_menu(main.ctrls[0], true)
	main.on_button("roominfo")
	main.rebuild_menu()
	check("Room info page opens from the menu with the floor size", main.menu_page == "roominfo" and main.room_info_lines()[0].begins_with("Floor 4.000 m × 3.000 m"), str(main.room_info_lines()))
	main.on_button("back")
	main.close_menu()
	var at := func(p: Vector3) -> Vector3: return main.content.to_local(p)
	var fa = main.make_shape("box", {"x": 0.5, "y": 0.5, "z": 0.5}, at.call(Vector3(20, 0.25, -1.4)), main.content.quaternion.inverse(), "Fit A")
	var fb = main.make_shape("box", {"x": 0.5, "y": 0.5, "z": 0.5}, at.call(Vector3(20.5, 0.25, -0.5)), main.content.quaternion.inverse(), "Fit B")
	var fc = main.make_shape("box", {"x": 0.5, "y": 0.5, "z": 0.5}, at.call(Vector3(20.8, 0.25, -0.5)), main.content.quaternion.inverse(), "Fit C")
	await get_tree().physics_frame
	await get_tree().physics_frame
	main.set_fit_check(true)
	main.update_fit(0.0, true)
	check("Fit check: box through the wall is flagged", fa.fit_hits == ["wall face"], str(fa.fit_hits))
	check("...turns red and says why on its label", fa.wire_mat.albedo_color == main.C_RED and (fa.label.get_child(3) as Label3D).text.contains("wall face"))
	check("...sitting on the floor doesn't count", not fb.fit_hits.has("floor") and not fa.fit_hits.has("floor"))
	check("Two overlapping boxes flag each other", fb.fit_hits == ["Fit C"] and fc.fit_hits == ["Fit B"], "%s / %s" % [fb.fit_hits, fc.fit_hits])
	fc.node.position = at.call(Vector3(21.0, 0.25, -0.5))
	fa.node.position = at.call(Vector3(20, 0.25, -1.25))
	await get_tree().physics_frame
	main.update_fit(0.0, true)
	check("Boxes touching side by side, and flush against the wall, fit", fb.fit_hits.is_empty() and fc.fit_hits.is_empty() and fa.fit_hits.is_empty(), "%s %s %s" % [fa.fit_hits, fb.fit_hits, fc.fit_hits])
	check("...and go back to their own colour", fa.wire_mat.albedo_color == fa.color)
	fa.node.position = at.call(Vector3(20, 0.25, -1.4))
	await get_tree().physics_frame
	main.update_fit(0.0, true)
	main.on_button("fitcheck")
	check("Fit check off clears the warning", not main.fit_check and fa.fit_hits.is_empty() and fa.wire_mat.albedo_color == fa.color)
	main.on_button("fitcheck")
	var ex2: Dictionary = main.export_all()
	var js = JSON.parse_string(FileAccess.get_file_as_string(ex2.base + ".json"))
	check("JSON export includes the room scan summary", js is Dictionary and js.has("room_scan") and is_equal_approx(js.room_scan.floor_area_m2, 12.0))
	for s in [fa, fb, fc]:
		main.remove_shape(s)
		s.node.queue_free()
	for n in fake:
		n.queue_free()
	main.surfaces.clear()
	main.fit_ignore.clear()

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

	# Player move: left stick slides you (the room moves the other way), right stick turns 15°; Reset position.
	main.set_tool("playermove")
	var home: Transform3D = main.content.transform
	var pl = main.ctrls[0]
	pl.drag = null
	main.player_move(pl, {"sx": 0.0, "sy": 1.0}, 0.5)
	var moved: Vector3 = main.content.transform.origin - home.origin
	check("Player move: left stick slides you through the room (75 cm in ½ s at full tilt)", absf(moved.length() - 0.75) < 0.01 and absf(moved.y) < 0.001, str(moved))
	var pr = main.ctrls[1]
	pr.drag = null
	main.player_move(pr, {"sx": 1.0, "sy": 0.0}, 0.25)
	check("Right stick left/right turns you smoothly (15° in ¼ s at full tilt, no snap)", absf(absf(rad_to_deg(main.yaw_of_quat(main.content.quaternion) - main.yaw_of_quat(home.basis.get_rotation_quaternion()))) - 15.0) < 0.01, str(rad_to_deg(main.yaw_of_quat(main.content.quaternion))))
	main.player_move(pr, {"sx": 0.0, "sy": 0.5}, 0.1)
	var y1: float = main.content.transform.origin.y
	check("Right stick up raises you smoothly (the room goes down a little)", y1 < home.origin.y and y1 > home.origin.y - 0.1, str(y1))
	main.player_move(pr, {"sx": 0.0, "sy": -1.0}, 1.0)
	check("Right stick down lowers you", main.content.transform.origin.y > y1 + 0.5, str(main.content.transform.origin.y))
	main.on_button("resetpos")
	check("Reset position puts the room back where it really is", main.content.transform.is_equal_approx(home))
	main.set_tool("select")

	# Edit: point at a face, trigger, pull it along its axis.
	main.set_tool("edit")
	var eb = main.make_shape("box", {"x": 0.4, "y": 0.3, "z": 0.2}, Vector3(5, 0.15, 5))
	var ce = main.ctrls[1]
	ce.ui = null
	ce.drag = null
	ce.handle_hit = null
	ce.o = Vector3(5.6, 0.15, 5.0)
	ce.d = Vector3.LEFT
	ce.shape_hit = {"shape": eb, "point": Vector3(5.2, 0.15, 5.0), "normal": Vector3.RIGHT, "dist": 0.4}
	main.on_trigger_down(ce, {"trigger": true})
	check("Edit: trigger on a face grabs that face", ce.drag != null and ce.drag.type == "edit" and ce.drag.key == "x", str(ce.drag))
	ce.o = Vector3(5.3, 1.0, 5.0)
	ce.d = Vector3.DOWN
	main.update_edit(ce, ce.drag)
	check("...and outlines it in yellow", main.edit_hl.visible)
	check("Pulling the +X face 10 cm: 50 cm long, the -X face stays put", absf(eb.dims.x - 0.5) < 0.001 and absf(eb.node.position.x - 0.25 - 4.8) < 0.001, "%s %s" % [eb.dims, eb.node.position])
	check("...other sides unchanged", is_equal_approx(eb.dims.y, 0.3) and is_equal_approx(eb.dims.z, 0.2))
	main.on_drag_release(ce)
	ce.shape_hit = null
	main.undo()
	check("Undo puts the face back", absf(eb.dims.x - 0.4) < 0.001)
	main.remove_shape(eb)
	eb.node.queue_free()

	# Box: tip on one corner, pull to the opposite corner.
	main.set_tool("boxmake")
	var cb = main.ctrls[1]
	cb.ui = null
	cb.shape_hit = null
	cb.drag = null
	var nb0: int = main.shapes.size()
	cb.o = Vector3(6, 0, 6)
	main.on_trigger_down(cb, {"trigger": true})
	cb.o = Vector3(6.6, 0.4, 6.3)
	main.tip_up(cb)
	var bx = main.shapes[-1]
	check("Box: corner to corner makes a 60 × 40 × 30 cm box on the floor", main.shapes.size() == nb0 + 1 and is_equal_approx(bx.dims.x, 0.6) and is_equal_approx(bx.dims.y, 0.4) and is_equal_approx(bx.dims.z, 0.3) and absf(bx.node.position.y - 0.2) < 0.001, str(bx.dims))
	cb.o = Vector3(7, 0, 7)
	main.on_trigger_down(cb, {"trigger": true})
	main.tip_up(cb)
	check("A quick click starts click-move-click", main.draft.get("click", false))
	cb.o = Vector3(7.5, 0.5, 7.5)
	main.on_trigger_down(cb, {"trigger": true})
	check("...the second click finishes it", main.shapes.size() == nb0 + 2 and main.draft.is_empty())

	# Trace: an L-shaped outline, then the height.
	main.set_tool("trace")
	var ntr: int = main.shapes.size()
	for q in [Vector3(8, 0, 8), Vector3(9, 0, 8), Vector3(9, 0, 8.5), Vector3(8.5, 0, 8.5), Vector3(8.5, 0, 9), Vector3(8, 0, 9)]:
		cb.o = q
		main.on_trigger_down(cb, {"trigger": true})
		main.tip_up(cb)
	cb.o = Vector3(8.01, 0, 8.01)
	main.on_trigger_down(cb, {"trigger": true})
	check("Trace: clicking the first corner closes the outline", main.draft.get("phase", "") == "height")
	cb.o = Vector3(8.5, 1.0, 10.0)
	cb.d = (Vector3(8.5, 2.5, 8.5) - cb.o).normalized()
	check("Trace height follows where you point: aim 2.5 m up without reaching", absf(main.trace_top_y(cb) - 2.5) < 0.001, str(main.trace_top_y(cb)))
	cb.d = (Vector3(8.5, 0.8, 8.5) - cb.o).normalized()
	main.on_trigger_down(cb, {"trigger": true})
	var trc = main.shapes[-1]
	check("...a click sets the height: L-shaped trace 1 × 0.8 × 1 m", main.shapes.size() == ntr + 1 and is_equal_approx(trc.dims.x, 1.0) and is_equal_approx(trc.dims.y, 0.8) and is_equal_approx(trc.dims.z, 1.0), str(trc.dims))
	check("Its volume is the L (0.6 m³), not its box (0.8 m³)", absf(main.shape_volume(trc) - 0.6) < 0.001, str(main.shape_volume(trc)))
	check("...and the pointer hits its real shape", trc.col.shape is ConvexPolygonShape3D)
	main.set_tool("trace")
	cb.o = Vector3(12, 0, 12)
	main.on_trigger_down(cb, {"trigger": true})
	cb.stroke_t0 -= 1.0
	for i in 10:
		cb.o = Vector3(12 + 0.04 * i, 0, 12)
		main.tip_hold(cb)
	check("Holding trigger draws freehand (a point every 3 cm)", main.draft.pts.size() >= 9, str(main.draft.pts.size()))
	main.tip_grip(cb)
	check("Grip undoes the last point", main.draft.pts.size() >= 8)
	main.set_tool("select")

	# Trace / Box toggle in the objects menu sidebar: tap again to turn it off.
	main.set_tool("select")
	main.open_tray(main.ctrls[0])
	main.run_side(main.ctrls[0], "side:trace")
	check("Sidebar Trace turns Trace on", main.mode == "trace")
	main.open_tray(main.ctrls[0])
	check("...its button says Trace: ON", main.tray_side.item("side:trace").label == "Trace: ON")
	main.run_side(main.ctrls[0], "side:trace")
	check("...tap it again: Trace off, back to Rotate/Move", main.mode == "select" and main.tray_side.item("side:trace").label == "Trace: off")
	main.run_side(main.ctrls[0], "side:box")
	main.open_tray(main.ctrls[0])
	main.run_side(main.ctrls[0], "side:box")
	check("Box toggles off the same way", main.mode == "select")
	main.close_tray()

	# Custom objects: Save selected, pick it again, remove it.
	main.select(trc)
	main.custom_objs.clear()
	main.open_tray(main.ctrls[0])
	main.run_side(main.ctrls[0], "side:save")
	check("Save selected adds it to Custom objects", main.custom_objs.size() == 1 and main.custom_objs[0].label == "Trace")
	main.run_side(main.ctrls[0], "side:custom")
	check("Custom... shows your saved objects", main.tray_page == "custom" and main.tray.item("cus:0") != null)
	main.load_custom()
	check("Custom objects are saved on the headset", main.custom_objs.size() == 1 and main.custom_objs[0].outline.has("poly"))
	var cg3 = main.ctrls[1]
	cg3.drag = null
	cg3.ui = {"panel": main.tray, "id": "cus:0", "dist": 0.5, "point": main.tray.global_position}
	var nc: int = main.shapes.size()
	main.on_trigger_down(cg3, {"trigger": true})
	check("Picking a custom object puts a copy in your hand, same size and shape", main.shapes.size() == nc + 1 and main.shapes[-1].dims == trc.dims and not main.shapes[-1].outline.get("poly", []).is_empty())
	cg3.ui = null
	main.on_drag_release(cg3)
	main.run_side(main.ctrls[0], "side:remove")
	cg3.ui = {"panel": main.tray, "id": "cus:0", "dist": 0.5, "point": main.tray.global_position}
	main.on_trigger_down(cg3, {"trigger": true})
	check("Remove: on deletes a custom object", main.custom_objs.is_empty())
	cg3.ui = null
	main.tray_page = "all"
	main.custom_remove = false
	main.close_tray()
	main.select(null)

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
