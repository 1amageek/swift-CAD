# Original Polyline

## Purpose and Scope
Own the normalized Euclidean-length clock of original authored XYZ points. Parent: [CADGeometry](../DESIGN.md). No children.

## Responsibilities and Boundaries
The raw points and closure flag are source identity. Only adjacent supplied points form segments; the closure flag neither snaps endpoints nor appends a segment. Exact zero-length segments contribute no clock interval. Caller compatibility validation owns its existing adjacent-distance and closure-distance policy.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Geometry](../DESIGN.md) | parent | Original curve preparation | Shared enum and owning dispatch | No native spline promotion |
| [Rational algebra](../RationalBivariateAlgebra/DESIGN.md) | depends on | OriginalEuclideanPolyline3DParameterLaw | Exact sqrt lengths, prefix and total | Explicit independent algebra admission |

## Architecture
```text
raw points + closure flag
    -> exact Euclidean length law
        -> exact selected segment fractions
            -> original affine XYZ values and one-sided jets
```

## Contracts and Invariants
The proof constructor takes an explicit caller algebra cap, source cap and spatial cap with the same work/storage admission. This adds no hidden algebra ceiling to legacy numerical point behavior. Cached exact coefficients and preparation caps are excluded from source equality and serialization. At an exact station the numerical first derivative selects the preceding segment. Closed owning covers retain both original sides, exact field fraction endpoints and raw point index; a raw point index is not a native spline index. D2 and higher vanish within each owning segment, but do not establish continuity across corners. A whole smooth jet requires identical exact first derivatives across every selected positive-width segment.

## State, Ownership, and Lifecycle
The immutable source owns its original points and a paid exact length receipt. Query-local buffers are pre-admitted by concrete stride. A reduced later algebra cap re-admits the raw law using the same caller admission before querying it.

## Failure, Concurrency, and Constraints
Nonfinite points, no positive total length, invalid normalized range or exhausted independent caller capabilities fail explicitly. Closure provenance is not an exact endpoint coincidence receipt. Numerical representatives require original coordinate boxes narrow enough for the original tolerance.

## Verification and Change Impact
Behavioral verification must cover unequal lengths, exact corners and preceding tangent selection, explicit repeated closure points, no implicit closing segment, tiny/large source coordinates, reduced algebra admission and work/storage exhaustion. Common curve preparation, arc length, drawing owning covers and Kernel nil-exact curve receipts are affected. Source edits alone do not establish these behaviors.
