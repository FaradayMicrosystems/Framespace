# Framespace native (Quest 3 app)

This is a native Quest 3 app (APK), so it doesn't use the browser. It works fully offline, saves rooms, and has no guardian boundary.
Built with Godot 4.6.2 and Meta's official OpenXR plugin (GodotOpenXRVendors 5.0.0).

## Get the APK

- **Latest release (v0.22):** [Releases > latest](https://github.com/FaradayMicrosystems/Framespace/releases/latest), file `framespace.apk`. Direct link: https://github.com/FaradayMicrosystems/Framespace/releases/latest/download/framespace.apk
- **Newest build from `main` (may be ahead of the release):** [Releases > native-latest](https://github.com/FaradayMicrosystems/Framespace/releases/tag/native-latest), file `framespace.apk`.
- **Any branch or PR:** Actions > "Native Quest APK" > pick a run > Artifacts > `framespace-quest-apk` (a zip that holds the APK).

## Sideload it (one-time setup, then about 1 minute per update)

1. **Developer mode.** On your phone, open the Meta Horizon app > Devices > your Quest 3 > Headset settings > Developer mode > On. If it asks you to create a developer organisation, make one (free) at https://developers.meta.com/horizon/ and then try again.
2. **Connect.** Plug the Quest into your PC with a USB-C data cable. In the headset, accept **Allow USB debugging** (tick "Always allow from this computer").
3. **Install, with either tool:**
   - **Meta Quest Developer Hub (MQDH)**, for Windows or Mac: https://developers.meta.com/horizon/downloads/package/oculus-developer-hub-win (or the Mac version). Open Device Manager and drag `framespace.apk` onto "Apps". Or
   - **SideQuest (Advanced installer)**: https://sidequestvr.com/setup-howto. Click the "Install APK file from folder" icon and choose `framespace.apk`.
4. **Launch.** In the headset, open Library > filter **Unknown Sources** > **Framespace**.
5. **First launch.** Allow the **Spatial data** permission. Framespace needs it to see your walls and tables.

Updates install over the top and keep your saved rooms, because every build is signed with the same key (`framespace-sideload.keystore`).
Uninstalling the app deletes its saved rooms.

## Controls

Think brush and canvas: point at things, pick them up with the trigger, put them down where you want.

| Do this | Get this |
|---|---|
| **Click a thumbstick** | **Tools** menu, 70 cm in front of that controller (stays put); point and pull the trigger to pick (it closes): Rotate/Move, Scale, Edit, Player move, the measuring tools and Reset position. Click again to close without picking |
| **Click both thumbsticks** | Tools menu, fixed in front of you |
| **Left ≡ button** | **Settings** menu, stuck to the left hand: units, grid, room lines, scan, save, Rooms..., export, clear, Turn room, Accuracy test, Room info, Fit check, quit |
| **X** or **A** | **Clipboard** menu. Pointing at a shape: Cut / Copy / Delete / Duplicate / **Pin** / Drop / **Bigger 5%** / **Smaller 5%** / **Reset size** / **Undo**. On empty space: Paste (where you pointed) / Next clip / Undo |
| **Y** or **B** | **Objects** menu from [`objects.csv`](../objects.csv), with a sidebar: **Trace**, **Box**, **Custom...**, **Save selected** |
| **Tap** X / A / Y / B | X / A: the clipboard menu pops up 20 cm in front of that controller and **stays put**. Y / B: the objects menu pops up **70 cm in front of that controller** and stays there; trigger-grab objects from it, tap again to close. Picking from it doesn't close it (the clipboard menu follows whatever you select). Tap the same button again to close it |
| **Hold** X / A / Y / B | Quick-pick. X / A: point at an item **with the same hand** and **let go of the button** to pick it. Y / B: letting go picks nothing; the menu stays up until you **trigger-grab** one object, then it closes. The menu closes. An object you quick-pick hangs on your pointer: click the trigger to put it down |
| **Rotate/Move:** hold **trigger** on an object | Pick it up. It hangs on your pointer. **Twist your wrist** to turn it. **Touch a surface** and it snaps to the grid on top of it, turning in 15° steps. Let go to place it; let go in mid-air and it falls onto whatever is below |
| **Rotate/Move:** quick trigger **tap** on an object | Select it (nothing moves) |
| **Grip** on an object | Slide it on the grid, staying on its floor (steps up onto floors up to 30 cm high, e.g. into a container) |
| **Grip + trigger** | Lift it off the floor (same as a trigger carry) |
| Stick **left / right** while holding | Turn it smoothly (gentle near the centre, fast at full tilt) |
| Stick **forward / back** while holding | Push it away / pull it in, continuously |
| **Scale** tool | Trigger an object, then trigger-drag its yellow / orange cubes to resize one side / the radius |
| **Edit** tool | Point at a face (it outlines in yellow), hold trigger and **pull**: that face moves along its axis, the opposite face stays put (1 mm steps). Round shapes: top/bottom = height, sides = radius |
| **Player move** tool | **Left stick** slides you through the wireframe, **right stick** left/right turns you smoothly, up/down raises or lowers you smoothly (the room moves, your real office doesn't). Grabbing still works. Tools > **Reset position** puts the room back where it really is |

**Two-hand resize:** carry an object with one hand, then grab it with the other (trigger). Pull your hands apart or together to stretch it along that direction (smooth, no snapping); turn your hands around each other to turn it. Let go with the second hand and the size locks in. Undo reverses the whole adjustment.

**Objects from the menu** appear at least 3 m away (their nearest edge), still on your pointer; pull them in with the stick.

**X / A with your hand inside an object** targets that object, not whatever the ray points at.

**Drawing with the controller tip** (a yellow dot shows the tip; points snap to corners within 2.5 cm):
- **Box** (objects sidebar): put the tip on one corner, hold trigger, pull to the opposite corner, let go. Or click, move, click. Grip cancels.
- **Trace** (objects sidebar): click each corner of the outline (or hold trigger and draw freehand), click the first corner again to close it, then **point** the controller up or down to set the height (the ray, not your reach, sets it) and click. You get a solid shape with the traced outline; its volume is the real shape's, not its box. Grip undoes the last point.
- **Trace / Box are toggles:** the sidebar button says ON while it's active; tap it again to turn it off and go back to Rotate/Move.

**Custom objects:** select any object (a trace, a box, a resized pallet...), open the objects menu (Y / B) and press **Save selected**. **Custom...** shows your saved objects; pick one to place a copy. **Remove: on** deletes them. They're kept on the headset between sessions.

**Walk-in loading:** the 10ft / 20ft / 40ft containers, the V7E open cargo, the F3E tray, the tandem trailer and the 4.5 t Pantech are hollow. Pin one, walk in, and drop or slide pallets onto its floor. Things dropped from above land on the roof.

**Shelving:** **Shelf 5 … 30 cm** are 900 × 250 floating boards (25 mm) at the top of a gap that tall, so stacking them puts boards that far apart. **Shelf spacer 50 cm** is a flat panel 50 cm up. Stack spacer + shelves to build a wall of shelves; things stand on the boards.

**Measuring tools** (Tools menu, yellow): **Tape**, **Circle 3-pt** (radius/diameter), **Rect 3-pt** (two corners + the far edge: W × D, area, perimeter), **Height** (point to floor), **Angle 3-pt** (arm, corner, arm), **Path** (multi-leg total; tap the last point again to finish), **Area** (tap an outline, tap the first point to close: area + perimeter). Points snap to corners and existing points.

There is no "Exit AR" button: a native app has no separate AR mode, so **Quit app** is how you leave.

## Accuracy test

Menu > **Accuracy test...** measures things whose true size you know, so you get a real error figure.

1. Pick a reference: A4 sheet (long 297 mm / short 210 mm), bank card (85.6 mm), door leaf height (2040 mm) or width (820 mm), or **Custom length** (tape-measure it first, then set it with the -100 … +100 mm buttons).
2. Tap its two ends with the trigger (same snapping as Tape). The label shows measured mm and the error; the status shows the running average.
3. Repeat as often as you like; switch references from the menu. Results are kept between sessions.
4. **Export results** writes `framespace-accuracy-<time>.csv` to `Download/Framespace/` (per-trial rows, then a summary: trials, average error mm and %, RMS, worst, bias, average distance from your head). **Clear results** starts over (Undo brings them back).

## Room info and Fit check

- Menu > **Room info...** shows the room from your Space Setup scan: floor size and area (L-shaped rooms use the real outline), ceiling height, room volume, wall count and perimeter, doors, windows and furniture. It's in the JSON export too (`room_scan`).
- **Fit check** (on by default, in the main menu and on the Room info page): any object that pushes more than 2 cm into a wall, the ceiling, a piece of scanned furniture or another object turns **red**, and its label says what it hits ("DOESN'T FIT: hits wall face"). It updates live while you carry things. Sitting on the floor, or flush against a wall or another object, is fine.

## Rooms

- Everything you place is **auto-saved** to the current room about half a second after each change.
- **Rooms...** in the menu lists your saved rooms. Pick one to load it. You can also start a **New room** or **Delete this room**.

### Putting a room back in place (default: where you stand)

A room is saved relative to **the spot you stood on and the way you faced** when you created it. It loads on the floor where you are standing, facing the way you look. To get it back exactly where it was:

1. Pick a spot you can find again, such as a mark on the floor or the corner of a rug, and a direction to face, such as a wall or a door frame.
2. Create the room standing there, facing that way.
3. Next time, stand on the same spot, face the same way, and **hold the Meta button to recenter**. The room snaps back into place.

Small errors in where you stand or which way you face carry straight into the room: 2 cm off on the floor is 2 cm off everywhere, and 1° off in heading is about 3.5 cm off at 2 m away. A floor mark and a clear target to face help most.

**Rooms... > Place room here** does the same as recentering, without leaving the app.

If the room or its grid is still a little off square after recentering, use **Turn room 1° / 5° left / right** in the main menu. It turns the whole room and grid around the spot you're standing on. Your saved layout isn't changed.

## Boundary

The app declares `com.oculus.feature.BOUNDARYLESS_APP` and requires passthrough, so the guardian boundary is off while it runs. The CI build fails if the manifest is missing either one.
Grid snapping doesn't use the boundary. The grid follows the room, which is square to the direction you faced when the room was created.

Real limits:
- Boundaryless only works in passthrough. If the system drops you into VR (a system dialog, for example), the boundary can come back until you return to the app.
- Tracking quality, not the boundary, limits how far you can walk. In big or featureless spaces, tracking can drift.
- Tape points land on real surfaces from **Space Setup** (walls, floor, furniture and the room mesh), with the floor as a fallback. If you haven't run Space Setup, use menu > **Scan room**.

## Exports

**Export** in the menu writes CSV, JSON and GLB to the headset's `Download/Framespace/` folder, and copies the CSV to the clipboard.
To get the files off the headset, use MQDH's file browser or plug in USB and open `Quest 3/Internal shared storage/Download/Framespace`.
If Android blocks the Download folder, the files go to the app's own storage instead, and the status line shows the path.

## Develop

- `scripts/main.gd` holds the whole app. `scripts/ui_panel.gd` draws the menus. `scripts/scene_anchor.gd` handles real surfaces from Space Setup.
- `scripts/selftest.gd` is a headless test that CI runs before every build: `godot --headless --path native -- --selftest`.
- The Meta plugin isn't committed. CI downloads it into `addons/`. For local work, unzip `godotopenxrvendorsaddon.zip` (5.0.0-stable) so it ends up at `native/addons/godotopenxrvendors`.
- Signing: `framespace-sideload.keystore` (password `framespace-sideload`) is committed on purpose. It's only for sideloading, and keeping it fixed lets updates install over the top. Make a private key before any store release.

**Pinned objects are locked:** no moving, resizing, cut, copy, duplicate or delete (Clear all skips them) until you Unpin them from the X / A menu.
