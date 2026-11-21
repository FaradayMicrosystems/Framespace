// Framespace prototype: wireframe design + measuring over passthrough on Meta Quest 3.
// Single module, no build step. three.js is vendored in ./vendor.
import * as THREE from 'three';
import { GLTFExporter } from './vendor/GLTFExporter.js';

const BUILD = '0.2.0';
const STORE_KEY = 'framespace-v1';
const V3 = THREE.Vector3;
const UP = new V3(0, 1, 0);
const MIN_SIZE = 0.01;          // 1 cm smallest dimension
const SNAP_SURFACE = 0.03;      // shapes snap to floor/tables within 3 cm
const SNAP_POINT = 0.025;       // tape points snap to corners/points within 2.5 cm
const CLIP_MAX = 5;

document.getElementById('build').textContent = BUILD;

// ---------------------------------------------------------------- emulator (desktop testing only)
const params = new URLSearchParams(location.search);
if (params.has('emulate')) {
  const { XRDevice, metaQuest3 } = await import('./vendor/iwer.module.js');
  const device = new XRDevice(metaQuest3);
  device.installRuntime({ forceInstall: true });
  window.__xrDevice = device;
}

// ---------------------------------------------------------------- renderer / scene
const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
renderer.setPixelRatio(window.devicePixelRatio);
renderer.setSize(innerWidth, innerHeight);
renderer.setClearColor(0x000000, 0);
renderer.xr.enabled = true;
renderer.xr.setReferenceSpaceType('local-floor');
document.getElementById('xr-host').appendChild(renderer.domElement);

const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(70, innerWidth / innerHeight, 0.01, 60);
camera.position.set(0, 1.6, 0);

const state = {
  units: 'metric',
  mode: 'select',          // select | tape | circle
  roomVisible: true,
  menuPinned: false,
  menuVisible: false,
  menuAttach: null,   // controller the menu rides on; null = fixed in front of you
  grid: 0.05,             // metres; 0 = off
  falling: [],
  selected: null,
  shapes: [],
  measures: [],
  clipboard: [],
  clipIndex: 0,
  history: [],
  pending: [],             // tape/circle points in progress
  pendingDots: [],
  status: 'Pick a shape or a measuring tool.',
  counters: { box: 0, sphere: 0, cylinder: 0, cone: 0, m: 0 },
  lastCtrl: null,
};

// ---------------------------------------------------------------- formatting
function L(m) {
  if (state.units === 'metric') return m < 1 ? `${(m * 100).toFixed(1)} cm` : `${m.toFixed(3)} m`;
  const inch = m / 0.0254;
  if (inch < 36) return `${inch.toFixed(2)} in`;
  const ft = Math.floor(inch / 12);
  return `${ft} ft ${(inch - ft * 12).toFixed(1)} in`;
}
function VOL(m3) {
  if (state.units === 'metric') return m3 < 1 ? `${(m3 * 1000).toFixed(2)} L` : `${m3.toFixed(3)} m³`;
  return `${(m3 * 35.3147).toFixed(3)} ft³ (${(m3 * 264.172).toFixed(2)} gal)`;
}
function AREA(m2) {
  return state.units === 'metric' ? `${m2.toFixed(2)} m²` : `${(m2 * 10.7639).toFixed(1)} ft²`;
}

// ---------------------------------------------------------------- canvas labels
function makeLabel(width = 0.26) {
  const canvas = document.createElement('canvas');
  canvas.width = 768; canvas.height = 220;
  const tex = new THREE.CanvasTexture(canvas);
  tex.colorSpace = THREE.SRGBColorSpace;
  const sprite = new THREE.Sprite(new THREE.SpriteMaterial({ map: tex, depthTest: false, transparent: true }));
  sprite.scale.set(width, width * 220 / 768, 1);
  sprite.renderOrder = 20;
  return { canvas, tex, sprite, key: '' };
}
function setLabel(label, lines, accent = '#00e5ff') {
  const key = lines.join('|') + accent;
  if (key === label.key) return;
  label.key = key;
  const c = label.canvas, g = c.getContext('2d');
  g.clearRect(0, 0, c.width, c.height);
  g.fillStyle = 'rgba(8,10,14,0.78)';
  roundRect(g, 4, 4, c.width - 8, c.height - 8, 28); g.fill();
  g.strokeStyle = accent; g.lineWidth = 5; g.stroke();
  const rowH = (c.height - 24) / lines.length;
  lines.forEach((t, i) => {
    let size = i === 0 ? 58 : 50;
    g.font = `${i === 0 ? 700 : 500} ${size}px system-ui, sans-serif`;
    while (g.measureText(t).width > c.width - 48 && size > 20) { size -= 2; g.font = `${i === 0 ? 700 : 500} ${size}px system-ui, sans-serif`; }
    g.fillStyle = i === 0 ? accent : '#ffffff';
    g.textBaseline = 'middle';
    g.fillText(t, 24, 12 + rowH * (i + 0.5));
  });
  label.tex.needsUpdate = true;
}
function roundRect(g, x, y, w, h, r) {
  g.beginPath(); g.moveTo(x + r, y); g.arcTo(x + w, y, x + w, y + h, r); g.arcTo(x + w, y + h, x, y + h, r);
  g.arcTo(x, y + h, x, y, r); g.arcTo(x, y, x + w, y, r); g.closePath();
}

// ---------------------------------------------------------------- shapes
function sphereWire(segments = 12, rings = 6) {
  const pts = [];
  const circle = (fn) => { for (let i = 0; i < 48; i++) { pts.push(fn(i / 48 * Math.PI * 2), fn((i + 1) / 48 * Math.PI * 2)); } };
  for (let s = 0; s < segments; s++) {
    const a = s / segments * Math.PI;
    circle(t => new V3(Math.cos(a) * Math.sin(t) * 0.5, Math.cos(t) * 0.5, Math.sin(a) * Math.sin(t) * 0.5));
  }
  for (let r = 1; r < rings; r++) {
    const phi = r / rings * Math.PI, y = Math.cos(phi) * 0.5, rad = Math.sin(phi) * 0.5;
    circle(t => new V3(Math.cos(t) * rad, y, Math.sin(t) * rad));
  }
  return new THREE.BufferGeometry().setFromPoints(pts);
}
const UNIT_GEO = {
  box: new THREE.BoxGeometry(1, 1, 1),
  sphere: new THREE.SphereGeometry(0.5, 24, 16),
  cylinder: new THREE.CylinderGeometry(0.5, 0.5, 1, 24, 1),
  cone: new THREE.ConeGeometry(0.5, 1, 24, 1),
};
const WIRE_GEO = {
  box: new THREE.EdgesGeometry(UNIT_GEO.box),
  sphere: sphereWire(),
  cylinder: new THREE.EdgesGeometry(new THREE.CylinderGeometry(0.5, 0.5, 1, 16, 1), 1),
  cone: new THREE.EdgesGeometry(new THREE.ConeGeometry(0.5, 1, 16, 1), 1),
};
const COLORS = { box: 0x00e5ff, sphere: 0x7cff6b, cylinder: 0xffb020, cone: 0xff5ad1 };
const NAMES = { box: 'Box', sphere: 'Sphere', cylinder: 'Cylinder', cone: 'Cone' };
const DEFAULT_DIMS = { box: { x: 0.3, y: 0.3, z: 0.3 }, sphere: { r: 0.15 }, cylinder: { r: 0.12, h: 0.3 }, cone: { r: 0.12, h: 0.3 } };
const HANDLE_DEFS = {
  box: [[1, 0, 0, 'x'], [-1, 0, 0, 'x'], [0, 1, 0, 'y'], [0, -1, 0, 'y'], [0, 0, 1, 'z'], [0, 0, -1, 'z']].map(([x, y, z, key]) => ({ axis: new V3(x, y, z), key, mode: 'face' })),
  sphere: [{ axis: new V3(1, 0, 0), key: 'r', mode: 'radius' }, { axis: new V3(0, 1, 0), key: 'r', mode: 'radius' }],
  cylinder: [{ axis: new V3(1, 0, 0), key: 'r', mode: 'radius' }, { axis: new V3(0, 0, 1), key: 'r', mode: 'radius' }, { axis: new V3(0, 1, 0), key: 'h', mode: 'face' }, { axis: new V3(0, -1, 0), key: 'h', mode: 'face' }],
};
HANDLE_DEFS.cone = HANDLE_DEFS.cylinder;
const handleGeo = new THREE.BoxGeometry(0.03, 0.03, 0.03);
const handleMat = { face: new THREE.MeshBasicMaterial({ color: 0xffe14d }), radius: new THREE.MeshBasicMaterial({ color: 0xff8a1f }) };

function scaleOf(s) {
  const d = s.dims;
  if (s.type === 'box') return new V3(d.x, d.y, d.z);
  if (s.type === 'sphere') return new V3(2 * d.r, 2 * d.r, 2 * d.r);
  return new V3(2 * d.r, d.h, 2 * d.r);
}
function halfHeight(s) { return scaleOf(s).y / 2; }
function extent(s, key) { return key === 'r' ? s.dims.r : (key === 'h' ? s.dims.h : s.dims[key]); }
function volumeOf(s) {
  const d = s.dims;
  switch (s.type) {
    case 'box': return d.x * d.y * d.z;
    case 'sphere': return 4 / 3 * Math.PI * d.r ** 3;
    case 'cylinder': return Math.PI * d.r ** 2 * d.h;
    case 'cone': return Math.PI * d.r ** 2 * d.h / 3;
  }
}
function shapeLines(s) {
  const d = s.dims, v = `Vol ${VOL(volumeOf(s))}`;
  const n = s.pinned ? `${s.name} (pinned)` : s.name;
  switch (s.type) {
    case 'box': return [n, `W ${L(d.x)} × H ${L(d.y)} × D ${L(d.z)}`, v];
    case 'sphere': return [n, `r ${L(d.r)}  ·  Ø ${L(2 * d.r)}`, v];
    case 'cylinder': return [n, `r ${L(d.r)}  ·  Ø ${L(2 * d.r)}  ·  H ${L(d.h)}`, v];
    case 'cone': return [n, `r ${L(d.r)}  ·  H ${L(d.h)}  ·  slant ${L(Math.hypot(d.r, d.h))}`, v];
  }
}
function dimsText(s) { return shapeLines(s)[1]; }

