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
| 07:23 | Pushed, CI + GitHub Pages deploy set up. | Claude |

## Effort split

- **Aurora:** about 6 short chat messages, created one repo. Roughly 10 minutes of attention.
- **Claude:** research, plan, all code, tests, CI, deployment, docs.
- **Elapsed:** about 20 minutes from request to a deployed, tested build.

## What a person would normally spend

A rough, conventional estimate for the same scope by one experienced WebXR developer: 1 day of research and planning, 3 to 5 days to build and test the prototype. Treat this as an estimate, not a measurement.

## Honest caveats

- Tested in an emulator so far. First on-headset test is the real proof.
- Accuracy is limited by the Quest 3 sensors (about ±1 to 3 cm at arm's length), not by the software.
