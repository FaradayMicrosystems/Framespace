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

## 2026-11-22 (Brisbane): accuracy test, room info, fit check

- Aurora picked two of three improvement ideas Claude suggested: an accuracy test (in the menu) to give the CTO a hard number, and using the Quest's room scan to answer "will this fit?".
- **Accuracy test** (menu > Accuracy test...): pick a known reference (A4, bank card, door leaf, or a custom tape-measured length), tap its ends, and every trial is logged with its error and distance from your head. Running average, worst, bias and RMS show in the menu; **Export results** writes a CSV. Why: "±X mm over N trials" is evidence, "looks about right" isn't.
- **Room info** (menu > Room info...): floor size and area (real outline for L-shaped rooms), ceiling height, volume, walls and perimeter, doors, windows, furniture, all from Space Setup. Also in the JSON export.
- **Fit check** (on by default): objects that push more than 2 cm into walls, ceiling, furniture or each other turn red, and the label names what they hit. Live while carrying. The floor and the whole-room mesh are ignored (things always touch them; the room mesh is too noisy). The 2 cm margin absorbs scan noise and flush contact.
- Built on top of PR #9 (brush-and-canvas controls), which was still unmerged. APK 0.5.0-native.
- Tests: native self-test 115 checks (was 93), run locally on Godot 4.6.2 before pushing.

## 2026-11-22 (Brisbane): stick forward/back pushes and pulls

- Aurora reported that in the APK, stick up/down while holding still scaled the object instead of moving it closer or farther away, as she'd asked on 2026-11-21.
- Native app: stick **forward / back** while holding (sliding or carrying) now pushes the shape away from you or pulls it in, smoothly. Tilting further moves it faster, up to 1.5 m/s, and it stops 10 cm from the controller. Sliding stays on the floor and grid; a free carry moves along the line from your hand to the shape. Why: placing things across the room without walking over, as with the "brush and canvas" feel she wants.
- Scaling moved to **Bigger 5% / Smaller 5%** in the hold-A menu (undoable). The resize cubes still work. Why: she rarely scales, so it shouldn't sit on the stick.
- Stick left/right still rotates 45° steps; a mostly-sideways flick never pushes.
- AI involvement: Claude found the cause (the stick-Y handler still called the scale step) and wrote the fix, docs and 5 new self-test checks in about 15 minutes.

## 2026-11-22 (Brisbane): grip slides, trigger holds, grip + trigger lifts; Y/B clipboard, X/A objects

- Aurora asked for grip alone to slide on the floor, grip + trigger to lift, and trigger alone on an object to hold it so a wrist twist rotates it. She also said the hold-A menu never appeared, and asked for the clipboard menu on Y and B and the objects menu on A as well as X.
- Native app: **trigger alone** on a shape now holds it like a brush. It follows the controller's position and rotation, and on release it drops and squares to the grid (45° steps). **Grip + trigger** (either order) lifts it and keeps its rotation. **Grip alone** slides it on the floor as before. "Grip + B to pick up" is gone because grip + trigger replaces it. Tapping trigger still selects, and trigger on a resize cube still resizes.
- **Y / B** press toggles the clipboard menu (cut, copy, delete, duplicate, pin, bigger/smaller, paste). Why: a press is more reliable than the old 0.25 s hold on A, which she couldn't get to open. **Hold X or A** shows the objects palette.
- 10 new self-test checks (77 total, all passing locally and in CI).

## 2026-11-22 (Brisbane): cleaner menus, walk-in containers, detailed wireframes

