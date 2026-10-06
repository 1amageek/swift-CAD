# Loft Finite Cap Contact

## Purpose and Scope
This component implements finite original cap/side contact validation for Loft. Parent: [CADKernel](../DESIGN.md). No children.

## Responsibilities and Boundaries
CADModeling owns cap and side construction and publishes the validated result. This component owns complete original face-pair intersections, finite trim clipping, and admission against original shared topology. Geometry owns whole-curve coincidence; Topology owns the input incidence.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADKernel](../DESIGN.md) | parent | injection | Concrete validator | Propagate typed failures |
| [Loft](../../CADModeling/Loft/DESIGN.md) | used by | LoftFiniteCapContactValidating | Constructed finite caps and sides | Both production builder routes inject the same port |
| [Prepared Boolean Operation](../PreparedBooleanOperation/DESIGN.md) | depends on | complete face-pair graph and UV split | Original finite intersections | No operation-specific empty shortcut |

## Architecture
```text
original BRep + cap/side IDs -> complete requested face-pair graph
    -> both finite trims including holes -> component geometry
        -> shared original vertex / whole shared edge subspan
            -> admission or typed invalid contact
```

## Contracts and Invariants
An isolated contact is permitted only at an original vertex shared by the two faces. A positive-dimensional intersection is permitted only when every retained original span is proved a subspan of an edge incident to both original faces. Support-only intersections outside either trim are omitted by the splitter. Coincident finite area is invalid; boundary-only coincidence must likewise consist solely of original shared topology. Source IDs, trims and surface laws are unchanged.

## Failure, Concurrency, and Constraints
Cancellation is checked before preparation, between pairs and before returning. Existing intersection, subdivision, coincidence and containment budgets and modeling tolerances are inherited. Ambiguity or inability to certify coincidence propagates failure, rather than absence of contact. No sampled point sequence establishes whole-span identity.

## Verification and Change Impact
Deferred behavioral evidence covers curved finite disjoint supports, holes, shared edge and vertex incidence, nonincident tangency, partial shared-edge spans, material-interior crossings, coplanar contacts, cancellation and budget failure through both Loft builders. Source construction is not verification evidence.
