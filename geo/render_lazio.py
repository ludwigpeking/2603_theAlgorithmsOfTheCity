"""
Render greaterRome.tif (DTM, int16 metres) as a topographic PNG.
  - hypsometric tinting  (sea → coastal → green → brown → alpine)
  - hillshading          (NW light, slope-proportional depth)
  - water layers:
      sea          = elevation <= 0, connected to raster boundary (avoids delta false-sea)
      lakes        = burned-in flat pixels (slope==0, elev>0)
      rivers       = D8 flow accumulation threshold (hydrological analysis)
  - NoData (-32768) → transparent
"""

import rasterio
import numpy as np
from PIL import Image
from scipy.ndimage import binary_dilation

INPUT      = "greaterRome.tif"
OUTPUT     = "greaterRome.png"
DOWNSAMPLE = 2        # 2× downsampling (46 m pixels) avoids road/bridge artifacts
NODATA     = -32768

# River tiers: (min_accum_cells, dilation_radius_px, RGB_color)
# At DOWNSAMPLE=2, pixel ≈ 46 m ≈ 2120 m²
#   40 000 cells ≈  85 km² |  150 000 ≈ 317 km²
#  400 000 cells ≈ 847 km² | 1 000 000 ≈ 2100 km²
RIVER_TIERS = [
    (  40_000, 1, [110, 175, 228]),  # minor rivers   ~85 km²
    ( 150_000, 2, [ 70, 148, 212]),  # medium rivers  ~317 km²
    ( 400_000, 3, [ 40, 115, 195]),  # main rivers    ~847 km²
    (1_000_000, 5, [ 15,  80, 175]), # Tiber channel  ~2 100 km²
]

# ── hypsometric color stops (elevation m → RGB) ───────────────────────────────
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

LIGHT_AZ  = 315
LIGHT_ALT =  45
Z_SCALE   = 0.00008


# ── helpers ───────────────────────────────────────────────────────────────────
def interp_color(stops, val):
    if val <= stops[0][0]:  return np.array(stops[0][1], dtype=np.float32)
    if val >= stops[-1][0]: return np.array(stops[-1][1], dtype=np.float32)
    for i in range(len(stops) - 1):
        v0, c0 = stops[i]; v1, c1 = stops[i+1]
        if v0 <= val <= v1:
            t = (val - v0) / (v1 - v0)
            return np.array(c0, dtype=np.float32)*(1-t) + np.array(c1, dtype=np.float32)*t
    return np.array(stops[-1][1], dtype=np.float32)

def make_lut(stops, vmin, vmax, size=4096):
    lut = np.zeros((size, 3), dtype=np.uint8)
    for i, v in enumerate(np.linspace(vmin, vmax, size)):
        lut[i] = np.clip(interp_color(stops, v), 0, 255).astype(np.uint8)
    return lut, vmin, vmax, size


# ── load ──────────────────────────────────────────────────────────────────────
print("Loading raster …")
with rasterio.open(INPUT) as src:
    orig_H, orig_W = src.height, src.width
    print(f"  Original size : {orig_W} × {orig_H}")
    out_H, out_W = orig_H // DOWNSAMPLE, orig_W // DOWNSAMPLE
    elev = src.read(1, out_shape=(out_H, out_W),
                    resampling=rasterio.enums.Resampling.nearest).astype(np.float32)
    H, W = elev.shape
    print(f"  Downsampled to: {W} × {H}")

nodata_mask = (elev == NODATA)
valid       = ~nodata_mask

# Working copy: fill nodata with high sentinel so water avoids it
elev_work = elev.copy()
elev_work[nodata_mask] = float(elev[valid].max()) + 9999.0


# ── lake extraction (burned-in constant elevation) ────────────────────────────
print("Extracting lakes …")
dy_e, dx_e = np.gradient(elev_work)
lake_mask = (dx_e == 0) & (dy_e == 0) & (elev > 0) & valid
# Sea = pixels at/below sea level that are connected to the raster boundary
# (avoids painting coastal lowlands / delta land with slight negative DTM as sea)
from scipy.ndimage import label as _label
_raw_sea = (elev <= 0) & valid
_labeled, _ = _label(_raw_sea)
_bnd = (set(_labeled[0, :]) | set(_labeled[-1, :]) |
        set(_labeled[:, 0]) | set(_labeled[:, -1]))
