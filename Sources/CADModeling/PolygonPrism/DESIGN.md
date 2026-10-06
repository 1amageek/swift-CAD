# Polygon Prism

## Purpose and Scope
Own directed planar polygon prism sewing requests. Parent: [CADModeling](../DESIGN.md). No children.

## Responsibilities and Boundaries
Construct two caps and each original polygon side for constant reach or an oblique terminal plane. Caller owns simple original polygon and base plane admission; sewing and Boolean clipping remain injected downstream authorities.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADModeling](../DESIGN.md) | parent | BRepSewingRequest | Common geometry producer | Existing constant-length callers retain their API. |
| [Face Offset](../FaceOffset/DESIGN.md) | used by | Oblique plane cap | Fixed wall growth | Supporting-plane reach does not establish finite wall coverage. |

## Architecture
```text
Original directed polygon + axis + reach/cap plane
    -> oriented base + carried cap stations -> planar side loops -> solid sewing request
```

## Contracts and Invariants
Constant-length construction retains the prior endpoint law. Oblique construction requires every original corner to reach the cap plane strictly ahead along the authored axis; no parallel or behind-axis cap succeeds. Cap and side orientations follow the directed polygon and actual positive reach. Each edge retains its directed native line interval and original plane pcurve. No sampled polygon or mesh substitutes for the input boundary.

## State, Ownership, and Lifecycle
Each request owns local immutable stations and patches. The producer introduces no shared mutable state.

## Failure, Concurrency, and Constraints
Invalid polygons, singular directions, parallel cap planes, nonpositive reach and failed pcurve construction throw typed errors. Tolerances and downstream resource limits remain unchanged.

## Verification and Change Impact
Deferred checks cover the old Draft/Extrude constant-length consumers, oblique caps in either directed polygon orientation, parallel and behind-axis rejection, and exact sewing/Boolean publication. Changes to line or plane chart authority require rechecking those consumers.
