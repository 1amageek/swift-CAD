# Knot Removal

## Purpose and Scope

Child of [CADGeometry](../DESIGN.md), with no children. Owns G3 immutable
multiplicity reduction of open/non-clamped/rational 2D and 3D B-spline curves
and either independently open or periodic tensor surface axis.

## Responsibilities and Boundaries

The operation constructs a lower-dimensional homogeneous candidate by inverse
Boehm refinement and column-pivoted QR. Numerical construction never authorizes
success: a separate full-domain interval certificate admits the final candidate
against the original source. Topology, application editing and capability
publication remain with their existing owners.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADGeometry](../DESIGN.md) | parent | Positive rational basis | Geometry values and validation | Source remains immutable |
| [PeriodicBSpline](../PeriodicBSpline/DESIGN.md) | depends on | Cyclic refinement, origin and period | Shared exact editing path constructs the reduction matrix | Rounded refinement alone is not an error certificate |
| [SurfaceFitting](../SurfaceFitting/DESIGN.md) | depends on | Full-rank Householder QR | Solves homogeneous coordinates | Rank/solve success does not establish geometric accuracy |

## Architecture

```text
source + exact knot + target multiplicity + budgets
    -> structural admission -> reduced knot basis
    -> inverse refinement matrix -> homogeneous QR candidate
    -> original/candidate span overlap partition
    -> outward Cox polynomial coefficients -> Bernstein residual hull
    -> positive weight lower bound -> entire-domain deviation certificate
    -> immutable result or typed rejection
```

## Contracts and Invariants

- Knot identity is exact stored equality. Open endpoints/exterior knots cannot
  be removed because the natural parameter domain must remain unchanged.
- Target multiplicity is nonnegative and strictly lower than the current
  multiplicity. Zero removes every copy; all requested reductions are atomic.
- Periodic parameters normalize to their cyclic knot representative. Removing
  the last seam copy rotates the stored base chart while retaining the period
  and chosen fundamental origin. Every candidate has positive finite weights.
- Degrees, source values, open domains, periodic flags and origins are retained.
- Certification compares the final result to the original source, covering every
  knot span and both sides of every knot. Samples never authorize acceptance.
- On each overlapping source/candidate span, outward arithmetic expands Cox
  basis polynomials and converts homogeneous residuals to Bernstein form.
  Their control hull bounds the residual over the complete interval, including
  outward-enclosed periodic chart translations and tiny boundary overlaps.
- With common local spatial origin, residual homogeneous XYZ bound D, weight
  residual bound E, candidate control radius R and source minimum weight w,
  positional deviation is at most (D + R*E)/w. A tensor's untouched positive
  basis is a convex combination of these line residuals; maxima over every
  line therefore certify the entire two-parameter domain. Curve2D uses an
  isometric XY embedding of the same construction and certificate.
- Tolerance rejection means this operation cannot certify its constructed
  candidate within the supplied tolerance; it does not claim global optimality
  over every possible approximation or a lower bound on actual error.

## Runtime Flows

One basis is solved per requested reduction. Surface lines share identical
axis requests and retain the untouched net dimension. The complete operation
returns only after all reductions and final original-source certification.

## State, Ownership, and Lifecycle

Only operation-local value buffers and budget counters exist. Inputs are value
borrows, outputs own arrays, and no cache, shared state or target-specific
isolation is introduced.

## Failure, Concurrency, and Constraints

BSplineKnotRemovalError distinguishes invalidInput, toleranceRejected,
numericalFailure and resourceLimitExceeded. Unsupported domain changes are
invalid input. Rank loss, nonpositive candidate weights, nonfinite arithmetic
or an unrepresentable retained periodic period are numerical failure.

Options admit any positive representable allocation/work budgets. The scalar
budget bounds cumulative generated scalar slots, including conservative
matrix/QR, homogeneous, line and interval-polynomial scratch charges; it is
stricter than peak memory. Work counts conservative scalar arithmetic units.
Every dimension product is overflow-checked and charged before its allocation
or loop. Defaults select 1,048,576 generated scalar slots and 16,777,216 work
units. Callers may raise either without changing geometric semantics.

## Verification and Change Impact

[KnotRemovalTests](../../../Tests/CADGeometryTests/KnotRemovalTests.swift)
owns exact and approximate reductions, rational/nonrational and non-clamped
curves, periodic seam/interior and degree-greater-than-cycle paths, 2D embedding,
U/V mixed and doubly periodic surfaces, origin/source/domain retention, invalid
requests, sharp-knot tolerance refusal and independent budget exhaustion.
Public operations execute QR construction and independent interval admission.
Downstream topology changes are outside this component. Normal WASM and
Embedded runtime evidence is owned by the package integration task.
