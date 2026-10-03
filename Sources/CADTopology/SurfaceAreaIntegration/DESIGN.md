# Surface Area Integration

## Purpose and Scope
Child of [CADTopology](../DESIGN.md). Owns certified area and area-centroid
integration over face loops on exact surfaces. No children.

## Responsibilities and Boundaries
Topology owns loop roles, orientation normalization, resource admission,
quadrature and acceptance. CADGeometry owns certified integrand derivatives.
Mesh/display data never enter this path.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADTopology](../DESIGN.md) | parent | face/coedge pcurves | Query routing | Missing trims fail. |
| [Geometry integrands](../../CADGeometry/SurfaceAreaIntegration/DESIGN.md) | depends on | outward bounds of density and centered moments | Exact fan pullback | Unsupported derivatives do not become zeros. |

## Architecture
```text
face loops -> continuous UV chains -> signed fan squares
    -> certified density and centered moments -> bounded adaptive integration
        -> normalize each loop's traversal -> subtract holes -> interval centroid
```

## Contracts and Invariants
- The exact fan map is `a + r(c(t)-a)`; its Jacobian is
  `r det(c(t)-a,c'(t))`. Signed integration permits concave loops and holes.
- Every consecutive pcurve endpoint agrees to parameter rounding precision;
  modeling-tolerance gaps are refused because they leave an undefined domain.
- Each outer loop contributes positive area; each inner loop subtracts area,
  independent of face and chain reversal.
- Area error is at most `distance^2 + relative * areaLower`; centroid
  Euclidean error is at most `distance`, certified by component intervals.
- Acceptance requires strictly positive area lower bound and finite moments.
- Structural affine support authority eliminates the radial integral exactly:
  boundary area density is `det/2`, and centered moments are
  `anchorOffset*det/2 + displacement*det/3`. Exact curved pcurves remain
  the integration source; their boundary fraction still receives certified bounds.
- Exact four-edge iso-parametric rectangular loops may use a geometry-owned
  translation certificate. The translation coordinate is integrated exactly
  at its interval-enclosed midpoint; only the other native parameter receives
  adaptive quadrature. A recoverable singular enclosure on this one-dimensional
  path subdivides only that varying parameter; subdividing the eliminated radial
  coordinate cannot improve the certificate. Other trim/support structures retain
  fan integration and its two-dimensional recoverable-enclosure subdivision rule.
- A conservative UV enclosure extending outside a bounded support requests
  boundary subdivision; it is never clipped to manufacture admission.
- A cell uses a centered Taylor enclosure, with first-derivative mean-value
  bounds when certified second derivatives are unavailable. Midpoint sample
  values themselves are interval bounds. No difference of sampled quadrature
  rules is used as an error proof.
- C0 support partitioning preserves the original signed fan and exact trim
  chart. A single native span permits one-sided smooth Taylor bounds; a cell
  crossing a knot uses only certified integrand value ranges times its full
  fan measure. No derivative of a discontinuous density enters Taylor bounds.
  Translation rectangles partition at exact native knot coordinates; span
  identity owns endpoint derivatives while shared boundaries have zero measure.
- Error targets are allocated once per query and shared across all curves,
  spans, pieces and loops. Range-only cells contribute their complete interval
  uncertainty to the same aggregate error target; they do not receive a new
  absolute tolerance per piece. Final area and centroid interval acceptance
  remains authoritative. Work and depth accounting also remain query-wide.
- Numeric mapped trims retain their original stored curve and source fraction
  chart. Geometry prepares exact directed offset or affine rigid chart authority
  against the face's exact support, after bounded nested input admission.
  Topology supplies this authority to fan/boundary enclosure evaluation; the
  original signed fan measure, loop winding and whole-query resource/error
  targets are unchanged. Geometry also admits the exact open connected affine
  implicit family under its original native-UV certificate and fraction authority;
  topology uses that prepared chart under the same signed fan and whole-query
  limits. Remaining implicit charts and non-affine rigid images retain typed
  unsupported failures. Invalid source fractions or foreign targets cannot
  become a clamped or approximately equivalent accepted trim.
- An admitted affine implicit chain retains the original equal `1/N` cell
  fractions and unequal native cell widths. Its geometry-owned chart proof
  distinguishes a smooth owning piece from a value-only join enclosure.
  Charts with native joins use the existing aggregate uncertainty integral;
  join-crossing cells never enter higher-order Taylor acceptance and subdivide
  the original boundary fraction T. The existing exact affine radial integral
  remains available on this path; it removes R without changing the signed fan.
  Every contribution, including a join-crossing range, consumes the original
  curve's error target and query-wide cell/depth/cancellation accounting. No
  piece receives a new allowance or silently closes a tolerance-sized gap.

## State, Ownership, and Lifecycle
Each invocation owns immutable prepared geometry. Smooth domains retain their
depth-first cell stack. C0 support and native-join chart domains own a balanced outward-sum tree and a heap of
refinable leaf uncertainties; at most `2*processedCells-1` tree records and
`processedCells` heap entries exist. Native initial partition depth counts
toward the original query depth limit. No shared mutable state or cache is
introduced.
Each retained boundary curve additionally owns one immutable prepared source
chart for its adaptive integration call. Chart preparation uses the original
query admission limits and never creates an independent adaptive budget.

## Failure, Concurrency, and Constraints
Admission limits boundary curves, input and expanded Bezier control points, processed cells and subdivision
depth. Cancellation is checked during preparation and between cells.
Resource exhaustion, singularity, unsupported charts and nonfinite/indeterminate
arithmetic throw typed KernelError. An uncertified value is never returned.

## Verification and Change Impact
[`SurfaceAreaIntegrationTests`](../../../Tests/CADTopologyTests/SurfaceAreaIntegrationTests.swift) owns exact planar and
curved fixtures, hole/reversal, boundary and typed resource/cancellation tests.
`FaceAreaMeasurementTests` proves public query routing and analytic regressions.
Changes require rechecking geometry derivative validity and capability claims.
