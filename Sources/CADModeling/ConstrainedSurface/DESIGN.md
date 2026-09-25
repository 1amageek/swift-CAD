# Constrained Surface

## Purpose and Scope

Child of [CADModeling](../DESIGN.md), no children. Constructs a sheet through
finite authored point constraints using the existing constrained least-squares
solver. [CADIR](../../CADIR/DESIGN.md) owns the retained point/options source.

## Responsibilities and Boundaries

Automatic parameterization selects a nondegenerate local projection plane.
The candidate is a cubic B-spline height graph over that plane. Only heights
are unknown; projection coordinates remain affine, preventing folds in the
parameterization. Angular tolerance bounds the normal change everywhere on the patch from the
minimum-height hard interpolant to a relaxed interpolant. The normal map of a
height graph is 1-Lipschitz in its world-space height gradient (geodesic metric).
Derivative control hulls bound both gradient differences, so scaling the
relaxation by at most angle / gradientBound certifies the full surface.
This is point-constrained fitting, not boundary G1/G2 fitting or mesh conversion.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADModeling](../DESIGN.md) | parent | feature evaluation | Owns dispatch and sewing | Publication follows independent validation. |
| [SurfaceFitting](../../CADGeometry/SurfaceFitting/DESIGN.md) | depends on | bounded equality least squares | Fits scalar heights | Solver success alone is not geometric admission. |
| [CADIR](../../CADIR/DESIGN.md) | depends on | point constraints | Retains points and tolerances | Failed fit must retain original input. |

## Architecture

```text
point constraints -> projection frame and UVs -> height constraints
    -> bounded cubic basis refinement -> constrained least squares
        -> independent point residuals and normal-change bounds -> existing B-spline sheet evaluator
            -> whole-domain regularity/embedding and exact BRep admission
```

## Contracts and Invariants

The source retains points in meters, positive
position tolerance, angular tolerance in radians within (0, pi], and an
optimization mode. Performance uses first control-net differences for its relaxed objective;
Smoothness uses second and mixed differences. Both retain a positive identity
term and start with the same minimum-height hard interpolant. Increasing angular
tolerance permits more relaxation while retaining the exact point constraints.
The official operation video confirms shape changes for point-only input; the
previous optional-normal-only interpretation was insufficient. This construction
defines Rupa's normal-change reference explicitly; it does not claim access to
Plasticity's private fitting algorithm. Hard position constraints are
never replaced with weighted soft penalties. A tighter tolerance cannot authorize
a larger residual. At least three noncollinear positions are required. A projection
collision with incompatible heights  is rejected.

## Failure, Concurrency, and Constraints

The evaluator owns its finite matrix/control-net budget and checks products
before allocation. Basis refinement stops at that budget; exhaustion is a typed
failure, not a surface result. Inputs and scratch values are task-local and
Sendable; there is no shared state, callback, I/O or target-specific isolation.

## Verification and Change Impact

CADModelingTests owns point residuals on evaluated surfaces, angular relaxation,
nonplanar geometry, both objectives and degenerate/conflicting input rejection.
CADExchangeTests owns retained source replay. Core/UI owns click acquisition,
point undo, identity-preserving replacement and failed-publication rollback.
Changing fitting must recheck the parent evaluator and Core source consumers.
