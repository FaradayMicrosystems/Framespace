# Framespace v0.32 (Quest 3 APK)

**Install:** download `framespace.apk` below and sideload it over v0.31. It keeps your saved rooms.

27 changes, all from Aurora's list: off-grid power you can lay out, trailers that hitch on, and bigger sites.

## New: Hitch snap (trailers hitch on)
- **Drop a trailer with its coupling within about 75 cm of a tow point and it snaps on.** It lines up straight behind the vehicle, the coupling sits on the tow point, and the wheels sit on the same ground as the vehicle's. The status says "hitched to ...".
- **Hitched trailers move with the vehicle.** Pick up or slide the ute or prime mover and the trailer comes too, along with everything loaded on it. A B-double moves as one: prime mover, then the A-trailer, then the B-trailer.
- **To unhitch, pick up the trailer and put it down away from the tow point.**
- **Tow bars** on the Toyota Hilux, Chery Stockman, Farizon V7E open cargo, Farizon F3E tray, Farizon H9E and Polaris Ranger take **ball couplings**: the box trailers, the cage trailer, the Solar Kart and the tiny home trailer.
- **Fifth wheels** take **kingpins**. They are on the Windrose prime mover, and at the back of the 20ft container A-trailer and the battery A-trailer.
- **objects.csv** has a new `hitch` column (`tow:` / `ball:` / `fifth:` / `pin:` x/y in mm), so you can give any object a tow point.

## New: Cable run tool (design your power layout)
- **Tools menu (stick click) > Cable run** (orange).
  - Point at the first device (panel, battery, inverter, switchboard) and press trigger.
  - Press trigger at each bend.
  - Press trigger on the last device twice to finish.
- **The label shows** the cable length, which devices it runs between (for example "Pylontech US5000 → Victron MultiPlus-II 48/5000"), and an order length with 10% slack added.
- **Export** includes each cable's length and its from / to devices.

## Power
- **Small camping batteries removed:** EcoFlow RIVER 3 (with its extra batteries), DELTA 3 Plus, DELTA 3 Max Plus, all DJI Power units and the Dune solar blanket.
- **Kept big systems:** DELTA Pro 3, DELTA Pro Ultra, Anker F3800 Plus + BP3800, and the home batteries.
- **Modular off-grid kit (real parts):**
  - Pylontech US5000 rack battery (4.8 kWh)
  - battery rack holding 4 x US5000 (19.2 kWh)
  - Victron MultiPlus-II 48/5000 and 48/10000 inverter/chargers (wall mount)
  - Victron SmartSolar MPPT 250/100 (wall mount)
  - PV isolator / combiner box
  - a 550 W panel on a ground frame, to line up into arrays
- **Freestanding pole arrays with shade underneath:** 1.1 kW (2 x 550 W on 4 posts) and 4.95 kW (9 x 550 W on 6 posts). Both have 2.4 m clearance underneath.
- **OFFGRID NOW Solar Kart** (made in Cooroy, QLD): a 2400 x 1500 single-axle trailer with 2.9 kW of panels, a 5 kW inverter and 10 kWh of battery. It hitches on.
- **Wind turbines:**
  - Primus AIR 40 (1.17 m rotor) on a 6 m pole
  - Aeolos-H 1 kW (3.2 m rotor) on a 9 m guyed tower
  - Aeolos-H 3 kW (4.8 m rotor) on a 9 m guyed tower

## Workshop
- **CNC:**
  - Shapeoko 5 Pro 4x4 router. Its footprint is 1524 x 1499 mm and it cuts 1237 x 1237. It's drawn on an 850 mm bench, which we added.
  - Langmuir CrossFire PRO plasma table, 1753 x 1372 mm. Its height is an estimate.
- **Formlabs Form 4** desktop-industrial resin printer, 398 x 367 x 554 mm. The Giga and the Fuse 1+ are already in.
- **Moved into Workshop:**
  - the server racks (the Racks category is gone)
  - all the industrial wall and ceiling gear: pegboard, wall cabinet, fold-down bench, cantilever rack, hose and lead reels, distribution board, fume arm, exhaust fans, gas bracket, steel shelving, high bay, chain hoist and ceiling reels
  - These still stick to walls and ceilings as before.
- **Rolling workbench rebuilt:** 1230 long (was 1880).
  - It's the drawer stack plus one tilt-out drawer right beside it, with no gap.
  - The push handle is at the tilt-out drawer end.
  - If the handle is on the wrong end compared with yours, say so and I'll mirror it.

## Storage (new category, Bunnings)
- **Heavy-duty waterproof tubs:**
  - Ezy Storage Bunker Tough 55L, 80L and 160L (the biggest)
  - Inabox Heavy Duty 65L
  - Keter Marvel Plus 270L
  - Keter Rockwood 570L
- **Rhino site box 1175 x 755 x 850** (Bunnings Trade): a steel lock box with forklift skids, so you can carry it with the forklift.

## Trailers and vehicles
- **Single-axle box trailer 6x4:** the small version of the tandem.
- **Tandem cage trailer 8x5:** a 900 mm mesh cage with an open rear gate.
- **Toyota Hilux SR dual-cab tray:** a walk-in tray you can load.
- **Windrose R700 electric prime mover:** the size is estimated, because Windrose doesn't publish dimensions.
- **Battery A-trailer:** a generic design, because Windrose sells no battery trailer that I could find.
- **Containers on skel trailers:**
  - a walk-in 20ft container on an A-trailer, with a fifth wheel at the back
  - a walk-in 40ft container on a B-trailer
  - Both snap onto the Windrose, or the B-trailer onto the A-trailer.

## Buildings and portable structures
- **Machinery barn 12 x 18 m:** 4.5 m walls and a fully open front.
- **More structures:**
  - two hard-top gazebos, 3.6 x 3 m and 4.8 x 3.6 m
  - an inflatable work shelter, 6 x 4 m
  - a site shelter tent, 6 x 3 m
  - a 6-post shade structure, 9 x 6 m
- **Tiny home trailer (Cabintech The Bach):**
  - **Folded:** 7.15 x 2.25 m for towing. It hitches on.
  - **Expanded:** 6.3 m wide, about 21 m² inside, and you can walk in.

## Test on the headset (feedback I need)
1. **Hilux + box trailer:**
   - Drop the 6x4 trailer near the Hilux tow bar. Does it snap on, straight behind?
   - Slide the Hilux. Does the trailer follow?
   - Pick the trailer up and put it down away from the ute. Does it unhitch?
2. **B-double:**
   - Hitch the 20ft A-trailer to the Windrose, then the 40ft B-trailer to the A-trailer.
   - Move the Windrose. Does the whole set follow?
3. **Cable run:** run a cable from a panel to the MPPT, then to the battery rack. Is the length right, and are the from / to names right?
4. **Rolling workbench:** is the tilt-out drawer and handle on the right side compared with yours?
5. **Sizes:** do the Windrose and the battery trailer look about right? Both are estimates.
