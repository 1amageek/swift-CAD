# Intersection Algebra

## Purpose and Scope

Child of [CADGeometry](../DESIGN.md), without children. Owns exact original
rational intersection equations and ideal preparation. General real component
decomposition and public SSI/CS closure remain required; finite real fibers and algebra preparation
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

### Intersection Classification and Proximity Boundary

This is the approved target contract; it is not a claim that the existing
public implementations already satisfy it. The workspace policy is linked
from the parent module design. Algebra preparation continues to own equations
and ideals only; composing intersection/proximity producers own the obligations
below.

| Contract | Assumption | Guarantee | Failure |
|---|---|---|---|
| Original intersection | Authoritative source laws and selected domains are retained | All original common points/curves and their parameter fibers are covered; tangent and singular contacts remain distinct from absence | Unresolved coverage cannot publish complete success |
| Original coincidence | A common image region and both source domains are identified | Whole-region source equality and parameter correspondence are established, including differing parameterizations | Small residuals, parallelism within angular tolerance, and samples alone cannot establish coincidence |
| Proximity | The metric, threshold, and compared domains are explicit | Certified distance bounds and corresponding source locations/regions justify the threshold decision | A bound straddling the threshold is unresolved, not silently accepted |
| Empty intersection | The whole selected product domain has been examined or otherwise excluded | No original common point exists in the requested domain | A failed search or exhausted allowance is not an empty result |

Intersection classification describes the common geometric image and retains
parameter-fiber dimension separately. In particular, a collapsed parameter
region is not automatically an image coincidence region. Proximity is a separate
relation that may hold alongside exact intersection; query kind and guarantee
remain explicit. Equality at a proximity threshold is accepted only when the
specified non-strict bound is established. No numerical residual tolerance is
an equality predicate.

```text
retained original sources and selected domains
  -> original intersection/coincidence proof -> original relation and coverage
  -> independent proximity proof            -> metric bounds and correspondence
                    -> explicit modeling repair policy
                    -> changed geometry/connectivity and deviation evidence
```

The original coefficients/laws determine identity. Numerical enclosures control
representation error; modeling tolerances bound a proximity query; input-source
uncertainty is separately retained when provided. None changes the authored
source law implicitly. Filtered numerical predicates may accelerate a decision
only when their bounds prove it; uncertain cases refine under the same caller
allowance or fail explicitly. Arbitrary-precision work does not imply an
unbounded time or storage entitlement.

The existing plane-pair tolerance branch and original interval-exclusion branch
currently have different public semantics. Migrate them through explicit result
contracts and dispatch, with caller migration recorded rather than a silent
change to the meaning of the existing coincidence result. This document resolves
the design decision, not those unimplemented migrations. General legacy source
coverage remains required before foundation completion.

Verification must distinguish separated parallel planes within the proximity
threshold, truly coincident planes, a shallow-angle real intersection, exact
tangency and nearby disjoint geometry. The same authoritative sources must
produce the same original classification through every public dispatch route.
Additional checks must reject transitive merging of pairwise-near entities,
unproven whole-region equality, threshold-straddling distance bounds, and partial
coverage reported as complete. Exhaustion and cancellation must remain explicit.
These are future behavioral completion obligations, not tests already passed.

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

### Finite Real Fiber Contract

`OriginalFiniteIntersectionFiber` consumes a verified zero-dimensional ideal
or a unit ideal. It owns complete enumeration of distinct real parameter tuples
within the requested coordinate domains; it does not classify contact order or
positive-dimensional real components. A positive-dimensional complex ideal is
rejected explicitly rather than called an empty real fiber.

For coordinate k, lexicographic elimination supplies all basis equations involving
only coordinates 0...k. Substitution of retained preceding exact roots gives
univariate polynomials over that root's ordered field. Their common real roots
are enumerated using exact GCD and the existing complete Sturm root issuer.
Pure leading powers for every coordinate ensure a nonzero monic equation at
each stage; loss of this invariant is an explicit failure. A constant GCD excludes
that whole prefix. The root issuer's global coefficient bound covers all real
roots; no arbitrary search window is introduced.

Each extension retains its defining root and embeds earlier coordinates into
the same descendant field. Closed domain boundaries are compared by exact signs
against their original Double coefficient values. Final tuples must satisfy every
retained original generator exactly. Repeated algebraic roots are emitted once;
the original ideal remains retained for the later contact-order owner.

```text
verified original ideal
 -> all real coordinate-0 roots
 -> specialized coordinate-1 common roots over each retained field
 -> remaining coordinates and exact closed-domain exclusion
 -> check every original equation -> complete finite parameter tuples
```

One caller ledger owns all stages, root visits, field allocations and final
tuples. Its parameter-root depth is passed unchanged; coefficient-root depth is
not invented for original rational coefficients. Failure in any stage discards
the whole publication. Tests must cover irrational towers, distinct roots with
the same preceding coordinate, repeated roots, complex-only fibers, exact closed
endpoint inclusion, excluded domains, cancellation and root/work/storage limits.
