/**
 * sim-engine.js — pathfinding simulation engine for Chapter III
 * Direct port of the working code in geo/rome_sim.html.
 * Replaces THREE.js vertex-colour rendering with 2D canvas ImageData.
 *
 * Globals exposed:
 *   initTerrain(dataPath) → Promise   load terrain once before any createSim()
 *   createSim(canvasId, P)            factory — returns a sim instance
 *   bindSlider(id, valId, onChange)   UI helper
 *   wireButtons(prefix, sim, getPathDep?)  UI helper
 */

'use strict';

// ── Grid constants ─────────────────────────────────────────────────────────────
const COLS   = 512;
const ROWS   = 338;
const MIN_E  = -8.0;
const MAX_E  = 1792.0;
const UNIT_M = 187.6;
const N      = COLS * ROWS;
const NDIRS  = 16;

const SQ2  = Math.SQRT2, SQ5 = Math.sqrt(5);
const DR16 = new Int8Array([-1,1,0,0,-1,-1,1,1,-2,-2,2,2,-1,-1,1,1]);
const DC16 = new Int8Array([ 0,0,-1,1,-1,1,-1,1,-1,1,-1,1,-2,2,-2,2]);
const DD16 = new Float32Array([1,1,1,1,SQ2,SQ2,SQ2,SQ2,SQ5,SQ5,SQ5,SQ5,SQ5,SQ5,SQ5,SQ5]);

// ── Shared terrain arrays (filled by initTerrain, read-only after) ─────────────
let elevData, isWater, nbrIdx, nbrDElev, baseImageData;

// ── Image loader ──────────────────────────────────────────────────────────────
function readImg(src, w, h) {
  return new Promise((res, rej) => {
    const img = new Image();
    img.crossOrigin = 'anonymous';
    img.onload = () => {
      const cv  = Object.assign(document.createElement('canvas'), {width: w, height: h});
      const ctx = cv.getContext('2d');
      ctx.drawImage(img, 0, 0, w, h);
      res(ctx.getImageData(0, 0, w, h));
    };
    img.onerror = () => rej(new Error('Cannot load ' + src));
    img.src = src;
  });
}

// ── Load terrain once ─────────────────────────────────────────────────────────
async function initTerrain(dataPath) {
  const base = dataPath.replace(/\/?$/, '/');
  const [hImg, cImg] = await Promise.all([
    readImg(base + 'heightmap.png',       COLS, ROWS),
    readImg(base + 'heightmap_color.png', COLS, ROWS),
  ]);
  baseImageData = cImg;

  elevData = new Float32Array(N);
  isWater  = new Uint8Array(N);
  for (let i = 0; i < N; i++) {
    elevData[i] = (hImg.data[i*4] / 255) * (MAX_E - MIN_E) + MIN_E;
    const r = cImg.data[i*4], b = cImg.data[i*4+2];
    if (b > r + 50 && b > 170) isWater[i] = 1;
  }

  nbrIdx   = new Int32Array(N * NDIRS).fill(-1);
  nbrDElev = new Float32Array(N * NDIRS);
  for (let row = 0; row < ROWS; row++) {
    for (let col = 0; col < COLS; col++) {
      const i = row * COLS + col;
      for (let d = 0; d < NDIRS; d++) {
        const nr = row + DR16[d], nc = col + DC16[d];
        if (nr < 0 || nr >= ROWS || nc < 0 || nc >= COLS) continue;
        const nb = nr * COLS + nc;
        nbrIdx  [i * NDIRS + d] = nb;
        nbrDElev[i * NDIRS + d] = elevData[nb] - elevData[i];
      }
    }
  }
}

// ── MinHeap (copied from rome_sim.html) ───────────────────────────────────────
class MinHeap {
  constructor() { this.h = []; }
  push(pri, val) {
    this.h.push([pri, val]);
    let i = this.h.length - 1;
    while (i > 0) {
      const p = (i-1) >> 1;
      if (this.h[p][0] <= this.h[i][0]) break;
      [this.h[p], this.h[i]] = [this.h[i], this.h[p]]; i = p;
    }
  }
  pop() {
    const top = this.h[0], last = this.h.pop();
    if (this.h.length) {
      this.h[0] = last; let i = 0;
      for (;;) {
        let s=i, l=2*i+1, r=2*i+2;
        if (l < this.h.length && this.h[l][0] < this.h[s][0]) s=l;
        if (r < this.h.length && this.h[r][0] < this.h[s][0]) s=r;
        if (s === i) break;
        [this.h[i], this.h[s]] = [this.h[s], this.h[i]]; i = s;
      }
    }
    return top;
  }
  get size() { return this.h.length; }
}

