# Finite Curve Clipping

## Purpose and Scope
Parent: [CADKernel](../DESIGN.md). Own finite authored face clipping of an exact parameter-curve lift for imprint/edit routes. No children.

## Responsibilities and Boundaries
Retain the original candidate curve/support law, split at complete boundary contacts, and select event-free intervals by finite face containment. Curve intersection and subdivision producers own completeness. This component preserves source and endpoint lineage in the resulting sewing edges.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADKernel](../DESIGN.md) | parent | imprint/edit composition | Atomic finite clipping publication | Empty results are deliberate along-edge semantics only |
| [Source Face Patch](../../CADModeling/SourceFacePatch/DESIGN.md) | depends on | original trim extraction | Boundary contact source | Preserve exact original coedge law |
| [CADTopology](../../CADTopology/DESIGN.md) | depends on | BRepEdgeGeometryClassifier | Original closed/singular admission | Endpoint proximity is not closedness |
| [CADModeling](../../CADModeling/DESIGN.md) | depends on | original edge subdivision | Directed trim and endpoint ancestry | Full contact partition remains lower authority |

## Architecture
```text
original face chart lift + original trim edges -> complete contacts
    -> original edge subdivision -> event-free finite material containment
        -> optional proved closed-span subdivision -> sewing edges + endpoint parents
```

## Contracts and Invariants
Closed-span subdivision requires the original structural periodic-law classification. Numerically close open endpoints do not authorize splitting as a closed traversal. Generated edges retain both endpoint parent lists of their original admitted pieces and the candidate edge parents. Geometric source, native trim and pcurve remain unchanged when stable IDs are assigned.

## Failure, Concurrency, and Constraints
All caches and buffers are invocation-local. Contact/containment/subdivision failures propagate. The legacy producer's complete callback/storage chain remains a bounded-query gap; an outer contact count cannot certify its lower work. Coincident interval completeness and critical boundary sectors remain inherited original contact producer gaps.

## Verification and Change Impact
Deferred checks cover true periodic loops, short open spans, holes, along-edge semantics, inherited endpoint parents and failed original contacts without partial publication. Recheck original closedness and edge subdivision when their source law admission changes. No tests or behavioral verification are claimed in the source phase.
