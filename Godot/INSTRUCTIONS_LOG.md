# Instruction log

A running record of the author's instructions for the Godot shopping-street model,
and what was done in response. Newest at the bottom.

---

## #1 · 2026-09-23 · Project start

> I try to do a shopping street/center spatial optimization, where we should model
> merchandises, space and customer behaviors. I created an empty godot project …
> we can start to work on it.

**Done (v0.1):** tenant-mix model — 7 merchandise categories, 3 customer profiles,
agent-based shoppers (shopping lists, impulse visits, comparison shopping, café rests),
simulated annealing over tenant placement, two layouts (high street, dumbbell mall).
Now archived in `archive/v0.1_tenant_mix/` (+ `scripts/core`, `scripts/view`, ignored by Godot)
because it stacked too many layers at once — see #2.

---

## #2 · 2026-09-23 · Restart with fewer layers: traffic first

> 1. Create the boundary street traffic, assuming some through foot traffic in all
>    directions, and make the amount of each origin/destination pair adjustable.
> 2. The interface has overflow text.
> 3. Create a log of my instructions in the folder.
> 4. Don't add the layers together. First generic customers and generic shops;
>    test traffic efficiency, cost only on traffic density.
> 5. Each trade has some trade surplus (交易剩余), shared by both parties; each trade has
>    trade costs: recognition, foot distance, credit (seeing people transacting).
> 6. Customer: reduce the cost of transaction, maximise the surplus. Different customers
>    have their own demand and purchasing power.
> 7. Shops: maximise surplus = flow × profit.
> 8. Facility: pressure test on shops — raise rent, squeeze low-performance shops
>    out of good positions.
>
> Know these things, but we start with fewer layers.

**Done (v0.2 · Layer 1 — Traffic):**
- City block surrounded by four boundary streets; gates N / E / S / W at the map edges.
- Adjustable 4 × 5 origin–destination matrix (gate → gate through traffic, gate → shop visits), persons / min.
- Generic shops (all identical) and generic walkers. The only cost is walking time,
  which rises with crowd density (speed–density relation). Routes adapt to congestion.
- Metrics: travel-time efficiency (free-flow ÷ actual), mean delay, crowded exposure,
  share of through traffic using the block, peak density; shop frontage exposure.
- Four block layouts to compare (closed, E–W arcade, cross arcade, cross + plaza) and a benchmark.
- UI rebuilt so text wraps / clips inside the panel.

**Roadmap (not built yet, one layer at a time):**

| Layer | Adds | From instruction |
|---|---|---|
| 1 · Traffic | density-dependent walking cost | #2.1, #2.4 |
| 2 · Trade | surplus per trade, shared; trade costs = recognition + foot distance + credit (social proof) | #2.5 |
| 3 · Customers | heterogeneous demand and purchasing power; choose trades that maximise net surplus | #2.6 |
| 4 · Shops | profit = flow × margin; shops respond to their own surplus | #2.7 |
| 5 · Facility | landlord raises rent; low performers are squeezed out of prime positions | #2.8 |

---

## #3 · 2026-09-23 · Only our side, only corners

> For boundary traffic, we only care about the foot traffic on our side,
> and only the corners matter, directions don't.

**Done (v0.3):**
- Removed the far side of the boundary streets. The walkable realm is now only our
  sidewalk ring (3 cells ≈ 4 m) around the block, plus any arcades / plazas.
- Gates are the four block corners NW / NE / SE / SW (where people cross onto our side),
  replacing the N / E / S / W map edges.
- Demand is by undirected corner pair: one two-way total per pair, spawned half in each
  direction. The editor shows each pair once (lower triangle mirrors it in gray).
- Presets: Balanced, Diagonal (block on the desire line), Busy side (NW–NE), Clear.

---

## #4 · 2026-09-23 · Typed input, shop traffic, free geometry, restart on change

> The numbers should be input rather than clicking. We should show the accumulated
> traffic of the shops, also colour-coded. We should allow diagonal passages and free
> polygonal boundaries. A setting change should restart the simulation.

**Done (v0.4):**
- OD matrix: typed number fields (commit with Enter / leaving the field); upper triangle =
  two-way pair, lower triangle mirrors it; last column = shop visits per corner.
- Shops: fill colour (warm ramp, √ scale) and a number on each shop = accumulated
  passers-by since the run started; colour bar under the map; inspector shows share of total.
- Geometry: the block is any polygon; every vertex is a corner / gate (named by compass
  direction). Passages are segments at any angle (4 cells wide), plus optional plazas.
  Shop units are tiles clipped by the polygon and passages, so they follow diagonal edges.
- Movement is 8-connected (diagonal = √2, no corner cutting); all distances are Dijkstra.
- Edit mode: drag corners and passage ends; double-click an edge to add a corner;
  right-click to delete a corner or passage; buttons add straight / diagonal passages.
  Crossing edges are rejected and reverted.
- Presets: A closed · B orthogonal cross · C diagonal X · D diagonal X + plaza ·
  E pentagon (5 corners) · F wedge (3 corners).
- Any model setting (shape, passages, OD, demand, jam density, routing) restarts the run
  with a fixed seed. Changing the number of corners resets the OD matrix to Balanced.