function makeShape(type, dims, position, quaternion, name, outline) {
  const group = new THREE.Group();
  group.position.copy(position);
  if (quaternion) group.quaternion.copy(quaternion);
  const color = COLORS[type];
  if (type !== 'box' || !outline?.pts) outline = undefined;
  const wire = new THREE.LineSegments(outline ? outlineWire(outline) : WIRE_GEO[type], new THREE.LineBasicMaterial({ color, transparent: true, opacity: 0.95 }));
  const fill = new THREE.Mesh(UNIT_GEO[type], new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.06, depthWrite: false, side: THREE.DoubleSide }));
  const label = makeLabel();
  group.add(wire, fill, label.sprite);
  if (!name) name = `${NAMES[type]} ${++state.counters[type]}`;
  const shape = { type, name, dims: { ...dims }, group, wire, fill, label, color, handles: [], outline };
  fill.userData.shape = shape;
  scene.add(group);
  state.shapes.push(shape);
  refreshShape(shape);
  return shape;
}
function refreshShape(s) {
  const sc = scaleOf(s);
  s.wire.scale.copy(sc); s.fill.scale.copy(sc);
  s.label.sprite.position.set(0, sc.y / 2 + 0.07, 0);
  setLabel(s.label, shapeLines(s), '#' + s.color.toString(16).padStart(6, '0'));
  for (const h of s.handles) {
    const hd = h.userData.handle;
    const e = hd.mode === 'radius' ? s.dims.r : extent(s, hd.key) / 2;
    h.position.copy(hd.axis).multiplyScalar(e + 0.015);
  }
}
function removeShape(s) {
  if (state.selected === s) select(null);
  scene.remove(s.group);
  state.shapes = state.shapes.filter(x => x !== s);
}
function restoreShape(s) { if (!state.shapes.includes(s)) { scene.add(s.group); state.shapes.push(s); } }
function snapshot(s) { return { dims: { ...s.dims }, pos: s.group.position.clone(), quat: s.group.quaternion.clone() }; }
function applySnapshot(s, snap) { s.dims = { ...snap.dims }; s.group.position.copy(snap.pos); s.group.quaternion.copy(snap.quat); refreshShape(s); }

function select(s) {
  const prev = state.selected;
  if (prev) {
    prev.wire.material.color.setHex(prev.color); prev.fill.material.opacity = 0.06;
    for (const h of prev.handles) prev.group.remove(h);
    prev.handles = [];
  }
  state.selected = s;
  if (s) {
    s.wire.material.color.setHex(0xffffff); s.fill.material.opacity = 0.14;
    s.handles = s.pinned ? [] : HANDLE_DEFS[s.type].map(hd => {
      const m = new THREE.Mesh(handleGeo, handleMat[hd.mode]);
      m.userData.handle = { ...hd, shape: s };
      s.group.add(m);
      return m;
    });
    refreshShape(s);
  }
  panel.dirty = true;
}

// ---------------------------------------------------------------- surfaces (floor + detected horizontal planes)
function surfaceHeights() { return [0, ...room.heights]; }

// ---------------------------------------------------------------- measurements
const dotGeo = new THREE.SphereGeometry(0.006, 12, 8);
const measureMat = new THREE.LineBasicMaterial({ color: 0xffe14d, depthTest: false, transparent: true });
const dotMat = new THREE.MeshBasicMaterial({ color: 0xffe14d, depthTest: false, transparent: true });

function circleFrom3(a, b, c) {
  const ab = b.clone().sub(a), ac = c.clone().sub(a);
  const n = ab.clone().cross(ac);
  const n2 = n.lengthSq();
  if (n2 < 1e-8) return null;
  const center = a.clone().add(
    n.clone().cross(ab).multiplyScalar(ac.lengthSq()).add(ac.clone().cross(n).multiplyScalar(ab.lengthSq())).divideScalar(2 * n2));
  return { center, normal: n.normalize(), r: center.distanceTo(a) };
}
function measureLines(m) {
  if (m.type === 'line') {
    const [a, b] = m.points, d = b.clone().sub(a);
    return [`${m.name}  ${L(d.length())}`, `↕ ${L(Math.abs(d.y))}  ·  ↔ ${L(Math.hypot(d.x, d.z))}`];
  }
  return [`${m.name}  Ø ${L(2 * m.r)}`, `r ${L(m.r)}  ·  circ ${L(2 * Math.PI * m.r)}`];
}
function createMeasure(type, points, name) {
  const group = new THREE.Group();
  const m = { type, name: name || `M${++state.counters.m}`, points: points.map(p => p.clone()), group, label: makeLabel(0.22) };
  for (const p of m.points) { const dot = new THREE.Mesh(dotGeo, dotMat); dot.position.copy(p); dot.renderOrder = 15; group.add(dot); }
  let labelPos;
  if (type === 'line') {
    const line = new THREE.Line(new THREE.BufferGeometry().setFromPoints(m.points), measureMat);
    line.renderOrder = 15; group.add(line);
    labelPos = m.points[0].clone().lerp(m.points[1], 0.5);
  } else {
    const c = circleFrom3(...m.points);
    if (!c) return null;
    Object.assign(m, c);
    const u = m.points[0].clone().sub(c.center).normalize(), v = c.normal.clone().cross(u);
    const pts = [];
    for (let i = 0; i <= 64; i++) { const t = i / 64 * Math.PI * 2; pts.push(c.center.clone().addScaledVector(u, Math.cos(t) * c.r).addScaledVector(v, Math.sin(t) * c.r)); }
    const loop = new THREE.Line(new THREE.BufferGeometry().setFromPoints(pts), measureMat);
    loop.renderOrder = 15; group.add(loop);
    const cdot = new THREE.Mesh(dotGeo, dotMat); cdot.position.copy(c.center); group.add(cdot);
    labelPos = c.center.clone();
  }
  m.label.sprite.position.copy(labelPos).add(new V3(0, 0.05, 0));
  group.add(m.label.sprite);
  setLabel(m.label, measureLines(m), '#ffe14d');
  scene.add(group);
  state.measures.push(m);
  return m;
}
function removeMeasure(m) { scene.remove(m.group); state.measures = state.measures.filter(x => x !== m); }
function restoreMeasure(m) { if (!state.measures.includes(m)) { scene.add(m.group); state.measures.push(m); } }

const preview = (() => {
  const line = new THREE.Line(new THREE.BufferGeometry().setFromPoints([new V3(), new V3(), new V3(), new V3()]), new THREE.LineDashedMaterial({ color: 0xffe14d, dashSize: 0.01, gapSize: 0.008, depthTest: false, transparent: true }));
  line.renderOrder = 15; line.frustumCulled = false; line.visible = false;
  const label = makeLabel(0.2); label.sprite.visible = false;
  scene.add(line, label.sprite);
  return { line, label };
})();
function clearPending() {
  for (const d of state.pendingDots) scene.remove(d);
  state.pending = []; state.pendingDots = [];
  preview.line.visible = false; preview.label.sprite.visible = false;
}
function addPendingPoint(p) {
  state.pending.push(p.clone());
  const dot = new THREE.Mesh(dotGeo, dotMat); dot.position.copy(p); dot.renderOrder = 15; scene.add(dot); state.pendingDots.push(dot);
  const need = state.mode === 'tape' ? 2 : 3;
  if (state.pending.length < need) {
    setStatus(state.mode === 'tape' ? 'Now point at the second end.' : `Point ${state.pending.length + 1} of 3 on the round edge.`);
    return;
  }
  const m = createMeasure(state.mode === 'tape' ? 'line' : 'circle', state.pending);
  clearPending();
  if (!m) { setStatus('Those 3 points are in a line. Try again, spread them out.'); return; }
  pushHistory({ undo: () => removeMeasure(m), redoLabel: m.name });
  setStatus(`${m.name}: ${measureLines(m)[0].replace(m.name, '').trim()}`);
  persist();
}

// ---------------------------------------------------------------- history / clipboard
function pushHistory(entry) { state.history.push(entry); if (state.history.length > 60) state.history.shift(); }
function undo() {
  if (state.pending.length) { clearPending(); setStatus('Cancelled the measurement in progress.'); return; }
  const e = state.history.pop();
  if (!e) { setStatus('Nothing to undo.'); return; }
  e.undo(); setStatus('Undone.'); persist();
}
function clipItem(s) { return { type: s.type, dims: { ...s.dims }, quat: s.group.quaternion.clone(), name: s.name, outline: s.outline }; }
function copySelected(cut) {
  const s = state.selected;
  if (!s) { setStatus('Select a shape first.'); return; }
  state.clipboard.unshift(clipItem(s));
  if (state.clipboard.length > CLIP_MAX) state.clipboard.pop();
  state.clipIndex = 0;
  if (cut) {
    removeShape(s);
    pushHistory({ undo: () => restoreShape(s) });
    setStatus(`Cut ${s.name}. Point somewhere and press Paste.`);
    persist();
  } else setStatus(`Copied ${s.name}. Point somewhere and press Paste.`);
}
function pasteAt(point, item = state.clipboard[state.clipIndex], offset = null) {
  if (!item) { setStatus('Clipboard is empty. Copy or Cut a shape first.'); return; }
  const pos = point.clone();
  const s = makeShape(item.type, item.dims, pos, item.quat, undefined, item.outline);
  if (offset) s.group.position.add(offset);
  else s.group.position.y += halfHeight(s);   // sit on the surface we pointed at
  settle(s);
  select(s);
  pushHistory({ undo: () => removeShape(s) });
  setStatus(`Pasted ${s.name} (copy of ${item.name}).`);
  persist();
}

// ---------------------------------------------------------------- room: planes + meshes from Space Setup
const room = { group: new THREE.Group(), planes: new Map(), meshes: new Map(), heights: [], planeInfo: [] };
scene.add(room.group);
const planeMat = new THREE.LineBasicMaterial({ color: 0x00e5ff, transparent: true, opacity: 0.8 });
const meshMat = new THREE.LineBasicMaterial({ color: 0x3fa9ff, transparent: true, opacity: 0.25 });

