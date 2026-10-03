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

## State, Ownership, and Lifecycle
Each invocation owns immutable prepared geometry and a depth-first cell stack.
No shared mutable state or cache is introduced.

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
