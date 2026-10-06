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

A linear fiber uses its exact parent-field quotient rather than adding a
redundant algebraic extension. Every coordinate retains its original root witness
separately, including linear coordinates. The source ideal, root witnesses and
coordinate tuple therefore survive this exact representation reduction.

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
the whole publication. A cancellation-checking adapter holds the exclusively
borrowed ledger value during lifting and restores it on both return and throw;
it forwards all four admission operations without creating or resetting an
allowance. Tests must cover irrational towers, distinct roots with
the same preceding coordinate, repeated roots, complex-only fibers, exact closed
endpoint inclusion, excluded domains, cancellation and root/work/storage limits.

### Full Rational Projection Preparation

`ExactIntersectionProjection` owns a full Collins projection polynomial set;
its result is preparation for sign-invariant lifting, never a real-component
or intersection publication. Unlike restricted well-oriented projection, it
retains degree changes and nullification witnesses. The construction follows
[the full projection operator and principal subresultant matrix definition](https://ceur-ws.org/Vol-1974/RP2.pdf).

`ExactIntersectionProjectionTower` applies this operator from the highest
original coordinate down through coordinate zero and retains every level's
source/output set. Original coordinate slots are preserved rather than renamed.
The last level has no nonconstant projection output; its univariate sources
remain available for complete root lifting. No level publishes representative
samples as a whole-cell proof.

For each input polynomial, retain every nonzero reductum obtained by removing
its current highest-axis coefficient. Project each reductum's leading coefficient
and all principal subresultant coefficients with its derivative. For each pair
of input polynomials, project principal subresultants of every pair of their
reducta. Axis-independent input polynomials pass to the lower level unchanged.
Only identically zero or nonzero rational constant outputs are omitted. Nonzero
outputs are normalized by a rational scalar, never by a parameter-dependent
coefficient. Duplicate suppression checks exact polynomial equality.

For degrees m and n, principal index j uses the first n-j shifted rows of the
first polynomial and the first m-j shifted rows of the second, restricted to
the first m+n-2j columns of the Sylvester matrix. Its exact determinant is
computed by fraction-free Bareiss elimination over the remaining polynomial
ring. Row permutations retain their determinant sign. Every division is exact
polynomial division with a strictly descending leading monomial; a nonzero
remainder is an explicit invariant failure. The empty determinant is one.

```text
original rational polynomials
 -> all nonzero reducta and leading coefficients
 -> derivative and pair principal subresultants
 -> exact lower-coordinate projection set
 -> sign-invariant lifting (separate completion obligation)
```

The same caller pays coefficient extraction, reducta, matrix payloads, arithmetic,
deduplication and recursive levels before retained growth. No matrix dimension,
polynomial count or degree is converted into a fresh allowance. Cancellation,
ring mismatch, overflow, nonexact division and exhausted work/storage abort the
whole preparation. Storage admission covers retained payload slots, not an
unmeasured claim about Swift allocator overhead. Scratch matrices are local;
immutable outputs have identical Sendable semantics on all targets.

Verification must compare index-zero elimination against the existing independent
bivariate resultant, verify repeated-root principal coefficients, retain witnesses
for degree drops and complete fiber nullification, and reject nonexact division,
invalid axes/rings and independent ledger exhaustion. Projection preparation alone
does not prove delineability, real cell adjacency or public SSI/CS completion.

### Rational Real Cell Lifting

`OriginalRationalIntersectionCells` owns a sign-invariant cylindrical partition
of the full real parameter space for original rational equations and closed or
unrestricted coordinate domains. It consumes only a tower issued by the full
projection constructor. Domain endpoint polynomials are inserted before tower
preparation, making exact domain selection a union of whole cells. It owns
parameter-cell dimensions, not geometric image dimensions, curve joins or
singular incidence. General nonrational producers remain a separate obligation.

At axis k, every lower-level cell is connected and sign-invariant for the
projection polynomials. Specialize level-k source polynomials at its retained
exact sample and isolate all distinct real roots of each nonconstant source.
A linear source with an exact rational parent-field quotient issues that root
directly with a point isolation. Other sources use the complete Sturm issuer.
Merge these complete source root sets by exact ordering and equality: disjoint
isolations establish order; overlapping isolations establish equality only when
the exact source GCD has a root in their intersection. The unique-root contracts
limit that count to one. Distinct overlapping roots refine under inherited depth
until separated. A duplicate retains the intersection isolation and both causal
depths; it never merges on interval overlap alone. Known rational roots are not
bisected and no aggregate product introduces avoidable degree/coefficient growth.
Admission or arithmetic failure propagates without changing the allowance.
Full projection fixes each source's degree, nullification, root multiplicities,
root ordering and shared-root membership over the whole lower cell. Its ordered
continuous root sections, together with open sectors between consecutive
sections and the two unbounded sectors, cover the complete next coordinate.
Identically zero specializations are permitted only as whole-fiber nullification
under this projection certificate; no representative-only exclusion is used.

Each stack retains its parent cell, source degrees, complete root isolation and
ordered child-cell indices. Each child retains its stack, root ordinal (section)
or bounding root ordinals (sector), exact sample in one ordered-field context,
parameter dimension, inherited admission depth independent of sample-field depth,
and signs of the retained level sources. Section samples
retain original root witnesses; rational sector samples are chosen strictly
between the two roots after exact rational isolation separation. Refinement
uses the original caller's inherited depth and ledger, never a fixed search box.
Unbounded sectors use rational witnesses strictly outside the complete root
isolations; a rootless fiber uses zero as its witness. A linear section uses its
exact parent-field quotient without discarding its retained root identity or
resetting the partition's causal isolation depth. Sector depth includes both
bounding root isolations; every child inherits at least its parent's depth.

```text
original equations + exact closed-domain endpoint polynomials
 -> issued full projection tower
 -> real line roots / sections / sectors
 -> repeat over every connected lower cell
 -> full real product-domain partition
 -> exact original signs and whole-cell domain selection
```

Every child is admitted through the same parameter-cell capability even when
its sample is rational. Local invocation scratch, field arithmetic, root work,
stack/cell payloads and copied prefix arrays share one cumulative ledger.
Cancellation forwarding restores the same consumed caller state on throw.
Publication is atomic; a failed stack cannot publish an empty or partial result.
An empty solution-cell list means all complete full-dimensional partition cells
have been excluded by original equation/domain signs, not that tracing found no
representative. No cell adjacency or source-family completeness is implied.

Tests must distinguish a positive-complex-dimensional sum of squares with one
real point, a complex locus with no real points, real curves, whole-space
coincidence, complete nullified fibers, closed endpoint selection, unbounded
sectors, repeated roots, nested irrational sections and independent failures.
The finite-fiber and cell-lifting paths share ordered-field polynomial evaluation;
that helper owns original coordinate substitution only and does not issue
whole-cell proofs independently of the retained projection owner.

### Original Differential Rank Strata

`ExactIntersectionDeterminant` owns exact square polynomial matrix evaluation;
principal subresultants and Jacobian minors both consume this contract rather
than duplicating fraction-free elimination. It validates dimensions and rings,
retains row permutation sign, and rejects nonexact divisions. Matrix payload
creation remains the caller's responsibility; the caller supplies admitted,
uniquely held invocation scratch. Both production callers construct fresh local
arrays before evaluation. The determinant owns admitted updates to that buffer.

`ExactIntersectionJacobian` retains derivatives of each original equation and
all square minors with their original row/coordinate indices. Its witness set
includes constants and zeros so rank remains traceable to the original matrix.
Minor enumeration is exhaustive through min(equationCount, coordinateCount),
with checked payload dimensions and caller admission before combination growth.
Equations are not replaced by a radical or square-free ideal: repeated contact
laws retain their own linearization, even when their zero sets are the same.

`OriginalRationalIntersectionStrata` augments real-cell partition preparation
with those minors as sign witnesses, not additional zero constraints. The cell
owner publishes the witness sign offset so no consumer reconstructs its internal
domain/source ordering. On each selected solution cell the maximum order of a
nonzero minor proves the original equation Jacobian's constant rank throughout
that cell. No nonzero minor means rank zero. Empty original equation sets have
rank zero over their whole selected domain.

```text
original equations -> exact derivatives -> all indexed square minors
  -> original equations + domain boundaries + partition-only witnesses
  -> sign-invariant real cells -> retained original Jacobian rank per cell
  -> singular branch incidence (separate completion obligation)
```

This partitions the crossing of xy=0 into the origin and four open rays by
adding x and y as derivative witnesses. Rank evidence alone does not prove
geometric regularity, contact multiplicity, Whitney conditions, image rank,
connected components, adjacency, or a particular branch attachment. Those
contracts remain with their composing owners. All stages are immutable outputs
and invocation-local scratch, using the same cumulative admission and atomic
failure publication. Tests must verify higher-order indexed minors, crossings,
repeated original equations, zero equations and independent work/storage failures.
