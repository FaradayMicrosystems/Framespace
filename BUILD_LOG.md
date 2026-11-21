# Build log: how this was built

For the "is AI-assisted development worth it?" conversation. All times UTC, 2026-11-17.

| Time | What happened | Who |
|---|---|---|
| 07:04 | Request: "AR design + measuring + wireframe tool for Quest 3, full plan, testable in an hour." | Aurora |
| 07:05 | ETA given. Research started: Quest 3 WebXR features (hit-test, planes, anchors), Passthrough Camera API, GitHub Actions 2026 pricing. | Claude |
| 07:08 | Full plan delivered: stack decision with reasons, phases, accuracy targets, data model, exports, GitHub Actions cost model, testing phases, launch steps (`docs/PLAN.md`). | Claude |
| 07:07–07:10 | Scope set: wireframe shapes, move/scale, length/width/radius/volume, cut/copy/paste + clipboard, exports. Name: Framespace. | Aurora |
| 07:10–07:20 | Prototype written: ~950 lines, single page, no build step. Emulated-headset test suite written. | Claude |
| 07:20 | Test run in emulated Quest 3: 16/17 pass. Bug found (paste without depth hit floated in the air), fixed, 17/17 pass. | Claude |
| 07:17 | GitHub repo created. | Aurora |
| 07:23 | Pushed, CI + GitHub Pages deploy set up. Emulated-headset test runs on every push. | Claude |
| 07:38 | New control scheme specified in plain English (grip/trigger/B, stick, A/X/Y, grid). | Aurora |
| 07:40–07:48 | Controls rebuilt: polling input state machine, grid snapping, gravity drop onto floor/tables/shapes, palette and context pop-ups. Test suite grown to 27 checks; 1 real overlap bug found (palette hidden behind tools menu) and fixed. 27/27 pass. | Claude |

## Effort split

- **Aurora:** about 6 short chat messages, created one repo. Roughly 10 minutes of attention.
- **Claude:** research, plan, all code, tests, CI, deployment, docs.
- **Elapsed:** about 20 minutes from request to a tested build; about 10 more for a full control-scheme rewrite.

## What a person would normally spend

A rough, conventional estimate for the same scope by one experienced WebXR developer: 1 day of research and planning, 3 to 5 days to build and test the prototype. Treat this as an estimate, not a measurement.

## Honest caveats

