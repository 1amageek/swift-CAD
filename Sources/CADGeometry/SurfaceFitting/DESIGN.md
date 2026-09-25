# Surface Fitting

## Purpose and Scope

Child of [CADGeometry](../DESIGN.md), with no children. Owns the numerical
construction of constrained surfaces, not BRep publication or UI state.
Column-pivoted Householder QR supports equality-constrained least squares.
A bounded dogleg trust-region primitive handles nonlinear least squares. A
sequential equality-constrained least-squares solver handles hard nonlinear
constraints and objectives. Geometric certification and feature consumers remain
pending SC1.8 work.

## Responsibilities and Boundaries

QR owns a finite row-major factor buffer, reflector coefficients and a column
permutation. It does not certify geometric error, continuity or surface validity.
No existing Sketch or intersection solver is replaced by this component.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADGeometry](../DESIGN.md) | parent | finite geometry and typed failure | Hosts fitting arithmetic | Solver convergence is not geometric certification. |
| [CADModeling](../../CADModeling/DESIGN.md) | future consumer | verified surface construction | Composes admitted geometry into features | No production feature is connected until its construction contract is complete. |

## Architecture

```text
finite matrix + explicit rank tolerance + element budget
    -> scaled column-pivoted Householder QR
        -> orthogonal transforms / triangular coefficients / numerical rank
            -> full-column-rank least-squares solve
equality matrix C and target d
    -> QR of transpose(C) -> particular solution + implicit null space
        -> least squares in free coordinates -> verify every original equality
```

## Contracts and Invariants

- Fixed-basis point interpolation preserves the supplied degrees, knots and
  positive rational weights. Point constraints specify UV locations and world
  positions, not control points. The equality matrix is the normalized rational
  tensor-product basis. Out-of-domain UVs are rejected rather than clamped.
- A positive reference weight minimizes control-point displacement from the
  supplied template; a separate nonnegative control-net fairness weight adds
  second finite differences along each grid direction. This discrete objective
  is not a geometric curvature integral, G1/G2 constraint or accuracy tolerance.
  Neither weight relaxes the positional equalities. Callers own both weights.
- The numerical solver factors common equality and reduced objective matrices
  once for multiple coordinate right-hand sides. Its element budget includes
  coefficient matrices, right-hand sides and returned solutions before allocating
  scratch storage. Individual right-hand sides must have matching dimensions.
- The interpolator checks every resulting point using the actual rational
  surface evaluator and a Euclidean positional tolerance. This verifies discrete
  point interpolation only: surface regularity, boundary-wide continuity, BRep
  admission and automatic parameterization remain separate required contracts.
  Invalid input, conflicting constraints and exhausted arithmetic/storage fail
  without returning a surface. The template is immutable input.
- Factorization uses `A P = scale Q R`; R is stored at normalized matrix scale.
- Columns are pivoted using freshly computed trailing norms. Rank is a numerical
  decision relative to the largest initial column norm and caller-supplied
  threshold, not a proof of mathematical rank or a singular-value estimate.
- Full-rank least squares solves without forming normal equations. Deficient
  or underdetermined systems fail this operation; a basic solution is never
  mislabeled as a minimum-norm solution.
- Dimensions, finite values, integer products, rank tolerance and the element
  budget are checked before scratch allocation. Nonfinite arithmetic fails.
- Input values are preserved. One mutable matrix buffer is needed to store the
  factors; Swift value semantics may copy shared input storage. Reflectors are
  applied without constructing Q; each transform owns one vector result.
- State is immutable after initialization and unconditionally Sendable. There
  is no shared mutable state, I/O, callback or target-specific synchronization.
- Equality-constrained least squares minimizes `||A x - b||` subject to `C x = d`.
  Redundant consistent equalities are accepted; every original equality is
  checked against a caller-owned absolute residual tolerance before returning.
  QR of transposed C supplies the constrained and free coordinates. The reduced
  objective must have full column rank; nonunique minima fail as singular rather
  than silently choosing an arbitrary control net. No penalty weight relaxes C.
- Zero equality rows reduce to ordinary least squares. Zero objective rows are
  allowed only when equalities uniquely determine the solution. Matrix dimensions
  and combined coefficient/right-hand-side/output element budget are checked
  before scratch allocation. Scratch storage is a constant multiple of that budget;
  the orthogonal null-space matrix is never materialized. Residual checking is
  numerical, not interval-certified boundary-wide geometric verification.
- Nonlinear fitting accepts analytic residuals and a row-major Jacobian from a
  synchronous throwing evaluator; dimensions remain fixed after initialization.
  The caller owns coordinate/residual units and supplies radii, tolerances,
  evaluation and matrix budgets. QR computes a full-rank Gauss-Newton step;
  dogleg limits it to the trust region. Actual versus predicted decrease decides
  acceptance. Rejected candidates never replace the last accepted iterate.
