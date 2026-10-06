# Intersection Algebra

## Purpose and Scope

Child of [CADGeometry](../DESIGN.md), without children. Owns exact original
rational intersection equations and ideal preparation. General real component
decomposition and public SSI/CS closure remain required; algebra preparation
alone completes neither intersection requirement.

## Responsibilities and Boundaries

Owns the polynomial ring, ideal preparation and native homogeneous embedding.
Original native producers retain their validated source/domain authority.
No fitted, rounded or interval coefficient becomes an original source value.
Numerical tracing, public intersection publication and upper features are outside
this component.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADGeometry](../DESIGN.md) | parent | Original source families | Owns public dispatch | Equations are not intersection results |
| [Rational Bivariate Algebra](../RationalBivariateAlgebra/DESIGN.md) | depends on | Original rational coefficients, native homogeneous laws, caller ledger | Reuses exact arithmetic | Complex dimension is not real coverage |
| [Surface Surface Query Admission](../SurfaceSurfaceQueryAdmission/DESIGN.md) | coordinates with | Cumulative original invocation | SSI composition | No private allowance |
| [Curve Surface Query Admission](../CurveSurfaceQueryAdmission/DESIGN.md) | coordinates with | Independent caller limits | CS composition | No depth-cap conversion |

## Architecture

```text
original native laws + original selected domains
  -> homogeneous embedding
  -> three coincidence equations + denominator guards
  -> exact lexicographic ideal
  -> real decomposition / parameter lifting / whole-domain coverage
```

## Contracts and Invariants

CS coordinates are (t,u,v); SSI coordinates are (u1,v1,u2,v2). One additional
coordinate can express denominator saturation. Exponents are nonnegative and
checked for overflow. Higher indexed coordinates have lexicographic priority.
Zero terms are absent; reduced bases are monic and deterministic.

For every spatial coordinate the equation is H1*W2-H2*W1=0. Both original
denominators remain retained. Saturation adds z*W1*W2-1=0, excluding components
where either denominator vanishes. Source/domain owners survive cancellation
of every coincidence equation.

A unit ideal proves algebraic absence. A pure leading power of every coordinate
proves zero complex dimension. Missing pure powers indicate positive complex
dimension. Neither is complete real-root lifting or geometric image dimension.

The foundation must support every existing Curve3D/Surface3D source family,
isolated/regular/critical/coincident strata, whole-domain coverage, exact closed
incidence and original periodic/pole semantics. A successful graph join requires
shared original solution identity and branch incidence. Representative proximity,
overlapping intervals or endpoint curvature times a gap do not establish identity.
Numerical residual and whole-component proof are distinct obligations. Empty
results require exclusion of the whole requested domain. Exhaustion or unresolved
required coverage cannot return partial success. Upper feature repairs are excluded.

## State, Ownership, and Lifecycle

Immutable Sendable source values own equations. Scratch buffers and pair queues
are invocation-local; there is no shared mutable state or target-specific isolation.

## Failure, Concurrency, and Constraints

The same RationalAlgebraAdmitting owner pays all original preparation, arithmetic
and payload storage through RationalAlgebraStorage. Admission precedes growth.
Cancellation is checked during preparation/reduction. Overflow, invalid binding,
exhaustion and failed ideal identities propagate typed errors. A partial basis
is never published after failure. Parameter, geometric and coefficient depth
remain separate capabilities of composing callers.

## Verification and Change Impact

IntersectionAlgebraTests must check original equations, denominator exclusion,
elimination, redundant generators, deterministic finite/positive-dimensional/unit
classification, fractional coefficients and independent work/storage failures.
Every original generator and every final S-pair must reduce to zero. These
certify exact ideals only; real decomposition must separately prove lifting,
branch incidence and domain coverage before public dispatch completion.