// ── FastHeap — typed-array binary heap for dijkstraFrom ───────────────────────
// Uses Float32Array (keys) + Int32Array (values) to avoid GC pressure.
// Capacity = N * NDIRS = worst-case total pushes in Dijkstra.
class FastHeap {
  constructor(cap) {
    this._k = new Float32Array(cap);
    this._v = new Int32Array(cap);
    this._n = 0;
  }
  get size() { return this._n; }
  reset()    { this._n = 0; }
  push(k, v) {
    let i = this._n++;
    this._k[i] = k; this._v[i] = v;
    while (i > 0) {
      const p = (i - 1) >> 1;
      if (this._k[p] <= this._k[i]) break;
      let t;
      t = this._k[p]; this._k[p] = this._k[i]; this._k[i] = t;
      t = this._v[p]; this._v[p] = this._v[i]; this._v[i] = t;
      i = p;
    }
  }
  pop() {
    const v = this._v[0];
    const l = --this._n;
    if (l > 0) {
      this._k[0] = this._k[l]; this._v[0] = this._v[l];
      let i = 0;
      for (;;) {
        let s = i, a = 2*i+1, b = 2*i+2;
        if (a < l && this._k[a] < this._k[s]) s = a;
        if (b < l && this._k[b] < this._k[s]) s = b;
        if (s === i) break;
        let t;
        t = this._k[s]; this._k[s] = this._k[i]; this._k[i] = t;
        t = this._v[s]; this._v[s] = this._v[i]; this._v[i] = t;
        i = s;
      }
    }
    return v;
  }
}

// Pre-allocated reusable buffers for dijkstraFrom (module-level, single-threaded JS is safe)
const _dijkDist = new Float32Array(N);
const _dijkDone = new Uint8Array(N);
const _dijkHeap = new FastHeap(N * NDIRS); // worst-case capacity

// ── Simulation factory ────────────────────────────────────────────────────────
/**
 * Create one simulation instance tied to a canvas element.
 * All logic is a direct port of rome_sim.html's working code.
 * @param {string} canvasId   id of <canvas> element
 * @param {object} initP      { uphill, downhill, waterFactor, transition, maxSlope }
 */
