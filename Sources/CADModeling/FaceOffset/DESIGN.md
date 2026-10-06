# Face Offset

## Purpose and Scope
Own Push Face surface replacement and staged planar growth. Parent: [CADModeling](../DESIGN.md). No children.

## Responsibilities and Boundaries
Resolve the authored target faces before editing, preserve original surface replacement and carried identities, and compose injected extrusion, sewing and Boolean application. Lower original surface correspondence, finite intersections and exact model validation remain their owners' contracts.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADModeling](../DESIGN.md) | parent | FeatureEvaluating | Evaluator composition | Ports must be injected by the Kernel composition root. |
| [Exact Surface Trim](../ExactSurfaceTrim/DESIGN.md) | depends on | Original finite trim admission | Retained boundary authority | A numerical supporting plane is not whole original trim evidence. |
| [CADKernel](../../CADKernel/DESIGN.md) | used by | Sewing and exact Boolean application | Staged body publication | Scratch tools cannot become published parents. |

## Architecture
```text
Original selected faces -> replacement/rebuild -> exact validation -> carried identity
                      -> retained profiles -> staged extrusion -> union/cut
                      -> Fixed polygonal oblique fill -> sewn prism -> union
```

## Contracts and Invariants
All selected profiles are extracted before the first mutation. Staged parallel planar pushes retain one original profile per face, publish only the final feature, and preserve the complete replacement history. Fixed growth into an oblique supporting wall constructs every cap station by the authored axis/plane intersection and delegates complete material clipping to the injected Boolean applicator. Scratch prism identities are removed from removed-subshape sets and lineage parents before publication. Moving growth first fills each parallel gap, then replaces each reached wall by its remaining requested displacement. Common fields and Sendable semantics remain identical across targets.

The current planar wall admission is partial: complete finite wall coverage, curved boundaries, differently directed pushes, oblique Moving walls and generic adjacent-angle growth remain mandatory source gaps. Successful planar cases do not establish the whole E4 gate.

## State, Ownership, and Lifecycle
The evaluator retains immutable injected ports. Each evaluation owns local stages and model values; profile snapshots precede staged edits. No shared mutable cache is introduced.

## Failure, Concurrency, and Constraints
Missing ports, invalid profiles, ambiguous walls, failed reconstruction, sewing, intersections, resource exhaustion and cancellation propagate through the feature boundary. Existing lower limits and tolerance policy remain unchanged.

## Verification and Change Impact
Deferred behavioral verification covers multi-face parallel Grow None/Fixed/Moving, Fixed polygonal oblique walls, original finite wall admission, complete history, scratch identity exclusion, and failure propagation. Recheck profile, prism, extrusion, Boolean and source replacement dependencies when their original geometry authority changes.
