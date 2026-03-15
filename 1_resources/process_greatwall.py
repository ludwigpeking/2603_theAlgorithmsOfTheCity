"""
process_greatwall.py
Export greatWall.tif as PNG heightmap + colour map for Three.js 3D viewer.

Outputs (written to same directory as this script):
  gw_heightmap.png       — greyscale PNG (elevation normalised 0-255)
  gw_heightmap_color.png — RGB PNG (hypsometric + sea + lakes + rivers)
  gw_heightmap.json      — metadata (dims, bounds, elev min/max for decode)

Pipeline mirrors geo/export_heightmap.py:
  Priority-Flood sink fill → D8 flow direction → flow accumulation → rivers.

Target size: height = 1080 px.  Width computed from geographic aspect ratio.
Run from the 1_resources/ directory:
  cd 1_resources
  python process_greatwall.py
"""

import rasterio, heapq as _hq, math, json
import numpy as np
from rasterio.enums import Resampling
from scipy.ndimage import label as _label, distance_transform_cdt, binary_dilation
from PIL import Image

INPUT    = "greatWall.tif"
NODATA   = -32768
TARGET_H = 1080

# ── Elevation colour stops for China / Great Wall terrain ─────────────────────
# Spans coastal plains (0 m) → Loess Plateau / mountains (2000–4000 m).
ELEV_STOPS = [
    ( -60, (  5,  45, 100)),   # deep sea
    (  -1, ( 15,  90, 175)),   # shallow sea
    (   0, ( 25, 110, 190)),   # coastline
    (   1, (218, 212, 152)),   # coastal plain
    (  80, (182, 208, 122)),   # low plains
    ( 280, (135, 182,  88)),   # rolling hills
    ( 650, (115, 158,  62)),   # uplands
    (1200, (152, 138,  68)),   # low mountains
    (1900, (132, 102,  48)),   # mountains
    (3000, (148, 128, 108)),   # high mountains
    (4500, (192, 182, 172)),   # very high
    (6500, (232, 228, 224)),   # alpine / snow-capped
]

def interp_color(val):
    s = ELEV_STOPS
    if val <= s[0][0]:  return np.array(s[0][1],  np.float32)
    if val >= s[-1][0]: return np.array(s[-1][1],  np.float32)
    for i in range(1, len(s)):
        if val <= s[i][0]:
            t = (val - s[i-1][0]) / (s[i][0] - s[i-1][0])
            return np.array(s[i-1][1], np.float32)*(1-t) + np.array(s[i][1], np.float32)*t

# ── River drainage-area tiers in km² ─────────────────────────────────────────
# Converted to cell counts after unit_m is known.
# Colours go light→dark blue (lighter = smaller stream).
RIVER_TIERS_KM2 = [
    ( 1_000,  0, [130, 185, 225]),  # minor streams  ~1 000 km²
    ( 5_000,  0, [ 90, 155, 210]),  # medium rivers  ~5 000 km²
    (20_000,  1, [ 55, 120, 195]),  # main rivers   ~20 000 km²
    (80_000,  2, [ 15,  80, 178]),  # major (Yellow River trunk)
]

def _disk(r):
    y, x = np.ogrid[-r:r+1, -r:r+1]
    return (x*x + y*y <= r*r)

MIN_RIVER_SEG = 12   # drop isolated pixel blobs shorter than this

def _filter_river(mask):
    lab, _ = _label(mask)
    sizes  = np.bincount(lab.ravel())
    sizes[0] = 0
    return (lab > 0) & (sizes[lab] >= MIN_RIVER_SEG)

# ── Load + downsample ─────────────────────────────────────────────────────────
print("Loading raster …")
with rasterio.open(INPUT) as src:
    bounds  = src.bounds
    lat_mid = (bounds.top + bounds.bottom) / 2
    # Geographic aspect ratio corrected for latitude compression
    geo_ar  = (bounds.right - bounds.left) * math.cos(math.radians(lat_mid)) \
              / (bounds.top - bounds.bottom)
    target_w = round(TARGET_H * geo_ar)

    # NEAREST  → pure integer pixel values; used for sea/lake detection
    # BILINEAR → smooth averages; used for hydrology + tinting
    elev_near = src.read(1, out_shape=(TARGET_H, target_w),
                         resampling=Resampling.nearest).astype(np.float32)
    elev_raw  = src.read(1, out_shape=(TARGET_H, target_w),
                         resampling=Resampling.bilinear).astype(np.float32)

H, W = elev_raw.shape

nodata_mask = elev_near <= (NODATA + 100)
elev_near[nodata_mask] = 0.0
elev_raw [nodata_mask] = 0.0
valid = ~nodata_mask
print(f"  Grid: {W} × {H}   geo_ar = {geo_ar:.3f}")

