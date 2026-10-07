# Shopping street / centre spatial optimisation (Godot 4.7)

Built **one layer at a time**. See `INSTRUCTIONS_LOG.md` for the author's instructions and roadmap.

## Current: Layer 1 — Traffic, network version (v0.9)

No congestion and no path widths. The public realm is a **network of lines** (metres):
the block's sides (our sidewalk) and passages at any angle. The block is any polygon;
every vertex is a corner where people join or leave our side.

```
network:  building line = the drawn outline (stable); sidewalk axis = outline offset outward
          by half the passage width (mitred)
          edges = sidewalk-axis sides + passage pieces inside the axis polygon
          nodes = corners, passage/side junctions, passage crossings, dead-ends
shops:    the block fills completely (frontage-seeded Voronoi, v0.7):
          faces = block cut along through-passages;
          seeds = n = round(L / frontage) points equally spaced on each frontage edge;
          shop  = Voronoi cell of its seed within its face (bisector half-planes),
                  then minus a setback band around each passage axis (optional: sides);
                  the seed stays on the axis = conceptual entrance, where traffic is counted
flows:    each corner pair's two-way flow q takes its shortest path;
          equal shortest paths share q in proportion to the number of paths via each edge:
              flow(e = u→v) += q · σ(s,u) · σ(v,t) / σ(s,t)   if d(s,u) + |e| + d(v,t) = d(s,t)
          shop visitors from corner c pick shop s with p ∝ exp(−d(c,s)/θ), walk there and back
shop traffic = whole flow on its edge + visitors walking part of that edge  (per hour)
```

Results: mean trip length, person-km / h, share of walking on passages, traffic per shop
(mean / min / max), Gini, share of weak shops (< 25 % of mean). Everything recomputes
instantly, also live while dragging geometry. "Compare" evaluates all presets with the same
corner count plus the current shape.

| File | Role |
|---|---|
| `scripts/traffic/layout_spec.gd` | editable polygon + passages |
| `scripts/traffic/block_presets.gd` | starting shapes A–G |
| `scripts/traffic/street_network.gd` | line network, shops, all-pairs shortest paths + path counts |
| `scripts/traffic/flow_model.gd` | flow assignment, shop traffic, summary statistics |
| `scripts/traffic/od_matrix.gd` | corner-pair demand (any number of corners) |
| `scripts/ui/network_view.gd` | drawing + edit overlay |
| `scripts/ui/od_matrix_editor.gd`, `ui_kit.gd` | typed OD matrix, theme |
| `scripts/main.gd` | panel, geometry editing, comparison |

Dormant (v0.4 grid + congestion engine, kept for a later congestion layer):
`street_grid.gd`, `layout_builder.gd`, `traffic_sim.gd`, `street_view.gd`, `series_chart.gd`.

## Roadmap

2 Trade (surplus, recognition / distance / credit costs) → 3 Customers (demand,
purchasing power) → 4 Shops (flow × profit) → 5 Facility (rent pressure, squeeze-out).

## Archive

v0.1 (tenant mix + annealing) is in `archive/v0.1_tenant_mix/`, plus `scripts/core` and
`scripts/view`, which carry a `.gdignore` so Godot skips them.

## Run

Open this folder in Godot 4.7 and press F5. The project uses the Compatibility (OpenGL)
renderer with low-processor mode, which avoids the window flicker seen with Forward+ / D3D12.
