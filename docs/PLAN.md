# Framespace: Plan from first test to launch

**Product:** A Meta Quest 3 mixed-reality tool to (1) measure real objects and rooms, (2) place and design 3D objects in the room, and (3) build a wireframe map of the space and export it.
**Plan date:** 2026-11-17 · **Author:** Vesper (Claude) for Aurora

---

## 0. The short version

| Question | Answer |
|---|---|
| First thing you can test on the headset | **About 1 hour** from the moment a GitHub repo exists. |
| How | A single web page (WebXR + three.js) opened in the Quest Browser. No install, no developer mode, no build tools. |
| Time to a public launch (web app) | **About 4 to 5 weeks.** |
| Time to launch if we also need a native app | **About 9 to 11 weeks.** Only needed if the web version proves too limited (decided at Gate G2, week 3). |
| GitHub Actions cost through launch | **$0** on a public repo. **$0 to about $5 per month** on a private repo. Worst case through launch: **under $25 total.** |
| Biggest risk | Measurement accuracy is limited by the headset's sensors to roughly ±1 to 3 cm at arm's length. This is a tape-measure replacement for planning, not for machining. |

**Why web first:** The web route is the only path that gets a working build onto your headset in one hour. A Unity app needs an install of the editor (several GB), Android build tools, developer mode on the headset, and a first build that alone can take 20 to 40 minutes. The web route also covers about 80% of the features this product needs (see section 2). We switch to native only if testing proves we need what the web can't do.

---

## 1. The 1-hour fast path

**Goal:** You stand in your room, point at a table edge, click twice, and see a distance in cm and inches. You can also drop a box in the room and see the detected walls/floor drawn as wireframe.

### Who does what

| Time | Who | Step | Why |
|---|---|---|---|
| 0:00 to 0:10 | **Aurora** | On the Quest 3: Settings → Physical Space → **Space Setup**. Scan the room. | Plane detection (walls, floor, table) only returns data after a Space Setup scan. |
| 0:00 to 0:10 | **Aurora** | Create an empty GitHub repo (suggest name `framespace`, **public**). Attach it to this project. | GitHub Pages gives free HTTPS hosting. WebXR refuses to run without HTTPS. A public repo makes Actions free. |
| 0:10 to 0:35 | **Vesper** | Write one file, `index.html`: three.js loaded from a CDN, an `immersive-ar` session, hit-test reticle, point-to-point measuring, plane wireframes, place-a-box, unit toggle. Add a GitHub Pages deploy workflow. | One file with no build step means nothing to install and nothing to break. |
| 0:35 to 0:45 | **Vesper** | Push, deploy to Pages, send you the URL. | |
| 0:45 to 1:00 | **Aurora** | Open the URL in the Quest Browser → "Enter AR". Measure a door, a table, a known object. Write down the true vs. measured values. | This is our first accuracy data point and tells us if the web path is good enough. |

### What the 1-hour build does

- Passthrough AR session (you see your room).
- Reticle that sticks to real surfaces (WebXR hit-test, which on Quest 3 uses the depth sensor, works to about 5 m, and needs no scan).
- Trigger or pinch: drop point A, drop point B, show the distance as a floating label. Units: cm / m / inches / feet.
- Detected planes (floor, walls, tables) drawn as wireframe rectangles.
- Button to place a 50 cm cube you can grab and move.

### What it does not do yet

No saving, no export, no undo, no snapping. That is Phase 1. Quick and dirty, as ordered.

### If the hour goes wrong

| Symptom | Fix |
|---|---|
| "Enter AR" button missing | The page is not on HTTPS, or the Quest Browser is out of date. Update the browser. |
| No planes drawn | Space Setup was skipped, or the room permission prompt was denied. Re-run Space Setup, reload, and allow. |
| Reticle jitters | Normal on dark, shiny or glass surfaces. The depth sensor struggles there. Test on matte surfaces first. |

---

## 2. Stack decision

### What the Quest 3 can do (checked 2026-11-17)