function createSim(canvasId, initP) {
  const canvas = document.getElementById(canvasId);
  const ctx    = canvas.getContext('2d');
  const P      = {...initP};

  // Per-simulation state arrays
  const nbrBase        = new Float32Array(N * NDIRS).fill(Infinity);
  const nbrTc          = new Uint32Array(N * NDIRS);
  const cellUsage      = new Uint32Array(N);
  const cellTransCount = new Uint32Array(N);
  let   landPool       = [];
  let   isFarmable     = null;

  let running = false;
  let timer   = null;
  let travel  = 0;
  let found   = 0;

  // ── Build base costs (from rome_sim.html) ──────────────────────────────────
  function buildBaseCosts() {
    const slopeLimit = P.maxSlope > 0 ? P.maxSlope / 100 : Infinity;
    nbrBase.fill(Infinity);
    for (let i = 0; i < N; i++) {
      const wCur = isWater[i];
      for (let d = 0; d < NDIRS; d++) {
        const nb = nbrIdx[i * NDIRS + d];
        if (nb < 0) continue;
        const dist  = DD16[d];
        const dElev = nbrDElev[i * NDIRS + d];
        const slope = Math.abs(dElev) / (dist * UNIT_M);
        if (slope > slopeLimit) continue;
        const wNb = isWater[nb];
        let cost = (wCur && wNb) ? dist * P.waterFactor : dist;
        if (dElev > 0) cost += P.uphill   *  dElev  / UNIT_M * dist;
        else           cost += P.downhill * (-dElev) / UNIT_M * dist;
        if (!!wCur !== !!wNb) cost += P.transition;
        nbrBase[i * NDIRS + d] = cost;
      }
    }
    _buildFarmable();
    _rebuildLandPool();
  }

  function _buildFarmable() {
    isFarmable = new Uint8Array(N);
    for (let i = 0; i < N; i++) {
      if (isWater[i]) continue;
      let maxSl = 0;
      for (let d = 0; d < 8; d++) {
        const nb = nbrIdx[i * NDIRS + d]; if (nb < 0) continue;
        const sl = Math.abs(nbrDElev[i * NDIRS + d]) / (DD16[d] * UNIT_M);
        if (sl > maxSl) maxSl = sl;
      }
      if (maxSl >= 0.001 && maxSl <= 0.10) isFarmable[i] = 1;
    }
  }

  function _rebuildLandPool() {
    if (!isFarmable) return;
    landPool = [];
    for (let i = 0; i < N; i++) {
      if (!isFarmable[i]) continue;
      for (let d = 0; d < 8; d++) {
        if (isFinite(nbrBase[i * NDIRS + d])) { landPool.push(i); break; }
      }
    }
  }

  // ── Edge cost (from rome_sim.html) ─────────────────────────────────────────
  function edgeCost(i, d) {
    const base = nbrBase[i * NDIRS + d];
    if (!isFinite(base)) return Infinity;
    const tc = nbrTc[i * NDIRS + d];
    const moveFactor = 0.5 + Math.pow(0.5, tc + 1);
    const nb = nbrIdx[i * NDIRS + d];
    if (nb >= 0 && (!!isWater[i] !== !!isWater[nb])) {
      return (base - P.transition) * moveFactor + P.transition * Math.pow(0.5, tc);
    }
    return base * moveFactor;
  }

  // ── A* (from rome_sim.html, with MinHeap + done[] closed set) ──────────────
  function aStar(start, goal, usePathDep) {
    if (start === goal) return [start];
    const g    = new Float32Array(N).fill(Infinity);
    const came = new Int32Array(N).fill(-1);
    const done = new Uint8Array(N);
    const gr = Math.floor(goal / COLS), gc = goal % COLS;
    const h = idx => {
      const dr = Math.floor(idx / COLS) - gr, dc = (idx % COLS) - gc;
      return Math.sqrt(dr * dr + dc * dc);
    };
    g[start] = 0;
    const open = new MinHeap();
    open.push(h(start), start);
    while (open.size) {
      const [, cur] = open.pop();
      if (cur === goal) {
        const path = []; let c = goal;
        while (c !== -1) { path.push(c); c = came[c]; }
        return path.reverse();
      }
      if (done[cur]) continue;
      done[cur] = 1;
      for (let d = 0; d < NDIRS; d++) {
        const nb = nbrIdx[cur * NDIRS + d];
        if (nb < 0 || done[nb]) continue;
        const cost = usePathDep ? edgeCost(cur, d) : nbrBase[cur * NDIRS + d];
        if (!isFinite(cost)) continue;
        const ng = g[cur] + cost;
        if (ng < g[nb]) {
          g[nb] = ng; came[nb] = cur;
          open.push(ng + h(nb), nb);
        }
      }
    }
    return null;
  }

  // ── Record path (from rome_sim.html) ───────────────────────────────────────
  function recordPath(path) {
    for (let k = 0; k < path.length - 1; k++) {
      const cur = path[k], nb = path[k + 1];
      for (let d = 0; d < NDIRS; d++) {
        if (nbrIdx[cur * NDIRS + d] === nb) { nbrTc[cur * NDIRS + d]++; break; }
      }
      for (let d = 0; d < NDIRS; d++) {
        if (nbrIdx[nb  * NDIRS + d] === cur) { nbrTc[nb  * NDIRS + d]++; break; }
      }
      if (!!isWater[cur] !== !!isWater[nb]) {
        cellTransCount[cur]++;
        cellTransCount[nb]++;
      }
    }
  }

  function randomLandCell() {
    return landPool[Math.floor(Math.random() * landPool.length)];
  }

  // ── 2D canvas render (replaces applyTrafficToMesh from rome_sim.html) ──────
  // Hillshaded terrain base + ochre/blue/red traffic overlay.
  const ROAD_LAND  = [0.50, 0.35, 0.12];  // ochre
  const ROAD_WATER = [0.10, 0.40, 0.90];  // blue
  const ROAD_TRANS = [1.00, 0.05, 0.00];  // red
  const USAGE_SAT  = 5;
  const NBR_BLEED  = 0.4;

  function paint() {
    const img  = ctx.createImageData(COLS, ROWS);
    const data = img.data;
    const base = baseImageData.data;
    for (let i = 0; i < N; i++) {
      let u = cellUsage[i], uT = cellTransCount[i];
      for (let d = 0; d < 8; d++) {
        const nb = nbrIdx[i * NDIRS + d];
        if (nb >= 0) { u += cellUsage[nb] * NBR_BLEED; uT += cellTransCount[nb] * NBR_BLEED; }
      }
      const t  = Math.min(1, u  / USAGE_SAT);
      const tT = Math.min(1, uT / USAGE_SAT);
      const road = isWater[i] ? ROAD_WATER : ROAD_LAND;
      const bi   = i * 4;
      const s = _hillshade(Math.floor(i / COLS), i % COLS);
      let r, g, b;
      if (isWater[i]) { r = base[bi]/255; g = base[bi+1]/255; b = base[bi+2]/255; }
      else            { r = g = b = Math.min(1, s); }
      r = r*(1-t) + road[0]*t;
      g = g*(1-t) + road[1]*t;
      b = b*(1-t) + road[2]*t;
      r = r*(1-tT) + ROAD_TRANS[0]*tT;
      g = g*(1-tT) + ROAD_TRANS[1]*tT;
      b = b*(1-tT) + ROAD_TRANS[2]*tT;
      data[bi]   = r * 255;
      data[bi+1] = g * 255;
      data[bi+2] = b * 255;
      data[bi+3] = 255;
    }
    ctx.putImageData(img, 0, 0);
  }

  // ── Simulation tick (from rome_sim.html's simTick) ─────────────────────────
  function _tick(totalEl, countEl, foundEl, startBtn, stopBtn, usePathDep) {
    const total = Math.max(1, +totalEl.value || 100);
    for (let r = 0; r < 10 && travel < total; r++) {
      const s = randomLandCell(), g = randomLandCell();
      if (s === g) { r--; continue; }
      const path = aStar(s, g, usePathDep);
      travel++;
      if (path && path.length > 1) {
        for (const cell of path) cellUsage[cell]++;   // same as rome_sim.html
        recordPath(path);
        found++;
      }
    }
    countEl.textContent = `${travel} / ${total}`;
    foundEl.textContent = found;
    paint();
    if (travel < total) {
      timer = setTimeout(() => _tick(totalEl, countEl, foundEl, startBtn, stopBtn, usePathDep), 150);
    } else {
      stop(startBtn, stopBtn);
    }
  }

  function start(totalEl, countEl, foundEl, startBtn, stopBtn, usePathDep) {
    if (running) return;
    running = true;
    startBtn.disabled = true; stopBtn.disabled = false;
    _tick(totalEl, countEl, foundEl, startBtn, stopBtn, usePathDep);
  }

  function stop(startBtn, stopBtn) {
    running = false;
    clearTimeout(timer);
    startBtn.disabled = false; stopBtn.disabled = true;
  }

  function reset(totalEl, countEl, foundEl, startBtn, stopBtn) {
    stop(startBtn, stopBtn);
    nbrTc.fill(0); cellUsage.fill(0); cellTransCount.fill(0);
    travel = 0; found = 0;
    countEl.textContent = `0 / ${totalEl.value}`;
    foundEl.textContent = '0';
    paint();
  }

  function pathCost(path) {
    if (!path || path.length < 2) return 0;
    let total = 0;
    for (let k = 0; k < path.length - 1; k++) {
      const cur = path[k], nb = path[k + 1];
      for (let d = 0; d < NDIRS; d++) {
        if (nbrIdx[cur * NDIRS + d] === nb) { total += nbrBase[cur * NDIRS + d]; break; }
      }
    }
    return total;
  }

  // ── Dijkstra full cost map from a single source ────────────────────────
  // Returns Float32Array[N]: minimum travel cost from start to every tile.
  // Uses module-level pre-allocated buffers; no per-call allocation.
  function dijkstraFrom(start) {
    _dijkDist.fill(Infinity);
    _dijkDone.fill(0);
    _dijkDist[start] = 0;
    _dijkHeap.reset();
    _dijkHeap.push(0, start);
    while (_dijkHeap.size) {
      const cur = _dijkHeap.pop();
      if (_dijkDone[cur]) continue;
      _dijkDone[cur] = 1;
      const base = cur * NDIRS;
      for (let dir = 0; dir < NDIRS; dir++) {
        const nb = nbrIdx[base + dir];
        if (nb < 0 || _dijkDone[nb]) continue;
        const ec = nbrBase[base + dir];
        if (!isFinite(ec)) continue;
        const nd = _dijkDist[cur] + ec;
        if (nd < _dijkDist[nb]) {
          _dijkDist[nb] = nd;
          _dijkHeap.push(nd, nb);
        }
      }
    }
    return new Float32Array(_dijkDist); // copy — buffer is reused next call
  }

  return { P, buildBaseCosts, paint, start, stop, reset,
           findPath: (start, goal, usePathDep) => aStar(start, goal, usePathDep),
           pathCost, dijkstraFrom };
}