- Aurora asked to strip shapes, clipboard, undo, drop and delete out of the thumbstick menu (the Y/B menu covers them), to add Undo to the Y/B menu, and to make X/A a toggle like Y/B. She also asked to cut the objects list down to useful items, to give forklifts, pallet jacks and pallets real wireframes, to add a motorcycle, and for walk-in 20ft/40ft containers (doors open) and a V7E load bed she can actually load, for load-master training and house planning.
- Thumbstick menu is down to 16 buttons (tools, units, grid, room, file, quit, turn room). The Y/B menu gains **Undo**. **X/A** toggles the objects menu, and picking an object closes it.
- objects.csv goes from 39 to 26 objects and gains a `parts` column (boxes, lines, wheels in mm). `s:`/`c:` parts make an object **hollow**: only those parts are solid, so things land on a container's floor (not its roof) and the pointer reaches inside through the open doors. Still editable without code.
- Hollow: 20ft and 40ft containers (outside 6058 / 12192 x 2438 x 2591; 150 mm floor; doors open flat against the sides) and the V7E open cargo (510 mm load bed, open rear). Detailed: AU/EUR/US pallets, loaded AU pallet, crate, IBC cage, forklift (forks, carriage, mast, guard, seat, wheels), pallet jack (forks, rollers, pump, handle), and a new 2150 mm motorcycle.
- Sliding on the floor now steps up onto or down off surfaces up to 30 cm, so a pallet slid into a container rises onto its floor. Why: loading by sliding, the way you would with a pallet jack.
- Wireframes stay as lines only, so rendering cost stays negligible. 85/85 self-test checks (8 new for hollow containers, menus and palette), run locally and in CI.
- Answered: scanning real objects into wireframes is possible with the Quest 3 Passthrough Camera API, but full reconstruction is a big build. Offered corner-capture boxes (~1 h) or phone-scan glTF import (~half day) as next steps.
- Follow-up (same morning): Aurora said the V7E open cargo looked like a flatbed. It now uses the full van body (sides and roof) with only the rear open, plus a rear portal, ribs and floor boards, and it stays walk-in. She asked for a trayback version too, so I added the **Farizon F3E tray** (V7E cab, 5830 long, 3700 wheelbase): solid deck at 950 mm with drop sides, tailgate and headboard. The tray size is estimated, since none is published. 27 objects, 87/87 self-test checks.

## 2026-11-22 (Brisbane): v0.21, first versioned release (PRs #9, #10, #11 merged)

- Aurora asked to merge everything unmerged and publish a full GitHub release named v0.21 before any new features.
- #9/#10 (brush controls, measuring tools, accuracy test, room info, fit check) and #11 (Y/B clipboard menu, X/A objects, walk-in containers, detailed wireframes) were built in parallel from the same base and conflicted in 17 places in main.gd. Resolution: #10's tools and trigger carry (wrist twist, surface snap), plus #11's button layout, which matches her newest feedback. Stick click opens the main menu (tools and settings only), X/A opens the objects menu, Y/B opens the clipboard menu (now also Drop and Reset size). #11's objects list (27, no basic shapes) wins over #10's building blocks, which she later asked to remove.
- Release: a `v*` tag now builds the APK and publishes a full (non-prerelease, "latest") GitHub Release. Android version 0.21 (code 21, up from 5, so it installs over older builds and keeps rooms).
- Tests: native self-test 125/125, run locally on Godot 4.6.2.
- AI involvement: Claude did the conflict analysis, resolution, test rework and release pipeline in about 50 minutes.

## 2026-11-22 (Brisbane): v0.22, palette menus, Tools / Settings split, drawing tools, 21 new objects

- Aurora asked for: X/A and Y/B swapped (X/A = clipboard, Y/B = objects); tap a face button = menu 20 cm in front that stays like a painter's palette, hold = quick-pick on release; stick click = a Tools menu (measuring tools + Free draw), the old menu moved to the left ≡ button; Player move (left stick slide, right stick turn) for walking a big layout in a small office; Edit (pull a face along its axis); Trace, Box and Custom objects in an objects sidebar; and new objects: cartons, 10ft container, tandem trailer, 4.5 t Pantech, beds, wardrobe, kitchen bench, dryer (stackable), floating shelves at 5–30 cm plus a 50 cm spacer, and the 4 most common server racks (18/24/42/48 RU, 1200 deep).
- Decisions: Free draw kept alongside Trace (Trace = upright extrusions; Free draw = any faceted shape, e.g. ramps). Player move turns in 15° snaps (comfort in passthrough). Rotate/Move, Scale, Edit and Player move sit together in the Tools menu. Traced / drawn shapes keep their real volume (an L-shaped trace isn't counted as its box) and use their convex shape for pointing and stacking. Object categories deferred at Aurora's request.
- Tests: native self-test 161/161 (was 125), run locally on Godot 4.6.2; new checks cover tap vs hold menus, Tools / Settings menus, Player move, Edit, Box, Trace (L-shape volume), Free draw (closed cube = 0.125 m³), Custom objects, and stacking dryer on washer, shelves on a spacer, a pallet into the Pantech.
- AI involvement: Claude designed and built all of the above in one session, about 2.5 hours from "go".
