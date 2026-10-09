# Original Ruled Intersection Sources

## Purpose and Scope

This component prepares exact homogeneous laws for the existing `RuledSurface3D` whose two boundaries are direct, aperiodic, positive-weight Native B-splines with exactly one positive native knot span. It owns original source preparation and the CS/SSI equation adapters, not root search or public dispatch. Its parent is [CADGeometry](../DESIGN.md); it has no children.

## Responsibilities and Boundaries

The issuer retains the original ruled value and both original native polynomial receipts. U is the unchanged native parameter of **both** boundaries; V is the original linear fraction in [0,1]. It does not normalize individual curves, convert to a surface net, fit, cancel denominator factors, or infer contact from a sample. The existing relation resolver owns exact cells and incidence. Its empty result does not prove tolerance-contact absence.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADGeometry](../DESIGN.md) | parent | Original procedural source semantics | Owns shared enum and public dispatch | Parent integration is root-owned |
| [RationalBivariateAlgebra](../RationalBivariateAlgebra/DESIGN.md) | depends on | OriginalRationalCurvePolynomial, exact arithmetic, RationalAlgebraAdmitting | Preserves raw bits, native ownership and denominators | Storage is UInt32 words |
| [IntersectionAlgebra](../IntersectionAlgebra/DESIGN.md) | depends on | OriginalPolynomialRelation | Consumes original closed domains and predicates | Exact equality does not decide tolerance absence |

## Architecture

```text
raw ruled source + requested closed UV box + caller admission
  -> two selected original native curve polynomial receipts
  -> H=(1-V)*A*WB+V*B*WA, W=WA*WB
  -> retained homogeneous source/domain receipt
     -> CS (t,u,v) / SSI (u,v,s,t) equality + denominator guards
     -> existing original relation resolver (outside this component)
```

## Contracts and Invariants

The entire declared ruled U domain must lie exactly inside both native spans. The requested finite closed UV box, including singleton edges/corners, must lie exactly inside that U domain and V [0,1]; no tolerance enlargement or outward localization is used as membership. Source validation preserves the existing ruled positive-domain width rule and native validity. Positive original weights imply positive native W throughout each closed span. The unreduced product W is retained explicitly even if it is constant or cancels mathematically.

CS adapters retain their supplied curve polynomial and require finite exact target bounds inside its source span. SSI adapters retain their supplied native surface polynomial and its original domain. They produce three cross-multiplied XYZ equations and two distinct nonzero-denominator predicates. Variable order is CS (t,u,v) and SSI (u,v,s,t). Raw multiplicities and both denominator laws remain unchanged. No algebraic/root cell visit is needed during preparation.

## State, Ownership, and Lifecycle

Immutable Sendable receipts retain raw source values and exact polynomial backing after caller values are mutated or released. There is no new cache, mutable state or private allowance. The existing caller admits every source visit, exact arithmetic operation and typed temporary/output buffer before allocation. Bytes map by checked ceil(bytes/4) to the same UInt32-word storage owner. Surface-to-boundary descent needs positive remainingSourceDepth; flat native boundaries then consume zero further structural descent. Root and coefficient depth remain independent and unused here.

## Failure, Concurrency, and Constraints

Invalid coordinates/weights/domains propagate typed native errors. Unsupported boundary families, periodic sources and multiple positive spans fail with explicit unsupportedCapability and an INCOMPLETE marker identifying the public composition gap. Exact closed-domain violations fail invalidInput. Exhausted caller work/storage, cancellation and arithmetic overflow propagate atomically: no partial receipt or successful empty relation is published. Prior admitted work remains spent. Entry and final admission callbacks are followed by cancellation checks.

## Verification and Change Impact

[OriginalRuledIntersectionSourceTests](../../../Tests/CADGeometryTests/OriginalRuledIntersectionSourceTests.swift) owns exact varying-weight/nonunit-domain composition, boundary/singleton membership, immutable lifetime, CS/SSI ring equations and denominator predicates, native invalid and unsupported failures, independent source-depth/work/storage ceilings, and entry/final callback cancellation. Focused tests run against complete stable Native Core/Geometry, using the existing warm proof cache. Shared CS/SSI/public composition remains a root-owned integration checkpoint and is not counted as whole procedural or seven-domain acceptance.


## Planned Composition Consumer Migration

Status: design only; current implementation guarantees above remain unchanged.
Ruled intersection preparation will consume issued common-U laws and full finite covers; legacy boundary preparation remains authoritative until its replacement passes the public gate.
The [common consumer handoff](../OriginalSourceIssuance/DESIGN.md#composition-consumer-handoff-design)
owns coefficient transport, complete-cover, publication and migration acceptance.