function planeLines(info) {
  const name = (info.label || info.orientation || 'plane');
  return [name.charAt(0).toUpperCase() + name.slice(1), `${L(info.w)} × ${L(info.d)}  ·  ${AREA(info.w * info.d)}`];
}
function updateRoom(frame, ref) {
  const heights = [], infos = [];
  if (frame.detectedPlanes) {
    for (const plane of frame.detectedPlanes) {
      let e = room.planes.get(plane);
      if (!e || e.t !== plane.lastChangedTime) {
        if (e) room.group.remove(e.obj);
        const pts = plane.polygon.map(p => new V3(p.x, 0, p.z));
        const obj = new THREE.Group(); obj.matrixAutoUpdate = false;
        obj.add(new THREE.LineLoop(new THREE.BufferGeometry().setFromPoints(pts), planeMat));
        const box = new THREE.Box3().setFromPoints(pts);
        const info = { label: plane.semanticLabel, orientation: plane.orientation, w: box.max.x - box.min.x, d: box.max.z - box.min.z };
        const label = makeLabel(0.3);
        label.sprite.position.set((box.max.x + box.min.x) / 2, 0.03, (box.max.z + box.min.z) / 2);
        obj.add(label.sprite);
        e = { obj, t: plane.lastChangedTime, info, label, pts, horizontal: false, y: 0, inv: new THREE.Matrix4() };
        room.planes.set(plane, e); room.group.add(obj);
      }
      setLabel(e.label, planeLines(e.info), '#00e5ff');
      const pose = frame.getPose(plane.planeSpace, ref);
      if (pose) {
        e.obj.matrix.fromArray(pose.transform.matrix);
        e.obj.matrixWorldNeedsUpdate = true;
        const ny = new V3(0, 1, 0).transformDirection(e.obj.matrix).y;
        e.horizontal = plane.orientation === 'horizontal' && ny > 0.9;
        e.y = pose.transform.position.y;
        e.inv.copy(e.obj.matrix).invert();
        if (e.horizontal) heights.push(e.y);
      }
      infos.push(e.info);
    }
    for (const [plane, e] of room.planes) if (!frame.detectedPlanes.has(plane)) { room.group.remove(e.obj); room.planes.delete(plane); }
  }
  if (frame.detectedMeshes) {
    for (const mesh of frame.detectedMeshes) {
      let e = room.meshes.get(mesh);
      if (!e || e.t !== mesh.lastChangedTime) {
        if (e) room.group.remove(e.obj);
        const geo = new THREE.BufferGeometry();
        geo.setAttribute('position', new THREE.BufferAttribute(new Float32Array(mesh.vertices), 3));
        geo.setIndex(new THREE.BufferAttribute(new Uint32Array(mesh.indices), 1));
        const obj = new THREE.LineSegments(new THREE.WireframeGeometry(geo), meshMat);
        obj.matrixAutoUpdate = false;
        e = { obj, t: mesh.lastChangedTime };
        room.meshes.set(mesh, e); room.group.add(obj);
      }
      const pose = frame.getPose(mesh.meshSpace, ref);
      if (pose) { e.obj.matrix.fromArray(pose.transform.matrix); e.obj.matrixWorldNeedsUpdate = true; }
    }
    for (const [mesh, e] of room.meshes) if (!frame.detectedMeshes.has(mesh)) { room.group.remove(e.obj); room.meshes.delete(mesh); }
  }
  room.heights = heights;
  room.planeInfo = infos;
}

// ---------------------------------------------------------------- in-world menu
const MENU_W = 1024, MENU_H = 980, HEADER = 230, ROW_H = 150;
const BUTTONS = [
  ['box', 'sphere', 'cylinder', 'cone'],
  ['tape', 'circle', 'select', 'units'],
  ['copy', 'cut', 'paste', 'nextclip'],
  ['duplicate', 'drop', 'delete', 'undo'],
  ['room', 'clear', 'grid', 'exit'],
];
function buttonText(id) {
  switch (id) {
    case 'box': return '+ Box'; case 'sphere': return '+ Sphere'; case 'cylinder': return '+ Cylinder'; case 'cone': return '+ Cone';
    case 'tape': return 'Tape'; case 'circle': return 'Circle 3-pt'; case 'select': return 'Move/Size';
    case 'units': return state.units === 'metric' ? 'Units: cm' : 'Units: in';
    case 'copy': return 'Copy'; case 'cut': return 'Cut'; case 'paste': return 'Paste'; case 'nextclip': return 'Next clip';
    case 'duplicate': return 'Duplicate'; case 'drop': return 'Drop'; case 'delete': return 'Delete'; case 'undo': return 'Undo';
    case 'room': return state.roomVisible ? 'Room: on' : 'Room: off'; case 'clear': return 'Clear all';
    case 'grid': return `Grid: ${state.grid ? Math.round(state.grid * 100) + ' cm' : 'off'}`; case 'exit': return 'Exit AR';
  }
}
function buttonActive(id) { return (id === 'tape' && state.mode === 'tape') || (id === 'circle' && state.mode === 'circle') || (id === 'select' && state.mode === 'select'); }
function buttonEnabled(id) {
  if (id === 'drop') return !!state.selected && !state.selected.pinned;
  if (['copy', 'cut', 'duplicate', 'delete'].includes(id)) return !!state.selected;
  if (['paste', 'nextclip'].includes(id)) return state.clipboard.length > 0;
  return true;
}
const panel = (() => {
  const canvas = document.createElement('canvas'); canvas.width = MENU_W; canvas.height = MENU_H;
  const tex = new THREE.CanvasTexture(canvas); tex.colorSpace = THREE.SRGBColorSpace;
  const w = 0.3, mesh = new THREE.Mesh(new THREE.PlaneGeometry(w, w * MENU_H / MENU_W), new THREE.MeshBasicMaterial({ map: tex, transparent: true, side: THREE.DoubleSide }));
  mesh.renderOrder = 30;
  scene.add(mesh);
  return { canvas, tex, mesh, dirty: true, hover: null, placed: false, moving: false };
})();
function drawPanel() {
  const g = panel.canvas.getContext('2d');
  g.clearRect(0, 0, MENU_W, MENU_H);
  g.fillStyle = 'rgba(12,15,20,0.9)'; roundRect(g, 0, 0, MENU_W, MENU_H, 40); g.fill();
  g.strokeStyle = '#00e5ff'; g.lineWidth = 4; g.stroke();
  g.textBaseline = 'middle';
  g.fillStyle = '#00e5ff'; g.font = '700 54px system-ui, sans-serif';
  g.fillText('FRAMESPACE', 36, 52);
  g.fillStyle = '#9aa6b4'; g.font = '500 38px system-ui, sans-serif';
  const modeName = { select: 'Move/Size', tape: 'Tape', circle: 'Circle 3-pt' }[state.mode];
  g.fillText(`Mode: ${modeName}`, 600, 52);
  g.fillStyle = '#ffffff'; g.font = '500 38px system-ui, sans-serif';
  fitText(g, state.status, 36, 118, MENU_W - 72, 38);
  const clip = state.clipboard[state.clipIndex];
  g.fillStyle = '#ffe14d';
  fitText(g, clip ? `Clipboard ${state.clipIndex + 1}/${state.clipboard.length}: ${clip.name}, ${dimsText({ ...clip })}` : 'Clipboard: empty', 36, 178, MENU_W - 72, 34);
  const bw = (MENU_W - 40) / 4;
  BUTTONS.forEach((row, r) => row.forEach((id, c) => {
    const x = 20 + c * bw, y = HEADER + r * ROW_H;
    const en = buttonEnabled(id), act = buttonActive(id), hov = panel.hover === id;
    g.fillStyle = act ? '#00e5ff' : hov && en ? '#3a4452' : '#232a34';
    roundRect(g, x + 8, y + 10, bw - 16, ROW_H - 20, 22); g.fill();
    g.fillStyle = act ? '#001014' : en ? '#ffffff' : '#5c6673';
    g.font = '600 40px system-ui, sans-serif';
    const t = buttonText(id); let size = 40;
    while (g.measureText(t).width > bw - 36 && size > 22) { size -= 2; g.font = `600 ${size}px system-ui, sans-serif`; }
    g.fillText(t, x + (bw - g.measureText(t).width) / 2, y + ROW_H / 2);
  }));
  panel.tex.needsUpdate = true;
  panel.dirty = false;
}
function fitText(g, t, x, y, maxW, size) {
  g.font = `500 ${size}px system-ui, sans-serif`;
  while (g.measureText(t).width > maxW && size > 20) { size -= 2; g.font = `500 ${size}px system-ui, sans-serif`; }
  g.fillText(t, x, y);
}
function buttonAt(uv) {
  const x = uv.x * MENU_W, y = (1 - uv.y) * MENU_H;
  if (y < HEADER) return null;
  const r = Math.floor((y - HEADER) / ROW_H), c = Math.floor((x - 20) / ((MENU_W - 40) / 4));
  return BUTTONS[r]?.[c] ?? null;
}
function setStatus(t) { state.status = t; panel.dirty = true; }

function pointTarget(ctrl) {
  const u = ctrl?.userData;
  if (u?.target) return u.target.point.clone();
  const { o, d } = rayOf(ctrl || controllers[0]);
  return o.addScaledVector(d, 0.8);
}
function spawnPoint() {
  const c = state.lastCtrl || controllers.find(c => c.userData.inputSource) || controllers[0];
  if (c.userData.target) return c.userData.target.point.clone();
  const head = camera.getWorldPosition(new V3()), dir = camera.getWorldDirection(new V3()); dir.y = 0; dir.normalize();
  return head.addScaledVector(dir, 0.7).setY(Math.max(0, head.y - 0.6));
}
function onButton(id, ctrl) {
  if (!buttonEnabled(id)) { setStatus(id === 'paste' || id === 'nextclip' ? 'Clipboard is empty.' : 'Select a shape first (Move/Size mode, point and trigger).'); return; }
  switch (id) {
    case 'box': case 'sphere': case 'cylinder': case 'cone': {
      const p = spawnPoint();
      const s = makeShape(id, DEFAULT_DIMS[id], p);
      s.group.position.y += halfHeight(s); settle(s);
      state.mode = 'select'; clearPending(); select(s);
      pushHistory({ undo: () => removeShape(s) });
      setStatus(`Added ${s.name}. Grab to move, drag yellow cubes to resize.`); persist(); break;
    }
    case 'tape': state.mode = 'tape'; clearPending(); select(null); setStatus('Tape: point at the first end and press trigger.'); break;
    case 'circle': state.mode = 'circle'; clearPending(); select(null); setStatus('Circle: tap 3 points around a round edge.'); break;
    case 'select': state.mode = 'select'; clearPending(); setStatus('Move/Size: point at a shape and hold trigger to move it.'); break;
    case 'units':
      state.units = state.units === 'metric' ? 'imperial' : 'metric';
      state.shapes.forEach(refreshShape);
      state.measures.forEach(m => setLabel(m.label, measureLines(m), '#ffe14d'));
      setStatus(`Units: ${state.units}.`); persist(); break;
    case 'copy': copySelected(false); break;
    case 'cut': copySelected(true); break;
    case 'paste': {
      // Paste where the *other* hand is pointing would be confusing; the hand that pressed is on the menu, so use the last pointing hand.
      const other = controllers.find(c => c !== ctrl && c.userData.target) || null;
      pasteAt(other ? other.userData.target.point : spawnPoint()); break;
    }
    case 'nextclip': state.clipIndex = (state.clipIndex + 1) % state.clipboard.length; setStatus('Next clipboard item. Press Paste to place it.'); break;
    case 'duplicate': {
      const s = state.selected;
      const dx = new V3(1, 0, 0).applyQuaternion(s.group.quaternion).multiplyScalar(scaleOf(s).x + 0.05);
      pasteAt(s.group.position, clipItem(s), dx);
      break;
    }
    case 'drop': { const s = state.selected; pushHistory({ undo: (sn => () => applySnapshot(s, sn))(snapshot(s)) }); settle(s); setStatus(`Dropped ${s.name} onto the surface below.`); persist(); break; }
    case 'delete': { const s = state.selected; removeShape(s); pushHistory({ undo: () => restoreShape(s) }); setStatus(`Deleted ${s.name}. Undo brings it back.`); persist(); break; }
    case 'undo': undo(); break;
    case 'room': state.roomVisible = !state.roomVisible; room.group.visible = state.roomVisible; break;
    case 'clear': {
      const shapes = [...state.shapes], measures = [...state.measures];
      shapes.forEach(removeShape); measures.forEach(removeMeasure); clearPending();
      pushHistory({ undo: () => { shapes.forEach(restoreShape); measures.forEach(restoreMeasure); } });
      setStatus('Cleared. Undo brings everything back.'); persist(); break;
    }
    case 'grid': { const opts = [0.05, 0.1, 0.01, 0]; state.grid = opts[(opts.indexOf(state.grid) + 1) % opts.length]; setStatus(state.grid ? `Grid ${Math.round(state.grid * 100)} cm` : 'Grid off'); break; }
    case 'exit': renderer.xr.getSession()?.end(); break;
  }
  panel.dirty = true;
}