- Termination distinguishes residual satisfaction from first-order stationarity;
  neither certifies geometric constraints or a global minimum. Rank deficiency,
  finite-range failure, stagnation and budget exhaustion throw. Evaluator errors
  propagate, including cancellation. At most one evaluation occurs per trial.
  Each trial uses at most 64 scalar bisections to locate the dogleg boundary.
  No penalty residual implicitly stands in for a hard geometric constraint.

- Nonlinear equality fitting composes the existing QR-constrained least-squares
  step with an Armijo L1 merit line search. Analytic objective and constraint
  Jacobians have fixed dimensions. The caller owns residual/constraint scaling,
  absolute constraint tolerance, projected-gradient tolerance, maximum step
  radius and evaluation/storage budgets. The objective may encode fairness;
  constraint values always encode hard equalities to zero.
- A result requires actual equality residuals within tolerance and the objective
  gradient projected onto the equality Jacobian's null space within the requested
  relative tolerance. The projected gradient is normalized by the larger of one
  and the full gradient norm, in caller-scaled coordinates. This is local first-order stationarity, not a global minimum
  or geometric certificate. Inconsistent linearizations and undetermined free
  directions fail explicitly. A feasible stationary initial input is admissible.
- The merit weight only selects trial steps; it never changes the final feasibility
  test. The actual improvement relative to directional prediction shrinks or
  grows the step radius within the caller limit. Merit differences use a difference
  of squares to retain small changes near a nonzero-residual optimum. Rejected
  trials retain the accepted state. Every trial evaluation counts
  toward the finite budget; evaluator failures, including cancellation, propagate.
  All coefficients and arithmetic must remain finite. Scratch storage is a
  constant multiple of the combined matrix/vector element budget. State is local
  to one synchronous invocation; no conditional isolation or shared state exists.

## Failure, Concurrency, and Constraints

The caller supplies the maximum matrix element count and relative rank tolerance.
Invalid input, exhausted storage budget, singular solve and numeric range loss
are distinct existing KernelError codes. Factorization work is bounded by
`O(m n min(m,n))`, storage by `O(m n + m + n)`; transforms use `O(m min(m,n))`.

## Verification and Change Impact

[SurfaceFittingQRTests](../../../Tests/CADGeometryTests/SurfaceFittingQRTests.swift)
checks reconstruction, orthogonality, pivoting, least-squares residuals, numerical
rank, extreme scaling and invalid/resource-limited inputs. These tests do not
establish a complete constrained surface feature. Changes require rechecking
dependent least-squares and trust-region solvers when those are implemented.

[SurfaceFittingLeastSquaresTests](../../../Tests/CADGeometryTests/SurfaceFittingLeastSquaresTests.swift)
checks constrained optima, redundant and inconsistent equalities, unique and
nonunique solutions, zero-row cases, scaling, and invalid/resource-limited input.

[SurfaceFittingTrustRegionTests](../../../Tests/CADGeometryTests/SurfaceFittingTrustRegionTests.swift)
checks nonlinear convergence, rejected trials, nonzero-residual stationarity,
budgets, malformed evaluation and propagated evaluator failure.
Dogleg algorithm context: [MINPACK dogleg](https://www.netlib.org/minpack/dogleg.f).

Algorithm reference: [LAPACK QR with column pivoting](https://www.netlib.org/lapack/lug/node42.html).
Minimum-norm rank-deficient solving requires additional orthogonal factorization,
as described in [LAPACK complete orthogonal factorization](https://www.netlib.org/lapack/lug/node43.html).

[SurfaceFittingPointInterpolationTests](../../../Tests/CADGeometryTests/SurfaceFittingPointInterpolationTests.swift)
verifies actual off-control-grid point interpolation, nonunit rational weights,
objective/constraint separation, contradictory UV constraints, input preservation
and explicit resource/domain refusal. The primitive has no UI or feature entry
yet and does not establish completion of Constrained Surface.

[SurfaceFittingNonlinearEqualityTests](../../../Tests/CADGeometryTests/SurfaceFittingNonlinearEqualityTests.swift)
checks hard nonlinear feasibility against competing objectives, constrained
stationarity, redundant/conflicting constraints, rejection, resource ceilings and
propagated evaluator failures. The line-search formulation follows the
[NTNU SQP notes](https://wiki.math.ntnu.no/_media/tma4180/2019v/sqp.pdf);
the local quadratic model uses the least-squares Jacobian rather than BFGS.
