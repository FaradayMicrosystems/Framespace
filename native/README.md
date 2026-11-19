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
5. **First launch.** Allow the **Spatial data** permission. Framespace needs it to see your walls and tables and to keep rooms anchored in place.

Updates install over the top and keep your saved rooms, because every build is signed with the same key (`framespace-sideload.keystore`).
Uninstalling the app deletes its saved rooms.

## Controls

| Do this | Get this |
|---|---|
| **Click a thumbstick** | Main menu, attached to that hand. Point and trigger with the other hand. Click again to close it |
| **Click both thumbsticks** | Main menu, fixed in front of you |
| Point + **trigger** | Select a shape / press a button |
| Point + **grip**, push or pull | Scale the shape (push = bigger, pull = smaller, x2 per 20 cm) |
| **Grip + trigger** on a shape | Slide it along the floor, snapped to the grid |
| **Grip + trigger + B** | Pick it up freely. Let go and it drops onto the floor, a table or another shape, squared to the grid |
| Stick **up / down** while holding | Scale +5% / -5% |
| Stick **left / right** while holding | Rotate 45° clockwise / counter-clockwise |
| Hold **A** on a shape | Cut / Copy / Delete / Duplicate |
| Hold **A** on empty space | Paste / Next clip |
| Hold **X** | Object palette from [`objects.csv`](../objects.csv) (shared with the web app): pallets, containers, IBC, forklift, door, car, person and more |
| Yellow / orange cubes on a selected shape | Drag with trigger to resize one side / the radius |

The main menu has the tools (tape, circle, move/size), units, grid, undo, clipboard, room lines, room scan, clear, save room, **Rooms...** (load, new, delete), export and quit.
There is no "Exit AR" button: a native app has no separate AR mode, so **Quit app** is how you leave.

## Rooms

- Everything you place is **auto-saved** to the current room about half a second after each change.
- Each room is pinned to a **Meta spatial anchor** on the floor where you created it. When you load a room, it reappears in the same physical spot.
- **Rooms...** in the menu lists your saved rooms. Pick one to load it. You can also start a **New room** or **Delete this room**.
- If the headset can't find the anchor (another location, or you cleared Space Setup), the room still loads, placed relative to where you are standing.

## Boundary

The app declares `com.oculus.feature.BOUNDARYLESS_APP` and requires passthrough, so the guardian boundary is off while it runs. The CI build fails if the manifest is missing either one.
Grid snapping doesn't use the boundary. The grid follows the room anchor, which is square to the direction you faced when the room was created.

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
