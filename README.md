# Framespace

Measure, design and wireframe real spaces on **Meta Quest 3**, right in the browser. No install.

**Open on the headset:** https://faradaymicrosystems.github.io/Framespace/

## Controls (Touch controllers, either hand)

| Do this | Get this |
|---|---|
| Point + **trigger** | Select a shape / press a button |
| Point + **grip**, push or pull | Scale the shape (push = bigger, pull = smaller, x2 per 20 cm) |
| **Grip + trigger** on a shape | Slide it along the floor, snapped to the grid |
| **Grip + trigger + B** | Pick it up freely. Let go and it drops onto the floor, a table or another shape, squared to the grid |
| Stick **up / down** while holding | Scale +5% / -5% |
| Stick **left / right** while holding | Rotate 45° clockwise / counter-clockwise |
| Hold **A** on a shape | Cut / Copy / Delete / Duplicate |
| Hold **A** on empty space | Paste / Next clip |
| Hold **X** | Shape palette: point at one with the other controller, trigger or grip, drop it in |
| **Y** | Show / hide the tools menu (tape, circle 3-pt, units, grid, undo, room, export) |
| Yellow / orange cubes on a selected shape | Drag with trigger to resize one side / the radius |

The grid (5 cm default; 1 cm, 10 cm or off in the tools menu) is aligned to the direction you face when you recenter the headset.

## What it does

- **Wireframe shapes over passthrough** with live width, height, depth, radius and **volume** labels.
- **Tape measure** that lands on real surfaces (Quest depth sensor) and on shapes. Shows total, vertical and horizontal distance. Snaps to corners.
- **Circle 3-pt:** three points on a round edge give diameter, radius and circumference.
- **Cut / Copy / Paste** with a 5-item clipboard. **Undo** for everything.
- **Room wireframe:** walls, floor and tables from Space Setup, labelled with size and area.
- **Export:** CSV, JSON and GLB (3D).

## Develop

No build step. Edit `index.html` / `app.js`, push to `main`, and GitHub Pages redeploys in about a minute.

```bash
npm install && npx playwright install chromium
npm test          # runs the app in an emulated Quest 3 (Meta IWER) and checks 27 behaviours
```

Desktop try-out: open the page with `?emulate` to load the Quest 3 emulator.

## Docs

- [Full plan: development to launch, costs, testing](docs/PLAN.md)
- [Build log](BUILD_LOG.md)

Third-party: three.js (MIT) and Meta IWER (MIT), vendored in `vendor/`.
