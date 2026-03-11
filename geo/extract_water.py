"""
Extract water layer from SAR HH polarization GeoTIFF.

Water bodies appear as near-zero backscatter in SAR HH data because
smooth water surfaces cause specular reflection away from the radar antenna.

Output: water_mask.tif  — binary raster (1=water, 0=land)
        water_only.tif  — original values where water, NoData elsewhere
"""

import rasterio
import numpy as np
from rasterio.transform import from_bounds

INPUT  = "output_hh1.tif"
OUT_MASK  = "water_mask.tif"
OUT_VALUES = "water_only.tif"

# Threshold: pixels at or below this value are classified as water.
# Negative values and exact zeros are specular-reflection returns (water).
# A small positive buffer (0.5) catches noisy water edges.
WATER_THRESHOLD = 0.5

with rasterio.open(INPUT) as src:
    band = src.read(1)
    profile = src.profile.copy()

    water_mask = (band <= WATER_THRESHOLD).astype(np.uint8)

    print(f"Total pixels  : {band.size:,}")
    print(f"Water pixels  : {water_mask.sum():,}  ({water_mask.sum()/band.size*100:.1f}%)")
    print(f"Land pixels   : {(water_mask==0).sum():,}  ({(water_mask==0).sum()/band.size*100:.1f}%)")

    # --- Save binary water mask ---
    mask_profile = profile.copy()
    mask_profile.update(dtype=rasterio.uint8, nodata=255)
    with rasterio.open(OUT_MASK, "w", **mask_profile) as dst:
        dst.write(water_mask, 1)
    print(f"\nSaved binary mask  → {OUT_MASK}")
    print("  Values: 1 = water, 0 = land")

    # --- Save original values for water pixels only (land = NoData) ---
    water_values = band.copy()
    water_values[water_mask == 0] = np.nan   # mask out land
    val_profile = profile.copy()
    val_profile.update(dtype=rasterio.float32, nodata=np.nan)
    with rasterio.open(OUT_VALUES, "w", **val_profile) as dst:
        dst.write(water_values.astype(np.float32), 1)
    print(f"Saved water values → {OUT_VALUES}")
    print("  Values: original SAR backscatter where water, NoData elsewhere")
