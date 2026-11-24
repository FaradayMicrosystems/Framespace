// End-to-end test of Framespace in an emulated Quest 3 (Meta IWER) under headless Chromium.
const { chromium } = require('playwright');
const http = require('http'), fs = require('fs'), path = require('path');
const ROOT = process.argv[2] || path.join(__dirname, '..');
const types = { '.html': 'text/html', '.js': 'text/javascript', '.json': 'application/json', '.csv': 'text/csv' };
const server = http.createServer((req, res) => {
  const p = path.join(ROOT, decodeURIComponent(req.url.split('?')[0]).replace(/\/$/, '/index.html'));
  fs.readFile(p, (e, b) => { if (e) { res.writeHead(404); res.end(); return; } res.writeHead(200, { 'content-type': types[path.extname(p)] || 'application/octet-stream' }); res.end(b); });
}).listen(8765);

const results = [];
const check = (name, ok, info = '') => { results.push({ name, ok }); console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${info ? '  — ' + info : ''}`); };

fs.mkdirSync(path.join(__dirname, '..', 'test-results'), { recursive: true });
(async () => {
  const browser = await chromium.launch({ ...(process.env.PW_CHROMIUM ? { executablePath: process.env.PW_CHROMIUM } : {}), args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const page = await browser.newPage({ viewport: { width: 1000, height: 800 }, acceptDownloads: true });
  const errors = [];
  page.on('pageerror', e => errors.push(e.message));
  page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
  await page.goto('http://localhost:8765/?emulate');
  await page.waitForFunction(() => !document.getElementById('enter').disabled, null, { timeout: 15000 });
  check('Enter AR button enabled (immersive-ar supported)', true);
  await page.click('#enter');
  await page.waitForFunction(() => window.__framespace.controllers.every(c => c.userData.inputSource), null, { timeout: 10000 });
  check('AR session started, both controllers connected', true);

  const wait = (n = 6) => page.waitForTimeout(n * 40);
  // Aim a controller from `from` at world point `to`.
  const aim = (hand, from, to) => page.evaluate(([hand, from, to]) => {
    const { THREE } = window.__framespace, d = window.__xrDevice.controllers[hand];
    const f = new THREE.Vector3(...from), t = new THREE.Vector3(...to);
    const m = new THREE.Matrix4().lookAt(f, t, new THREE.Vector3(0, 1, 0));
    const q = new THREE.Quaternion().setFromRotationMatrix(m);
    d.position.set(...from); d.quaternion.set(q.x, q.y, q.z, q.w);
  }, [hand, from, to]);
  const press = async (hand) => { await page.evaluate(h => window.__xrDevice.controllers[h].updateButtonValue('trigger', 1), hand); await wait(); };
  const release = async (hand) => { await page.evaluate(h => window.__xrDevice.controllers[h].updateButtonValue('trigger', 0), hand); await wait(); };
  const click = async (hand) => { await press(hand); await release(hand); };
  const buttonWorld = (id) => page.evaluate((id) => {
    const { THREE, panel } = window.__framespace;
    const rows = [['box','sphere','cylinder','cone'],['tape','circle','select','units'],['copy','cut','paste','nextclip'],['duplicate','drop','delete','undo'],['room','clear','pin','exit']];
    let r, c; rows.forEach((row, i) => { const j = row.indexOf(id); if (j >= 0) { r = i; c = j; } });
    const W = 1024, H = 980, HEADER = 230, ROW_H = 150, bw = (W - 40) / 4;
    const px = 20 + c * bw + bw / 2, py = HEADER + r * ROW_H + ROW_H / 2;
    const w = 0.3, h = 0.3 * H / W;
    const local = new THREE.Vector3((px / W - 0.5) * w, (0.5 - py / H) * h, 0);
    panel.mesh.updateMatrixWorld(true);
    const world = panel.mesh.localToWorld(local.clone());
    const front = panel.mesh.localToWorld(local.clone().add(new THREE.Vector3(0, 0, 0.25)));
    return { world: world.toArray(), front: front.toArray() };
  }, id);
  const btnS = (hand, id, v) => page.evaluate(([h, id, v]) => window.__xrDevice.controllers[h].updateButtonValue(id, v), [hand, id, v]);
  // Click both thumbsticks together: main menu fixed in front of you.
  const openFixedMenu = async () => {
    await btnS('left', 'thumbstick', 1); await wait(2); await btnS('left', 'thumbstick', 0); await wait(2);
    await btnS('right', 'thumbstick', 1); await wait(2); await btnS('right', 'thumbstick', 0); await wait(2);
  };
  const menuOpen = () => page.evaluate(() => window.__framespace.state.menuVisible);
  const menu = async (id) => { if (!(await menuOpen())) await openFixedMenu(); const b = await buttonWorld(id); await aim('right', b.front, b.world); await wait(); await click('right'); };
  const S = () => page.evaluate(() => {
    const { state } = window.__framespace;
    return { shapes: state.shapes.map(s => ({ name: s.name, dims: { ...s.dims }, pos: s.group.position.toArray() })), measures: state.measures.length, clip: state.clipboard.length, mode: state.mode, status: state.status, selected: state.selected?.name };
  });

  const btn = (hand, id, v) => page.evaluate(([h, id, v]) => window.__xrDevice.controllers[h].updateButtonValue(id, v), [hand, id, v]);
  const stick = (hand, x, y) => page.evaluate(([h, x, y]) => window.__xrDevice.controllers[h].updateAxes('thumbstick', x, y), [hand, x, y]);
  const box1 = () => page.evaluate(() => { const s = window.__framespace.state.shapes[0]; return { pos: s.group.position.toArray(), dims: { ...s.dims }, yaw: new window.__framespace.THREE.Euler().setFromQuaternion(s.group.quaternion, 'YXZ').y * 180 / Math.PI }; });
  const resetBox = () => page.evaluate(() => { const s = window.__framespace.state.shapes[0]; s.dims = { x: 0.3, y: 0.3, z: 0.3 }; s.group.position.set(0, 0.15, -1); s.group.quaternion.identity(); });
  const near = (a, b, tol = 0.006) => Math.abs(a - b) < tol;
  const onGrid = v => near(v / 0.05, Math.round(v / 0.05), 0.01);
  const popupTile = (which, index) => page.evaluate(([which, index]) => {
    const { THREE } = window.__framespace, p = window.__framespace[which];
    const w = p.canvas.width, h = p.canvas.height, col = index % p.cols, row = Math.floor(index / p.cols);
    const local = new THREE.Vector3((10 + col * 260 + 130) / w - 0.5, 0.5 - (90 + row * 180 + 90) / h, 0);
    p.mesh.updateMatrixWorld(true);
    return { world: p.mesh.localToWorld(local.clone()).toArray(), front: p.mesh.localToWorld(local.clone().add(new THREE.Vector3(0, 0, 0.25))).toArray() };
  }, [which, index]);

  await wait(10);
  check('Menu starts closed (no floating panel)', !(await menuOpen()));
  await btnS('left', 'thumbstick', 1); await wait(2); await btnS('left', 'thumbstick', 0); await wait(2);
  const att = await page.evaluate(() => window.__framespace.state.menuVisible && window.__framespace.state.menuAttach?.userData.inputSource.handedness);
  check('Stick click opens the menu on that hand', att === 'left', String(att));
  await btnS('left', 'thumbstick', 1); await wait(2); await btnS('left', 'thumbstick', 0); await wait(2);
  check('Stick click again closes it', !(await menuOpen()));
  await openFixedMenu();
  check('Both sticks: menu fixed in front', await page.evaluate(() => window.__framespace.state.menuVisible && !window.__framespace.state.menuAttach));
  // 1. Add a box with a real ray click on the tools menu.
  await menu('box');
  let s = await S();
  check('Menu click via controller ray adds a box', s.shapes.length === 1 && s.selected === 'Box 1', s.status);
  await resetBox(); await wait();

  // 2. Grip + trigger slides the box along the floor on the grid.
  await aim('right', [0.2, 1.0, -0.2], [0, 0.15, -1]); await wait();
  await btn('right', 'squeeze', 1); await wait(); await btn('right', 'trigger', 1); await wait();
  await aim('right', [0.52, 1.0, -0.2], [0.32, 0.15, -1]); await wait(8);
  let b = await box1();
  check('Grip + trigger slides the shape, snapped to the 5 cm grid', onGrid(b.pos[0]) && near(b.pos[0], 0.3, 0.03) && near(b.pos[1], 0.15), `pos=${b.pos.map(v => v.toFixed(3))}`);
  // 3. Stick while holding: left = 45° clockwise, up = +5%.
  await stick('right', -1, 0); await wait(); await stick('right', 0, 0); await wait();
  b = await box1();
  check('Stick left rotates 45° clockwise (seen from above)', near(b.yaw, -45, 0.5), `yaw=${b.yaw.toFixed(1)}°`);
  await stick('right', 1, 0); await wait(); await stick('right', 0, 0); await wait();
  b = await box1();
  check('Stick right rotates 45° counter-clockwise', near(b.yaw, 0, 0.5), `yaw=${b.yaw.toFixed(1)}°`);
  await stick('right', 0, -1); await wait(); await stick('right', 0, 0); await wait();
  b = await box1();
  check('Stick up scales +5%', near(b.dims.x, 0.315, 0.0005) && near(b.pos[1] - b.dims.y / 2, 0, 0.003), `W=${b.dims.x}, bottom=${(b.pos[1] - b.dims.y / 2).toFixed(3)}`);
  await stick('right', 0, 1); await wait(); await stick('right', 0, 0); await wait();
  b = await box1();
  check('Stick down scales -5% (back exactly)', near(b.dims.x, 0.3, 0.0005), `W=${b.dims.x}`);
  await btn('right', 'trigger', 0); await btn('right', 'squeeze', 0); await wait();

  // 4. Grip alone grabs to move: pushing / lifting the hand never changes the size.
  await resetBox(); await wait();
  await aim('right', [0, 0.9, -0.2], [0, 0.15, -1]); await wait();
  await btn('right', 'squeeze', 1); await wait();
  const dir = [0, -0.75, -0.8], len = Math.hypot(...dir), f = 0.2 / len;
  await aim('right', [0, 0.9 + dir[1] * f, -0.2 + dir[2] * f], [0, 0.15 + dir[1] * f, -1 + dir[2] * f]); await wait(8);
  await aim('right', [0, 1.4, -0.2], [0, 0.65, -1]); await wait(8);
  await btn('right', 'squeeze', 0); await wait();
  b = await box1();
  check('Grip alone moves only: pushing and lifting never resize', b.dims.x === 0.3 && b.dims.y === 0.3 && b.dims.z === 0.3, `dims=${JSON.stringify(b.dims)}`);
  // Trigger on a yellow resize cube while gripping must not start a resize.
  await resetBox(); await page.evaluate(() => { const { state } = window.__framespace; state.selected = null; }); await wait();
  await aim('right', [0, 0.9, -0.3], [0, 0.15, -1]); await wait(); await click('right');
  const hpos = await page.evaluate(() => { const s = window.__framespace.state.shapes[0]; const h = s.handles.find(h => h.userData.handle.axis.y > 0.5) || s.handles[0]; s.group.updateMatrixWorld(true); return h.getWorldPosition(new window.__framespace.THREE.Vector3()).toArray(); });
  await aim('right', [hpos[0], hpos[1] + 0.6, hpos[2] + 0.3], hpos); await wait();
  await btn('right', 'squeeze', 1); await wait(); await btn('right', 'trigger', 1); await wait();
  await aim('right', [hpos[0], hpos[1] + 0.9, hpos[2] + 0.3], [hpos[0], hpos[1] + 0.3, hpos[2]]); await wait(8);
  await btn('right', 'trigger', 0); await btn('right', 'squeeze', 0); await wait();
  b = await box1();
  check('Grip + trigger on a resize cube never resizes', b.dims.x === 0.3 && b.dims.y === 0.3 && b.dims.z === 0.3, `dims=${JSON.stringify(b.dims)}`);

  // 5. Grip + trigger + B: free pick-up, then drop to the floor on release.
  await resetBox(); await wait();
  await aim('right', [0.2, 1.0, -0.2], [0, 0.15, -1]); await wait();
  await btn('right', 'squeeze', 1); await wait(); await btn('right', 'trigger', 1); await wait(); await btn('right', 'b-button', 1); await wait();
  await aim('right', [0.27, 1.6, -0.2], [0.07, 0.75, -1]); await wait(8);
  b = await box1();
  check('Holding B lifts the shape freely', b.pos[1] > 0.6, `y=${b.pos[1].toFixed(2)}`);
  await btn('right', 'b-button', 0); await btn('right', 'trigger', 0); await btn('right', 'squeeze', 0);
  await page.waitForTimeout(1200);
  b = await box1();
  check('Released shape falls to the floor and snaps to the grid', near(b.pos[1], 0.15, 0.003) && onGrid(b.pos[0]) && onGrid(b.pos[2]), `pos=${b.pos.map(v => v.toFixed(3))}`);

  // 6. Hold X: shape palette; trigger on "EUR pallet" with the right controller and drop it in.
  await aim('left', [-0.25, 1.1, -0.3], [-0.25, 1.1, -1.0]); await wait();
  await btn('left', 'x-button', 1); await wait();
  check('Holding X opens the shape palette', await page.evaluate(() => window.__framespace.palette.open));
  const tile = await popupTile('palette', 1);
  await aim('right', tile.front, tile.world); await wait();
  await btn('right', 'trigger', 1); await wait();
  await btn('left', 'x-button', 0); await wait();
  await aim('right', [0.6, 1.1, -0.6], [1.0, 0.6, -1.6]); await wait(8);
  await btn('right', 'trigger', 0); await page.waitForTimeout(1200);
  s = await S();
  const crate = s.shapes[s.shapes.length - 1];
  check('Palette shape is grabbed, carried and dropped on the floor', s.shapes.length === 2 && near(crate.dims.x, 1.2) && near(crate.pos[1], 0.072, 0.003), `${crate.name} at ${crate.pos.map(v => v.toFixed(2))}`);
  check('Releasing X closes the palette', !(await page.evaluate(() => window.__framespace.palette.open)));
  const pal = await page.evaluate(() => window.__framespace.PALETTE.map(p => [p.label, p.dims]));
  const pallet = pal.find(p => p[0] === 'AU pallet');
  check('Palette loads objects.csv (163 objects incl. AU pallet 1165 mm)', pal.length === 163 && pallet && near(pallet[1].x, 1.165) && near(pallet[1].z, 1.165), `${pal.length} objects`);
  const van = await page.evaluate(() => window.__framespace.PALETTE.find(p => p.label === 'Farizon V7E open cargo'));
  check('Farizon V7E has a van outline and 2 wheels', van && van.outline.pts.length === 10 && van.outline.wheels.length === 2 && near(van.dims.x, 4.995));
  const open = await page.evaluate(() => window.__framespace.PALETTE.find(p => p.label === 'Farizon V7E open cargo'));
  check('V7E open cargo is the whole van with the internal load box', open && near(open.dims.y, 1.985) && open.outline.inner.length === 1 && open.outline.wheels.length === 2);
  check('Palette shape is named after its object', crate.name === 'EUR pallet 1', crate.name);

  // 7. Hold A on a shape: context menu → Copy. Hold A on empty floor → Paste.
  await resetBox(); await wait();
  await aim('right', [0, 0.9, -0.3], [0, 0.15, -1]); await wait();
  await btn('right', 'a-button', 1); await page.waitForTimeout(400); await btn('right', 'a-button', 0); await wait();
  check('Holding A on a shape opens Cut/Copy/Delete', await page.evaluate(() => window.__framespace.ctxMenu.open && window.__framespace.ctxMenu.items.map(i => i.id).join() === 'cut,copy,delete,duplicate,pin'));
  const near_hand = await page.evaluate(() => { const { ctxMenu, ctxLink, controllers, THREE } = window.__framespace; const r = controllers.find(c => c.userData.inputSource.handedness === 'right'); return ctxMenu.mesh.position.distanceTo(new THREE.Vector3().setFromMatrixPosition(r.matrixWorld)) < 0.5 && ctxLink.visible; });
  check('Object menu opens near the hand, dotted line to the object', near_hand);
  let t2 = await popupTile('ctxMenu', 1);
  await aim('right', t2.front, t2.world); await wait(); await click('right');
  s = await S(); check('Context Copy puts the shape on the clipboard', s.clip === 1, s.status);
  await aim('right', [-0.6, 1.0, -0.3], [-0.9, 0, -1.5]); await wait();
  await btn('right', 'a-button', 1); await page.waitForTimeout(400); await btn('right', 'a-button', 0); await wait();
  t2 = await popupTile('ctxMenu', 0);
  await aim('right', t2.front, t2.world); await wait(); await click('right');
  s = await S();
  const pasted = s.shapes[s.shapes.length - 1];
  check('Hold A on empty floor → Paste drops a copy there', s.shapes.length === 3 && near(pasted.pos[1], 0.15, 0.003) && near(pasted.pos[0], -0.9, 0.06), `${pasted.name} at ${pasted.pos.map(v => v.toFixed(2))}`);
  await aim('right', [-0.9, 0.9, -0.6], [-0.9, 0.15, -1.5]); await wait();
  await btn('right', 'a-button', 1); await page.waitForTimeout(400); await btn('right', 'a-button', 0); await wait();
  t2 = await popupTile('ctxMenu', 2);
  await aim('right', t2.front, t2.world); await wait(); await click('right');
  s = await S(); check('Context Delete removes the shape', s.shapes.length === 2, s.status);
  await menu('undo');
  s = await S(); check('Undo restores the deleted shape', s.shapes.length === 3);

  // 7b. Hold A → Pin: the shape can't be grabbed, saves as pinned, and Unpin frees it.
  await resetBox(); await wait();
  const holdA = async () => { await aim('right', [0, 0.9, -0.3], [0, 0.15, -1]); await wait(); await btn('right', 'a-button', 1); await page.waitForTimeout(400); await btn('right', 'a-button', 0); await wait(); };
  await holdA();
  t2 = await popupTile('ctxMenu', 4);
  await aim('right', t2.front, t2.world); await wait(); await click('right');
  let pinned = await page.evaluate(() => window.__framespace.sceneData().shapes[0].pinned === true && window.__framespace.state.shapes[0].handles.length === 0);
  check('Context Pin pins the shape (saved, no resize handles)', pinned);
  await aim('right', [0.2, 1.0, -0.2], [0, 0.15, -1]); await wait();
  await btn('right', 'squeeze', 1); await wait(); await btn('right', 'trigger', 1); await wait();
  await aim('right', [0.52, 1.0, -0.2], [0.32, 0.15, -1]); await wait(8);
  await btn('right', 'trigger', 0); await btn('right', 'squeeze', 0); await wait();
  b = await box1(); s = await S();
  check('A pinned shape cannot be grabbed or moved', near(b.pos[0], 0) && near(b.pos[2], -1) && /pinned/.test(s.status), s.status);
  await holdA();
  check('Pinned shape offers Unpin', await page.evaluate(() => window.__framespace.ctxMenu.items[4].label === 'Unpin'));
  t2 = await popupTile('ctxMenu', 4);
  await aim('right', t2.front, t2.world); await wait(); await click('right');
  await aim('right', [0.2, 1.0, -0.2], [0, 0.15, -1]); await wait();
  await btn('right', 'squeeze', 1); await wait(); await btn('right', 'trigger', 1); await wait();
  await aim('right', [0.52, 1.0, -0.2], [0.32, 0.15, -1]); await wait(8);
  await btn('right', 'trigger', 0); await btn('right', 'squeeze', 0); await wait();
  b = await box1();
  check('Unpin makes it grabbable again', near(b.pos[0], 0.3, 0.03) && !(await page.evaluate(() => window.__framespace.state.shapes[0].pinned)), `x=${b.pos[0].toFixed(3)}`);
  await resetBox(); await wait();

  // 8. Y no longer toggles a menu (the stick menu replaced it).
  const before = await menuOpen();
  await btn('left', 'y-button', 1); await wait(); await btn('left', 'y-button', 0); await wait();
  check('Y does nothing to the menu', (await menuOpen()) === before);

  // 9. Tape measure on the floor.
  await menu('tape');
  await aim('right', [-1, 1.0, -1.2], [-1, 0, -2]); await wait(); await click('right');
  await aim('right', [-0.5, 1.0, -1.2], [-0.5, 0, -2]); await wait(); await click('right');
  const m = await page.evaluate(() => window.__framespace.sceneData().measurements[0]);
  check('Tape measure on the floor', m && near(m.distance_m, 0.5, 0.005), m ? `${m.distance_m.toFixed(4)} m` : 'none');
  // 10. Circle 3-pt on the floor, r = 0.2 m.
  await menu('circle');
  for (const [x, z] of [[-0.8, -2.5], [-1, -2.3], [-1.2, -2.5]]) { await aim('right', [x, 1, z + 0.6], [x, 0, z]); await wait(); await click('right'); }
  const circ = await page.evaluate(() => window.__framespace.sceneData().measurements[1]);
  check('Circle 3-pt gives radius', circ && near(circ.radius_m, 0.2, 0.005), circ ? `r=${circ.radius_m.toFixed(4)}` : 'none');
  await menu('select');
  await menu('units');
  const unitsStatus = (await S()).status;
  check('Units toggle works', /imperial/.test(unitsStatus), unitsStatus);
  await menu('units');

  // 7. Exit and export.
  await menu('exit');
  await page.waitForTimeout(500);
  const report = await page.textContent('#report');
  check('Report shows measurements and shapes after exit', /M1/.test(report) && /Box 1/.test(report));
  const csv = await page.evaluate(() => window.__framespace.toCSV(window.__framespace.sceneData()));
  check('CSV export has header + rows', csv.split('\n').length >= 5, csv.split('\n')[0].slice(0, 60) + '…');
  const [dl] = await Promise.all([page.waitForEvent('download', { timeout: 10000 }), page.click('#dl-glb')]);
  const glbPath = await dl.path(); const glb = fs.readFileSync(glbPath);
  check('GLB export downloads a valid glTF binary', glb.slice(0, 4).toString() === 'glTF', `${glb.length} bytes`);
  await page.screenshot({ path: path.join(__dirname, '..', 'test-results', 'report.png'), fullPage: true });

  check('No JavaScript errors', errors.length === 0, errors.slice(0, 3).join(' | '));
  await browser.close(); server.close();
  const failed = results.filter(r => !r.ok).length;
  console.log(`\n${results.length - failed}/${results.length} checks passed`);
  process.exit(failed ? 1 : 0);
})().catch(e => { console.error(e); server.close(); process.exit(2); });