# ── Cell size in metres ───────────────────────────────────────────────────────
unit_m = (bounds.right - bounds.left) * math.cos(math.radians(lat_mid)) * 111_320 / W
print(f"  unit_m = {unit_m:.1f} m/px")

# Convert km² thresholds to cell counts
cell_area_km2 = (unit_m / 1000) ** 2
RIVER_TIERS = [
    (max(10, int(km2 / cell_area_km2)), radius, color)
    for km2, radius, color in RIVER_TIERS_KM2
]
for (km2, _, _), (thresh, _, _) in zip(RIVER_TIERS_KM2, RIVER_TIERS):
    print(f"  River {km2:>7,} km2  ->  {thresh:,} cells")

# ── Sea detection (boundary-connected pixels at or below 0 m) ─────────────────
raw_sea = (elev_near <= 0) & valid
labeled, _ = _label(raw_sea)
bnd = (set(labeled[0,:]) | set(labeled[-1,:]) |
       set(labeled[:,0]) | set(labeled[:,-1]))
bnd.discard(0)
sea_mask = np.isin(labeled, list(bnd)) & valid

# ── Lake detection (flat pixels above sea level) ──────────────────────────────
dy, dx    = np.gradient(elev_near)
lake_mask = (dx == 0) & (dy == 0) & (elev_near > 0) & valid

MIN_LAKE_PX = 30
_lk_lab, _ = _label(lake_mask)
_lk_sizes  = np.bincount(_lk_lab.ravel())
_lk_sizes[0] = 0
lake_mask = (_lk_lab > 0) & (_lk_sizes[_lk_lab] >= MIN_LAKE_PX)

print(f"  Sea pixels : {sea_mask.sum():,}   Lake pixels : {lake_mask.sum():,}")

# ── Smooth elevation for hydrology only ───────────────────────────────────────
# At 483 m/px a single noisy cell is a ~500 m bump — enough for D8 to route
# around it and break river continuity.  A light Gaussian (sigma=1.5 cells)
# removes sub-pixel noise while leaving valleys and ridges intact.
# elev_raw is kept unchanged for colour rendering and PNG export.
from scipy.ndimage import gaussian_filter as _gf
elev_hydro = _gf(elev_raw, sigma=1.5)
elev_hydro[nodata_mask] = 0.0

# ── Priority-Flood sink filling (Barnes et al. 2014) ─────────────────────────
print("Priority-Flood …")
high_val  = float(elev_hydro[valid].max()) + 9999.0
elev_work = elev_hydro.copy()
elev_work[nodata_mask] = high_val
filled    = elev_work.copy().astype(np.float64)
visited   = np.zeros(H * W, dtype=bool)
heap      = []
EPS       = 0.001
NBRS      = [(-1,0),(1,0),(0,-1),(0,1),(-1,-1),(-1,1),(1,-1),(1,1)]

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

# ── Flat-area routing (distance gradient to prevent flat-area artifacts) ──────
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
dist_to_drain  = distance_transform_cdt(~(has_lower & valid), metric='chessboard').astype(np.float32)
elev_d8        = filled + dist_to_drain * 0.01   # 10× stronger: decisive routing on flat plains

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
land_mask = valid & ~sea_mask & ~lake_mask
elev_tint = elev_raw.copy()
elev_tint[land_mask & (elev_tint < 1)] = 1.0

rgb  = np.zeros((H, W, 3), dtype=np.uint8)
flat = elev_tint.ravel()
for idx in range(len(flat)):
    r, c = divmod(idx, W)
    if valid[r, c]:
        rgb[r, c] = np.clip(interp_color(flat[idx]), 0, 255).astype(np.uint8)

rgb[sea_mask]    = [ 25, 105, 190]
rgb[lake_mask]   = [ 75, 148, 210]
rgb[nodata_mask] = [ 25, 105, 190]  # nodata boxes → same as sea

# Paint rivers from narrow (low tier) to wide (high tier) so wider overwrites.
# Do NOT exclude sea_mask here: near-sea-level river cells (delta, lower reaches)
# would otherwise create gaps that fragment paths below MIN_RIVER_SEG → removed.
# Rivers naturally overwrite sea colour where they meet the coast.
for thresh, radius, color in RIVER_TIERS:
    mask = _filter_river((accum_2d >= thresh) & valid)
    if mask.any():
        rgb[binary_dilation(mask, structure=_disk(radius))] = color

for thresh, _, _ in RIVER_TIERS:
    n = int(((accum_2d >= thresh) & valid).sum())
    print(f"  River cells >= {thresh:>7,} : {n:,}")

