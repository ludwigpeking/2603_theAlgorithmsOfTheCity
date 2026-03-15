"""
Render output_hh1.tif as a topography-style colored PNG.
Water (backscatter <= 0.5) → blue gradient
Land (backscatter > 0.5)   → terrain gradient (green → brown → light grey)
"""

import rasterio
import numpy as np
from PIL import Image

INPUT = "output_hh1.tif"
OUTPUT = "topo.png"
WATER_THRESHOLD = 0.5

# ── color stops for land (value 0..1 normalized) ─────────────────────────────
LAND_COLORS = [
    (0.00, ( 34, 139,  34)),   # forest green  – low backscatter / flat
    (0.25, ( 85, 170,  85)),   # light green
    (0.45, (200, 185, 120)),   # sandy / scrub
    (0.65, (160, 110,  60)),   # brown / dense urban
    (0.85, (130,  90,  50)),   # dark brown / very dense
    (1.00, (200, 195, 190)),   # light grey / high-rise tops
]

# ── color stops for water (value 0..1 normalized within water range) ─────────
WATER_COLORS = [
    (0.00, ( 10,  70, 160)),   # deep blue  (most negative / deepest water)
    (0.60, ( 30, 120, 210)),   # mid blue
    (1.00, ( 80, 170, 230)),   # shallow / edge blue
]

def interp_color(stops, t):
    t = float(np.clip(t, 0, 1))
    for i in range(len(stops) - 1):
        t0, c0 = stops[i]
        t1, c1 = stops[i + 1]
        if t0 <= t <= t1:
            f = (t - t0) / (t1 - t0)
            return tuple(int(c0[j] + f * (c1[j] - c0[j])) for j in range(3))
    return stops[-1][1]

with rasterio.open(INPUT) as src:
    band = src.read(1).astype(np.float32)

h, w = band.shape
rgb = np.zeros((h, w, 3), dtype=np.uint8)

# ── water pixels ──────────────────────────────────────────────────────────────
water_mask = band <= WATER_THRESHOLD
water_vals = band[water_mask]
w_min, w_max = water_vals.min(), WATER_THRESHOLD
w_norm = (water_vals - w_min) / max(w_max - w_min, 1e-6)
water_colors = np.array([interp_color(WATER_COLORS, t) for t in w_norm], dtype=np.uint8)
rgb[water_mask] = water_colors

# ── land pixels ───────────────────────────────────────────────────────────────
land_mask = ~water_mask
land_vals = band[land_mask]
# clip at 99th percentile so bright outliers don't wash out the colormap
p99 = np.percentile(land_vals, 99)
l_norm = np.clip(land_vals / p99, 0, 1)
land_colors = np.array([interp_color(LAND_COLORS, t) for t in l_norm], dtype=np.uint8)
rgb[land_mask] = land_colors

img = Image.fromarray(rgb, "RGB")
img.save(OUTPUT, compress_level=6)
print(f"Saved {OUTPUT}  ({w}×{h} px)")
print(f"Water pixels: {water_mask.sum():,}  ({water_mask.sum()/band.size*100:.1f}%)")
