# Tribe Simulation — Agriculture Density

A population-ecology simulation layered on the Great Wall terrain's agriculture density map.
50 clans compete for farmland, grow with surplus, migrate on shortage, absorb rivals, and split when large.

---

## Parameters

| Parameter | Slider range | Default | Meaning |
|---|---|---|---|
| Harvest radius | 5 – 80 km | 10 km | Circular territory each tribe harvests |
| Replenish rate | 1/2 – 1/30 /frame | 1/6 /frame | How fast depleted cells recover |
| Growth rate | 0.1 – 5 %/frame | 1 %/frame | Max population growth when surplus is ample |
| Starvation | 0.5 – 20 %/frame | 3 %/frame | Population loss per frame of shortage |
| Speed | 1 – 20× | 1× | Simulation frames per render frame |

---

## Resource Model

Each land cell carries a **base resource score** `agriBase[i]` (0–1), derived once at simulation start from:

```
agriBase = slopeScore × latFactor × elevFactor
```

where:
- `slopeScore` peaks at 1 for slopes 0.1–10%, falls to 0 at >50%
- `latFactor  = max(0, 1 − latReduction% × (lat − south_edge))`
- `elevFactor = max(0, 1 − elevReduction% × elev/100m)`

`resourceCurrent[i]` starts at `agriBase[i]` and is depleted by harvesting.
Each frame it recovers: `resourceCurrent += agriBase × replenishRate` (capped at base).

---

## Tribe Mechanics (per frame)

### 1. Exclusive cell ownership
Before any harvesting, each land cell is assigned to the **nearest tribe** whose harvest radius covers it.
Cells in two overlapping territories go to the closer centre — no sharing.

### 2. Harvest
Each tribe collects only from its owned cells:
```
capacity  = population × CONSUME_RATE × 2   // can harvest up to 2× bare need
collected = min(total_available_in_owned_cells, capacity)
```
Extraction is distributed proportionally across cells.

### 3. Storage & demography
```
storage += collected − population × CONSUME_RATE

if storage < 0:           # shortage
    storage = 0
    population *= (1 − starvation_rate)
    → tribe moves

if storage ≥ 0:           # surplus
    surplusRatio = min(1, storage / (population × CONSUME_RATE × 20))
    population  *= 1 + surplusRatio × growthRate
    storage     *= 0.98   # gradual spend-down
```

### 4. Migration (shortage only)
A tribe in shortage attempts to move to a random adjacent tile (8-connected).
Constraints: target must be **land** and **unoccupied** by another tribe.
The tribe keeps moving every frame until it finds enough food.

### 5. Absorption
After all movements, any two tribes whose centres are within `RPX` pixels of each other merge:
- The **larger absorbs the smaller** (gains its population and storage).
- The smaller is removed from the map.

### 6. Fission (split)
Each frame, a tribe with `pop > 1000` has a chance to split:
```
splitChance = clamp(log₂₀(pop / 1000), 0, 1) × 0.003
```
- At pop = 1 000: chance ≈ 0
- At pop = 20 000: chance ≈ 0.3 %/frame

On split: the parent stays in place; a **daughter tribe** is spawned at a random tile
just outside the harvest radius (distance ≈ RPX + 2). Each receives half the population
and half the storage. The daughter is placed only if the tile is free land.

---

## Visual Encoding

| Feature | Meaning |
|---|---|
| Circle radius | `sqrt(population) × 0.275` — area ∝ population |
| Blue fill | Tribe is in surplus (growing or stable) |
| Red fill | Tribe is in shortage (shrinking, migrating) |
| White number | Current population |
| Green `s:X.X` above | Stored surplus (green > 0.1, red ≤ 0.1) |

---

## Emergent behaviours to observe

- **Clustering in river plains** — flat, irrigated lowland has high agriScore; tribes settle and grow there.
- **Upland poverty** — high-altitude steppe (Tibetan Plateau, Mongolian Plateau) has near-zero agriScore; tribes that wander there starve and migrate.
- **Border wars** — when two large tribes' radii touch, absorption collapses one. Oscillation can follow if the survivor then overshoots its land.
- **Fission waves** — successful tribes in the North China Plain split repeatedly, filling the map with daughter clans that compete for adjacent farmland.
- **Ghost zones** — cells near large tribes become permanently depleted; nearby smaller tribes starve and flee, leaving empty territory behind.
