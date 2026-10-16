# Native Surface Chart Injection

## Purpose and Scope
Child of [CADGeometry](../DESIGN.md), with no children. Issue immutable proofs of
injectivity of original finite nonperiodic Native surface charts on their entire
closed native support. The proof recognizes two independent fractional-linear
XYZ coordinates from the original homogeneous coefficients; it is not a solver.

## Responsibilities and Boundaries
The Geometry producer issues this source-map proof. The SSI publisher consumes
and retains the proof; it does not infer injectivity from samples, normals or rank.
Original four-UV coverage and incidence continue to own all solution tuples,
closure and connectivity. Charts outside this proof scope use the existing graph.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADGeometry](../DESIGN.md) | parent | original geometry authority | Geometry owns Native meanings | Parent indexes this child |
| [Rational algebra](../RationalBivariateAlgebra/DESIGN.md) | depends on | exact coefficients and polynomial arithmetic | Checks all coefficient identities | Same caller admission |
| [Multi-chart SSI](../NativeMultiChartSurfaceSurfaceRelations/DESIGN.md) | used by | original closed chart bindings | Producer issues proofs before choosing publication | Both roles and every chart must prove injection |
| [SSI relations](../NativeSurfaceSurfaceRelations/DESIGN.md) | used by | complete common coverage and immutable receipt | Publisher retains validated proof | Single-chart positive and isolated routes remain unchanged |

## Architecture
```text
source-issued Native charts + original H/W + closed domains
 -> exact affine coefficient slices
 -> full polynomial cross identities + determinants + endpoint signs
 -> immutable chart injection proof
 -> validated common coverage binding
 -> complete four-UV cell images, image dimension = parameter dimension, fiber = 0
```

## Contracts and Invariants
For each parameter s, a distinct XYZ coordinate satisfies the polynomial identity
`(c*s+d)*H[k] = (a*s+b)*W` for every original coefficient. The retained determinant
`a*d-b*c` is nonzero. The affine denominator has the same nonzero exact sign at
both closed native endpoints, so it has no zero anywhere on that interval.
Consequently equal XYZ recovers each parameter uniquely. Negative determinants
and negative denominators are valid; no sign direction is guessed.

The source-issued law derives W from validated strictly positive source weights
and the original Cox-de Boor basis. Nonnegative basis and partition of unity on
closed native spans, including the one-sided closed knot endpoint law, make W
strictly positive throughout that support. The proof retains both issued owners,
full original homogeneous laws, domains, determinants, endpoint values and cross
identities. All source weights are checked, and owners validate the exact source
and full native support. Binding checks reject changed sources, span indices,
domains or homogeneous coefficients before consumption.

Proof issuance succeeds only if both surfaces of every retained chart pair have
two such independent coordinates. A minimum other-axis coefficient slice chooses
the candidate; a candidate outside affine representation or a failed identity
returns nil. This is limited eligibility, not a claim that other charts cannot be
injective. No root search is introduced. Once admission starts, work/storage and
cancellation failures propagate, without retry through the graph. Every normal
prepare decline checks current-task cancellation immediately before returning nil,
including empty inventory and a candidate map rejected after its final work callback.

On any selected four-UV cell within a proved pair, equality of XYZ implies equality
of both source UV tuples. Its image map is therefore injective and its dimension
is exactly the original cell dimension, with zero fiber dimension. Every selected
cell receives one complete image stratum; its ordinal is representation-local.
Different owners' UV preimages are retained even if XYZ images overlap. Exact
membership evaluates the retained original H/W and original cell condition.
Rational station subdomains reuse the same full-native proof. Noninjective or
collapsed maps retain the existing seven-coordinate graph path.

## State, Ownership, and Lifecycle
All proof fields are immutable Sendable values. The proof strongly retains the
original chart array and coefficient owners; public relation receipts retain this
proof, and fiber receipts retain their parent. There is no shared mutable state
or target-specific ownership. Arrays, owner/header strides and exact arithmetic
are admitted before allocation by the same cumulative ledger.

## Failure, Concurrency, and Constraints
Unsupported proof representation yields nil before publication selection.
Foreign binding, resource exhaustion and cancellation throw atomically. Existing
source/span/cell/depth/component limits and representative requirements remain.
Only positive common coverage can choose this proof; single-positive and all
zero-dimensional mathematical paths are unchanged.

## Verification and Change Impact
[NativeSurfaceChartInjectionTests](../../../Tests/CADGeometryTests/NativeSurfaceChartInjectionTests.swift)
checks weighted and reversed maps, exact closed endpoint recovery, degeneracy,
nonseparable/noninjective maps, foreign law/domain rejection, retained source
lifetime and independent work/storage/cancellation. Existing seven public multi-chart
SSI methods exercise complete joins, all UVs, mixtures, fibers and public failure.
The extra retained optional proof reference changes receipt storage accounting;
existing retained-fiber lifetime and independent-storage/final-cancellation methods
must be rechecked. Parent dispatch contracts remain unchanged.

## Direct Execution Admission

Source arithmetic borrows `A: ExactScalarAdmission & ~Copyable`; composed query
operations borrow `inout OriginalQueryExecution`. Source validation, native span
validation, structural comparisons and exact refinement receive that same admission.
The [execution owner](../OriginalQueryExecution/DESIGN.md) defines cumulative
work and actual byte accounting, independent depth axes, cancellation and lexical
proof scopes. Retained geometry and relation evidence stay immutable; no callback
adapter, copied counter or second allowance supplies arithmetic authority.
