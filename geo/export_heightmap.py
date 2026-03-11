"""
Export greaterRome.tif as PNG heightmap + colour map for Three.js 3D viewer.
Outputs:
  heightmap.png       — greyscale PNG (elevation normalised 0-255)
  heightmap_color.png — RGB PNG (hypsometric + sea + lakes + rivers)
  heightmap.json      — metadata (dims, bounds, elev min/max for decode)

Runs the same Priority-Flood / D8 / flow-accumulation pipeline as
render_lazio.py so rivers match between 2D and 3D views.
"""

import rasterio, heapq as _hq, math, json
import numpy as np
from rasterio.enums import Resampling
from scipy.ndimage import label as _label, distance_transform_cdt
from PIL import Image

INPUT    = "greaterRome.tif"
NODATA   = -32768
TARGET_W = 512

# River tiers — same geographic km² intent as render_lazio.py.
# Cell area at 512×338 ≈ 187.6 m/unit → 35 194 m²/cell.
# Thresholds scaled from DOWNSAMPLE=2 (2116 m²/cell) by ×(2116/35194)=0.0601.
RIVER_TIERS = [
    (  2_500, 0, [110, 175, 228]),   # minor  ~88 km²   — 1 px centerline
    (  9_000, 0, [ 70, 148, 212]),   # medium ~317 km²  — 1 px
    ( 24_000, 1, [ 40, 115, 195]),   # main   ~844 km²  — 3 px
    ( 48_000, 1, [ 15,  80, 175]),   # Tiber  ~1690 km² — 3 px
]

ELEV_STOPS = [
    (-20,  (  8,  48, 107)),
    ( -1,  ( 20, 100, 180)),
    (  0,  ( 30, 120, 200)),
    (  1,  (230, 220, 160)),
    ( 60,  (180, 215, 120)),
    (200,  (110, 180,  75)),
    (450,  (160, 145,  75)),
    (850,  (135, 100,  50)),
    (1400, (105,  75,  45)),
    (1805, (155, 140, 130)),
]

def interp_color(val):
    s = ELEV_STOPS
    if val <= s[0][0]:  return np.array(s[0][1],  np.float32)
    if val >= s[-1][0]: return np.array(s[-1][1],  np.float32)
    for i in range(1, len(s)):
        if val <= s[i][0]:
            t = (val - s[i-1][0]) / (s[i][0] - s[i-1][0])
            return np.array(s[i-1][1], np.float32)*(1-t) + np.array(s[i][1], np.float32)*t

# ── load + downsample ─────────────────────────────────────────────────────────
# Read twice:
#   NEAREST → pure pixel values, used only for sea/lake mask detection
#   BILINEAR → smooth averages, used for Priority-Flood / D8 / river routing / tinting
print("Loading raster …")
with rasterio.open(INPUT) as src:
    bounds   = src.bounds
    lat_mid  = (bounds.top + bounds.bottom) / 2
    geo_ar   = (bounds.right - bounds.left) * math.cos(math.radians(lat_mid)) \
               / (bounds.top - bounds.bottom)
    target_h = round(TARGET_W / geo_ar)

    elev_near = src.read(1, out_shape=(target_h, TARGET_W),
                         resampling=Resampling.nearest).astype(np.float32)
    elev_raw  = src.read(1, out_shape=(target_h, TARGET_W),
                         resampling=Resampling.bilinear).astype(np.float32)

H, W = elev_raw.shape

# nodata mask from nearest (bilinear can interpolate nodata to look valid)
nodata_mask         = elev_near <= (NODATA + 100)
elev_near[nodata_mask] = 0.0
elev_raw[nodata_mask]  = 0.0
valid               = ~nodata_mask
print(f"  {W} x {H}   geo_ar={geo_ar:.3f}")

# ── sea detection — use NEAREST to get pure sea pixels (bilinear blurs coastline) ──
raw_sea  = (elev_near <= 0) & valid
labeled, _ = _label(raw_sea)
bnd = (set(labeled[0,:]) | set(labeled[-1,:]) |
       set(labeled[:,0]) | set(labeled[:,-1]))
bnd.discard(0)
sea_mask  = np.isin(labeled, list(bnd)) & valid

