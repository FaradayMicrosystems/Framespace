# Framespace

Measure, design and wireframe real spaces on **Meta Quest 3**, right in the browser. No install.

**Open on the headset:** https://faradaymicrosystems.github.io/Framespace/

## What it does (prototype 0.1)

- **Wireframe shapes over passthrough:** box, sphere, cylinder, cone. Grab to move, drag the yellow/orange handles to resize. Live labels show width, height, depth, radius and **volume**.
- **Tape measure** that lands on real surfaces (Quest depth sensor) and on virtual shapes. Shows total, vertical and horizontal distance. Snaps to corners and earlier points.
- **Circle 3-pt:** tap three points on a round edge to get diameter, radius and circumference.
- **Cut / Copy / Paste** with a 5-item clipboard. **Undo** for everything.
- **Room wireframe:** walls, floor and tables from Space Setup, each labelled with its size and area.
- **Export:** CSV (spreadsheets), JSON (full data) and GLB (3D, opens in Blender / CAD viewers).
- Metric and imperial units.

## Use it

1. On the Quest 3: **Settings → Physical Space → Space Setup** (once per room).
2. Open the Quest Browser, go to the URL above, press **Enter AR**.
3. Controls are listed on the page. Point and press trigger (or pinch) for everything.
4. **Exit AR** to see the report and download files.

## Develop

No build step. Edit `index.html` / `app.js`, push to `main`, and GitHub Pages redeploys in about a minute.

```bash
npm install && npx playwright install chromium
npm test          # runs the app in an emulated Quest 3 (Meta IWER) and checks 17 behaviours
```

Desktop try-out: open the page with `?emulate` to load the Quest 3 emulator.

## Docs

- [Full plan: development to launch, costs, testing](docs/PLAN.md)
- [Build log](BUILD_LOG.md)

Third-party: three.js (MIT) and Meta IWER (MIT), vendored in `vendor/`.
