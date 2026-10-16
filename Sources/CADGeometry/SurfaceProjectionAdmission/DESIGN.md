# Surface Projection Admission

## Purpose and Scope

Child of [CADGeometry](../DESIGN.md), without children. Owns complete finite-domain
closest-point projection against the retained original surface law.

## Responsibilities and Boundaries

The caller owns a finite support domain and cumulative work/cell/depth admission.
Geometry owns original interval preparation, exclusion and distance coverage.
Numerical Newton stations choose representatives; complete original source
position intervals provide their residual upper bounds.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADGeometry](../DESIGN.md) | parent | original surface laws | Publishes finite inverse query. | Preserve native UV. |
| [Geometry Conversion](../GeometryConversion/DESIGN.md) | depends on | closed original prepared jets | Bounds values and one-sided derivatives. | No private proof budget. |

## Architecture

```text
caller domain + cumulative admission -> original immutable preparation
    -> whole position/gradient cells -> numerical witness + real residual bound
    -> complete distance exclusion -> source UV result
```

## Contracts and Invariants

Every visited cell and refinement step debits the same exclusive `inout OriginalQueryExecution`. The direct public projection ports replace escaping work callbacks; no invocation object or child total-work owner is retained. Nested original preparation retains the independently selected source-expression depth; geometric cell refinement spends only geometric depth. The caller supplies independent source, geometric and algebra ceilings, with historical local defaults of 16, 32 and 32 respectively. Bounds include closed
endpoints and native one-sided jets without asserting C1. Source position
rounding is enclosed when admitting any candidate distance. Exclusion uses
outward lower distances and conservative tolerance comparisons.

## State, Ownership, and Lifecycle

Original-proof selection, explicit local caps and prepared original surfaces are immutable values.
Cumulative state remains in the caller's Mutex; all targets use the same API.

## Failure, Concurrency, and Constraints

Caller limits only lower historical limits. Exhausted traversal, nonfinite
source bounds or unresolved distance coverage throw typed errors. No sampled
mesh or fitted support supplies successful projection evidence.

## Verification and Change Impact

After source phase, test analytic and rational finite domains, knots, poles,
original images, offsets and revolution roots, real residual admission, shared
budget exhaustion and cancellation. Recheck solid classifier projection callers.

The threshold result is a separate public requirement. It excludes every cell
whose original distance lower bound exceeds the unchanged modeling distance.
An unresolved cell fails; a closest-point residual upper bound alone never
establishes an outside-tolerance result. All result queries reuse the same
immutable original preparation and caller ledger through the complete traversal.