// Stick click opens the main menu riding just above that hand (the other hand selects).
// Click both sticks together to leave it fixed in front of you. Click again to close.
function menuHandPos(c) {
  const p = new V3().setFromMatrixPosition(c.matrixWorld), head = camera.getWorldPosition(new V3());
  const toHead = head.clone().sub(p); toHead.y = 0;
  const side = new V3().crossVectors(UP, toHead.normalize()).multiplyScalar(c.userData.inputSource?.handedness === 'left' ? 0.1 : -0.1);
  return p.add(new V3(0, 0.2, 0)).add(side);
}
function openMenu(c, fixed) {
  state.menuVisible = true; panel.mesh.visible = true;
  state.menuAttach = fixed ? null : c;
  if (fixed) updateMenuPlacement(true);
  else { panel.mesh.position.copy(menuHandPos(c)); panel.mesh.lookAt(camera.getWorldPosition(new V3())); }
  panel.dirty = true;
  if (c) haptic(c, 0.4, 30);
}
function closeMenu() { state.menuVisible = false; state.menuAttach = null; panel.mesh.visible = false; }
function updateMenuPlacement(instant) {
  if (state.menuAttach) { panel.mesh.position.copy(menuHandPos(state.menuAttach)); panel.mesh.lookAt(camera.getWorldPosition(new V3())); return; }
  if (!instant) return;   // fixed menus stay where they opened
  const head = camera.getWorldPosition(new V3());
  const fwd = camera.getWorldDirection(new V3()); fwd.y = 0;
  if (fwd.lengthSq() < 1e-6) fwd.set(0, 0, -1);
  fwd.normalize();
  const left = new V3().crossVectors(UP, fwd).normalize();   // points to the user's left
  const target = head.clone().addScaledVector(fwd, 0.5).addScaledVector(left, 0.22);
  target.y = head.y - 0.28;
  const dist = panel.mesh.position.distanceTo(target);
  if (instant || !panel.placed) { panel.mesh.position.copy(target); panel.placed = true; }
  else {
    if (dist > 0.3) panel.moving = true;
    if (panel.moving) { panel.mesh.position.lerp(target, 0.08); if (dist < 0.02) panel.moving = false; }
  }
  panel.mesh.lookAt(head);
}

// ---------------------------------------------------------------- grid, support and settling
// The grid is the local-floor reference space's own X/Z axes. Quest re-aligns that space to the
// direction you face whenever you recenter, so the grid follows recentering automatically.
function snapGrid(v) { const g = state.grid; return g ? Math.round(v / g) * g : v; }
function yawOfQuat(q) { return new THREE.Euler().setFromQuaternion(q, 'YXZ').y; }
function snapYawQuat(q) { const step = Math.PI / 4; return new THREE.Quaternion().setFromAxisAngle(UP, Math.round(yawOfQuat(q) / step) * step); }
function insidePolygon(pts, x, z) {
  let inside = false;
  for (let i = 0, j = pts.length - 1; i < pts.length; j = i++) {
    const a = pts[i], b = pts[j];
    if ((a.z > z) !== (b.z > z) && x < (b.x - a.x) * (z - a.z) / (b.z - a.z) + a.x) inside = !inside;
  }
  return inside;
}
// Highest surface under (x, z) that is at or below maxY: floor, detected tables, or the tops of other shapes.
function supportBelow(x, z, maxY, exclude) {
  let best = 0;
  for (const e of room.planes.values()) {
    if (!e.horizontal || e.y > maxY + 0.01 || e.y <= best) continue;
    const local = new V3(x, e.y, z).applyMatrix4(e.inv);
    if (insidePolygon(e.pts, local.x, local.z)) best = e.y;
  }
  for (const s of state.shapes) {
    if (s === exclude || state.falling.some(f => f.shape === s)) continue;
    s.group.updateMatrixWorld(true);
    const bb = new THREE.Box3().setFromObject(s.fill);
    if (x >= bb.min.x && x <= bb.max.x && z >= bb.min.z && z <= bb.max.z && bb.max.y <= maxY + 0.01 && bb.max.y > best) best = bb.max.y;
  }
  return best;
}
// Square the shape to the grid (yaw in 45° steps, X/Z on grid points) and let it fall onto what is below.
function settle(s) {
  const g = s.group;
  g.quaternion.copy(snapYawQuat(g.quaternion));
  g.position.x = snapGrid(g.position.x); g.position.z = snapGrid(g.position.z);
  refreshShape(s);
  const hh = halfHeight(s), bottom = g.position.y - hh;
  const support = supportBelow(g.position.x, g.position.z, bottom + 0.02, s);
  state.falling = state.falling.filter(f => f.shape !== s);
  if (bottom - support > 0.005) state.falling.push({ shape: s, from: g.position.y, to: support + hh, t0: performance.now() });
  else g.position.y = support + hh;
  refreshShape(s);
}
function updateFalling(now) {
  state.falling = state.falling.filter(f => {
    const t = (now - f.t0) / 1000, y = f.from - 4.9 * t * t;
    if (y <= f.to) { f.shape.group.position.y = f.to; refreshShape(f.shape); persist(); return false; }
    f.shape.group.position.y = y; return true;
  });
}
const gridPatch = new THREE.Group(); gridPatch.visible = false; scene.add(gridPatch);
let gridPatchSize = 0;
function showGridPatch(x, y, z) {
  if (!state.grid) { gridPatch.visible = false; return; }
  if (gridPatchSize !== state.grid) {
    gridPatch.clear();
    const gh = new THREE.GridHelper(1, Math.round(1 / state.grid), 0x00e5ff, 0x00e5ff);
    gh.material.transparent = true; gh.material.opacity = 0.35;
    gridPatch.add(gh); gridPatchSize = state.grid;
  }
  gridPatch.position.set(snapGrid(x), y + 0.002, snapGrid(z));
  gridPatch.visible = true;
}

