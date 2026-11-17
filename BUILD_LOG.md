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
