# Original Polynomial Curve-Surface Points

## Purpose and Scope

This component publishes every isolated original tuple of a finite, closed, aperiodic, single-span positive-weight Native rational curve against an original ruled surface issued by [OriginalRuledIntersectionSources](../OriginalRuledIntersectionSources/DESIGN.md). Its parent is [CADGeometry](../DESIGN.md); it has no children. This is the bounded SP.R.CS checkpoint, not complete procedural CS support.

## Responsibilities and Boundaries

The producer owns source preparation, exact requested/native domain intersection, complete selected-cell classification, and an immutable source/tuple receipt. It does not replace the ruled surface with a Native net. Existing algebra owns root search, exclusions, cell identity and incidence. The root-owned public dispatch and result carry this receipt; the shared exact point publisher owns representative refinement and classification from supplied raw homogeneous laws.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADGeometry](../DESIGN.md) | parent | Public rich/discrete dispatch | Carries the original point receipt through every public entry | Integration and parent index are root-owned |
| [OriginalRuledIntersectionSources](../OriginalRuledIntersectionSources/DESIGN.md) | depends on | Original ruled homogeneous law and guarded CS relation | Retains authored ruled and boundary source authority | Unchanged native U and linear V, no fitting |
| [IntersectionAlgebra](../IntersectionAlgebra/DESIGN.md) | depends on | Original rational cells, incidence and components | Proves complete parameter coverage and tuple identity | Same caller admission and inherited depth |
| [NativePointRelations](../CurveSurfaceOverlap/NativePointRelations/DESIGN.md) | coordinates with | NativeCurveSurfacePointAllowance, scalar localization and shared exact publication | Reuses the existing bounded representative algorithm | Source equality precedes numerical representative tolerances |

## Architecture

```text
original curve + original ruled source + options/caller
  -> same NativeCurveSurfacePointAllowance
  -> original native curve law + ruled polynomial receipt
  -> exact native/requested intersection
  -> raw XYZ zero laws + both nonzero denominator guards
  -> existing original cells / complete selected 0D check / incidence
  -> shared exact representative publisher
  -> immutable original sources + all cells + all exact tuples
  -> root-owned rich/discrete public result
```

## Contracts and Invariants

Coordinate order is original native curve T, original ruled U, original linear V. Default ranges are the original finite closed source ranges; explicit ranges intersect them exactly, including singleton boundaries. A disjoint intersection retains the original/native/requested domain arithmetic as complete exclusion evidence. Nonempty effective domains bind the retained original five-law relation and the complete cell partition. Both denominator guards and raw XYZ multiplicities remain original.

Every selected cell must be zero-dimensional before any point is published. Any positive-dimensional selected cell, including a mixed isolated/continuous relation, throws nonDiscreteIntersection atomically for both rich and discrete entries. Zero-dimensional points are retained individually even if their numerical images coincide or one T has several U/V preimages. Complete empty success requires either exact domain exclusion or a complete partition with no selected cells. Candidate count bounds every published tuple, not image clusters.

Each representative is certified by the existing Native publication algorithm against the original curve and supplied ruled homogeneous laws, with contained native/requested parameter representatives, exact scalar localization, original denominator proof, residual and source-position enclosure bounds. Tolerance controls numerical publication and contact-kind reporting only; it cannot alter exact equality or tuple identity.

## State, Ownership, and Lifecycle

The readonly receipt strongly retains original curve and ruled value, both original boundary polynomial owners, the unreduced guarded relation, complete partition/incidence, and parameter isolations/localizations. Handles retain their receipt and ordinal; foreign receipt access is rejected. Exact coordinates retain their original field owners and admission depth after caller inputs are mutated or released. All state is immutable Sendable; no cache or shared mutable ledger is introduced.

## Failure, Concurrency, and Constraints

One value-local Native allowance forwards the caller's work/storage admission through source preparation, root search, incidence, localization, representatives and final receipt/result allocation. Cell/coefficient visits retain the same cumulative count and maximum algebraic depth. Surface-to-boundary source descent requires positive remainingSourceDepth; each direct Native boundary requires no further structural descent. A single source product consumes one span and depth-zero subdivision admission. Source degree, candidate, refinement iteration, cancellation and allocation ceilings retain existing options/caller meanings. Every output/temporary buffer is charged and reserved before allocation; receipt heap metadata is charged separately. All failures propagate without partial result or fallback. Final admission is followed by cancellation checking.

## Verification and Change Impact

[OriginalPolynomialCurveSurfacePointTests](../../../Tests/CADGeometryTests/OriginalPolynomialCurveSurfacePointTests.swift) owns public ordinary/admitted rich/discrete isolated, multiple-UV, closed endpoint/singleton, complete-empty and nonDiscrete behavior, retained source/tuple lifetime and foreign owners, representative bounds, independent work/storage/source/algebraic depth/candidate failure and final cancellation. Root composes the stable component and shared publication/dispatch patch into the existing P warm full-module build path before focused execution. Changes to the issuer, algebra, localization or shared publisher require rechecking the corresponding assumptions; unchanged frozen SSI evidence is independent.