// ---------------------------------------------------------------- popups: shape palette (hold X) and context menu (hold A)
// The palette is loaded from objects.csv (one object per line, sizes in mm) so it can be edited without code changes.
// Fallback below is used only if the file can't be fetched.
const PALETTE = [
  { label: 'Cube', type: 'box', dims: { x: 0.1, y: 0.1, z: 0.1 } },
  { label: 'Sphere', type: 'sphere', dims: { r: 0.15 } },
  { label: 'Cylinder', type: 'cylinder', dims: { r: 0.12, h: 0.3 } },
  { label: 'Cone', type: 'cone', dims: { r: 0.12, h: 0.3 } },
];
// Optional side-view outline for a box (e.g. a vehicle): "x/y x/y ..." in mm, x from the front, y from the ground.
// Optional wheels: "x/diameter ...". Stored normalised to the unit box so the shape still scales like a box.
// Optional inner box (e.g. a cargo area): "x/y/length/width/height" in mm, x from the front, y = floor height, centred across.
function parseOutline(outline, wheels, inner, L, H, W) {
  const groups = (t, n) => (t || '').trim().split(/\s+/).filter(Boolean).map(p => p.split('/').map(Number)).filter(p => p.length === n && p.every(Number.isFinite));
  const pts = groups(outline, 2).map(([x, y]) => [0.5 - x / L, y / H - 0.5]);
  if (pts.length < 3) return undefined;
  return {
    pts,
    wheels: groups(wheels, 2).map(([x, d]) => [0.5 - x / L, d / 2 / L, d / 2 / H]),
    inner: groups(inner, 5).map(([x, y, l, w, h]) => [0.5 - (x + l) / L, 0.5 - x / L, y / H - 0.5, (y + h) / H - 0.5, w / 2 / W]),
  };
}
const outlineCache = new Map();
function outlineWire(o) {
  const key = JSON.stringify(o);
  if (outlineCache.has(key)) return outlineCache.get(key);
  const v = [], n = o.pts.length;
  for (const z of [-0.5, 0.5]) for (let i = 0; i < n; i++) { const a = o.pts[i], b = o.pts[(i + 1) % n]; v.push(a[0], a[1], z, b[0], b[1], z); }
  for (const p of o.pts) v.push(p[0], p[1], -0.5, p[0], p[1], 0.5);
  for (const [u0, u1, v0, v1, zw] of o.inner || []) {
    const c = [[u0, v0], [u1, v0], [u1, v1], [u0, v1]];
    for (const z of [-zw, zw]) for (let i = 0; i < 4; i++) v.push(c[i][0], c[i][1], z, c[(i + 1) % 4][0], c[(i + 1) % 4][1], z);
    for (const [a, b] of c) v.push(a, b, -zw, a, b, zw);
  }
  for (const [u, ru, rv] of o.wheels || []) for (const z of [-0.45, 0.45]) for (let k = 0; k < 24; k++) {
    const t0 = k / 24 * Math.PI * 2, t1 = (k + 1) / 24 * Math.PI * 2;
    v.push(u + Math.cos(t0) * ru, -0.5 + rv + Math.sin(t0) * rv, z, u + Math.cos(t1) * ru, -0.5 + rv + Math.sin(t1) * rv, z);
  }
  const g = new THREE.BufferGeometry(); g.setAttribute('position', new THREE.Float32BufferAttribute(v, 3));
  outlineCache.set(key, g);
  return g;
}
function parseObjects(text) {
  const out = [];
  let header = null;
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;
    const cells = line.split(',').map(c => c.trim());
    if (!header) { header = cells.map(c => c.toLowerCase()); continue; }
    const row = Object.fromEntries(header.map((h, i) => [h, cells[i] || '']));
    const mm = k => parseFloat(row[k]) / 1000, type = (row.shape || '').toLowerCase();
    let dims = null;
    if (type === 'box') dims = { x: mm('length_mm'), y: mm('height_mm'), z: mm('width_mm') };
    else if (type === 'sphere') dims = { r: mm('diameter_mm') / 2 };
    else if (type === 'cylinder' || type === 'cone') dims = { r: mm('diameter_mm') / 2, h: mm('height_mm') };
    if (!row.name || !dims || Object.values(dims).some(v => !(v > 0))) { console.warn('objects.csv: skipped line', line); continue; }
    const item = { label: row.name, type, dims, note: row.note || '' };
    if (type === 'box' && row.outline) item.outline = parseOutline(row.outline, row.wheels, row.inner, dims.x * 1000, dims.y * 1000, dims.z * 1000);
    out.push(item);
  }
  return out;
}
fetch('objects.csv', { cache: 'no-cache' }).then(r => r.ok ? r.text() : Promise.reject(r.status)).then(t => {
  const list = parseObjects(t);
  if (list.length) PALETTE.splice(0, PALETTE.length, ...list);
}).catch(e => console.warn('objects.csv not loaded, using built-in shapes', e));
const labelCounts = {};
function shortDims(type, d) {
  const metric = state.units === 'metric', k = metric ? 100 : 1 / 0.0254, unit = metric ? 'cm' : 'in';
  const n = v => +(v * k).toFixed(metric ? 0 : 1);
  if (type === 'box') return `${n(d.x)}×${n(d.y)}×${n(d.z)} ${unit}`;
  if (type === 'sphere') return `Ø ${n(2 * d.r)} ${unit}`;
  return `Ø ${n(2 * d.r)} × ${n(d.h)} ${unit}`;
}
const TILE = 260, TILE_H = 180, PHEAD = 90;
function makePopup(tileW) {
  const canvas = document.createElement('canvas');
  const tex = new THREE.CanvasTexture(canvas); tex.colorSpace = THREE.SRGBColorSpace;
  const mesh = new THREE.Mesh(new THREE.PlaneGeometry(1, 1), new THREE.MeshBasicMaterial({ map: tex, transparent: true, side: THREE.DoubleSide, depthTest: false }));
  mesh.renderOrder = 35; mesh.visible = false; scene.add(mesh);
  return { canvas, tex, mesh, items: [], cols: 3, title: '', hover: null, open: false, tileW, target: null, point: null };
}
const palette = makePopup(0.07), ctxMenu = makePopup(0.09);
function layoutPopup(p, title, items, cols) {
  p.title = title; p.items = items; p.cols = cols; p.hover = null;
  const w = cols * TILE + 20, h = PHEAD + Math.ceil(items.length / cols) * TILE_H + 10;
  if (p.canvas.width !== w || p.canvas.height !== h) { p.canvas.width = w; p.canvas.height = h; p.tex.dispose(); }
  const ww = cols * p.tileW; p.mesh.scale.set(ww, ww * h / w, 1);
  drawPopup(p);
}
function drawPopup(p) {
  const c = p.canvas, g = c.getContext('2d');
  g.clearRect(0, 0, c.width, c.height);
  g.fillStyle = 'rgba(12,15,20,0.92)'; roundRect(g, 2, 2, c.width - 4, c.height - 4, 30); g.fill();
  g.strokeStyle = '#00e5ff'; g.lineWidth = 4; g.stroke();
  g.textBaseline = 'middle'; g.fillStyle = '#00e5ff';
  fitText(g, p.title, 24, 48, c.width - 48, 42);
  p.items.forEach((it, i) => {
    const x = 10 + (i % p.cols) * TILE, y = PHEAD + Math.floor(i / p.cols) * TILE_H, en = it.enabled !== false;
    g.fillStyle = p.hover === it.id && en ? '#3a4452' : '#232a34';
    roundRect(g, x + 8, y + 8, TILE - 16, TILE_H - 16, 20); g.fill();
    let size = 44; g.font = `700 ${size}px system-ui, sans-serif`;
    while (g.measureText(it.label).width > TILE - 40 && size > 22) { size -= 2; g.font = `700 ${size}px system-ui, sans-serif`; }
    g.fillStyle = en ? (it.color || '#ffffff') : '#5c6673';
    g.fillText(it.label, x + (TILE - g.measureText(it.label).width) / 2, y + TILE_H * (it.sub ? 0.38 : 0.5));
    if (it.sub) {
      let s2 = 30; g.font = `500 ${s2}px system-ui, sans-serif`;
      while (g.measureText(it.sub).width > TILE - 30 && s2 > 16) { s2 -= 2; g.font = `500 ${s2}px system-ui, sans-serif`; }
      g.fillStyle = '#9aa6b4'; g.fillText(it.sub, x + (TILE - g.measureText(it.sub).width) / 2, y + TILE_H * 0.7);
    }
  });
  p.tex.needsUpdate = true;
}
function popupItemAt(p, uv) {
  const x = uv.x * p.canvas.width, y = (1 - uv.y) * p.canvas.height;
  if (y < PHEAD) return null;
  const col = Math.floor((x - 10) / TILE), row = Math.floor((y - PHEAD) / TILE_H);
  if (col < 0 || col >= p.cols) return null;
  const it = p.items[row * p.cols + col];
  return it && it.enabled !== false ? it : null;
}
function placePopup(p, pos) { p.mesh.position.copy(pos); p.mesh.lookAt(camera.getWorldPosition(new V3())); p.mesh.visible = true; p.open = true; }
function closePopup(p) { p.mesh.visible = false; p.open = false; p.hover = null; }

function openPalette(c) {
  const items = PALETTE.map((p, i) => ({ ...p, id: 'p' + i, sub: shortDims(p.type, p.dims), color: '#' + COLORS[p.type].toString(16).padStart(6, '0') }));
  layoutPopup(palette, 'Objects', items, 6);
  c.updateMatrixWorld(true);
  const head = camera.getWorldPosition(new V3()), pos = new V3().setFromMatrixPosition(c.matrixWorld);
  const away = pos.clone().sub(head).setY(0);
  if (away.lengthSq() < 1e-6) away.set(0, 0, -1);
  pos.addScaledVector(away.normalize(), 0.12).add(new V3(0, 0.12, 0));
  placePopup(palette, pos);
  haptic(c, 0.3, 20);
}
function spawnFromPalette(c, it, point) {
  labelCounts[it.label] = (labelCounts[it.label] || 0) + 1;
  const s = makeShape(it.type, it.dims, point.clone(), null, `${it.label} ${labelCounts[it.label]}`, it.outline);
  pushHistory({ undo: () => removeShape(s) });
  select(s); startFree(c, s, false); haptic(c, 0.5, 40);
  setStatus(`Placing ${s.name}`);
  persist();
}
function openContext(c) {
  const u = c.userData, s = u.shapeHit?.object.userData.shape;
  const head = camera.getWorldPosition(new V3());
  let anchor;
  if (s) {
    select(s); anchor = u.shapeHit.point.clone(); ctxMenu.target = s;
    layoutPopup(ctxMenu, s.name, [{ id: 'cut', label: 'Cut' }, { id: 'copy', label: 'Copy' }, { id: 'delete', label: 'Delete', color: '#ff6b6b' }, { id: 'duplicate', label: 'Duplicate' }, { id: 'pin', label: s.pinned ? 'Unpin' : 'Pin', color: '#ffd54f' }], 2);
  } else {
    anchor = u.target ? u.target.point.clone() : pointTarget(c); ctxMenu.target = null;
    const clip = state.clipboard[state.clipIndex];
    layoutPopup(ctxMenu, clip ? `Clipboard ${state.clipIndex + 1}/${state.clipboard.length}: ${clip.name}` : 'Clipboard empty',
      [{ id: 'paste', label: 'Paste', enabled: !!clip }, { id: 'nextclip', label: 'Next clip', enabled: state.clipboard.length > 1 }], 2);
  }
  ctxMenu.point = anchor.clone();
  // Open near the hand (never out at a far object), linked to the object by a dotted line in its colour.
  const { o, d } = rayOf(c);
  const pos = o.clone().addScaledVector(d, Math.min(0.35, anchor.distanceTo(o))).add(new V3(0, 0.1, 0));
  placePopup(ctxMenu, pos);
  drawCtxLink(pos, anchor, s ? s.color : 0x00e5ff);
  haptic(c, 0.4, 30);
}
const ctxLink = new THREE.LineSegments(new THREE.BufferGeometry(), new THREE.LineDashedMaterial({ color: 0xffffff, dashSize: 0.03, gapSize: 0.03, depthTest: false, transparent: true }));
ctxLink.renderOrder = 39; ctxLink.visible = false; scene.add(ctxLink);
function drawCtxLink(from, to, color) {
  ctxLink.geometry.dispose();
  ctxLink.geometry = new THREE.BufferGeometry().setFromPoints([from, to]);
  ctxLink.computeLineDistances();
  ctxLink.material.color.setHex(color);
  ctxLink.visible = from.distanceTo(to) > 0.05;
}
function runContext(id) {
  const s = ctxMenu.target, p = ctxMenu.point;
  closePopup(ctxMenu);
  switch (id) {
    case 'cut': if (s) { select(s); copySelected(true); } break;
    case 'copy': if (s) { select(s); copySelected(false); } break;
    case 'delete': if (s) { removeShape(s); pushHistory({ undo: () => restoreShape(s) }); setStatus(`Deleted ${s.name}`); persist(); } break;
    case 'duplicate': if (s) { select(s); onButton('duplicate'); } break;
    case 'pin': if (s) { setPinned(s, !s.pinned); pushHistory({ undo: () => setPinned(s, !s.pinned) }); setStatus(s.pinned ? `${s.name} pinned. It can't be grabbed until you unpin it (hold A > Unpin).` : `${s.name} unpinned.`); persist(); } break;
    case 'paste': pasteAt(p); break;
    case 'nextclip': state.clipIndex = (state.clipIndex + 1) % state.clipboard.length; setStatus('Next clipboard item'); break;
  }
  panel.dirty = true;
}