- Benchmark compares presets with the same corner count + the current (edited) shape.

---

## #5 · 2026-09-23 · No congestion; passages are lines; shops count traffic

> We don't consider congestion for now. The width of the lanes should not matter, so we
> consider the passages as lines, and all shops on the paths should get a traffic count.

**Done (v0.5 · network model):**
- Replaced the grid + agents with a line network in metres (`street_network.gd`):
  block sides (our sidewalk) and passages are edges; nodes at corners, where passages
  meet the sides, crossings and dead-ends.
- No congestion, no widths: each corner pair's two-way flow takes its shortest path;
  equally short paths share the flow in proportion to their number (`flow_model.gd`).
- Shop visitors choose a generic shop by distance (logit, scale θ) and walk there and back.
- Shops are frontage strips along edges (sides: inner side only; passages: both sides).
  Every shop on a path counts everyone passing it: whole-edge flow + visitors walking
  part of the edge. Shown as fill colour + passers-by per hour.
- Everything recomputes instantly, including live while dragging corners / passage ends.
- Results: mean trip length, person-km / h, share on passages, traffic per shop
  (mean / min / max), Gini, share of weak shops (< 25 % of mean). Compare runs instantly.
- Congestion is parked, not deleted: the v0.4 grid engine files (`street_grid.gd`,
  `layout_builder.gd`, `traffic_sim.gd`, `street_view.gd`, `series_chart.gd`) are dormant.

---

## #6 · 2026-09-23 · Use the space compactly — divide the triangles

> The space should be more compactly used up in the diagonal schemes, no spare space
> should be there. Find an algorithm to divide the triangular space.

**Done (v0.6 · straight-skeleton subdivision, cf. Vanegas et al. 2012, "Procedural
 generation of parcels in urban modeling"):**
1. Faces: the block is cut along every through-passage (dead-end spurs are pruned and
   don't cut; cuts are ordered outward from the boundary so no holes arise).
2. Each face is decomposed into convex parts (convex faces stay whole).
3. In each convex part, every frontage edge owns the points nearer to it than to any
   other frontage line — the straight-skeleton region, computed exactly as an
   intersection of bisector half-planes. The regions tile the part without gaps
   (a triangle → three wedges meeting at the incentre).
4. Each region is sliced perpendicular to its frontage into ≈ target-width shops;
   the end slices run to the region boundary.
- Result: 100 % of the block is shop floor (reported as "% used"); every shop has a
  frontage on a side or a passage and is counted by the traffic on that frontage.
- Depth slider removed (depth now follows the geometry); inspector shows frontage and m².

---

## #7 · 2026-09-23 · Equal shops along edges + Voronoi; window flashing

> The shop geometry should arrange the shops equally along the edge, then do a Voronoi
> diagram to find the geometry of the shops. And the Godot game window is flashing,
> maybe some GPU problem.

**Done (v0.7):**
- Shop geometry = frontage-seeded Voronoi. On every frontage edge of each face
  (piece of block between passages), n = round(length / target frontage) seeds are placed
  at the middles of n equal segments. Each shop is the Voronoi cell of its seed, clipped to
  its face (intersection of perpendicular-bisector half-planes). Cells tile the face and
  each touches its own frontage. Seeds are drawn as black dots. Replaces the v0.6
  straight-skeleton slicing.
- Flashing: switched the renderer from Forward+ on Direct3D 12 to **Compatibility
  (OpenGL)**, which is meant for 2D and avoids D3D12 flicker on some GPUs/drivers; enabled
  low-processor mode (redraw only on change) and V-Sync.

---

## #8 · 2026-09-23 · Setback from the path axis

> The shops should have some setback from the path axis, to articulate the passage,
> though the conceptual entrance of the shop still stays on the path, and the Voronoi is
> also centred at that point.

**Done (v0.8):**
- Seeds stay on the path axis and the Voronoi is computed from them exactly as before.
- Then a setback band (half-width = passage setback, square caps at the ends) around every
  passage axis is carved out of each cell; an optional block-side setback does the same
  inside the sidewalk line. The carved bands are drawn as public space.
- Each shop keeps its conceptual entrance on the axis (the seed, where its traffic is
  counted); a gray link joins it to the nearest point of the set-back shop front ("door").
- Sliders: passage setback (0–8 m each side, default 2 m = 4 m passage),
  block-side setback (0–6 m, default 0). Results split floor into shops + public setback.

---

## #9 · 2026-09-23 · Offset the boundary traffic outward

> The outer boundary traffic should offset out half of the passage width, so the area
> within the drawn boundary is stable.

**Done (v0.9):**
- The drawn outline is now the fixed building line. The sidewalk traffic axis is the
  outline offset outward by half the passage width (a mitred offset, so each corner stays
  one node; very sharp spikes are capped at 4 × the offset). Corners, side edges and all
  routing use this axis.
- Passage ends outside the outline are extended automatically so they always reach the
  offset axis, whatever the setback.
- Voronoi faces are built on the axis polygon, then every cell is clipped to the drawn
  outline: the area inside the outline no longer changes with the setback. Side shops keep
  their seed (entrance) on the sidewalk axis, linked to their front on the building line.
- The side-setback slider now means an extra setback inside the building line (default 0).