| Capability | Web (Quest Browser, WebXR) | Native (Unity + Meta XR SDK) |
|---|---|---|
| Passthrough AR | Yes | Yes |
| Hit-test on real surfaces | Yes, depth-based, ~5 m range (Browser 40.4+) | Yes (Depth API + raycasts) |
| Plane detection (walls/floor/tables) | Yes, needs Space Setup | Yes (MR Utility Kit) |
| Full room mesh (triangle mesh of the room) | Partial. Quest Browser has exposed `mesh-detection`, but Meta's current docs don't list it. **Verify in the 1-hour test.** | Yes (MR Utility Kit global mesh) |
| Raw depth frames | No for app use | Yes (Depth API) |
| Camera pixels (for edge detection, photos, AI object recognition) | **No** | **Yes** (Passthrough Camera API: Horizon OS v74+, Quest 3/3S, up to 1728×1728, 60 Hz, 20 to 40 ms latency) |
| Anchors that survive app restarts | Yes, but **max 8 per website** | Yes, effectively unlimited (spatial anchors) |
| Hand tracking | Yes | Yes (plus Meta Interaction SDK) |
| Distribution | A URL. Can be packaged as a PWA. | Meta Horizon Store, review needed |
| Time to first test | **Minutes** | Hours (install editor, SDK, first build) |

### Decision

1. **Phase 0 to 3: Web app.** TypeScript + three.js + Vite, hosted on GitHub Pages.
   - **Why:** fastest iteration (save → reload headset in seconds), zero install for testers, free hosting, and it covers measuring, placement, plane-based wireframe, and export.
2. **Gate G2 (end of week 3): decide on native.** Go native only if one of these is true:
   - Accuracy tests fail the target (section 6) and depth frames or camera pixels would fix it.
   - We need the full room mesh and the web `mesh-detection` test failed.
   - We need more than 8 saved anchors, or AI object recognition (needs camera pixels).
3. **If native: Unity 6 LTS + Meta XR Core SDK + MR Utility Kit + Interaction SDK + Passthrough Camera API.**
   - **Why Unity over Unreal:** Meta ships its MR features to Unity first (Passthrough Camera API reached Unity at v74, Unreal at v83), the samples are Unity-first, and Android builds are lighter.
   - **Why Unity over Meta Spatial SDK (Kotlin):** larger community and tooling for 3D editing UI. Spatial SDK is a fair second choice if you prefer Android-native code.
   - **What carries over from web:** the data model, the file formats, the test fixtures and the UX. The rendering and XR code is rewritten in C#.

---

## 3. Architecture (web app)

```
index.html
src/
  app.ts            Boot, session start/stop, main loop
  xr/
    session.ts      immersive-ar session, feature requests, fallbacks
    input.ts        Controllers + hands → one "pointer" with ray, select, grab
    spatial.ts      Hit-test, planes, (mesh), anchors
  tools/            One file per tool, all share a Tool interface
    measureLine.ts  Point A → point B
    measurePath.ts  Polyline with running total
    measureArea.ts  Polygon on a plane → area + perimeter
    measureHeight.ts Floor → point vertical distance
    boxFit.ts       Draw a box around a real object → W × D × H
  design/
    primitives.ts   Box, cylinder, plane, line, text label
    transform.ts    Grab, move, rotate, scale, numeric entry
    snapping.ts     Snap to planes, edges, 90°, grid, other objects
  model/
    document.ts     The project data (section 4), undo/redo
    storage.ts      IndexedDB save/load, persistent anchor handles
  export/
    gltf.ts  obj.ts  dxf.ts  csv.ts  json.ts
  ui/
    wristMenu.ts    Menu on the left wrist/controller
    labels.ts       Floating measurement labels, always face the user
tests/
  unit/            Geometry, units, exporters (Vitest)
  e2e/             Emulated headset tests (Playwright + Meta's IWER emulator)
```

**Why this split:** Each tool is a small file behind one interface, so adding a tool never touches the others. The `model/` layer has no three.js or WebXR in it, so it can be unit-tested on a plain CI runner and ported to C# without guessing.

**Coordinate rule:** Everything is stored relative to one **room anchor** (placed at the first measurement, or on the floor). **Why:** the headset's world origin moves between sessions. An anchor does not. This also keeps us under the 8-anchor web limit: 1 room anchor per room, up to 8 rooms per device.

---

## 4. Data model and export formats

### Native file: `*.qind.json`