// ---------------------------------------------------------------- controllers
const raycaster = new THREE.Raycaster();
function rayOf(c) {
  return { o: new V3().setFromMatrixPosition(c.matrixWorld), d: new V3(0, 0, -1).transformDirection(c.matrixWorld) };
}
function yawOf(c) { const d = new V3(0, 0, -1).transformDirection(c.matrixWorld); return Math.atan2(-d.x, -d.z); }
function makeReticle() {
  const r = new THREE.Mesh(new THREE.RingGeometry(0.008, 0.014, 24), new THREE.MeshBasicMaterial({ color: 0x00e5ff, depthTest: false, transparent: true, side: THREE.DoubleSide }));
  r.renderOrder = 40; r.visible = false; scene.add(r); return r;
}
function isHand(c) { const s = c.userData.inputSource; return !!(s && (s.hand || !s.gamepad)); }
const controllers = [0, 1].map(i => {
  const c = renderer.xr.getController(i);
  const ray = new THREE.Line(new THREE.BufferGeometry().setFromPoints([new V3(0, 0, 0), new V3(0, 0, -1)]), new THREE.LineBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.5 }));
  ray.visible = false; c.add(ray);
  c.userData = { index: i, inputSource: null, hitSource: null, ray, reticle: makeReticle(), target: null, drag: null, btn: null };
  c.addEventListener('connected', e => onConnected(c, e.data));
  c.addEventListener('disconnected', () => onDisconnected(c));
  // Controllers are read by polling (see processInput). Hands only get a basic pinch = trigger.
  c.addEventListener('selectstart', () => { if (isHand(c)) onTriggerDown(c, { grip: false }); });
  c.addEventListener('selectend', () => { if (isHand(c)) onDragRelease(c); });
  scene.add(c);
  return c;
});
function rightCtrl() { return controllers.find(c => c.userData.inputSource?.handedness === 'right'); }
function bHeld() { return !!rightCtrl()?.userData.btn?.high; }
function onConnected(c, src) {
  const u = c.userData;
  u.inputSource = src; u.btn = null;
  const session = renderer.xr.getSession();
  if (session?.requestHitTestSource && src.targetRaySpace) {
    try {
      session.requestHitTestSource({ space: src.targetRaySpace }).then(hs => { if (u.inputSource === src) u.hitSource = hs; else hs.cancel(); }).catch(() => {});
    } catch { /* hit-test not granted: fall back to virtual targets */ }
  }
}
function onDisconnected(c) {
  const u = c.userData;
  try { u.hitSource?.cancel(); } catch {}
  if (u.drag) onDragRelease(c);
  u.hitSource = null; u.inputSource = null; u.target = null; u.drag = null; u.btn = null;
  u.ray.visible = false; u.reticle.visible = false;
}
function haptic(c, strength = 0.3, ms = 25) {
  try { c.userData.inputSource?.gamepad?.hapticActuators?.[0]?.pulse(strength, ms); } catch {}
}

function snapPoint(p) {
  let best = null, bestD = SNAP_POINT;
  const consider = q => { const d = q.distanceTo(p); if (d < bestD) { bestD = d; best = q; } };
  state.pending.forEach(consider);
  state.measures.forEach(m => m.points.forEach(consider));
  for (const s of state.shapes) {
    const h = scaleOf(s).multiplyScalar(0.5);
    if (s.type === 'box') {
      for (const sx of [-1, 1]) for (const sy of [-1, 1]) for (const sz of [-1, 1]) consider(s.group.localToWorld(new V3(sx * h.x, sy * h.y, sz * h.z)));
    } else {
      consider(s.group.localToWorld(new V3(0, h.y, 0))); consider(s.group.localToWorld(new V3(0, -h.y, 0)));
    }
  }
  return best ? best.clone() : null;
}

function updatePointer(c, frame, ref) {
  const u = c.userData;
  if (!u.inputSource) return;
  c.updateMatrixWorld(true);
  u.ray.visible = true;
  const { o, d } = rayOf(c);
  let real = null;
  if (frame && u.hitSource) {
    const res = frame.getHitTestResults(u.hitSource);
    if (res.length) {
      const pose = res[0].getPose(ref);
      if (pose) {
        const m = new THREE.Matrix4().fromArray(pose.transform.matrix);
        const p = new V3().setFromMatrixPosition(m);
        real = { point: p, normal: new V3(0, 1, 0).transformDirection(m), dist: p.distanceTo(o), kind: 'surface' };
      }
    }
  }
  if (!real && d.y < -0.05) {
    // No depth hit (hit-test unavailable or a hard surface): fall back to the floor plane.
    const t = -o.y / d.y;
    if (t > 0.05 && t < 10) real = { point: o.clone().addScaledVector(d, t), normal: UP.clone(), dist: t, kind: 'surface' };
  }
  raycaster.set(o, d); raycaster.far = 20;
  const uiMeshes = [];
  if (palette.open) uiMeshes.push(palette.mesh);
  if (ctxMenu.open) uiMeshes.push(ctxMenu.mesh);
  if (panel.mesh.visible) uiMeshes.push(panel.mesh);
  const draggingThis = u.drag && u.drag.shape;
  const targets = [...uiMeshes, ...(state.selected ? state.selected.handles : []), ...state.shapes.filter(s => s !== draggingThis).map(s => s.fill)];
  const hits = raycaster.intersectObjects(targets, false);
  const first = hits[0];
  u.ui = null; u.handleHit = null; u.shapeHit = null;
  // Pop-ups (palette, context menu) win over everything else they overlap, including the tools menu.
  const popHit = hits.find(h => h.object === palette.mesh || h.object === ctxMenu.mesh);
  if (popHit) {
    u.ui = { kind: popHit.object === palette.mesh ? 'palette' : 'ctx', hit: popHit };
  } else if (first && first.object === panel.mesh) {
    u.ui = { kind: 'menu', hit: first };
  } else if (hits.length) {
    const h = hits.find(h => h.object.userData.handle && h.distance < hits[0].distance + 0.05);
    if (h) u.handleHit = h;
    const s = hits.find(h => h.object.userData.shape);
    if (s) u.shapeHit = s;
  }
  let best = real;
  const sh = u.shapeHit;
  if (sh && (!best || sh.distance < best.dist)) {
    const n = sh.face ? sh.face.normal.clone().transformDirection(sh.object.matrixWorld) : UP.clone();
    if (n.dot(d) > 0) n.negate();
    best = { point: sh.point.clone(), normal: n, dist: sh.distance, kind: 'shape' };
  }
  if (best && state.mode !== 'select') {
    const sp = snapPoint(best.point);
    if (sp) { best.point = sp; best.kind = 'snap'; }
  }
  u.target = u.ui ? null : best;

  const ret = u.reticle;
  if (u.ui) { ret.visible = false; u.ray.scale.z = u.ui.hit.distance; }
  else if (best && !u.drag) {
    ret.visible = true; ret.position.copy(best.point);
    ret.quaternion.setFromUnitVectors(new V3(0, 0, 1), best.normal);
    ret.material.color.setHex(best.kind === 'snap' ? 0xffe14d : best.kind === 'shape' ? 0xff5ad1 : 0x00e5ff);
    u.ray.scale.z = best.dist;
  } else { ret.visible = false; u.ray.scale.z = best ? best.dist : 3; }
}
function updateHovers() {
  const hov = { menu: null, palette: null, ctx: null };
  for (const c of controllers) {
    const ui = c.userData.inputSource && c.userData.ui;
    if (!ui) continue;
    if (ui.kind === 'menu') hov.menu = buttonAt(ui.hit.uv);
    else hov[ui.kind] = popupItemAt(ui.kind === 'palette' ? palette : ctxMenu, ui.hit.uv)?.id ?? null;
  }
  if (hov.menu !== panel.hover) { panel.hover = hov.menu; panel.dirty = true; }
  for (const [k, p] of [['palette', palette], ['ctx', ctxMenu]]) if (p.open && hov[k] !== p.hover) { p.hover = hov[k]; drawPopup(p); }
}

