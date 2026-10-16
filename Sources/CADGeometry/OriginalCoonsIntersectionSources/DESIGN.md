# Original Coons Intersection Sources

## Purpose and Scope

This component owns the shared original rational Coons position-cell issuer extracted from [Original Coons](../OriginalCoons/DESIGN.md), and its bounded CS/SSI source adapter. Its parent is [CADGeometry](../DESIGN.md), with no children. The initial intersection checkpoint accepts four authored finite directed traversals of direct positive-weight, aperiodic, single-span Native B-splines. General procedural publication remains with the parent.

## Responsibilities and Boundaries

The existing boundary-piece producer supplies normalized original homogeneous curves; the existing source constructor owns exact corner incidence and C0 admission. This component combines those same four pieces and exact rational corner coordinates using the existing Coons formula. It owns no alternative Coons construction, fit, tensor conversion, corner interval authority or root solver. The differential atlas consumes the same position cells and preserves its existing derivative numerators, own-axis factor stripping and normal proof. An intersection receipt is not an embedding certificate.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADGeometry](../DESIGN.md) | parent | Procedural source dispatch | Owns public composition | Parent index/public changes are root-owned |
| [Original Coons](../OriginalCoons/DESIGN.md) | depends on / used by | OriginalCoonsSurface3D and OriginalSplineTraversalPolynomialPiece | Retains exact corners, directed piece laws and differential consumers | Cached interval corners never become polynomial coefficients |
| [Source Issuance](../OriginalSourceIssuance/DESIGN.md#retained-coons-atlas-lift-hosts) | used by | Shared complete position atlas | Supplies retained Coons lift hosts | Does not widen the bounded CS/SSI adapter or prove embedding |
| [Original Root Span](../OriginalRootSpan/DESIGN.md) | depends on | Immutable authored traversal and independent caps | Binds native source and directed endpoints | No root reconstruction or parameter midpoint |
| [Original Ruled Intersection Sources](../OriginalRuledIntersectionSources/DESIGN.md) | depends on | Existing homogeneous relation ring adapter | Reuses XYZ cross-products and two denominator predicates | No duplicated relation solver |
| [IntersectionAlgebra](../IntersectionAlgebra/DESIGN.md) | depends on | OriginalPolynomialRelation | Consumes exact domains and predicates | Empty equality cannot exclude tolerance contact |

## Architecture

```text
original Coons + four retained directed traversals + caller allowance
  -> existing exact normalized boundary pieces and original corner coordinates
  -> shared unchanged Coons position formula on exact common cells
     -> differential atlas: existing tangent stripping and normal proof
     -> bounded original source/domain receipt
        -> existing CS(t,u,v) / SSI(u,v,s,t) relation equation adapter
```

## Contracts and Invariants

Position is `(1-v)bottom(u)+v*top(u)+(1-u)left(v)+u*right(v)-bilinearCorners(u,v)`. The original sequential denominator multiplication and unreduced numerator/weight laws are retained, with explicit W!=0. General shared preparation preserves the old atlas support gate and exact positive common-cell cover, including rational image/parameter/native partitions. Bounded intersection admission narrows its input to the four direct single-span sources and retains their source, actual native index and exact native parameter map `t=start+(end-start)*q`. Reversal changes that original directed map; it never reverses or refits a native net.

The requested normalized U/V closed rectangle, including singleton boundary/corner domains, must lie exactly inside [0,1]². Whole native directed endpoint containment is exact. The immutable source's certification tolerance must match the caller. The complete source and exact common cell remain attached to each relation, including its target polynomial receipt and all three XYZ equations plus both denominator guards.

## State, Ownership, and Lifecycle

All retained receipts are immutable Sendable values. They retain original surface/traversals/native source buffers, exact normalized pieces, exact corners and homogeneous cells after caller values are released or mutated. No mutable cache or new allowance is introduced. Typed cell/polynomial/array metadata buffers are admitted before allocation through checked bytes-to-UInt32-word accounting, on the same caller ledger. The consuming Coons differential path likewise preadmits tangent, normal and generated stripped-polynomial capacities using their actual element stride. Existing exact arithmetic remains caller-paid. Shared source-cell visits retain depth zero from the old atlas; they are partition admission, not root isolation. The bounded surface-to-boundary descent requires remainingSourceDepth>=1, independently of subdivision/algebra permission. Direct Native boundary leaves use depth zero and retained capabilities. No source preparation reset, new coefficient field or root cell search is performed.

## Failure, Concurrency, and Constraints

Unsupported input families, algebraic endpoints, periodic sources and multiple native spans fail with typed unsupportedCapability and a callable INCOMPLETE marker; they are not successful empty receipts. Native validation, exact source/domain mismatch, work/word/cell exhaustion, overflow and cancellation propagate without publication. Final callback cancellation is checked before returning a receipt. Shared general atlas preparation keeps its existing optional non-applicability contract; no unsupported intersection success is inferred from it. Original allowances and embedding proof inequalities are unchanged.

## Verification and Change Impact

[OriginalCoonsIntersectionSourceTests](../../../Tests/CADGeometryTests/OriginalCoonsIntersectionSourceTests.swift) owns independent exact Coons equation expectations, reversed/nonunit/varying-weight Native maps, exact corners and closed singleton domains, released-source lifetime, CS/SSI denominator and ring binding, shared differential quotient regression, and work/storage/source-depth/cancellation failures. Focused Native compile/link/runtime uses complete Core/Geometry and the existing fixed warm proof path after one source review. Public CS/SSI, other procedural domains and whole seven-target acceptance remain separate integration responsibilities.


## Planned Composition Consumer Migration

Status: design only; current implementation guarantees above remain unchanged.
Coons intersection preparation will consume retained endpoint coefficients and selected local laws. The existing differential atlas remains on its current path until separately verified delegation.
The [common consumer handoff](../OriginalSourceIssuance/DESIGN.md#composition-consumer-handoff-design)
owns coefficient transport, complete-cover, publication and migration acceptance.


### Direct Shared Position Formula

`OriginalCoonsHomogeneousAtlas.prepared` borrows the original generic
`ExactScalarAdmission & ~Copyable`. It readmits the Coons constructor's attained
scalar proof before consuming retained source authority; the source binding owns
actual source-tree depth. The existing exact Coons formula, complete positive
common-cell cover and original denominator guards remain unchanged. Scalar cell
visits and checked typed buffer growth debit that same owner directly. The
intersection adapter's remaining migration is owned separately by the parent.

## Direct Execution Admission

Source arithmetic borrows `A: ExactScalarAdmission & ~Copyable`; composed query
operations borrow `inout OriginalQueryExecution`. Source validation, native span
validation, structural comparisons and exact refinement receive that same admission.
The [execution owner](../OriginalQueryExecution/DESIGN.md) defines cumulative
work and actual byte accounting, independent depth axes, cancellation and lexical
proof scopes. Retained geometry and relation evidence stay immutable; no callback
adapter, copied counter or second allowance supplies arithmetic authority.
