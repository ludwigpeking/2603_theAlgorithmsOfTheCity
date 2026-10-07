1. resources: settlement and mobile
    variables:
    - ecological carrying capacity
    - model of economy: hunter-gatherer, pastoralist, agriculturalist
    - reachable distance
    - population of the settlement/mobile
    Formulas:
    ? (population of the settlement/mobile * consumption per capita) <= (ecological carrying capacity) * (reachable distance)**2 * PI * (model of economy factor)


2. hazards and locations
    variables:
    - $H = \sum(P_i\cdot H_i)$ //consider changing to bayesian form
    Probability of all hazards: landslides, floods, droughts, storms, earthquakes, tsunamis, volcanic eruptions, etc.
    - if H > Growth, settlement is in decline
    - if H < Growth, settlement is growing

3. beliefs and alliances
    variables:
    - added chance of survival due to beliefs and alliances
    - chance of dissolution, due toloss of beliefs and linages
    - rejoining/borrowing of beliefs and alliances, reforming of identity
    formulas:

4. path finding and trade
    concepts, variables:
    - model of transportation: foot, animal, watercraft, wheeled
    - friction of terrain: flat, hilly, mountainous, water 
    - cost of model change: loading, unloading, waiting, etc.
    - cost of transportation: path integration of segment(frictionByModel * lengthOfSegment) + cost of model changes  // reformed A* algorithm
    - reduced friction of travelled paths: roads, canals, etc.
    - trade surplus: division of labor
    - trade costs: information, transportation, risks
    formulas:



5. defense and walls
    concepts, variables:
    - cost of defendlessness
    - cost of building and maintaining defenses
    - marginal benifit/cost
    - layering of protection
    - project cost of offensiveto the opponent
    - convex hull
    - schemes (where to defend, where to give up defendless)

    formulas:
    cost = cost_1 + cost_2 + cost_3 + ...
    value_i = 1/(cost_i - cost_(i-1)) // marginal benefit of adding layer i
    value of defense = integral of value_i di

    liberty vs security tradeoff: 
    Value = P_survival * (1 + liberty_factor)   -  (1-P_survival) * Stakes
    Stakes = Stakes +  P_survival * (1 + liberty_factor)

6. symbiosis of castes
    concepts, variables:
    - caste system: division of labor, social hierarchy, suppression,etc.
    - symbiosis: (protection + suppression) trade for survival and growth
    - cost of maintaining caste system
    - benefits of caste system: professional soldiers, artisans, priests, etc.
    formulas:
    no protector vs with protector:
    P_survival * output ? P_protected * output - cost of protector


7. claiming and property
    concepts, variables:
    - cost of claiming
    - cost of lack of property rights
    if (cost of claiming) < (cost of lack of property rights) -> growth
    - voronoi diagrams.
    - weighted voronoi diagrams, with weights based on demand and power

8. growth and spatial optimization
marginal cost vs marginal benefit of growth:
spatial reduction of cost of trade:
 - crowding
 - infills
 - vertical growth
 - subdivision
 - sprawl

9. transportation and model changes