// ---------------------------------------------------------------- controller input
// Trigger: select / press. Grip: grab to move (never resizes). B (right) while moving: free pick-up.
// Stick while holding: up/down = scale ±5%, left = 45° clockwise, right = 45° counter-clockwise.
// Stick click: main menu on that hand (both sticks: fixed in front). Hold A (right): object menu. Hold X (left): palette.
const SCALE_STEP = 1.05;   // stick up / down: +5% / -5% (reversible)
const NO_BTN = { trigger: false, grip: false, stick: false, low: false, high: false, sx: 0, sy: 0 };
function readButtons(c) {
  const src = c.userData.inputSource, gp = src?.gamepad;
  if (!gp || src.hand) return null;
  const p = i => !!gp.buttons[i]?.pressed;
  return { trigger: p(0), grip: p(1), stick: p(3), low: p(4), high: p(5), sx: gp.axes[2] || 0, sy: gp.axes[3] || 0 };
}
function processInput(c, now) {
  const u = c.userData, b = readButtons(c);
  if (!b) return;
  const prev = u.btn || NO_BTN; u.btn = b;
  const down = k => b[k] && !prev[k], up = k => !b[k] && prev[k];
  if (down('stick') && !u.drag) {
    const other = controllers.find(k => k !== c);
    if (state.menuVisible && state.menuAttach === other && now - (other.userData.stickDownAt ?? -1e9) < 400) openMenu(c, true);
    else if (state.menuVisible) closeMenu();
    else openMenu(c, false);
    u.stickDownAt = now;
  }
  if (u.inputSource.handedness !== 'left') {
    if (down('low')) { u.aDownAt = now; if (ctxMenu.open) { closePopup(ctxMenu); u.aDownAt = null; } }
    if (b.low && u.aDownAt != null && now - u.aDownAt > 250) { u.aDownAt = null; openContext(c); }
    if (up('low')) u.aDownAt = null;
  } else {
    if (down('low')) { openPalette(c); panel.mesh.visible = false; }
    if (up('low')) { closePopup(palette); panel.mesh.visible = state.menuVisible; }
  }
  if (u.drag?.type === 'move' && bHeld()) convertToFree(c);
  if (down('trigger')) onTriggerDown(c, b);
  if (down('grip')) onGripDown(c, b);
  if (up('trigger')) u.pressShape = null;
  const t = u.drag?.type;
  if ((t === 'handle' && up('trigger')) || ((t === 'move' || t === 'free') && (up('trigger') || up('grip')))) onDragRelease(c);
  if (u.drag && (u.drag.type === 'move' || u.drag.type === 'free')) {
    if (Math.abs(b.sx) < 0.3) u.latchX = false;
    if (Math.abs(b.sy) < 0.3) u.latchY = false;
    if (!u.latchX && Math.abs(b.sx) > 0.7) { u.latchX = true; rotateHeld(c, b.sx < 0 ? -Math.PI / 4 : Math.PI / 4); haptic(c, 0.3, 20); }
    if (!u.latchY && Math.abs(b.sy) > 0.7) { u.latchY = true; scaleHeld(c, b.sy < 0 ? SCALE_STEP : 1 / SCALE_STEP); haptic(c, 0.3, 20); }
  } else { u.latchX = u.latchY = true; }   // stick must return to centre after a grab starts
}
function onTriggerDown(c, b) {
  const u = c.userData; state.lastCtrl = c;
  if (u.ui) {
    if (u.ui.kind === 'menu') { const id = buttonAt(u.ui.hit.uv); if (id) { haptic(c, 0.4, 30); onButton(id, c); } }
    else if (u.ui.kind === 'palette') { const it = popupItemAt(palette, u.ui.hit.uv); if (it) spawnFromPalette(c, it, u.ui.hit.point); }
    else { const it = popupItemAt(ctxMenu, u.ui.hit.uv); if (it) { haptic(c, 0.4, 30); runContext(it.id); } }
    return;
  }
  if (ctxMenu.open) { closePopup(ctxMenu); return; }
  if (u.handleHit && !b.grip && !anyoneCarrying()) { startHandle(c, u.handleHit.object); haptic(c); return; }
  if (state.mode !== 'select') {
    const p = u.target ? u.target.point : pointTarget(c);
    if (!u.target) setStatus('No surface there: used a point 80 cm along the ray.');
    haptic(c); addPendingPoint(p); return;
  }
  if (u.shapeHit) {
    const s = u.shapeHit.object.userData.shape;
    select(s); u.pressShape = s; haptic(c, 0.2, 15);
    if (b.grip && !refusePinned(c, s)) startMove(c, s);
    return;
  }
  if (state.selected) select(null);
}
function onGripDown(c, b) {
  const u = c.userData; state.lastCtrl = c;
  if (u.ui?.kind === 'palette') { const it = popupItemAt(palette, u.ui.hit.uv); if (it) spawnFromPalette(c, it, u.ui.hit.point); return; }
  if (u.drag?.type === 'handle') {
    // Grip during a resize: stop resizing (size stays) and grab to move instead.
    const hs = u.drag.shape; u.drag = null;
    if (!refusePinned(c, hs)) startMove(c, hs);
    return;
  }
  if (u.ui || state.mode !== 'select' || u.drag) return;
  const s = (b.trigger && u.pressShape) || u.shapeHit?.object.userData.shape;
  if (!s) return;
  select(s);
  if (refusePinned(c, s)) return;
  // Grabbing only ever moves a shape. Size and rotation change only with the stick (snap steps).
  startMove(c, s);
  haptic(c);
}
function onDragRelease(c) {
  const u = c.userData, dr = u.drag;
  if (!dr) return;
  u.drag = null;
  if (dr.type === 'move' || dr.type === 'free') { settle(dr.shape); gridPatch.visible = false; setStatus(`${dr.shape.name} placed`); }
  persist(); panel.dirty = true;
}
// Pinned shapes stay put: no grabbing, carrying, resizing or dropping until unpinned from the hold-A menu.
function setPinned(s, on) {
  s.pinned = on;
  if (state.selected === s) select(s); else refreshShape(s);
  panel.dirty = true;
}
function anyoneCarrying() { return controllers.some(k => k.userData.drag && (k.userData.drag.type === 'move' || k.userData.drag.type === 'free')); }
function refusePinned(c, s) {
  if (!s?.pinned) return false;
  setStatus(`${s.name} is pinned. Hold A on it and pick Unpin to move it.`);
  haptic(c, 0.6, 60);
  return true;
}
function snapUndo(s) { const sn = snapshot(s); return { undo: () => applySnapshot(s, sn) }; }
function startMove(c, s) {
  if (bHeld()) { startFree(c, s, true); return; }
  const { o } = rayOf(c);
  pushHistory(snapUndo(s));
  state.falling = state.falling.filter(f => f.shape !== s);
  c.userData.drag = { type: 'move', shape: s, c0: o.clone(), yaw0: yawOf(c), p0: s.group.position.clone(), baseY: s.group.position.y };
  setStatus(`Moving ${s.name}`);
}
function updateMove(c, dr) {
  const { o } = rayOf(c);
  const qy = new THREE.Quaternion().setFromAxisAngle(UP, yawOf(c) - dr.yaw0);
  const p = o.add(dr.p0.clone().sub(dr.c0).applyQuaternion(qy));
  const g = dr.shape.group;
  g.position.set(snapGrid(p.x), dr.baseY, snapGrid(p.z));
  refreshShape(dr.shape);
  showGridPatch(g.position.x, dr.baseY - halfHeight(dr.shape), g.position.z);
}
function startFree(c, s, pushUndo) {
  if (pushUndo) pushHistory(snapUndo(s));
  state.falling = state.falling.filter(f => f.shape !== s);
  c.updateMatrixWorld(true); s.group.updateMatrixWorld(true);
  c.userData.drag = { type: 'free', shape: s, rel: c.matrixWorld.clone().invert().multiply(s.group.matrixWorld) };
  setStatus(`Carrying ${s.name}`);
}
function convertToFree(c) { startFree(c, c.userData.drag.shape, false); haptic(c, 0.5, 40); }
function updateFree(c, dr) {
  const g = dr.shape.group;
  c.matrixWorld.clone().multiply(dr.rel).decompose(g.position, g.quaternion, new V3());
  refreshShape(dr.shape);
  showGridPatch(g.position.x, supportBelow(g.position.x, g.position.z, g.position.y, dr.shape), g.position.z);
}
function rotateHeld(c, ang) {
  const dr = c.userData.drag, g = dr.shape.group, qy = new THREE.Quaternion().setFromAxisAngle(UP, ang);
  if (dr.type === 'move') g.quaternion.copy(snapYawQuat(qy.multiply(g.quaternion)));
  else { g.quaternion.premultiply(qy); g.updateMatrixWorld(true); dr.rel = c.matrixWorld.clone().invert().multiply(g.matrixWorld); }
  refreshShape(dr.shape);
  setStatus(`${dr.shape.name}: rotated 45° ${ang < 0 ? 'clockwise' : 'counter-clockwise'}`);
}
function scaleHeld(c, f) {
  const dr = c.userData.drag, s = dr.shape;
  const bottom = s.group.position.y - halfHeight(s);
  for (const k of Object.keys(s.dims)) s.dims[k] = Math.max(MIN_SIZE, Math.round(s.dims[k] * f * 1000) / 1000);
  if (dr.type === 'move') { dr.baseY = bottom + halfHeight(s); s.group.position.y = dr.baseY; }
  refreshShape(s);
  setStatus(`${s.name}: ${dimsText(s)}`);
}
// Grip alone on a shape: push the controller forward to grow, pull back to shrink (x2 per 20 cm).
function closestT(p0, dir, o, r) {
  // Closest point on line p0 + dir*t to the ray o + r*u. Returns t.
  const w = p0.clone().sub(o), b = dir.dot(r), dd = dir.dot(w), e = r.dot(w);
  const denom = 1 - b * b;
  if (denom < 1e-5) return null;
  return (b * e - dd) / denom;
}
function startHandle(c, handle) {
  const hd = handle.userData.handle, s = hd.shape, g = s.group;
  pushHistory(snapUndo(s));
  const axisW = hd.axis.clone().applyQuaternion(g.quaternion).normalize();
  const fixedW = hd.mode === 'face' ? g.position.clone().addScaledVector(axisW, -extent(s, hd.key) / 2) : g.position.clone();
  c.userData.drag = { type: 'handle', shape: s, hd, axisW, fixedW };
  setStatus(`Resizing ${s.name}`);
}
function updateHandle(c, dr) {
  const { o, d } = rayOf(c);
  const t = closestT(dr.fixedW, dr.axisW, o, d);
  if (t === null) return;
  const v = Math.round(Math.max(MIN_SIZE, t) * 1000) / 1000;   // 1 mm steps
  const { shape: s, hd } = dr;
  if (hd.mode === 'face') {
    s.dims[hd.key] = v;
    s.group.position.copy(dr.fixedW).addScaledVector(dr.axisW, v / 2);
  } else s.dims.r = v;
  refreshShape(s);
  setStatus(`${s.name}: ${dimsText(s)}`);
}

function updatePreview() {
  const c = state.lastCtrl;
  if (!state.pending.length || !c?.userData.target) { preview.line.visible = false; preview.label.sprite.visible = false; return; }
  const p = c.userData.target.point;
  const pts = [...state.pending, p];
  while (pts.length < 4) pts.push(p);
  preview.line.geometry.setFromPoints(pts);
  preview.line.computeLineDistances();
  preview.line.visible = true;
  if (state.mode === 'tape') {
    const a = state.pending[0], dv = p.clone().sub(a);
    setLabel(preview.label, [L(dv.length()), `↕ ${L(Math.abs(dv.y))}  ·  ↔ ${L(Math.hypot(dv.x, dv.z))}`], '#ffe14d');
    preview.label.sprite.position.copy(a).lerp(p, 0.5).add(new V3(0, 0.05, 0));
    preview.label.sprite.visible = true;
  } else if (state.pending.length === 2) {
    const circ = circleFrom3(state.pending[0], state.pending[1], p);
    if (circ) {
      setLabel(preview.label, [`Ø ${L(2 * circ.r)}`, `r ${L(circ.r)}`], '#ffe14d');
      preview.label.sprite.position.copy(circ.center).add(new V3(0, 0.05, 0));
      preview.label.sprite.visible = true;
    }
  } else preview.label.sprite.visible = false;
}

// ---------------------------------------------------------------- main loop
const DRAG_UPDATE = { move: updateMove, free: updateFree, handle: updateHandle };
renderer.setAnimationLoop((time, frame) => {
  const ref = renderer.xr.getReferenceSpace();
  const now = performance.now();
  if (frame && ref) updateRoom(frame, ref);
  // Hand tracking has no sticks: keep the menu fixed in front so it's always reachable.
  if (!state.menuVisible && controllers.some(isHand) && !controllers.some(k => readButtons(k))) openMenu(null, true);
  if (state.menuVisible) updateMenuPlacement(!panel.placed);
  for (const c of controllers) {
    updatePointer(c, frame, ref);
    processInput(c, now);
    const dr = c.userData.drag;
    if (dr) DRAG_UPDATE[dr.type](c, dr);
  }
  updateHovers();
  if (ctxLink.visible && !ctxMenu.open) ctxLink.visible = false;
  updateFalling(now);
  updatePreview();
  if (panel.dirty) drawPanel();
  renderer.render(scene, camera);
});