// ── Hillshade helper (shared by paint() and paintTerrain()) ──────────────────
// Matches rome_sim.html's sun: position(-260, 500, 300) with Lambert shading.
// Returns a multiplier: ~0.35 (shadow) … ~1.10 (full sun).
function _hillshade(row, col) {
  const eL = elevData[row * COLS + Math.max(0, col - 1)];
  const eR = elevData[row * COLS + Math.min(COLS - 1, col + 1)];
  const eU = elevData[Math.max(0, row - 1) * COLS + col];
  const eD = elevData[Math.min(ROWS - 1, row + 1) * COLS + col];
  const gx = (eR - eL) / (2 * UNIT_M);   // east gradient
  const gz = (eD - eU) / (2 * UNIT_M);   // south gradient
  // Surface normal: normalize([-gx, 1, -gz])
  const mag = Math.sqrt(gx * gx + 1 + gz * gz);
  // Sun dir normalized(-260, 500, 300) ≈ (-0.407, 0.783, 0.470)
  const dot = (0.407 * gx + 0.783 - 0.470 * gz) / mag;
  return 0.35 + 0.75 * Math.max(0, dot);
}

// ── Standalone drawing helpers ────────────────────────────────────────────────
function paintTerrain(ctx) {
  const img  = ctx.createImageData(COLS, ROWS);
  const data = img.data;
  const base = baseImageData.data;
  for (let row = 0; row < ROWS; row++) {
    for (let col = 0; col < COLS; col++) {
      const i  = row * COLS + col;
      const bi = i * 4;
      const s  = _hillshade(row, col);
      if (isWater[i]) {
        data[bi] = base[bi]; data[bi+1] = base[bi+1]; data[bi+2] = base[bi+2];
      } else {
        const v = Math.min(255, 255 * s);
        data[bi] = data[bi+1] = data[bi+2] = v;
      }
      data[bi+3] = 255;
    }
  }
  ctx.putImageData(img, 0, 0);
}

