# Original Normal Angle Bounds

## Purpose and Scope
Child of [CADGeometry](../DESIGN.md), without children. Owns conservative
conversion between physical normal angles and unit-normal chord distances.

## Responsibilities and Boundaries
The original input angle is the stored binary number in physical radians.
Intrinsic surface chart labels have a separate owner. Boundary certification
owns actual normal chord bounds; CADIR owns semantic tolerance admission.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADGeometry](../DESIGN.md) | parent | original geometry bounds | Supplies physical scalar bounds | No libm candidate is proof |
| [Rational Bivariate Algebra](../RationalBivariateAlgebra/DESIGN.md) | depends on | exact original rational arithmetic and outward conversion | Admits physical sine via alternating bounds | All work/storage borrow the caller |
| [Boundary Continuity](../../CADIR/BoundaryContinuity/DESIGN.md) | used by | safe chord tolerance and certified angle upper bound | Preserves the original physical angle requirement | A smaller chord bound is conservative |

## Architecture
```text
original binary angle -> exact rational half-angle
    -> decreasing alternating sine terms -> exact two-sided bounds
    -> outward chord interval -> lower admission threshold
certified chord -> monotone binary angle brackets -> original chord signs
    -> retained upper angle bound
```

## Contracts and Invariants
For angles below the mathematical pi enclosure, the sine half-angle lies below
two and successive absolute terms strictly decrease. Consecutive alternating
partial sums enclose the original sine. Refinement stops at adjacent representable
outward bounds; a caller resource failure remains a failure. Angles at or above
the proved pi upper bound admit chord two. A binary pi label below mathematical
pi cannot silently admit opposite normals. Inverse bisection updates a side only
from proved chord signs; an unresolved comparison returns the maintained upper
bound. Chord zero has exact angle zero, and chord two uses the proved pi upper
bound. No rounded asin value or chart-label phase supplies proof.

## State, Ownership, and Lifecycle
All state is local to one borrowed rational invocation. No callback, allowance,
mutable shared cache or asynchronous lifetime is retained.

## Failure, Concurrency, and Constraints
Nonfinite or invalid inputs fail. A positive physical tolerance whose safe chord
lower bound has no positive floating representation fails explicitly. Work,
coefficient payload and cancellation are owned by the caller. Series order is
determined by actual representability; there is no separate arbitrary ceiling.

## Verification and Change Impact
After the source phase verify zero/two chord endpoints, tiny physical angles,
binary pi and pi upper-bound behavior, conservative roundtrip admission and
lowered caller budgets through the public boundary continuity evaluator.

## Direct Execution Admission

Source arithmetic borrows `A: ExactScalarAdmission & ~Copyable`; composed query
operations borrow `inout OriginalQueryExecution`. Source validation, native span
validation, structural comparisons and exact refinement receive that same admission.
The [execution owner](../OriginalQueryExecution/DESIGN.md) defines cumulative
work and actual byte accounting, independent depth axes, cancellation and lexical
proof scopes. Retained geometry and relation evidence stay immutable; no callback
adapter, copied counter or second allowance supplies arithmetic authority.