- Tested in an emulator so far. First on-headset test is the real proof.
- Accuracy is limited by the Quest 3 sensors (about ±1 to 3 cm at arm's length), not by the software.

## 2026-11-18 (Brisbane): native Quest app

- Aurora asked for a native, offline app with saved rooms and no guardian boundary, plus a stick-click hand menu.
- Stack: Godot 4.6.2 + Meta's GodotOpenXRVendors 5.0.0. Why: free, and CI builds the APK with no licence. Unity CI needs a licence tied to her account.
- The whole web app was ported to GDScript by Claude (`native/`), plus new features: rooms auto-saved and pinned to Meta spatial anchors, Space Setup surfaces for snapping, a stick-click menu attached to the hand, and 20ft/40ft container presets.
- CI (`.github/workflows/native.yml`) runs a headless self-test, builds the APK, fails if the manifest lacks BOUNDARYLESS_APP or PASSTHROUGH, and publishes `native-latest`.

## 2026-11-19 (Brisbane): 25 true-scale objects, editable palette

- Aurora asked for a pallet, then ~25 common objects to scale for simple planning, and for the list to be easy to update.
- Added 25 objects (AU / EUR / US pallets, IBC, 205 L drum, racking bay, forklift, door, car park bay, car, ute, person and more), Australian standards where they exist.
- Moved the whole palette into one shared `objects.csv` (sizes in mm) read by both the web and native apps. Why: one spreadsheet-style edit updates both builds, no code changes.
- Placed objects are named after what they are ("AU pallet 2"), so exports are readable.

## 2026-11-19 (Brisbane): Farizon V7E wireframes

- Aurora asked for a wireframe Farizon V7E, then a second one showing the internal load area with no barn or sliding doors, both as the whole van on its wheels.
- Dimensions from AU spec listings (CarsGuide, CarExpert; overhangs from VanReviewer): 4995 L x 1820 W x 1985 H, wheelbase 3200, 195/65 R16 tyres (660 mm), load area 2865 x 1690 x 1435 on a 510 mm floor.
- Added optional `outline`, `wheels` and `inner` columns to `objects.csv`. Why: any vehicle or odd-shaped object can be drawn from the spreadsheet, while measuring and scaling stay box-simple.

## 2026-11-20 (Brisbane): rooms drop where you stand

- Scope agreed: keep Framespace a home layout planner and make the proof of concept measurable before expanding it.
- Aurora asked for rooms to load where the user is standing, so that standing on the same spot, facing the same way and recentering puts everything back in place.
- Native app: a room's origin is now the floor under your head, facing the way you look. Loading a room places it there, and recentering (hold the Meta button) re-places it. **Rooms... > Place room here** does the same from the menu. Spatial anchors are still there as an option (**Rooms... > Placement**), so the two methods can be compared.
- 12 new self-test checks (43 total), including "back on the same spot, facing the same way, everything lines up exactly".

## 2026-11-20 (Brisbane): grabbing only moves, Turn room

- Aurora asked that grabbing never changes a shape's size, that size and rotation only change with the stick's snap steps, in 10% steps, and for a fine way to square the room and grid after recentering.
- Native app: grip alone now grabs and moves (no more push/pull scaling), and a free carry keeps the shape's rotation. Stick up / down is now ±10% (reversible), and rotation stays at 45° steps.
- New main-menu buttons, **Turn room 5° / 1° left / right**, turn the whole room and grid around where you stand. 50 self-test checks.
- Kept it simple: the spatial-anchor placement option was removed, so a room only ever loads where you stand (the "plan anywhere" workshop). Space Setup walls and tables are still used for snapping.

## 2026-11-21 (Brisbane): pin, no accidental scaling, menu by your hand

- Aurora asked to pin objects from the hold-A menu so they can't be grabbed by accident, reported that moving a controller while grabbing sometimes changed an object's size, asked for 5% stick steps, and said the hold-A menu for far objects opened out at the object (tiny, sometimes outside the play space).
- **Pin / Unpin** in the hold-A menu (both apps). A pinned shape can't be grabbed, carried, resized or dropped; it shows "(pinned)" on its label and stays pinned in saved rooms. Why: protects finished layout pieces while you work around them.
- **Accidental scaling fixed.** Cause: the trigger could catch a yellow resize cube while you held grip, so every hand movement resized the shape (the web app also still had push-to-scale). Now resize cubes only work with the trigger alone and never while anything is being held, and pressing grip mid-resize switches to moving. Stick steps are now ±5%.
- **Hold-A menu opens next to your hand** with a dotted line in the object's colour to the object.
- Web app: the stick-click menu replaces the floating panel and Y (matches the APK). Aurora now works on the APK only.
- Tests: native self-test 62 checks, web 41 checks.

## 2026-11-21 (Brisbane): brush-and-canvas controls, tool modes, 5 new measuring tools

- Aurora (in headset) asked for: stick click = the object chooser, with all controls in a 4×8 sidebar and a big object tray beside it (tray only in Move/Scale); X/A = one press to pick a tool mode (cut, copy, paste, move/scale...), plus Reset size; undo on hold B; grip = slide on the grid; trigger = pick up freely, twist the hand to turn it, snap to the grid on touching a surface; more tools like Circle 3-pt. "More like a painter with a brush and canvas."
- Built (APK, 0.4.0-native): sidebar + tray menu fixed in front of you (too wide to hang off a hand), tool modes on X/A, hold B/Y undo, trigger carry on the pointer with wrist-twist rotation and surface snapping (15° steps), quick tap = select only (no accidental nudges), Reset size (original size saved in rooms and the clipboard), and Rect 3-pt, Height, Angle 3-pt, Path and Area measuring tools (in JSON/CSV/GLB exports too).
- Tests: native self-test 81 checks (was 62), run locally with the same Godot build as CI before pushing.
- Web app unchanged (Aurora is on the APK only).
- Follow-up (same day, after first headset test): menus are stuck to the hands. Y/B tap = main menu (sidebar + tray), X/A = tool menu; hold Y/B = undo. "Move/Scale" became **Rotate/Move**: while holding, stick left/right turns smoothly and forward/back pushes/pulls continuously; hands do fine adjustment. Self-test 91 checks.
- Then: wrist-twist rotation kept ("really nice"); resizing moved into its own **Scale** tool (rarely used); 15 Lego-style **building blocks** added to objects.csv (bricks, slabs, beams, post, wall, peg, pillar, cap, ball). Self-test 93 checks.