```json
{
  "format": "framespace", "version": 1,
  "units": "metric",
  "rooms": [{
    "id": "room-1", "name": "Garage",
    "anchorHandle": "<persistent anchor id>",
    "planes": [{ "id": "p1", "label": "floor", "polygon": [[x,y,z], ...] }],
    "mesh": { "vertices": [...], "indices": [...] },
    "measurements": [{
      "id": "m1", "type": "line", "points": [[x,y,z],[x,y,z]],
      "value": 0.762, "unit": "m", "note": "Door width",
      "createdAt": "2026-11-17T08:00:00Z"
    }],
    "objects": [{
      "id": "o1", "type": "box", "name": "Shelf",
      "position": [x,y,z], "rotation": [x,y,z,w], "size": [w,h,d],
      "color": "#c08040"
    }]
  }]
}
```

All positions are metres, relative to the room anchor, Y up. **Why metres:** that is what WebXR and glTF use, so there is no conversion bug to write. Units are a display choice only.

### Exports

| Format | Contains | Opens in | Why include it |
|---|---|---|---|
| **glTF / GLB** | Room wireframe, planes, placed objects, measurement lines | Blender, three.js, Unity, most viewers | The modern standard for 3D. Best fidelity. |
| **OBJ** | Room geometry + objects as meshes | Almost every 3D/CAD tool | Universal fallback. |
| **DXF (R12, ASCII)** | Floor plan: 2D outline of walls + measurement lines with dimensions | AutoCAD, LibreCAD, Fusion, SketchUp | The CAD world's floor-plan language. R12 is the most widely readable version. |
| **CSV** | One row per measurement: name, type, value, unit, time | Excel, Sheets | For people who only want the numbers. |
| **JSON** | The full project | This app | Lossless save and reload. |

**Getting files off the headset:** Phase 1 uses the browser's download (saved to the headset's Downloads folder; copy over USB or the Quest file manager). Phase 3 adds "Share" (Web Share API) and a QR code with a short-lived link, if needed. **Why not cloud sync from day 1:** it adds accounts, a server and privacy work for little early value.

---

## 5. Features by phase

| Phase | Length | Ships | Exit check |
|---|---|---|---|
| **P0: Fast path** | 1 hour | Section 1 | You measured something on the headset. |
| **P1: Measuring MVP** | 3 to 4 days | Vite + TypeScript project, all 5 measuring tools, units, labels, undo/redo, save/load (IndexedDB), room anchor, CSV + JSON export, unit tests in CI | Accuracy protocol (section 6.4) run once. Results logged. |
| **Gate G1** | 1 day | Review accuracy data | Within target → continue. Not → tune (averaging, snapping to planes) before P2. |
| **P2: Design / placement** | 5 to 6 days | Primitives, grab/move/rotate/scale with hands and controllers, numeric entry ("make this 120 cm"), snapping (planes, 90°, grid, edges), object library, materials/colour, glTF + OBJ export | You can block out a piece of furniture against a real wall and export it to Blender. |
| **P3: Wireframe mapping** | 5 to 6 days | Room wireframe from planes (+ mesh if available), floor-plan generation, wall lengths auto-dimensioned, DXF export, multi-room (up to 8), view modes (passthrough / wireframe / both) | Floor plan of one room opens in LibreCAD with correct wall lengths (±2 cm). |
| **Gate G2** | 1 day | Web vs. native decision (section 2) | Written decision with reasons. |
| **P4: Native app** *(only if G2 says so)* | 4 to 6 weeks | Unity port, Passthrough Camera API edge snapping, depth-frame averaging, full room mesh, unlimited anchors | Native beats web on the accuracy protocol. |
| **P5: Beta** | 1 week | 5 to 10 testers, feedback form, crash/error logging, fixes | No blocker bugs open for 3 days. |
| **P6: Launch** | 2 to 5 days (web) / 1 to 3 weeks (Store review) | Section 9 | Live. |

### Time to completion (ETA)

| Route | Calendar time | Assumptions |
|---|---|---|
| **Web launch** | **4 to 5 weeks** | Vesper builds; Aurora tests on the headset about 30 to 60 min per day and replies within a day. |
| **Web + native launch** | **9 to 11 weeks** | Same, plus Meta Store review (typically 1 to 3 weeks, not in our control). |

**Why these numbers:** each phase is small enough to test on the headset at least daily. The largest unknown is your testing turnaround, not the coding. If testing slips a day, the plan slips a day.

---

## 6. Testing phases

