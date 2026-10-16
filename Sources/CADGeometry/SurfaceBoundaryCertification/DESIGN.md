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
            -> whole rectangular differences, tightened only by original continuity receipts
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

## Direct Original Query Execution

Ordinary parameter-curve and boundary entries create one independent execution
and call the same direct body. Composition forwards that original `inout
OriginalQueryExecution` through evaluation, differentiation, trimming, reversal,
chart lifting and interval jets. This component does not capture a mutable
execution in callbacks or create a child work/storage owner. Source/value/
coefficient and geometric ceilings remain independent. The original chart
producer's source ceiling of 16 remains an explicit local minimum.

Concrete parameter-curve owners retain their authored parameter law and current
guards. Dynamic polyline/control/sample arrays admit typed output storage before
allocation and each actual traversal visits the original execution. Immutable
source backing is borrowed or retained; a mutable result owns its charged output
allocation. Native B-spline validation uses the same execution instead of the
legacy cancellation-only scalar adapter.

Unsupported original coverage and existing incomplete numerical chart proposals
remain explicit. Direct accounting does not issue new source equality or chart
coverage authority. Bounded source validation forwards primitive families to the
main direct validation body; the main body never calls the bounded facade again.

Each side retains a support-bound original UV chart and a prepared original
surface. Singleton UV boxes remain singleton boxes; no nearby parameter substitutes
for the authored boundary. Whole rectangular differences are always valid value
bounds. Mean-value tightening requires a smooth owning UV interval and a retained
original surface continuity receipt of the corresponding order: position C0,
normal C1 and shape operator C2. Positional continuity alone does not authorize
normal or curvature tightening. Unknown continuity and unresolved regularity remain
explicit failures at the caller's existing subdivision limits.

The invocation admits its depth-bounded DFS buffer and fixed quantity buffers
before allocation. No private aggregate budget or fitted support is introduced.
CADIR's semantic continuity adapter and Modeling's final publication must forward
the same execution; nonlinear coedge fraction composition remains owned by its
original parameter-law producer.

The bounded quantity evaluator scales each original tangent by a finite positive
constant from its whole interval before forming the normal and metric. The
fundamental-form coefficients include the reciprocal tangent scales, so the
ambient shape operator and its boundary derivative still represent the original
physical law. This is an algebraic change of tangent basis, not a tolerance or
source change, and prevents squaring the raw coordinate magnitude before
normalization. Zero or unresolved regularity remains failure.


Chart-lift translation has one direct core. Existing original endpoint boxes are
transported outward and retained with their source/support; numerical lifts
without boxes remain candidates without original authority. A strict original
consumer requires the retained source, support and complete boxes at its own
entry and rejects missing authority. Translation never reconstructs a proof
from samples or silently drops existing boxes. Verification covers preservation
and explicit refusal of a missing-proof candidate by the strict consumer.

### Closed Parameter Loop Lift

`SurfaceParameterLoopLift` composes chart topology and the original sample
sequence under the same direct execution. Its ordinary constructor creates one
root and calls that body. Repeated closure removal, singular-start rotation,
periodic deltas, winding checks and singularity closure retain their existing
mathematics and failure guards. Typed output and scratch arrays are admitted
before materialization; each actual sample/singularity scan is charged to the
same owner. A numerical sample lift remains a chart path, not an original
boundary-identity certificate. Kernel materialization consumes this direct API.
Focused tests cover the original nonperiodic loop, repeated closure, exact
resource boundaries and cancellation through that actual constructor.

The chart-topology initializer is fallible and shares its single proof/data
construction body between ordinary and admitted callers. Recursive source
periods and singular-value transport use the original admission; retained
singular arrays are charged before construction. Consumers must propagate these
resource failures rather than treating absent admission as a nonsingular chart.

### Boundary Certifier Composition

The ordinary boundary certifier creates one common execution and enters the same
original-source body as the admitted `using:` entry. That entry lowers only the
geometric request depth with an immutable contribution scope on the caller
budget; independent value/coefficient limits are never derived from subdivision.
Prepared sides retain immutable source/chart receipts and local source-depth
policy, with no callback, admission adapter or mutable execution. Every quantity
query borrows the original execution at its actual parent cell depth. Typed DFS
and quantity buffers are admitted before allocation. Whole rectangular values,
continuity-gated mean-value tightening, singleton authored UV boxes, reversed
parameter/normal semantics and explicit unresolved-normal failure remain the
single certification algorithm. Publication checks cancellation after all cells.

The existing [SurfaceBoundaryCertificationTests](../../../Tests/CADGeometryTests/SurfaceBoundaryCertificationTests.swift)
remain the mathematical oracle for ordinary and direct entry composition. Direct
fixtures additionally verify ambient work accumulation, exact measured byte/work
refusal and cancellation under the same common budget.
