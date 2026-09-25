# Surface Fitting

## Purpose and Scope

Child of [CADGeometry](../DESIGN.md), with no children. Owns the numerical
construction of constrained surfaces, not BRep publication or UI state.
Column-pivoted Householder QR supports equality-constrained least squares.
Nonlinear trust-region fitting remains pending SC1.8 work.

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
  and combined input matrix element budget are checked before scratch allocation.
  Scratch storage is a constant multiple of that budget plus vector dimensions;
  the orthogonal null-space matrix is never materialized. Residual checking is
  numerical, not interval-certified boundary-wide geometric verification.

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

Algorithm reference: [LAPACK QR with column pivoting](https://www.netlib.org/lapack/lug/node42.html).
Minimum-norm rank-deficient solving requires additional orthogonal factorization,
as described in [LAPACK complete orthogonal factorization](https://www.netlib.org/lapack/lug/node43.html).
