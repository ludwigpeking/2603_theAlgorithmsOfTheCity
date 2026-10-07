# The Algorithms of Cities

A ten-minute lecture, layered historically.
Slides with speaker notes. Each slide ≈ 1 minute.

---

## Slide 1 — Thesis: the city as *process*

**A city is not an object but a process — the (never-attained) equilibrium of innumerable decisions, by many agents, under continually changing constraints.**

**Working definition.** An *algorithm of the city* is a triple
$$
\mathcal{A} \;=\; \langle\, f,\;\; \mathcal{C}_{t},\;\; \pi \,\rangle
$$
— an objective $f$, a time-varying constraint set $\mathcal{C}_{t}$, and a decision rule $\pi$ acting on city-state $s_{t}$:
$$
s_{t+1} \;=\; \pi\bigl(s_{t}\bigr) \quad \text{s.t.}\quad \mathcal{C}_{t}\bigl(s_{t+1}\bigr),\quad \text{maximizing } f.
$$

**Composition.** The city-state is the (loose) fixed point of many such algorithms running *concurrently* and *asynchronously*:
$$
s^{*} \;\approx\; \bigl(\mathcal{A}_{1}\,\|\,\mathcal{A}_{2}\,\|\,\dots\,\|\,\mathcal{A}_{n}\bigr)\,s^{*}
$$
— the operator $\|$ denotes parallel composition, **not** strict sequencing.

**Today.** Nine such algorithms, presented in a *vague* historical order. They coexist, recur, and overwrite one another; neither time nor space orders them strictly.

> **Speaker note (≈55 s):** What we call "the city" is best understood not as a *thing* designed but as a *process* — the equilibrium of a sequence of infinite decisions, repeated by many agents, under changing constraints. If that is right, then each historical layer of urban form could be, as I attempt, expressible as an algorithm — with some function, some constraints, and a rule for action. Today I will sketch nine such algorithms in the order in which, vaguely, they historically come into play. They come back and forth, and are most likely to coexist; they are not necessarily ordered in time or in space.

---

## Slide 2 — Resources: Settlement and Mobility

**Variables.** ecological carrying capacity $K$ (yield · area⁻¹ · time⁻¹); economic-mode factor $\mu$; reachable radius $r$; population $N$; per-capita consumption $c$.

**Sustainability constraint.**
$$
N \cdot c \;\le\; \pi r^{2} \cdot K \cdot \mu
$$

**Maximum sustainable population on a fixed range.**
$$
N_{\max} \;=\; \frac{\pi r^{2}\,K\,\mu}{c}
$$

- $\mu$: hunter-gatherer $\ll$ pastoralist $<$ swidden $<$ intensive agriculture.
- Mobile clans expand $r$ through time (translation of the disk); settled clans expand $K$ through cultivation (intensification of the disk).

> **Speaker note (≈70 s):** The first algorithm any human group runs is a budget. The carrying-capacity inequality says: the food a population eats must not exceed what its reachable territory yields, modulated by an economic-mode factor μ that captures how much energy each subsistence regime can extract from a unit of land. The choice between settlement and mobility is then a choice of which factor to relax: a mobile clan moves its disk through space, expanding $r$ in time; a sedentary clan intensifies $K$ in place through cultivation. The equation is crude, but the historical fork — pastoralist transhumance versus agrarian fixity — falls out of it directly.

---

## Slide 3 — Hazards, Yields, and Site Selection

**Two opposing terms at every site $x$.**
- Terrain yield $Y(x)$: expected output per unit area in a normal year (alluvial soil, water, microclimate, slope, aspect).
- Aggregate hazard $H(x) = \sum_{i} P_{i}\,D_{i}$: expected annual loss across hazard types $i$ (flood, landslide, drought, storm, earthquake, tsunami, eruption).

**Expected net output.**
$$
\mathbb{E}\bigl[\text{output}(x)\bigr] \;=\; Y(x) \;-\; H(x) \;=\; Y(x) \;-\; \sum_{i} P_{i}\,D_{i}
$$

**Site-selection rule.** Choose
$$
x^{*} \;=\; \arg\max_{x}\;\bigl[\,Y(x) - H(x)\,\bigr],
$$
and settle iff $Y(x^{*}) - H(x^{*}) > G_{\min}$, the minimum surplus needed to sustain growth.