_bnd.discard(0)
sea_mask = np.isin(_labeled, list(_bnd)) & valid

unique_elev, counts = np.unique(elev[lake_mask], return_counts=True)
order = np.argsort(counts)[::-1]
print(f"  Sea   pixels : {sea_mask.sum():>10,}")
print(f"  Lake  pixels : {lake_mask.sum():>10,}")
print("  Largest lake bodies:")
for i in order[:6]:
    print(f"    {unique_elev[i]:6.0f} m → {counts[i]:,} px")


# ── Priority-Flood sink filling (Barnes et al. 2014) ─────────────────────────
# Seeds from every boundary cell, then propagates inward via min-heap.
# Each cell is filled to max(DEM[cell], parent_w + EPS), guaranteeing every
# interior cell has a strictly positive drop toward at least one neighbour
# (the one that spawned it).  This eliminates all spurious pits in one pass,
# O(n log n), so full river networks accumulate correctly.
import heapq as _hq
print("Priority-Flood sink filling (Barnes 2014) …")
NBRS     = [(-1,0),(1,0),(0,-1),(0,1),(-1,-1),(-1,1),(1,-1),(1,1)]
EPS      = 0.001          # 1 mm – small enough not to distort real topography
high_val = float(elev[valid].max()) + 9999.0

filled_elev = elev_work.copy().astype(np.float64)
visited     = np.zeros(H * W, dtype=bool)
heap        = []

def _seed(r, c):
    idx = r * W + c
    if valid[r, c] and not visited[idx]:
        visited[idx] = True
        _hq.heappush(heap, (float(filled_elev[r, c]), r, c))

for r in range(H):
    _seed(r, 0); _seed(r, W - 1)
for c in range(1, W - 1):
    _seed(0, c); _seed(H - 1, c)