### 6.1 Unit tests (every push, in CI)
- Geometry: distance, polyline length, polygon area, plane projection, box fitting.
- Units: cm/m/in/ft conversion and rounding.
- Exporters: output a known scene, compare against stored "golden" files. Run Khronos `gltf-validator` on GLB output.
- **Why:** these are the parts that silently produce wrong numbers. Cheap to test, costly to get wrong.

### 6.2 Emulated headset tests (every push to main, in CI)
- Playwright (headless Chromium) + Meta's **Immersive Web Emulation Runtime (IWER)**, which fakes a Quest 3 with controllers, hands and planes.
- Scripted flows: enter AR → measure → save → reload → value matches → export.
- **Why:** catches "button does nothing" and crash bugs before you put the headset on.

### 6.3 On-device smoke test (every deploy, Aurora, ~5 min)
Enter AR, measure one known object, place one box, save, reload, export. Checklist kept in the repo (`TESTING.md`).

### 6.4 Accuracy protocol (end of P1, P3, P4; Aurora, ~30 min)
- 10 fixed references measured with a steel tape: e.g. A4 sheet (29.7 cm), door width, door height, table length, room wall.
- Measure each 3 times at 0.5 m, 1 m, 2 m, 3 m distance, with controller and with hand.
- Log in a CSV template (provided in repo). CI script computes mean error and spread.
- **Targets:** ≤ 1 cm error under 1 m, ≤ 2 cm at 1 to 3 m, ≤ 2% beyond 3 m.
- **Why these targets:** they match what the Quest 3 depth and tracking hardware can realistically do. Better than this needs a laser measure, not a headset.
- **Known weak spots:** glass, mirrors, black or shiny surfaces, low light, and points beyond ~5 m (depth range limit).

### 6.5 Performance test (end of P2 and P3)
- Frame rate holds 72 fps (target 90) with 200 objects and a full room wireframe. Measured with the browser's performance overlay / OVR Metrics Tool.
- **Why:** dropped frames in AR cause discomfort and jittery labels.

### 6.6 Usability test (end of P2, during beta)
- 3 to 5 people, no instructions, 4 tasks: measure a door, find the room area, place a shelf, export a floor plan. Note where they get stuck.
- **Why:** XR menus that seem obvious to the builder are often invisible to everyone else.

### 6.7 Export validation (end of P3)
- Open each export in Blender, LibreCAD, a glTF viewer and Excel. Check scale and orientation (most common bug: Y-up vs Z-up, metres vs millimetres).

### 6.8 Beta (P5)
- 5 to 10 testers on their own Quest 3/3S, 1 week. In-app "Report a problem" button that copies a debug log.

### 6.9 Release checklist (P6)
Privacy policy live, error logging working, accuracy disclaimer shown on first launch, all CI green, smoke test passed on a freshly reset browser.

---

## 7. GitHub Actions: workflows and cost

### Prices used (checked 2026-11-17, GitHub docs)

| Runner | Price per minute |
|---|---|
| Linux 2-core x64 | $0.006 |
| Linux 2-core arm64 | $0.005 |
| Windows 2-core | $0.010 |
| macOS | $0.062 |

- **Public repos: standard runners are free.**
- Private repos: included minutes per month on personal plans are **2,000 (GitHub Free)** and **3,000 (GitHub Pro)**, and GitHub has said these quotas stay the same. *(These two figures are from my knowledge, not the page I checked. Verify in your billing settings.)*
- Minutes round up per job.
- The planned $0.002/min fee on self-hosted runners was **postponed**, so it does not apply.

**We use Linux runners only. Why:** cheapest, and nothing in this project needs Windows or macOS (Quest apps are Android builds, which Linux can produce).

### Workflows

| Workflow | Trigger | Minutes per run | Runs per month (est.) | Minutes per month |
|---|---|---|---|---|
| `ci.yml`: lint, typecheck, unit tests, exporter goldens | every push / PR | 2 | 200 | 400 |
| `e2e.yml`: Playwright + IWER emulator | push to main, PRs | 5 | 100 | 500 |
| `deploy.yml`: build + publish to GitHub Pages | push to main | 1 | 100 | 100 |
| `accuracy.yml`: compute accuracy stats from your CSV | when the CSV changes | 1 | 10 | 10 |
| **Web phases total** | | | | **~1,010** |
| `unity-build.yml` *(P4 only)*: Android APK via GameCI, cached | merges to main + tags | 20 | 40 | 800 |
| **Native phase total** | | | | **~1,810** |