# ── lake detection (flat pixels above sea level) ───────────────────────────────
dy, dx    = np.gradient(elev_near)   # use nearest: bilinear smears flat lake edges
lake_mask = (dx == 0) & (dy == 0) & (elev_near > 0) & valid

# Drop isolated lake pixels — keep only connected components >= MIN_LAKE_PX.
# At 512×338, Lake Bracciano ≈ 1 500 px; noise = 1–5 px.  Threshold = 30 px.
MIN_LAKE_PX = 30
_lk_lab, _lk_n = _label(lake_mask)
_lk_sizes       = np.bincount(_lk_lab.ravel())
_lk_sizes[0]    = 0                         # background is not a lake
lake_mask       = (_lk_lab > 0) & (_lk_sizes[_lk_lab] >= MIN_LAKE_PX)

print(f"  Sea pixels : {sea_mask.sum():,}   Lake pixels : {lake_mask.sum():,}")

# ── Priority-Flood sink filling (Barnes et al. 2014) ─────────────────────────
print("Priority-Flood …")
high_val    = float(elev_raw[valid].max()) + 9999.0
elev_work   = elev_raw.copy()
elev_work[nodata_mask] = high_val
filled      = elev_work.copy().astype(np.float64)
visited     = np.zeros(H * W, dtype=bool)
heap        = []
EPS         = 0.001
NBRS        = [(-1,0),(1,0),(0,-1),(0,1),(-1,-1),(-1,1),(1,-1),(1,1)]

def _seed(r, c):
    idx = r * W + c
    if valid[r, c] and not visited[idx]:
        visited[idx] = True
        _hq.heappush(heap, (float(filled[r, c]), r, c))

for r in range(H):
    _seed(r, 0); _seed(r, W - 1)
for c in range(1, W - 1):
    _seed(0, c); _seed(H - 1, c)

while heap:
    w, r, c = _hq.heappop(heap)
    for dr, dc in NBRS:
        nr, nc = r + dr, c + dc
        if 0 <= nr < H and 0 <= nc < W:
            nidx = nr * W + nc
            if valid[nr, nc] and not visited[nidx]:
                nw = max(float(elev_work[nr, nc]), w + EPS)
                filled[nr, nc] = nw
                visited[nidx]  = True
                _hq.heappush(heap, (nw, nr, nc))

filled = filled.astype(np.float32)
print(f"  Done. Cells raised: {int((filled > elev_work).sum()):,}")

# ── Flat-area routing (distance gradient) ─────────────────────────────────────
DR = np.array([-1,-1, 0, 1, 1, 1, 0,-1], np.int32)
DC = np.array([ 0, 1, 1, 1, 0,-1,-1,-1], np.int32)
DD = np.array([1., 1.414, 1., 1.414, 1., 1.414, 1., 1.414], np.float32)

has_lower = np.zeros((H, W), dtype=bool)
for d in range(8):
    dr, dc = int(DR[d]), int(DC[d])
    rs = slice(max(0,-dr), H+min(0,-dr)); cs = slice(max(0,-dc), W+min(0,-dc))
    rn = slice(max(0, dr), H+min(0, dr)); cn = slice(max(0, dc), W+min(0, dc))
    has_lower[rs, cs] |= (filled[rn, cn] < filled[rs, cs])

has_lower[0,:] = has_lower[-1,:] = has_lower[:,0] = has_lower[:,-1] = True
dist_to_drain  = distance_transform_cdt(~(has_lower & valid),
                                        metric='chessboard').astype(np.float32)
elev_d8        = filled + dist_to_drain * 0.001

# ── D8 flow direction ──────────────────────────────────────────────────────────
print("D8 flow direction …")
rg = np.arange(H, dtype=np.int32).reshape(-1,1) * np.ones((1,W), np.int32)
cg = np.ones((H,1), np.int32) * np.arange(W, dtype=np.int32).reshape(1,-1)

all_drops = np.full((8, H, W), -np.inf, np.float32)
for d in range(8):
    dr, dc, dist = int(DR[d]), int(DC[d]), float(DD[d])
    rs = slice(max(0,-dr), H+min(0,-dr)); cs = slice(max(0,-dc), W+min(0,-dc))
    rn = slice(max(0, dr), H+min(0, dr)); cn = slice(max(0, dc), W+min(0, dc))
    all_drops[d, rs, cs] = (elev_d8[rs, cs] - elev_d8[rn, cn]) / dist

