# Framespace native (Quest 3 app)

This is a native Quest 3 app (APK), so it doesn't use the browser. It works fully offline, saves rooms, and has no guardian boundary.
Built with Godot 4.6.2 and Meta's official OpenXR plugin (GodotOpenXRVendors 5.0.0).

## Get the APK

- **Latest build from `main`:** [Releases > native-latest](https://github.com/FaradayMicrosystems/Framespace/releases/tag/native-latest), file `framespace.apk`.
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
| **Click a thumbstick** | The menu, fixed in front of you: a **4×8 tools sidebar** on the left and, in Move/Scale, the **object tray** on the right. Click again to close it |
| Trigger on a **tray object** (or grip) | It's in your hand; the menu closes. Let go to place it |
| **X or A** | Quick tool menu by your hand: Move/Scale, Cut, Copy, Paste, Duplicate, Delete, Reset size, Drop, Pin, Next clip |
| Hold **B or Y** (½ s) | Undo |
| **Move/Scale:** hold **trigger** on an object | Pick it up. It hangs on your pointer. **Twist your wrist** to turn it. **Touch a surface** (floor, table, another object's top) and it snaps to the grid on top of it, turning in 15° steps. Let go to place it; let go in mid-air and it falls onto whatever is below |
| **Move/Scale:** quick trigger **tap** on an object | Select it (nothing moves) |
| **Grip** on an object | Slide it on the grid, staying on its floor/surface |
| Stick **up / down** while holding | Scale +5% / -5% |
| Stick **left / right** while holding | Turn 45° |
| Yellow / orange cubes on a selected shape | Trigger-drag to resize one side / the radius (Move/Scale only) |
| **Cut / Copy / Duplicate / Delete / Reset size / Drop / Pin** tool | Trigger on an object does that. Cut and Copy switch you to Paste |
| **Paste** tool | Trigger where you want the clipboard item. Next clip cycles the clipboard |
| **Reset size** | Back to the size it was created with (from the tray or objects.csv) |

**Measuring tools** (sidebar, yellow): **Tape**, **Circle 3-pt** (radius/diameter), **Rect 3-pt** (two corners + the far edge: W × D, area, perimeter), **Height** (point to floor), **Angle 3-pt** (arm, corner, arm), **Path** (multi-leg total; tap the last point again to finish), **Area** (tap an outline, tap the first point to close: area + perimeter). Points snap to corners and existing points.

The sidebar also has units, grid, undo, room lines, room scan, save, **Rooms...** (load, new, delete), export, clear, place room here, quit and **Turn room** (5° or 1°, left or right).
There is no "Exit AR" button: a native app has no separate AR mode, so **Quit app** is how you leave.

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