n_raised = 0
n_total  = int(valid.sum())
n_done   = int(visited.sum())
report   = max(1, n_total // 20)
while heap:
    w, r, c = _hq.heappop(heap)
    n_done += 1
    if n_done % report == 0:
        print(f"  … {n_done:,}/{n_total:,}", end="\r")
    for dr, dc in NBRS:
        nr, nc = r + dr, c + dc
        if 0 <= nr < H and 0 <= nc < W:
            nidx = nr * W + nc
            if valid[nr, nc] and not visited[nidx]:
                nw = max(float(elev_work[nr, nc]), w + EPS)
                if nw > elev_work[nr, nc]:
                    n_raised += 1
                filled_elev[nr, nc] = nw
                visited[nidx] = True
                _hq.heappush(heap, (nw, nr, nc))

filled_elev = filled_elev.astype(np.float32)
print(f"\n  Cells raised : {n_raised:,}  (of {n_total:,} valid)")


# ── D8 hydrological river extraction ──────────────────────────────────────────
print("Computing D8 flow direction …")

# ── Flat-area routing (Garbrecht-Martz distance-gradient) ────────────────────
# After Priority-Flood, integer-elevation river channels remain flat (no gradient).
# D8 argmin on a flat area returns direction 0 (northward) — wrong.
# Fix: compute chessboard distance from each flat cell to the nearest "drainage"
# cell (one with a lower neighbor).  Add eps * dist to filled_elev so that
# farther-from-drainage = higher pseudo-elevation → D8 correctly routes
# flat cells toward their drainage outlet without disturbing real slopes.
print("  Flat-area routing (distance gradient) …")

DR = np.array([-1,-1, 0, 1, 1, 1, 0,-1], dtype=np.int32)
DC = np.array([ 0, 1, 1, 1, 0,-1,-1,-1], dtype=np.int32)
DD = np.array([1., 1.414, 1., 1.414, 1., 1.414, 1., 1.414], dtype=np.float32)

has_lower = np.zeros((H, W), dtype=bool)
for d in range(8):
    dr, dc = int(DR[d]), int(DC[d])
    rs = slice(max(0, -dr), H + min(0, -dr))
    cs = slice(max(0, -dc), W + min(0, -dc))
    rn = slice(max(0,  dr), H + min(0,  dr))
    cn = slice(max(0,  dc), W + min(0,  dc))
    has_lower[rs, cs] |= (filled_elev[rn, cn] < filled_elev[rs, cs])

# Raster boundary cells are always outlets (flow exits the raster there)
has_lower[0, :] = has_lower[-1, :] = has_lower[:, 0] = has_lower[:, -1] = True

from scipy.ndimage import distance_transform_cdt
# dist = 0 for drainage cells, >0 for flat cells proportional to BFS distance
dist_to_drain = distance_transform_cdt(
    ~(has_lower & valid), metric='chessboard'
).astype(np.float32)

n_flat = int((~has_lower & valid).sum())
print(f"    Flat cells: {n_flat:,}  max dist to drainage: {int(dist_to_drain[valid].max())} px")

elev_d8 = filled_elev + dist_to_drain * 0.001   # 1 mm per BFS step

rows_grid = np.arange(H, dtype=np.int32).reshape(-1, 1) * np.ones((1, W), dtype=np.int32)
cols_grid = np.ones((H, 1), dtype=np.int32) * np.arange(W, dtype=np.int32).reshape(1, -1)

# Compute drop for all 8 directions into a (8, H, W) array.
all_drops = np.full((8, H, W), -np.inf, dtype=np.float32)
for d in range(8):
    dr, dc, dist = int(DR[d]), int(DC[d]), float(DD[d])
    rs = slice(max(0, -dr), H + min(0, -dr))
    cs = slice(max(0, -dc), W + min(0, -dc))
    rn = slice(max(0,  dr), H + min(0,  dr))
    cn = slice(max(0,  dc), W + min(0,  dc))
    all_drops[d, rs, cs] = (elev_d8[rs, cs] - elev_d8[rn, cn]) / dist

best_dir  = np.argmax(all_drops, axis=0)
best_drop = all_drops[best_dir, rows_grid, cols_grid]

flow_r = np.clip(rows_grid + DR[best_dir], 0, H - 1).astype(np.int32)
flow_c = np.clip(cols_grid + DC[best_dir], 0, W - 1).astype(np.int32)

outlet    = (best_drop <= 0)   # no positive-drop neighbour = outlet/boundary
flow_flat = flow_r * W + flow_c
flow_flat[outlet] = -1

print("Computing flow accumulation (elevation-band method) …")
# int16 DTM: integer elevations, so we iterate over unique integer levels
# descending. Typically ≤ 3000 iterations — fast even for 29 M cells.
accum        = np.ones(H * W, dtype=np.int32)
valid_flat   = valid.ravel()
flow_flat_1d = flow_flat.ravel()

# Build a topological sort order using Kahn's algorithm.
# This correctly handles flat areas where multiple cells share the same elevation:
# a chain A→B→C (all at 100m) will be ordered A,B,C so accumulation propagates.
# Sort valid cells by elev_d8 descending (upstream before downstream).
# The southward tilt ensures northerly cells sort before southerly at same elevation,
# matching the Tiber's actual north→south flow direction.
sorted_valid = np.argsort(-elev_d8.ravel())
sorted_valid = sorted_valid[valid_flat[sorted_valid]]
n_cells      = len(sorted_valid)
report_every = max(1, n_cells // 10)
for step, idx in enumerate(sorted_valid):
    if step % report_every == 0:
        print(f"  … {step:,}/{n_cells:,}", end="\r")
    down = flow_flat_1d[idx]
    if down >= 0:
        accum[down] += accum[idx]
print(f"  … {n_cells:,}/{n_cells:,} done   ")

accum_2d = accum.reshape(H, W)

# River mask: high-accumulation cells that are land (not already lake/sea)
with rasterio.open(INPUT) as _src:
    _b = _src.bounds
    import math as _math
    _lat_mid  = (_b.top + _b.bottom) / 2
    _px_m     = 111320 * _math.cos(_math.radians(_lat_mid)) * (_b.right - _b.left) / W
_cell_km2 = (_px_m ** 2) / 1_000_000

max_accum = int(accum_2d[valid].max())
max_km2   = max_accum * _cell_km2
max_idx   = int(np.argmax(accum_2d * valid))
max_lat   = _b.top  - (max_idx // W) / H * (_b.top  - _b.bottom)
max_lon   = _b.left + (max_idx  % W) / W * (_b.right - _b.left)
print(f"  Pixel size       : {_px_m:.1f} m  ({_cell_km2*1e6:.0f} m2/cell)")
print(f"  Max accumulation : {max_accum:,} cells (~{max_km2:.0f} km2)")
print(f"  Max accum loc    : {max_lat:.4f}N  {max_lon:.4f}E")
for nm, lat, lon in [("Tiber mouth", 41.734, 12.232),
                     ("Rome",        41.895, 12.482),
                     ("N boundary",  42.170, 12.490)]:
    _c = int((lon - _b.left) / (_b.right - _b.left) * W)
    _r = int((_b.top - lat)  / (_b.top   - _b.bottom) * H)
    if 0 <= _r < H and 0 <= _c < W:
        _r0,_r1 = max(0,_r-10), min(H,_r+11)
        _c0,_c1 = max(0,_c-10), min(W,_c+11)
        _nb     = accum_2d[_r0:_r1, _c0:_c1]
        print(f"    {nm:16s}: point={accum_2d[_r,_c]:>9,}  nb_max={_nb.max():>9,}  "
              f"elev={int(elev[_r,_c])}m")
for thresh, _, _ in RIVER_TIERS:
    n = int(((accum_2d >= thresh) & valid & (~sea_mask) & (~lake_mask)).sum())
    print(f"  River cells >= {thresh:>9,} : {n:,}")

# Top-20 land accumulation locations (to find where rivers actually route)
_land_a = accum_2d.copy().astype(np.int64)
_land_a[~(valid & ~sea_mask & ~lake_mask)] = 0
_top = np.argpartition(_land_a.ravel(), -20)[-20:]
_top = _top[np.argsort(-_land_a.ravel()[_top])]
print("  Top-20 land accumulation cells:")
for _ti in _top:
    _r, _c = divmod(int(_ti), W)
    _lat = _b.top  - _r / H * (_b.top  - _b.bottom)
    _lon = _b.left + _c / W * (_b.right - _b.left)
    print(f"    {_lat:.4f}N {_lon:.4f}E  {accum_2d[_r,_c]:>9,} cells  elev={int(elev[_r,_c])}m")

# Check max accumulation in western coastal strip (where Tiber exits to the sea)
_wlim = int((12.35 - _b.left) / (_b.right - _b.left) * W)
_west_strip = accum_2d[:, :_wlim].copy()
_west_strip[~valid[:, :_wlim]] = 0
_wi = int(np.argmax(_west_strip))
_wr, _wc = divmod(_wi, _wlim)
_wlat = _b.top - _wr/H * (_b.top - _b.bottom)
_wlon = _b.left + _wc/W * (_b.right - _b.left)
print(f"  Max accum west of 12.35E: {_west_strip.max():,} at {_wlat:.4f}N {_wlon:.4f}E  "
      f"elev={int(elev[_wr,_wc])}m")
# Also show max accum in ±50px around Rome (wide search)
_lr, _lc = (int((_b.top-41.895)/(_b.top-_b.bottom)*H),
            int((12.468-_b.left)/(_b.right-_b.left)*W))
_nr0,_nr1 = max(0,_lr-50), min(H,_lr+51)
_nc0,_nc1 = max(0,_lc-50), min(W,_lc+51)
_nb2 = accum_2d[_nr0:_nr1, _nc0:_nc1]
print(f"  Rome ±50px neighbourhood max: {_nb2.max():,}  (centre elev={int(elev[_lr,_lc])}m)")

# D8 flow direction at key points (shows which way cells are actually routing)
_DIR_NAMES = ['N','NE','E','SE','S','SW','W','NW']
print("  D8 flow direction at key cells:")
for _nm2, _lat2, _lon2 in [
    ("Coast cell 5m",   41.780, 12.060),
    ("Tiber ~15m",      41.840, 12.320),
    ("Rome Tiber",      41.895, 12.468),
    ("N-entry Tiber",   42.165, 12.420),
]:
    _rc = int((_b.top - _lat2) / (_b.top - _b.bottom) * H)
    _cc = int((_lon2 - _b.left) / (_b.right - _b.left) * W)
    if 0 <= _rc < H and 0 <= _cc < W:
        _d = int(best_dir[_rc, _cc])
        _bd = float(best_drop[_rc, _cc])
        _fdown = int(flow_flat[_rc, _cc])
        _fe = float(filled_elev[_rc, _cc])
        print(f"    {_nm2:18s} ({_lat2:.3f}N,{_lon2:.3f}E): "
              f"dir={_DIR_NAMES[_d]}  drop={_bd:.4f}  filled_elev={_fe:.3f}  "
              f"accum={accum_2d[_rc,_cc]:,}")


# ── hypsometric tint ──────────────────────────────────────────────────────────
print("Applying hypsometric tint …")
elev_filled = elev.copy()
elev_filled[nodata_mask] = 0

# Clamp non-sea land pixels to >= 1 m so coastal lowlands/delta don't get sea-blue tint
elev_for_tint = elev_filled.copy()
land_pixels = valid & (~sea_mask) & (~lake_mask)
elev_for_tint[land_pixels & (elev_for_tint < 1)] = 1

e_min = float(elev_for_tint[valid].min())
e_max = float(elev_for_tint[valid].max())
lut, lut_min, lut_max, lut_size = make_lut(ELEV_STOPS, e_min, e_max)

idx = ((elev_for_tint - lut_min) / (lut_max - lut_min) * (lut_size - 1)).astype(np.int32)
idx = np.clip(idx, 0, lut_size - 1)
rgb = lut[idx]


# ── hillshading ───────────────────────────────────────────────────────────────
print("Computing hillshade …")
az  = np.radians(LIGHT_AZ);  alt = np.radians(LIGHT_ALT)
lx  =  np.cos(alt) * np.sin(az)
ly  = -np.cos(alt) * np.cos(az)
lz  =  np.sin(alt)

dy_h, dx_h = np.gradient(elev_filled)
px_size_m   = 25.0 * DOWNSAMPLE
gx = dx_h / px_size_m * Z_SCALE * 1e6
gy = dy_h / px_size_m * Z_SCALE * 1e6
norm_len = np.sqrt(gx**2 + gy**2 + 1)
shade = np.clip((-gx/norm_len)*lx + (-gy/norm_len)*ly + (1/norm_len)*lz, 0, 1).astype(np.float32)

# Scale shadow depth by slope magnitude so flat land is unshaded.
# slope_norm → 0 for flat (no shadow), → 1 for steep (full shadow).
# k²=16 sets the crossover at slope_mag≈4 (~5% grade at 50 m/px resolution).
slope_mag  = np.sqrt(gx**2 + gy**2).astype(np.float32)
slope_norm = slope_mag**2 / (slope_mag**2 + 16.0)
blend = 1.0 - slope_norm * 0.50 * (1.0 - shade)   # flat→1.0, steep→0.5+0.5*shade
rgb   = np.clip(rgb.astype(np.float32) * blend[..., np.newaxis], 0, 255).astype(np.uint8)


# ── paint water layers ────────────────────────────────────────────────────────
# Sea
rgb[sea_mask]   = [ 30, 110, 200]

# Lakes (burned-in flat areas)
rgb[lake_mask]  = [ 55, 150, 220]

# Rivers: variable width by morphological dilation.
# Paint lowest→highest threshold; each pass overpaints with a wider+darker
# band so the Tiber ends up the widest and darkest river.
def _disk(r):
    y, x = np.ogrid[-r:r+1, -r:r+1]
    return (x*x + y*y) <= r*r

land = valid & (~sea_mask) & (~lake_mask)
for thresh, radius, color in RIVER_TIERS:
    mask = (accum_2d >= thresh) & land
    if mask.any():
        rgb[binary_dilation(mask, structure=_disk(radius))] = color


# ── nodata → transparent ──────────────────────────────────────────────────────
rgba = np.dstack([rgb, np.full((H, W), 255, dtype=np.uint8)])
rgba[nodata_mask, 3] = 0

img = Image.fromarray(rgba, "RGBA")

# ── correct geographic aspect ratio ───────────────────────────────────────────
# At latitude ~42°N each degree of longitude is shorter than a degree of latitude
# by factor cos(lat).  Raw pixel grid is W × H but covers lon_range × lat_range
# degrees, so pixels are rectangles (taller than wide).  Resize to square pixels.
import math as _m
_lat_c   = (_b.top + _b.bottom) / 2
_geo_ar  = (_b.right - _b.left) * _m.cos(_m.radians(_lat_c)) / (_b.top - _b.bottom)
_pix_ar  = W / H
_out_H   = round(H * (_pix_ar / _geo_ar))   # stretch height to correct squish
img      = img.resize((W, _out_H), Image.LANCZOS)
print(f"  Aspect correction: {W}×{H} → {W}×{_out_H}  (geo_ar={_geo_ar:.3f})")

img.save(OUTPUT, compress_level=6)
print(f"\nSaved {OUTPUT}  ({W}×{_out_H} px)")
print(f"Elevation range : {e_min:.0f} m → {e_max:.0f} m")