best_dir  = np.argmax(all_drops, axis=0)
best_drop = all_drops[best_dir, rg, cg]
flow_r    = np.clip(rg + DR[best_dir], 0, H-1).astype(np.int32)
flow_c    = np.clip(cg + DC[best_dir], 0, W-1).astype(np.int32)
outlet    = (best_drop <= 0)
flow_flat = flow_r * W + flow_c
flow_flat[outlet] = -1

# ── Flow accumulation ──────────────────────────────────────────────────────────
print("Flow accumulation …")
accum        = np.ones(H * W, dtype=np.int32)
valid_flat   = valid.ravel()
flow_flat_1d = flow_flat.ravel()
sorted_valid = np.argsort(-elev_d8.ravel())
sorted_valid = sorted_valid[valid_flat[sorted_valid]]
for idx in sorted_valid:
    down = flow_flat_1d[idx]
    if down >= 0:
        accum[down] += accum[idx]
accum_2d = accum.reshape(H, W)
print(f"  Max accumulation: {accum_2d[valid].max():,} cells")

# ── Hypsometric colours ────────────────────────────────────────────────────────
print("Computing colours …")
land_mask  = valid & ~sea_mask & ~lake_mask
elev_tint  = elev_raw.copy()
elev_tint[land_mask & (elev_tint < 1)] = 1.0

rgb  = np.zeros((H, W, 3), dtype=np.uint8)
flat = elev_tint.ravel()
for idx in range(len(flat)):
    r, c = divmod(idx, W)
    if valid[r, c]:
        rgb[r, c] = np.clip(interp_color(flat[idx]), 0, 255).astype(np.uint8)

rgb[sea_mask]  = [ 30, 110, 200]
rgb[lake_mask] = [ 70, 148, 212]

# Paint rivers lowest→highest tier so wider/darker tiers overwrite narrower ones
from scipy.ndimage import binary_dilation
def _disk(r):
    y, x = np.ogrid[-r:r+1, -r:r+1]
    return (x*x + y*y <= r*r)

MIN_RIVER_SEG = 15   # drop isolated dots / short disconnected segments

def _filter_river(mask):
    lab, _ = _label(mask)
    sizes  = np.bincount(lab.ravel())
    sizes[0] = 0
    return (lab > 0) & (sizes[lab] >= MIN_RIVER_SEG)

for thresh, radius, color in RIVER_TIERS:
    mask = _filter_river((accum_2d >= thresh) & valid)
    rgb[binary_dilation(mask, structure=_disk(radius))] = color

for thresh, _, _ in RIVER_TIERS:
    n = int(((accum_2d >= thresh) & valid).sum())
    print(f"  River cells >= {thresh:>7,} : {n:,}")

# ── Save ───────────────────────────────────────────────────────────────────────
min_e = float(elev_raw[valid].min())
max_e = float(elev_raw[valid].max())
elev_norm = np.clip((elev_raw - min_e) / (max_e - min_e) * 255, 0, 255).astype(np.uint8)
elev_norm[nodata_mask] = 0

Image.fromarray(elev_norm, mode='L').save("heightmap.png")
Image.fromarray(rgb, mode='RGB').save("heightmap_color.png")

unit_m = (bounds.right - bounds.left) * math.cos(math.radians(lat_mid)) * 111320 / W
meta = {
    "width":    W,
    "height":   H,
    "min_elev": round(min_e, 1),
    "max_elev": round(max_e, 1),
    "unit_m":   round(unit_m, 2),
    "geo_ar":   round(geo_ar, 4),
    "bounds": {
        "west": bounds.left, "east": bounds.right,
        "south": bounds.bottom, "north": bounds.top,
    }
}
with open("heightmap.json", "w") as f:
    json.dump(meta, f, indent=2)

print(f"  heightmap.png       : {W}x{H}  elev {min_e:.0f} to {max_e:.0f} m")
print(f"  heightmap_color.png : {W}x{H}  RGB with rivers")
print(f"  unit_m              : {unit_m:.1f} m/px")