- *High-$Y$, high-$H$ sites are not paradoxes — they are the rule.* Flood plains co-locate the maxima of $Y$ and $H$: the same hydrology that destroys is what makes the soil worth rebuilding on (Nile, Tigris–Euphrates, Indus, Huang He).

> **Speaker note (≈55 s):** Once we ask *where* to settle, we cannot read hazard in isolation — we have to read it against yield. Every site carries two opposing terms: a terrain-output factor $Y$, what the land gives in a normal year, and an aggregate hazard $H$, what it takes back in a bad one. The decision is a *balance*, not a minimization. The historical proof of this is the great flood-plain civilizations — Egypt, Mesopotamia, the Indus, the Yellow River — where the very hydrology that periodically destroys is what makes the soil rich enough to be worth rebuilding. Settlements relocate only when expected net output falls below the surplus needed for growth.

---

## Slide 4 — Beliefs, Alliances, and Group Selection

**Proposition (Darwinian).** A tribe carrying a shared belief system $B$, and the alliance-network that belief underwrites, is a *fitter unit* — culturally *and* physically — than a tribe without. Selection acts at the level of the **group**.

**Group survival rate.**
$$
\sigma(B) \;=\; \sigma_{0} \;+\; \Delta\sigma(B) \;-\; m(B)
$$
- $\Delta\sigma(B)$: cooperation bonus from shared belief and alliance (mutual defense, trade, charity, conflict resolution).
- $m(B)$: maintenance cost (ritual, taboo, sacrifice, in-group obligation).

**Three fates of a belief-less tribe.**
1. **Extinction** — outcompeted in conflict, or fails the carrying-capacity inequality of Slide 2.
2. **Absorption** — dissolved into a neighbouring tribe's $B$, paying its $m$ in exchange for $\Delta\sigma$.
3. **Reformation** — synthesises a hybrid $B'$ from contact (historically the modal outcome; every world religion is a palimpsest).

**Selection across tribes (replicator dynamics).**
$$
\dot{p}(B) \;=\; p(B)\,\bigl[\,\sigma(B) \;-\; \bar\sigma\,\bigr]
$$
The share of population carrying $B$ rises iff $\sigma(B) > \bar\sigma$.

**Sacred hardware as a Darwinian trait.** A built shrine, temple, or burial ground at $x_{S}$ — cost $K_{S}$ once, $m_{S}$ to maintain — *lowers* the dissolution rate of the belief:
$$
\delta \;\longrightarrow\; \delta_{0}\,e^{-\beta\,K_{S}}.
$$
A tribe with **built** belief outlasts a tribe with only **spoken** belief; the shrine is therefore selected for, and becomes the first piece of urban fixed capital (Göbekli Tepe, ziggurat precincts, ancestral grounds).

> **Speaker note (≈75 s):** The third layer is Darwin applied to tribes. A tribe carrying a shared belief system, and the alliance-network it underwrites, is a fitter *group* than one without — fitter culturally *and* physically, and the two are inseparable. Cooperation under shared belief raises the group's per-generation survival rate, even after subtracting the maintenance cost: ritual, taboo, sometimes blood. A tribe *without* belief faces three fates, all observed historically: it is extinguished in conflict, it is absorbed by a neighbouring tribe whose belief it adopts, or it synthesises a hybrid belief out of contact — the modal outcome, and the reason every world religion is a palimpsest. The replicator dynamics are clean: belief-systems whose group fitness exceeds the average rise in share. And the hardware layer — the shrine, the temple, the burial ground — is not decoration but advantage: it lowers the dissolution rate and ties belief to a place. A tribe with *built* belief outlasts a tribe with only *spoken* belief. From this slide forward, belief is a physical fact in the landscape, and we are back in the field of urbanism.

---

## Slide 5 — Pathfinding and Trade

**Path cost across mixed modes $\{m_{k}\}$.**
$$
C(\gamma) \;=\; \sum_{k} \int_{\gamma_{k}} f_{m_{k}}(x)\,dx \;+\; \sum_{k} T\!\left(m_{k}\to m_{k+1}\right)
$$

