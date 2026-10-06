# Original Field Scalar Root

## Purpose and Scope

Parent: [RationalBivariateAlgebra](../DESIGN.md). This child transports one retained
original ordered-field value into an exact rational univariate scalar endpoint.
It has no children. Curve source binders retain the original native constraint and
span; this child does not replace physical incidence or source membership.

## Responsibilities and Boundaries

The original value, original field tower relations and selected real embeddings
are authorities. Recursive norm/resultant descent produces a rational annihilator.
Exact source value signs and retained isolation select its actual scalar root.
No midpoint, fitted coefficient, new system solve or independent root selection
can replace the original value.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Intersection Algebra](../../IntersectionAlgebra/DESIGN.md) | used by | Rational norm of X minus an original field value | Binds original ordered coefficients | Norms preserve selected embeddings; coefficient isolation is separately owned |
| [Parent](../DESIGN.md) | parent | Original field polynomials, exact resultants and Sturm count | Descends original source relations | Norm zeros alone do not identify the selected real value |
| [OriginalRootSpan](../../OriginalRootSpan/DESIGN.md) | used by | Original scalar endpoint binding | Supplies exact native source constraints | An annihilator is not a physical curve contact proof |
| [CurveCurveContact](../../CurveCurveContact/DESIGN.md) | used by | Retained projected scalar source value | Publishes exact guide cuts | Work/storage and independent geometric/coefficient caps stay cumulative |

## Architecture

```text
original field value
 -> z - value
 -> clear ORIGINAL coefficient denominators
 -> remove denominator-pole conjugates without removing selected real embedding
 -> successive original defining-relation resultants
 -> Q[z] square-free law
 -> exact ORIGINAL value signs / retained narrowing / Sturm unique count
 -> retained exact scalar endpoint
```

## Contracts and Invariants

Each norm step preserves the original selected embedding. Saturation removes only
factors proved nonzero at the retained original root. The final polynomial is
verified to vanish at the ORIGINAL value before any scalar endpoint is issued.
Root count equals one on exact retained bounds with explicit endpoint exclusions.
`OriginalSingularFieldValueOrder.compare` returns the sign of first minus second
across unrelated immutable field owners. Verified disjoint bounds and rational
singletons decide directly; overlapping algebraic bounds bind each selected
original value to its existing rational norm law and use the existing endpoint
GCD/Sturm equality and order port. Its inout isolations retain the original values
and achieved causal depth. Endpoint bounds are verified against the original value
before replacing a retained enclosure.

Seeded transport maps original source operations from `context.depth` to the
retained `sourceDepth`, with only the remaining caller depth available. Source
isolation and rational endpoint operations already carry causal depth and pass
through without a second mapping. Coefficient visits preserve their independent
domain and cap; transporting parameter roots creates no coefficient-root visits.
Every phase checks cancellation and forwards paid work/storage to the same caller.
The legacy fresh initializer rejects inadmissible original depth domains before
any work, storage or root visit, then guards both caps throughout fresh isolation
with identity depth admission. Cancellation from the last paid callback is checked
before a scalar root or scalar order can be issued.
Every endpoint exclusion comparison advances the retained source-value isolation rather
than restarting its depth from the original context. Achieved source depth is preserved; coefficient-cell admission remains independent
from geometric scalar refinement. All typed coefficient/matrix buffers are paid
before allocation under the caller's live work/storage allowance.

## Failure, Concurrency, and Constraints

Cancellation, budget exhaustion, pole ambiguity and a zero annihilator propagate
explicitly. Failure publishes no scalar replacement. Mutable temporary buffers are
invocation-exclusive; retained original field owners are immutable Sendable values.

## Verification and Change Impact

[OriginalSingularFieldValueOrderTests](../../../../Tests/CADGeometryTests/OriginalSingularFieldValueOrderTests.swift)
owns scalar-order behavior: unrelated equal embeddings, opposite and distinct
values, retained causal depth with C0, independent depth/work/storage failure,
legacy coefficient-cap admission and final-callback cancellation. Near distinct
values succeed within parameter depth 32 and unchanged finite budgets. The tested
closer-than-Double input instead exhausts finite work explicitly and preserves its
original seeds; this is not evidence of successful order for that input.

Reducible defining laws, pole conjugates and multiple norm factors remain outside
this comparison verification. These tests do not establish whole S8 completion.
