// End-to-end test of Framespace in an emulated Quest 3 (Meta IWER) under headless Chromium.
const { chromium } = require('playwright');
const http = require('http'), fs = require('fs'), path = require('path');
const ROOT = process.argv[2] || path.join(__dirname, '..');
const types = { '.html': 'text/html', '.js': 'text/javascript', '.json': 'application/json' };
const server = http.createServer((req, res) => {
  const p = path.join(ROOT, decodeURIComponent(req.url.split('?')[0]).replace(/\/$/, '/index.html'));
  fs.readFile(p, (e, b) => { if (e) { res.writeHead(404); res.end(); return; } res.writeHead(200, { 'content-type': types[path.extname(p)] || 'application/octet-stream' }); res.end(b); });
}).listen(8765);

const results = [];
const check = (name, ok, info = '') => { results.push({ name, ok }); console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${info ? '  — ' + info : ''}`); };

fs.mkdirSync(path.join(__dirname, '..', 'test-results'), { recursive: true });
(async () => {
  const browser = await chromium.launch({ args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
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
  const menu = async (id) => { const b = await buttonWorld(id); await aim('right', b.front, b.world); await wait(); await click('right'); };
  const S = () => page.evaluate(() => {
    const { state } = window.__framespace;
    return { shapes: state.shapes.map(s => ({ name: s.name, dims: { ...s.dims }, pos: s.group.position.toArray() })), measures: state.measures.length, clip: state.clipboard.length, mode: state.mode, status: state.status, selected: state.selected?.name };
  });

  await wait(10);
  // 1. Add a box with a real ray click on the menu.
  await menu('box');
  let s = await S();
  check('Menu click via controller ray adds a box', s.shapes.length === 1 && s.selected === 'Box 1', s.status);
  // Move box to a known place for the following steps.
  await page.evaluate(() => { const b = window.__framespace.state.shapes[0]; b.group.position.set(0, 1.0, -1.0); b.group.quaternion.identity(); });
  await wait();

  // 2. Grab and move.
  await aim('right', [0.2, 1.0, -0.2], [0, 1.0, -1.0]);
  await wait(); await press('right');
  await aim('right', [0.5, 1.0, -0.2], [0.3, 1.0, -1.0]);
  await wait(8); await release('right');
  s = await S();
  check('Grab with trigger moves the box', Math.abs(s.shapes[0].pos[0] - 0.3) < 0.05, `x=${s.shapes[0].pos[0].toFixed(3)}`);
  await page.evaluate(() => { const b = window.__framespace.state.shapes[0]; b.group.position.set(0, 1.0, -1.0); b.group.quaternion.identity(); });
  await wait();

  // 3. Drag the +x handle (at x = 0.15 + 0.015) out to x = 0.35 → width ≈ 0.5.
  await aim('right', [0.165, 1.0, -0.5], [0.165, 1.0, -1.0]);
  await wait(); await press('right');
  await aim('right', [0.35, 1.0, -0.5], [0.35, 1.0, -1.0]);
  await wait(8); await release('right');
  s = await S();
  check('Dragging the +X handle resizes width', Math.abs(s.shapes[0].dims.x - 0.5) < 0.02, `W=${s.shapes[0].dims.x}`);

  // 4. Tape measure between two points on the box front face (z = -0.85).
  await menu('tape');
  await aim('right', [-0.1, 1.0, -0.3], [-0.1, 1.0, -1.0]); await wait(); await click('right');
  await aim('right', [0.1, 1.05, -0.3], [0.1, 1.05, -1.0]); await wait(); await click('right');
  s = await S();
  const m = await page.evaluate(() => window.__framespace.sceneData().measurements[0]);
  check('Tape measure creates a measurement', s.measures === 1 && m && Math.abs(m.distance_m - Math.hypot(0.2, 0.05)) < 0.01, m ? `${m.distance_m.toFixed(4)} m (expected ${Math.hypot(0.2, 0.05).toFixed(4)})` : 'none');

  // 5. Circle 3-pt directly via measurement API correctness (points on a 10 cm radius circle).
  await menu('circle');
  for (const [x, y] of [[0.1, 0], [0, 0.1], [-0.1, 0]]) { await aim('right', [x, 1 + y, -0.3], [x, 1 + y, -1.0]); await wait(); await click('right'); }
  const circ = await page.evaluate(() => window.__framespace.sceneData().measurements[1]);
  check('Circle 3-pt gives radius', circ && Math.abs(circ.radius_m - 0.1) < 0.005, circ ? `r=${circ.radius_m.toFixed(4)}` : 'none');

  // 6. Copy / paste / cut / undo.
  await menu('select');
  await aim('right', [0.0, 1.0, -0.3], [0.0, 1.0, -1.0]); await wait(); await click('right');   // select box
  await menu('copy');
  s = await S(); check('Copy puts the shape on the clipboard', s.clip === 1, s.status);
  await aim('left', [0.6, 1.0, -0.3], [0.8, 0.0, -1.0]); await wait();   // left hand points at the floor
  await menu('paste');
  s = await S(); check('Paste creates a copy where the other hand points', s.shapes.length === 2 && Math.abs(s.shapes[1].dims.x - 0.5) < 0.02, `${s.shapes[1]?.name} at ${s.shapes[1]?.pos.map(v => v.toFixed(2))}`);
  check('Pasted shape sits on the floor', s.shapes[1] && Math.abs(s.shapes[1].pos[1] - 0.15) < 0.03, `y=${s.shapes[1]?.pos[1].toFixed(3)}`);
  await menu('cut');
  s = await S(); check('Cut removes the shape and keeps it on clipboard', s.shapes.length === 1 && s.clip === 2);
  await menu('undo');
  s = await S(); check('Undo restores the cut shape', s.shapes.length === 2);
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