- $f_{m}(x)$: friction of terrain $x$ under mode $m$ (foot, animal, cart, watercraft, rail).
- $T(\cdot)$: modal-change cost — loading, unloading, waiting.

**Path dependency.** Reuse erodes friction:
$$
f_{m}(x,\,t+1) \;=\; f_{m}(x,\,t)\,\bigl(1 - \rho\,u(x,t)\bigr)
$$

**Trade rule.** Trade occurs iff
$$
\Delta U_{\text{division of labor}} \;>\; C(\gamma) + C_{\text{info}} + C_{\text{risk}}
$$

> **Speaker note (≈75 s):** Now movement. A path's cost is the integral of friction along it, summed across mode segments, plus the cost of every modal change. This is a generalized A\* — the standard algorithm, but with two additions that matter for cities. First, friction is mode-dependent: a mountain pass that is trivial for a mule is impassable for a cart. Second, modal change is expensive: loading and unloading at a port often dominates the in-water cost, which is why ports become cities and not the rivers they sit on. Finally, friction decays with reuse — paths become roads, roads become canals — so the network is path-dependent, and trade only happens when the gain from division of labor exceeds the full transport-plus-information-plus-risk cost.

---

## Slide 6 — Defense and Walls

**Cumulative cost of $n$ layers.** $C = \sum_{i=1}^{n} c_{i}$.

**Marginal value of layer $i$.**
$$
v_{i} \;=\; \frac{1}{c_{i} - c_{i-1}}, \qquad V \;=\; \int v(i)\,di
$$

**Liberty–security tradeoff.**
$$
\mathcal{V} \;=\; P_{s}\,(1+\lambda) \;-\; (1-P_{s})\,S
$$

where $\lambda$ is a liberty premium and $S$ the stakes if defense fails.

- Geometric heuristic: the **convex hull** of assets bounds the minimum-perimeter wall. Indefensible salients are abandoned.

> **Speaker note (≈55 s):** Walls are layered, and each layer has a diminishing marginal benefit — the second wall buys less than the first, the third less than the second. Total defense value is the integral of marginal value over layers. But security is not free of liberty: a fortress that is perfectly safe is also a prison, so the value functional includes a liberty premium times survival probability, against the stakes of failure. Geometrically, a rational defender encloses the convex hull of what is worth defending and abandons salients. The medieval European walled town is the literal solution to this optimization.

---

## Slide 7 — Symbiosis of Castes

**The protection contract.**
$$
P_{\text{prot}} \cdot Y \;-\; C_{p} \;>\; P_{0}\cdot Y
$$

- $Y$: output of the producer caste.
- $P_{0},\,P_{\text{prot}}$: survival probability without and with the protector.
- $C_{p}$: cost of maintaining the protector class (food, status, immunity).

**Generalization.** The same inequality, with different $C$ and $\Delta P$, governs artisans, priests, and scribes — symbiosis as a Pareto improvement under structural inequality.

> **Speaker note (≈55 s):** A caste system is a division of labor with hierarchy attached. The defining inequality is the protection contract: a producer accepts to feed a protector class if and only if the increase in survival probability times output exceeds the cost of feeding the protector. The same algebra rationalizes the scribe, the priest, and the artisan caste — each is a specialization that pays for itself in expectation. This is uncomfortable as ethics and unanswerable as accounting; both are true at once, and that is the point.

---

## Slide 8 — Claiming and Property

**Emergence rule.**
$$
C_{\text{claim}} \;<\; C_{\text{no-rights}} \;\Rightarrow\; \text{property institutions emerge}
$$

**Voronoi tessellation.**
$$
V_{i} \;=\; \bigl\{\,x : d(x,p_{i}) \le d(x,p_{j})\;\forall j\,\bigr\}
$$

**Weighted (multiplicative) Voronoi — claims with power $w_{i}$.**
$$
V_{i} \;=\; \Bigl\{\,x : \tfrac{d(x,p_{i})}{w_{i}} \le \tfrac{d(x,p_{j})}{w_{j}}\;\forall j\,\Bigr\}
$$

- Informal occupation = Voronoi without enforcement; weights collapse to demand.