// ---------------------------------------------------------------- session start / end
const enterBtn = document.getElementById('enter'), supportEl = document.getElementById('support');
async function checkSupport() {
  if (!navigator.xr) { supportEl.textContent = 'WebXR not available. Open this page in the Meta Quest Browser on the headset.'; supportEl.className = 'bad'; return; }
  const ok = await navigator.xr.isSessionSupported('immersive-ar').catch(() => false);
  if (!ok) { supportEl.textContent = 'This browser cannot run AR. Open this page in the Meta Quest Browser on a Quest 3 / 3S.'; supportEl.className = 'bad'; return; }
  supportEl.textContent = 'Ready. Put the headset on and press Enter AR.';
  enterBtn.disabled = false;
}
enterBtn.addEventListener('click', async () => {
  try {
    const session = await navigator.xr.requestSession('immersive-ar', {
      requiredFeatures: ['local-floor'],
      optionalFeatures: ['hit-test', 'plane-detection', 'mesh-detection', 'hand-tracking', 'anchors'],
    });
    session.addEventListener('end', onSessionEnd);
    await renderer.xr.setSession(session);
    panel.placed = false; closeMenu();
    setStatus('Click a thumbstick for the menu.');
  } catch (err) {
    supportEl.textContent = `Could not start AR: ${err.message}`; supportEl.className = 'bad';
  }
});
function onSessionEnd() {
  for (const c of controllers) onDisconnected(c);
  room.planes.forEach(e => room.group.remove(e.obj)); room.planes.clear();
  room.meshes.forEach(e => room.group.remove(e.obj)); room.meshes.clear();
  persist(); renderReport();
}
checkSupport();

// ---------------------------------------------------------------- persistence + report + export
function sceneData() {
  return {
    app: 'Framespace', build: BUILD, savedAt: new Date().toISOString(), units: state.units,
    shapes: state.shapes.map(s => ({ name: s.name, type: s.type, dims: s.dims, volume_m3: volumeOf(s), position: s.group.position.toArray(), quaternion: s.group.quaternion.toArray(), ...(s.outline ? { outline: s.outline } : {}), ...(s.pinned ? { pinned: true } : {}) })),
    measurements: state.measures.map(m => {
      const base = { name: m.name, type: m.type, points: m.points.map(p => p.toArray()) };
      if (m.type === 'line') { const d = m.points[1].clone().sub(m.points[0]); return { ...base, distance_m: d.length(), vertical_m: Math.abs(d.y), horizontal_m: Math.hypot(d.x, d.z) }; }
      return { ...base, radius_m: m.r, diameter_m: 2 * m.r, circumference_m: 2 * Math.PI * m.r, center: m.center.toArray() };
    }),
    room: room.planeInfo.map(p => ({ label: p.label || p.orientation, width_m: p.w, depth_m: p.d, area_m2: p.w * p.d })),
  };
}
let lastRoom = [];
function persist() {
  const data = sceneData();
  if (data.room.length) lastRoom = data.room; else data.room = lastRoom;
  try { localStorage.setItem(STORE_KEY, JSON.stringify(data)); } catch {}
}
function loadSaved() { try { return JSON.parse(localStorage.getItem(STORE_KEY) || 'null'); } catch { return null; } }
function currentData() { const live = sceneData(); if (!live.room.length) live.room = lastRoom; return (live.shapes.length || live.measurements.length) ? live : (loadSaved() || live); }

const esc = s => String(s).replace(/[&<>"]/g, ch => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[ch]));
function dataShapeLines(sd) { const fake = { ...sd, dims: sd.dims }; return shapeLines(fake); }
function renderReport() {
  const data = currentData();
  const el = document.getElementById('report');
  if (!data.shapes.length && !data.measurements.length && !data.room.length) { el.innerHTML = '<p class="sub">Nothing measured yet.</p>'; return; }
  const prevUnits = state.units; state.units = data.units || state.units;
  let html = '';
  if (data.measurements.length) {
    html += '<h3>Measurements</h3><table><tr><th>Name</th><th>Type</th><th>Result</th><th>Details</th></tr>';
    for (const m of data.measurements) {
      if (m.type === 'line') html += `<tr><td>${esc(m.name)}</td><td>Tape</td><td>${L(m.distance_m)}</td><td>vertical ${L(m.vertical_m)}, horizontal ${L(m.horizontal_m)}</td></tr>`;
      else html += `<tr><td>${esc(m.name)}</td><td>Circle</td><td>Ø ${L(m.diameter_m)}</td><td>radius ${L(m.radius_m)}, circumference ${L(m.circumference_m)}</td></tr>`;
    }
    html += '</table>';
  }
  if (data.shapes.length) {
    html += '<h3>Shapes</h3><table><tr><th>Name</th><th>Dimensions</th><th>Volume</th></tr>';
    for (const s of data.shapes) { const lines = dataShapeLines(s); html += `<tr><td>${esc(s.name)}</td><td>${esc(lines[1])}</td><td>${esc(lines[2].replace('Vol ', ''))}</td></tr>`; }
    html += '</table>';
  }
  if (data.room.length) {
    html += '<h3>Room surfaces (from Space Setup)</h3><table><tr><th>Surface</th><th>Size</th><th>Area</th></tr>';
    for (const p of data.room) html += `<tr><td>${esc(p.label)}</td><td>${L(p.width_m)} × ${L(p.depth_m)}</td><td>${AREA(p.area_m2)}</td></tr>`;
    html += '</table>';
  }
  state.units = prevUnits;
  el.innerHTML = html;
}
function toCSV(data) {
  const rows = [['kind', 'name', 'type', 'length_m', 'width_m', 'height_m', 'depth_m', 'radius_m', 'diameter_m', 'volume_m3', 'area_m2', 'distance_m', 'vertical_m', 'horizontal_m', 'circumference_m']];
  const f = v => v === undefined || v === null ? '' : (+v).toFixed(4);
  for (const m of data.measurements) rows.push(m.type === 'line'
    ? ['measurement', m.name, 'tape', '', '', '', '', '', '', '', '', f(m.distance_m), f(m.vertical_m), f(m.horizontal_m), '']
    : ['measurement', m.name, 'circle', '', '', '', '', f(m.radius_m), f(m.diameter_m), '', '', '', '', '', f(m.circumference_m)]);
  for (const s of data.shapes) {
    const d = s.dims;
    if (s.type === 'box') rows.push(['shape', s.name, s.type, '', f(d.x), f(d.y), f(d.z), '', '', f(s.volume_m3), '', '', '', '', '']);
    else if (s.type === 'sphere') rows.push(['shape', s.name, s.type, '', '', '', '', f(d.r), f(2 * d.r), f(s.volume_m3), '', '', '', '', '']);
    else rows.push(['shape', s.name, s.type, '', '', f(d.h), '', f(d.r), f(2 * d.r), f(s.volume_m3), '', '', '', '', '']);
  }
  for (const p of data.room) rows.push(['room', p.label, 'plane', f(p.width_m), f(p.depth_m), '', '', '', '', '', f(p.area_m2), '', '', '', '']);
  return rows.map(r => r.map(c => /[",\n]/.test(c) ? `"${c.replace(/"/g, '""')}"` : c).join(',')).join('\n');
}
function download(name, blob) {
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob); a.download = name;
  document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(a.href), 4000);
}
const stamp = () => new Date().toISOString().slice(0, 16).replace(/[:T]/g, '-');
function exportScene(data) {
  const root = new THREE.Group(); root.name = 'Framespace';
  for (const s of data.shapes) {
    const fake = { type: s.type, dims: s.dims };
    const mesh = new THREE.Mesh(UNIT_GEO[s.type], new THREE.MeshStandardMaterial({ color: COLORS[s.type], transparent: true, opacity: 0.5 }));
    mesh.scale.copy(scaleOf(fake));
    const g = new THREE.Group(); g.name = s.name; g.position.fromArray(s.position); g.quaternion.fromArray(s.quaternion);
    g.userData = { type: s.type, dims_m: s.dims, volume_m3: s.volume_m3 };
    g.add(mesh); root.add(g);
  }
  for (const m of data.measurements) {
    const pts = m.points.map(p => new V3().fromArray(p));
    const line = new THREE.Line(new THREE.BufferGeometry().setFromPoints(m.type === 'line' ? pts : [...pts, pts[0]]), new THREE.LineBasicMaterial({ color: 0xffe14d }));
    line.name = m.name; line.userData = { ...m, points: undefined };
    root.add(line);
  }
  return root;
}
document.getElementById('dl-csv').onclick = () => download(`framespace-${stamp()}.csv`, new Blob([toCSV(currentData())], { type: 'text/csv' }));
document.getElementById('dl-json').onclick = () => download(`framespace-${stamp()}.json`, new Blob([JSON.stringify(currentData(), null, 2)], { type: 'application/json' }));
document.getElementById('dl-glb').onclick = () => {
  new GLTFExporter().parse(exportScene(currentData()), glb => download(`framespace-${stamp()}.glb`, new Blob([glb], { type: 'model/gltf-binary' })), err => alert('Export failed: ' + err), { binary: true });
};
document.getElementById('copy-report').onclick = async (e) => {
  const csv = toCSV(currentData());
  try { await navigator.clipboard.writeText(csv); e.target.textContent = 'Copied!'; } catch { e.target.textContent = 'Copy blocked'; }
  setTimeout(() => (e.target.textContent = 'Copy to clipboard'), 2000);
};
document.getElementById('restore').onclick = () => {
  const data = loadSaved();
  if (!data) return;
  if (state.shapes.length || state.measures.length) return;   // only restore into an empty scene
  state.units = data.units || 'metric';
  for (const s of data.shapes) makeShape(s.type, s.dims, new V3().fromArray(s.position), new THREE.Quaternion().fromArray(s.quaternion), s.name, s.outline);
  for (const m of data.measurements) createMeasure(m.type, m.points.map(p => new V3().fromArray(p)), m.name);
  state.counters.m = state.measures.length;
  lastRoom = data.room || [];
  renderReport();
  document.getElementById('restore').textContent = 'Restored. Enter AR to see it';
};
renderReport();

// Test hook (used by the automated emulator test; harmless on the headset).
window.__framespace = { THREE, palette, ctxMenu, ctxLink, PALETTE, state, onButton, controllers, sceneData, toCSV, panel, buttonAt, exportScene };