# ── Save outputs ───────────────────────────────────────────────────────────────
min_e = float(elev_raw[valid].min())
max_e = float(elev_raw[valid].max())

# 16-bit elevation encoded as two 8-bit channels (R = high byte, G = low byte).
# This gives 65535 levels over the elevation range, avoiding the ~12 m banding
# that an 8-bit grayscale would produce (2998 m / 255 steps ≈ 11.8 m/step).
# The HTML decoder reads:  uint16 = R*256 + G
elev_u16 = np.clip((elev_raw - min_e) / (max_e - min_e) * 65535, 0, 65535).astype(np.uint16)
elev_u16[nodata_mask] = 0

elev_rg = np.zeros((H, W, 3), dtype=np.uint8)
elev_rg[:, :, 0] = (elev_u16 >> 8).astype(np.uint8)   # high byte → R
elev_rg[:, :, 1] = (elev_u16 & 0xFF).astype(np.uint8)  # low byte  → G

Image.fromarray(elev_rg, mode='RGB').save("gw_heightmap.png")
Image.fromarray(rgb, mode='RGB').save("gw_heightmap_color.png")

# ── Debug: all streams coloured by log-scaled flow accumulation ────────────────
# Every land cell with accum >= 2 is shown; colour goes light sky (low) → navy (high).
# This lets you verify the catchment routing independently of the tier thresholds.
print("Debug river map …")
log_acc = np.log1p(accum_2d.astype(np.float32))
log_max = float(log_acc[valid].max())
t = np.clip(log_acc / log_max, 0, 1)          # 0 = tiny trickle, 1 = trunk
stream_mask = (accum_2d >= 2) & valid

debug_rgb = np.full((H, W, 3), 220, dtype=np.uint8)   # neutral gray background
# Streams: light sky [185,220,245] → deep navy [10,45,120]
debug_rgb[stream_mask, 0] = np.clip(185 - 175 * t[stream_mask], 0, 255).astype(np.uint8)
debug_rgb[stream_mask, 1] = np.clip(220 - 175 * t[stream_mask], 0, 255).astype(np.uint8)
debug_rgb[stream_mask, 2] = np.clip(245 - 125 * t[stream_mask], 0, 255).astype(np.uint8)
Image.fromarray(debug_rgb, mode='RGB').save("gw_debug_rivers.png")
print(f"  gw_debug_rivers.png: {stream_mask.sum():,} stream cells painted")

# ── D8 flow-direction PNG (for 3D line debug in HTML) ─────────────────────────
# Each valid flowing cell stores its D8 direction (0-7, same order as DR/DC).
# Outlets and nodata store 255.  HTML uses this to draw LineSegments cell→downstream,
# floating above the terrain mesh so they cannot be overwritten by vertex colours.
flowing = valid & ~outlet
flowdir_img = np.full((H, W), 255, dtype=np.uint8)
flowdir_img[flowing] = best_dir[flowing].astype(np.uint8)
Image.fromarray(flowdir_img, mode='L').save("gw_flowdir.png")

# ── Log-normalised accumulation PNG (RG 16-bit, same encoding as heightmap) ───
log_acc_max = float(np.log1p(float(accum_2d[valid].max())))
accum_u16   = np.clip(
    np.log1p(accum_2d.astype(np.float32)) / log_acc_max * 65535, 0, 65535
).astype(np.uint16)
accum_rg = np.zeros((H, W, 3), dtype=np.uint8)
accum_rg[:, :, 0] = (accum_u16 >> 8).astype(np.uint8)
accum_rg[:, :, 1] = (accum_u16 & 0xFF).astype(np.uint8)
Image.fromarray(accum_rg, mode='RGB').save("gw_accum.png")
print(f"  gw_flowdir.png + gw_accum.png: D8 direction + log accumulation")

meta = {
    "width":    W,
    "height":   H,
    "min_elev": round(min_e, 1),
    "max_elev": round(max_e, 1),
    "unit_m":   round(unit_m, 2),
    "geo_ar":   round(geo_ar, 4),
    "bounds": {
        "west":  bounds.left,
        "east":  bounds.right,
        "south": bounds.bottom,
        "north": bounds.top,
    },
    "log_accum_max": round(log_acc_max, 4),
}
with open("gw_heightmap.json", "w") as f:
    json.dump(meta, f, indent=2)

print(f"\n  gw_heightmap.png       : {W}×{H}  elev {min_e:.0f} to {max_e:.0f} m")
print(f"  gw_heightmap_color.png : {W}×{H}  RGB with rivers")
print(f"  gw_heightmap.json      : metadata")
print(f"  unit_m = {unit_m:.1f} m/px,  cell area = {cell_area_km2*1e6:.0f} m2")
print("Done.")