### Cost

| Repo type | Web phases (P0 to P3, P5, P6) | Native phase (P4) | Total through launch |
|---|---|---|---|
| **Public** | $0 | $0 | **$0** |
| Private, GitHub Free (2,000 min) | $0 (1,010 < 2,000) | $0 (1,810 < 2,000) | **$0** |
| Private, worst case (double the runs, no free minutes left) | ~2,000 min × $0.006 = **$12/month** | ~3,600 min × $0.006 = **$22/month** | **under $25** for the expected 1 to 2 months over quota, at most |

**Storage:** APK artifacts (~100 to 200 MB each) kept 3 days only. **Why:** artifact storage is billed on private repos and old builds have no use. Caches (Unity's Library folder, npm) use the separate free 10 GB cache allowance.

**Recommendation: make the repo public.** **Why:** Actions is free, GitHub Pages is free, and nothing in a measuring tool is secret. If you need it private, the cost is still about zero.

### Other costs (not GitHub, for completeness)

| Item | Cost | Needed when |
|---|---|---|
| Domain name (optional) | ~$12/year | Launch, if you want a nice URL |
| Meta developer account | Free | P4 / Store |
| Unity Personal | Free (under the revenue cap) | P4 only |
| Unity license in CI | Free with a Personal license file; GameCI documents the setup | P4 only |

---

## 8. Interaction design

- **Pointer:** controller ray or hand ray, same behaviour. **Why:** testers will switch between them constantly.
- **Select:** trigger or pinch. **Grab:** grip or fist. **Undo:** B button or a wrist-menu button.
- **Wrist menu (left hand):** tool picker, units, save, export, view mode. **Why:** always reachable, never blocks the view, standard in Quest apps.
- **Labels:** float at the midpoint of a measurement, always face you, scale with distance so they stay readable.
- **Snapping, on by default:** to planes, 90° angles and existing points. Hold the grip to turn it off. **Why:** snapping is the single biggest accuracy gain for hand input.
- **Precision mode:** hold still for 0.5 s on a point and the app averages the last 15 hit results. **Why:** averaging cuts reticle jitter.
- **Comfort:** no forced camera movement, no flashing, labels at least 0.5 m away.

---

## 9. Launch

### Web launch (default)
1. Custom domain on GitHub Pages (optional), HTTPS on.
2. PWA manifest so it can be "installed" from the Quest Browser.
3. Optional: list the PWA in the Meta Horizon Store (Meta supports packaged PWAs; confirm current requirements at that time).
4. Landing page with a 30-second video and the accuracy disclaimer.
5. Privacy policy. **Why:** the app reads room geometry, which counts as user data, even though we keep it on the device.

### Native launch (only if P4 happens)
1. Meta Developer Dashboard: create app, upload APK through the release channels (alpha → beta → production).
2. Pass Meta's technical requirements (performance, permissions, comfort).
3. Camera use: a clear permission explanation and policy compliance. Camera images count as user data under Meta's developer data policy.
4. Expect 1 to 3 weeks of review.

---

## 10. Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Accuracy worse than ±2 cm | Medium | High | Snapping, averaging, plane-projection. Gate G1. Native depth/camera at G2. Clear disclaimer. |
| Web room mesh unavailable | Medium | Medium | Wireframe from planes works without it. Full mesh moves to native. |
| 8-anchor web limit | Low | Low | 1 anchor per room; store everything relative to it. |
| Quest Browser update breaks a feature | Low to medium | Medium | Daily smoke test; feature detection with graceful fallback. |
| Tracking drift over large rooms | Medium | Medium | Re-anchor per room; warn when you move > 5 m from the anchor. |
| Store review delay (native) | Medium | Low | Web launch does not depend on it. |
| Unity licensing in CI (native) | Low | Low | GameCI documented flow; fallback is local builds. |
| Your testing time | Medium | High | Daily 30-min test window is the plan's pacing item. |

---

## 11. What I need from you to start

1. **Run Space Setup** on the Quest 3 in the room you'll test in.
2. **Create a GitHub repo** (public recommended, e.g. `framespace`) and **attach it to this project** so I can push to it.
3. **Say "go"**, and the 1-hour clock starts.

*Questions I am deciding for you unless you object:* metric units by default (inch toggle included), public repo, web-first. Each choice and reason is above.