function drawPath(ctx, path, color) {
  if (!path || path.length < 2) return;
  ctx.save();
  ctx.strokeStyle = color;
  ctx.lineWidth = 2;
  ctx.beginPath();
  ctx.moveTo((path[0] % COLS) + 0.5, Math.floor(path[0] / COLS) + 0.5);
  for (let k = 1; k < path.length; k++) {
    ctx.lineTo((path[k] % COLS) + 0.5, Math.floor(path[k] / COLS) + 0.5);
  }
  ctx.stroke();
  ctx.restore();
}

function drawPin(ctx, idx, label, color) {
  if (idx < 0) return;
  const x = (idx % COLS) + 0.5;
  const y = Math.floor(idx / COLS) + 0.5;
  ctx.save();
  // White outline for contrast
  ctx.beginPath();
  ctx.arc(x, y, 7, 0, Math.PI * 2);
  ctx.strokeStyle = '#ffffff';
  ctx.lineWidth = 2.5;
  ctx.stroke();
  // Filled circle
  ctx.fillStyle = color;
  ctx.fill();
  // Label
  ctx.fillStyle = '#ffffff';
  ctx.font = 'bold 10px sans-serif';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText(label, x, y);
  ctx.restore();
}

// ── Slider binder helper ──────────────────────────────────────────────────────
function bindSlider(id, valId, onChange) {
  const el  = document.getElementById(id);
  const vEl = document.getElementById(valId);
  el.addEventListener('input', () => { vEl.textContent = el.value; if (onChange) onChange(+el.value); });
}

// ── Button wiring helper ──────────────────────────────────────────────────────
// getPathDep: optional function that returns bool (for path-dependency toggle)
function wireButtons(prefix, sim, getPathDep) {
  const startBtn = document.getElementById(prefix + '-start');
  const stopBtn  = document.getElementById(prefix + '-stop');
  const totalEl  = document.getElementById(prefix + '-total');
  const countEl  = document.getElementById(prefix + '-count');
  const foundEl  = document.getElementById(prefix + '-found');
  const pd = getPathDep || (() => false);
  startBtn.addEventListener('click', () => sim.start(totalEl, countEl, foundEl, startBtn, stopBtn, pd()));
  stopBtn .addEventListener('click', () => sim.stop(startBtn, stopBtn));
  document.getElementById(prefix + '-reset').addEventListener('click',
    () => sim.reset(totalEl, countEl, foundEl, startBtn, stopBtn));
}