> **Speaker note (≈55 s):** Property is a cost comparison. It emerges when the cost of claiming — surveying, fencing, registering, defending — falls below the cost of operating without rights. The spatial signature of claiming is a Voronoi tessellation: each holder dominates the points closer to it than to any rival. When power is asymmetric, weights enter the metric, and we get weighted Voronoi diagrams — the geometry of feudal estates, of market hinterlands, of empire. Informal settlement is the same algorithm with the enforcement term zeroed out.

---

## Slide 9 — Growth and Spatial Optimization

**Five strategies of densification.** crowding · infill · vertical growth · subdivision · sprawl.

**Parcel-scale objective (project chapter VII).**
$$
\min \;\; w_{1}\sum_{i} d(t_{i},\,e) \;+\; w_{2}\sum_{i<j} d(t_{i},\,t_{j})
$$

subject to:
- vertical support: a tile on floor $f+1$ requires its projection on $f$ occupied;
- shared staircase: vertical movement only through a single tile shared across floors;
- Manhattan distance within a floor; 15 m vertical penalty per floor.

> **Speaker note (≈55 s):** When a settlement grows, it must reduce the friction cost of its own internal trade. There are five canonical responses — crowding, infill, vertical growth, subdivision, sprawl — and each is a different solution to the same optimization. At parcel scale, our chapter-seven simulation makes this concrete: minimize a weighted sum of distance-to-entrance and distance-to-each-other-tile, subject to support and circulation constraints. The marginal-benefit-of-density curve crossing the marginal-cost-of-friction curve defines the equilibrium form: it is why Manhattan is tall and Houston is flat.

---

## Slide 10 — Synthesis

**The stack.**
$$
\underbrace{\text{Resources}}_{\text{Ch. I}} \;\to\;
\underbrace{\text{Hazards}}_{\text{Ch. II}} \;\to\;
\underbrace{\text{Beliefs}}_{\text{Ch. III}} \;\to\;
\underbrace{\text{Paths \& Trade}}_{\text{Ch. IV–V}} \;\to\;
\underbrace{\text{Defense}}_{\text{Ch. V}} \;\to\;
\underbrace{\text{Caste}}_{\text{Ch. VI}} \;\to\;
\underbrace{\text{Claiming}}_{\text{Ch. VII}} \;\to\;
\underbrace{\text{Density}}_{\text{Ch. VIII}}
$$

- **Transport modal change** $T(m\to m')$ is the connective tissue: it propagates from Slide 5 into every subsequent layer.
- The city is the fixed point of this composition.

> **Speaker note (≈55 s):** Stepping back: each algorithm composes with the next. Resources set the population. Hazards filter the sites. Beliefs lower the cost of cooperation. Paths and trade set the cost of distance. Defense, caste, and claiming determine who keeps the surplus. Density closes the loop by reducing the trade cost that started the sequence. The transport modal-change cost — that $T$ in Slide 5 — propagates through every subsequent layer; it is the parameter that, more than any other, separates a Mesopotamian river city from an Andean mountain one. Cities are not designed: they are the fixed point of this composition. Our task in this course is to code each layer, run it, and watch the patterns of history precipitate out.

---

## Closing — The course as research program

- We will implement each layer as an interactive simulation in `/1_resources … /8_growth`.
- Parameters are knobs; the *patterns* are the dependent variable.
- A successful theory is one whose simulation, given plausible parameters, recovers a city we already know.

> **Speaker note (≈30 s):** The reason to build these simulations and not just to write the equations is that the equations interact. A small change in transport friction reshapes the Voronoi of claims, which reshapes the optimal defensive perimeter, which reshapes the caste contract. We will not derive that by hand. We will run it. Thank you.

---

### Timing budget

| Block | Slides | Cumulative |
|---|---|---|
| Thesis | 1 | 0:55 |
| Resources | 2 | 2:05 |
| Hazards | 3 | 3:00 |
| Beliefs | 4 | 3:55 |
| Paths & Trade | 5 | 5:10 |
| Defense | 6 | 6:05 |
| Caste | 7 | 7:00 |
| Claiming | 8 | 7:55 |
| Density | 9 | 8:50 |
| Synthesis | 10 | 9:45 |
| Closing | — | 10:15 |
