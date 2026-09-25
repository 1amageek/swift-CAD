# Surface Boundary Certification

## Purpose and Scope

Child of [CADGeometry](../DESIGN.md), with no children. Owns independent,
whole-interval comparison of two oriented surface boundaries. It consumes
surface geometry and parameter curves, not fitted control-point residuals.

## Responsibilities and Boundaries

The shared numeric UV interval-jet helper owns affine, iso-parametric, harmonic,
rational B-spline, offset-image and periodic-translation chart derivatives.
Other chart representations return explicit unsupported capability.

Each immutable invocation owns prepared surface enclosures and a bounded
subdivision stack. It proves upper bounds for position difference, oriented
unit-normal chord difference and ambient shape-operator difference. CADIR owns
G0/G1/G2 request vocabulary; modeling owns topology and publication. No sampled
success or solver termination stands in for these bounds.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADGeometry](../DESIGN.md) | parent | outward interval jets and exact geometry | Supplies certified third-order derivatives | Inconclusive enclosures are not success. |
| [SurfaceFitting](../SurfaceFitting/DESIGN.md) | coordinates with | candidate geometry | Numerical construction precedes independent admission | No fitting state or objective is consumed. |
| [CADIR](../../CADIR/DESIGN.md) | used by | continuity level and tolerances | Converts angle tolerance to a normal chord limit | Parameter direction and face orientation differ. |

## Architecture

```text
surface + UV curve + traversal + face orientation
    -> prepared interval surface and UV jets
        -> position / unit normal / shape operator and boundary derivatives
            -> centered mean-value enclosure of pairwise differences
                -> every interval certified or explicit failure
```

## Contracts and Invariants

- Both boundaries use the same normalized fraction with independent traversal.
  Face reversal changes the normal and signed shape operator, not position.
- Outward interval arithmetic bounds the boundary functions and their first
  derivatives. Surface third derivatives are required for curvature variation.
  Centered mean-value bounds retain correlation along the common fraction.
- The ambient shape operator uses reciprocal tangent vectors and the second
  fundamental form. Its Frobenius difference bounds action on every unit tangent;
  scalar principal-curvature comparisons alone cannot prove G2.
- Position is always checked. Curvature requests also require a normal bound.
  Callers own physical position, normal-chord and inverse-length curvature limits,
  subdivision count and depth. Angles are converted by the semantic caller.
- A certificate covers the complete normalized interval. Unsupported UV jets,
  singular/unresolved normals, nonfinite arithmetic and exhausted subdivision
  produce typed failure. Inputs and published source are never mutated.
- Geometry derivatives must exist on the inspected intervals. B-spline knots
  that lack the requested parametric smoothness are rejected; removable knots
  may be simplified by the construction owner before certification.

## Failure, Concurrency, and Constraints

Scratch storage is bounded by subdivision depth and immutable prepared geometry.
At most the caller's cell limit is inspected. The synchronous operation owns no
shared mutable state. Cancellation is checked between cells. An interval that
cannot be bisected representably fails; no enlarged tolerance is substituted.

## Verification and Change Impact

`Tests/CADGeometryTests/SurfaceBoundaryCertificationTests.swift` owns equal and
reversed boundaries, between-sample displacement/normal/curvature violations,
rational and nonunit domains, resource failures and degenerate supports.
Changes require rechecking surface-lift parameter-jet consumers and CADIR's
continuity tolerance mapping.
