# Framespace

Measure, design and wireframe real spaces on **Meta Quest 3**, right in the browser. No install.

**Open on the headset:** https://faradaymicrosystems.github.io/Framespace/

**Native app (offline, saved rooms, no boundary):** see [native/README.md](native/README.md). Download the APK from the [latest release](https://github.com/FaradayMicrosystems/Framespace/releases/latest) (v0.21a) and sideload it.

## Controls (Touch controllers, either hand)

| Do this | Get this |
|---|---|
| Point + **trigger** | Select a shape / press a button |
| **Click a thumbstick** | Main menu on that hand (click both: fixed in front of you). Click again to close |
| Point + **grip** (or grip + trigger) on a shape | Slide it along the floor, snapped to the grid. Grabbing never changes its size |
| **Grip + trigger + B** | Pick it up freely. Let go and it drops onto the floor, a table or another shape, squared to the grid |
| Stick **up / down** while holding | Scale +5% / -5% |
| Stick **left / right** while holding | Rotate 45° clockwise / counter-clockwise |
| Hold **A** on a shape | Cut / Copy / Delete / Duplicate / **Pin** (a pinned shape can't be grabbed, moved or resized until you Unpin it) |
| Hold **A** on empty space | Paste / Next clip |
| Hold **X** | Object palette (37 true-scale objects: pallets, IBC, drum, racking, forklift, door, car, person...): point at one with the other controller, trigger or grip, drop it in |
| Yellow / orange cubes on a selected shape | Drag with trigger alone to resize one side / the radius. Ignored while you're gripping or holding anything |

The grid (5 cm default; 1 cm, 10 cm or off in the tools menu) is aligned to the direction you face when you recenter the headset.

## What it does

- **Wireframe shapes over passthrough** with live width, height, depth, radius and **volume** labels.
- **Tape measure** that lands on real surfaces (Quest depth sensor) and on shapes. Shows total, vertical and horizontal distance. Snaps to corners.
- **Circle 3-pt:** three points on a round edge give diameter, radius and circumference.
- **Cut / Copy / Paste** with a 5-item clipboard. **Undo** for everything.
- **Room wireframe:** walls, floor and tables from Space Setup, labelled with size and area.
- **Export:** CSV, JSON and GLB (3D).

## Editing the object palette

Everything in the Hold-X palette comes from one file: [`objects.csv`](objects.csv). Both the web app and the native Quest app read it, so one edit updates both.

- **Add an object:** add a line. **Remove:** delete the line. **Reorder:** move lines (the palette shows them in file order).
- Sizes are in **millimetres**. `shape` is `box` (fill length, width, height), `cylinder` or `cone` (fill diameter, height) or `sphere` (fill diameter).
- Do not put commas inside a value. Lines starting with `#` are ignored. A line with a missing size is skipped.
- Opens fine in Excel or Google Sheets; save as CSV.
- Edit it on GitHub (pencil icon) and commit to `main`: the web app updates in about a minute, the native APK rebuilds in about 10 minutes.

Example: `Shopping trolley,box,950,560,1000,,Typical supermarket trolley`

**Vehicle-shaped wireframes (optional, boxes only):** three extra columns draw a shape inside the box instead of plain box edges. The object still measures, snaps and scales as its outer box.
- `outline`: side-view points `x/y x/y ...` in mm (x back from the front, y up from the ground), at least 3.
- `wheels`: `x/diameter ...` in mm (wheels touch the ground, so the object stands at true ride height).
- `inner`: `x/y/length/width/height` in mm for a box drawn inside, e.g. a cargo area (y = floor height).

See the two `Farizon V7E` lines in `objects.csv` for a worked example.

## Develop

No build step. Edit `index.html` / `app.js`, push to `main`, and GitHub Pages redeploys in about a minute.

```bash
npm install && npx playwright install chromium
npm test          # runs the app in an emulated Quest 3 (Meta IWER) and checks 31 behaviours
```

Desktop try-out: open the page with `?emulate` to load the Quest 3 emulator.

## Docs

- [Full plan: development to launch, costs, testing](docs/PLAN.md)
- [Build log](BUILD_LOG.md)

Third-party: three.js (MIT) and Meta IWER (MIT), vendored in `vendor/`.
