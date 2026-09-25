# Boundary Continuity

## Purpose and Scope

Child of [CADIR](../DESIGN.md), with no children. Maps existing continuity levels,
orientations and physical tolerances to whole-boundary geometric certification.

## Responsibilities and Boundaries

The evaluator consumes immutable surfaces and parameter curves and returns
certified upper bounds or throws. Feature construction, references, BRep
publication and UI state belong to their existing owners.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADIR](../DESIGN.md) | parent | SurfaceContinuityLevel, SurfaceContinuityTolerances | Owns semantic G0/G1/G2 vocabulary | Existing sampled results are not certificates. |
| [SurfaceBoundaryCertification](../../CADGeometry/SurfaceBoundaryCertification/DESIGN.md) | depends on | complete interval certificate | Owns geometric bounds | Unsupported charts and exhausted budgets throw. |
| [CADModeling](../../CADModeling/DESIGN.md) | used by | certified admission before publication | Consumes proved bounds | No feature capability is implied by this primitive. |

## Architecture

```text
continuity request + oriented boundary sources
    -> angle-to-chord tolerance conversion
        -> geometry interval certificate
            -> typed physical upper bounds
```

## Contracts and Invariants

Normalized boundary fractions define correspondence. Parameter traversal and
face orientation are independent. Position is mandatory; G1 adds oriented normals;
G2 adds a bound for every direction of the signed shape operator. The kernel's
Frobenius bound is conservative with respect to existing tangent-action checks.
Tolerances, subdivision limits and depth are caller-owned. The returned certificate
contains interval counts, never a sampled success count. All values are immutable
and Sendable. Failures and cancellation propagate without publication.

## Verification and Change Impact

`Tests/CADIRTests/SurfaceBoundaryContinuityTests.swift` verifies G0/G1/G2 mapping,
orientation and strict angle admission. Changes require rechecking the geometry
certifier and dependent modeling admission.
