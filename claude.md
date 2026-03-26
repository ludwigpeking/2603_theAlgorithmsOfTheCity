This is a project of:
1. to reveal the algorithms in the being of Cities;
2. to run simulations to test the algorithms;
3. to generalize theory and formulas of the algorithms;

The algorithms are revealed layer by layer. It has a historical viewpoint.

# Graphics Style:
Light color, white background.
annotaion color: black, gray, blue, red.

# at the webpage, each entry has 
each chapter has its own folder and a long webpage. the simulation they run is the same core we have, but taking different parameter sets.
- brief explanation paragraph
- pseudo code block of the key algorithm
- a window to run the simulation of the algorithm, with related adjustable parameters 
- have the liberty to improve the language


# Algorithms:
Each is a webpage, with a few canvases. Use graphs to simulate the algorithm. There can be multiple canvases to show different stages of the algorithm. The webpage should have a narrative to explain the algorithm and its significance in the context of cities.


I. Resource distribution
1. density of resources and population
2. mobile and residual clans
3. surplus and accumulation

II. Storytelling
1. belief system
2. mutation/crossbreeding of belief systems 

III. Pathfindings
"I shall either find a way or make one."
— Hannibal Barca (attributed)
"Nature is thrifty in all its actions... Nature always takes the shortest path."
— Pierre de Fermat
1. A brief introduction to Pathfinding algorithms
2. elevation-change cost pathfinding: elevation change penalty increase movement cost.
3. modes of transportation: pedestrian, mules, carts, watercraft, trains: elevation change penalty to different mode is different, e.g. pedestrian is more adaptable to steep slope than vehicle.
4. modal changes: intermodal pathfinding, for example change from boat to cart, takes great effort of loading, unloading, waiting and vehicle accessibility, change model is expensive.
5. path dependency, reduced cost of path reuse: knowledge of existing path, infrastructure improvement, artificial evenness can reduce the cost of finding a new path

IV. spatial syntax
travel time/cost based tiers. Bill Hillier's space syntax theory, which is based on the idea that the configuration of spaces in a city can influence social interactions and movement patterns. The theory uses a mathematical approach to analyze the spatial layout of cities and identify key areas of connectivity and accessibility. It has been used to inform urban design and planning decisions, as well as to understand the social dynamics of cities.

create a chapter/folder 4_spatialSyntax. it uses the same map as in chapter 3. also use as much as the code in /common. JUST add a layer:
on init, 1. calculate the reachedable tiles of each tile, at the cost of 50, 150, and 450, and also, by pedestian and vehicular modes, so this is a 3x2 = 6 set of arrays of tiles precalculated and stored in the tile object.
the interaction is to click onto a tile. and there're options of pedestrian or vehicular, then the 3 tiers of reachable tiles are color displayed.
1. 

V. Trade
1. Trade gain and trade cost
2. expertisations: concentration, mobile reaccuring markets patterns
3. 

VI. Claiming
1. Voronoi claiming,
2. Weighted Voronoi claiming.
3. Informal Occupation.



VII. Spatial Optimization
a rectangular parcel, with a grid of 5x15 (meter tiles)x 3floors= 225 possible tiles
one edge is the road, one edge(segment) on an random edge is the entrance to the parcel. 
distances: manhattan distance for the same floor, and 15 meters for the vertical distance between floors.
if there's a tile on the upper floor, the tile directly below it must be occupied.
and there need to be a staircase tile on all floors (same location), the internal movement between floors is only possible through the staircase tile. 

the scoring:

   the sum of the distance from each tile to the entrance * weight1 + the sum of each tile's the distance to the rest of the tiles * weight2
   weights adjustable, default 0.5 and 0.5 

simulations 
1. start with random placing of 10 tiles, and a random entrance, and run the optimization algorithm to find the optimal configuration of the 10 tiles.
the upper floor is possible when only the lower floor of its projection is occupied. 
and the staricase tile is also random and to be optimized, adding one more dimension to the optimization.


VIII. Defenses

IX. 

_____
# folder structure
- A common entrance of the home page file which connects to all the chapters and entries.
- a folder for each chapter, with a webpage for each algorithm entry. The webpage has a narrative, pseudo code, and a simulation window.
- the common function, style and library managed in a separate folder, and imported into each webpage.
- utility scripts for data processing, e.g. to convert the DTM data into a format that can be used in the simulation, can be in a separate folder.
- legacy code that is no longer used can be archived in a separate folder, for reference and potential future use.



