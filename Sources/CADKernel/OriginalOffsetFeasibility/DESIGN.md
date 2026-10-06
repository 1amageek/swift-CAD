# Original Offset Feasibility

## Purpose and Scope
Parent: [CADKernel](../DESIGN.md). Own the concrete result-face contact adapter for Surface Offset and Thicken. No children.

## Responsibilities and Boundaries
Consume an exactly validated result body and enumerate every owned face self-product and unordered pair of distinct owned faces. Reuse the original geometry embedding session and finite-face trim/contact producer to reject material intersections other than declared shared topology. This adapter does not fit surfaces or substitute mesh collision tests.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADKernel](../DESIGN.md) | parent | default feature composition | Inject concrete offset feasibility | Same adapter for both feature routes |
| [Shared Sheet Offset](../../CADModeling/SharedSheetOffset/DESIGN.md) | used by | OffsetResultValidating | Admission before publication | Exact result topology is the premise |
| [Thickened Sheet](../../CADModeling/ThickenedSheet/DESIGN.md) | used by | joint layer publication | Admit caps and walls together | Lower model remains private until success |
| [Loft Finite Cap Contact](../LoftFiniteCapContact/DESIGN.md) | depends on | complete finite original face-pair contacts | Reuse original clip/contact authority | Distinct face groups only; failures propagate |
| [Original Surface Embedding](../../CADGeometry/OriginalSurfaceEmbedding/DESIGN.md) | depends on | immutable prepared self-query session | Shared original symmetric atlas | Consumer owns finite material trim, including holes |

## Architecture
```text
exact result body -> owned faces in stable order -> each unordered face pair
    -> original support intersection -> both finite trims including holes
        -> shared-edge/vertex contact admission -> publish or fail
```

## Contracts and Invariants
Every body face is visited exactly once in the outer traversal and every unordered distinct face pair is included. No bbox overlap heuristic or absence of sampled points authorizes disjointness. Intersections may coincide only with actual shared topology; coincident material regions and remote tangencies are failures. The original lower producer owns per-proof work, depth, cancellation and failure limits. `OffsetFeasibilityLimits` supplies optional caller-selected cumulative work and storage-byte ceilings. Absence preserves the original lower per-proof policies and is never a complete bounded receipt. A requested cumulative ceiling requires one result-scope admission propagated to every original graph, clipping, contact and allocation producer. Its original validation, same-face atlas and implicit finite-face cell phases now share that admission. Still-opaque shared-boundary and critical contact phases fail explicitly rather than invoking legacy contact work on the selected route. An outer pair counter cannot substitute for lower proof accounting. This adapter introduces no guessed feature-wide resource ceiling.

## Failure, Concurrency, and Constraints
All state is invocation-local. Missing ownership or original geometry fails explicitly. Unsupported, unresolved, cancellation and resource failures propagate without successful absence substitution. Same-face self-intersection across disjoint source charts, critical offset-sector splitting and full original intersection-family completeness remain explicit E1/E2 source gaps.

## Verification and Change Impact
Deferred verification covers remote upper/lower cap crossings, curved wall contacts, shared edges, hole walls and failures without replacement. Recheck the finite contact producer when its original component coverage or trim admission changes. No behavioral validation is claimed in the source phase.

## Same-Face Diagonal Exclusion
The [Original Surface Embedding](../../CADGeometry/OriginalSurfaceEmbedding/DESIGN.md) child owns the original symmetric product atlas, local contraction and immutable prepared self-query session. This consumer supplies actual face trim admission with holes and retains the exact result source receipt. Geometry remains independent of topology and publication; this component owns material-side contact rejection. Critical sectors, shared UV interfaces and distinct-face accounting remain the source gaps described below.

Native continuity admission consumes the Geometry-owned exact C0 issuer and keeps its immutable original source/tolerance receipt. `OffsetOriginalAlgebraAdmission` borrows the same invocation visit callback and optional byte callback; its storage count denotes UInt32 words and is checked before conversion to bytes. Every exact unit is charged to the shared owner, and algebra depth is checked independently. This receipt does not certify source C1, normal continuity, offset continuity, regularity or injectivity.

The additive receipt entry `validate(bodyID:validatedModel:)` derives original source and tolerance solely from the immutable exact/volumetric result receipt. Legacy raw admission remains compatible. `OffsetFeasibilityLimits` retains caller-overridable `SurfaceSurfaceIntersectionOptions` with its historical defaults, original source depth 16 (admitted 0...16), and independent algebra depth 32 (admitted 0...32). No cumulative work/byte ceiling is invented; the optional selected ceilings keep their prior semantics. Shared Sheet Offset retains its exact validation receipt once, and Thicken retains its existing volumetric validation as a receipt before this entry.

The result invocation owns one `Mutex`-protected checked work/storage accumulator on all targets. Optional storage selection is forwarded as an actual optional callback: absence never becomes a no-op bounded-byte witness. Original body component/shell/face visits, typed retained face capacity and ordering comparisons are admitted before execution. Each owned face retains one original self-pair preparation; its continuity witness and first-order hull use that preparation and the same independent capabilities. The symmetric atlas excludes a convex hull only after both continuity and contraction hold. Cross-pair graph cells use original parameter boxes and the exact result face's outer/hole trim predicates. A strictly disjoint parameter pair wholly inside material proves forbidden self-contact; outside material excludes only that original cell. Shared UV interfaces, straddling trims and non-graph critical/coincident contacts remain explicit unresolved failures until their original sector/exclusion producers exist. Distinct-face contact accounting remains a separate mandatory lower gap; successful self-atlas traversal does not certify that opaque phase's cumulative allowance.

Raw legacy entry obtains the existing exact validation receipt before result admission. A selected cumulative invocation instead uses the additive bounded original BRep receipt constructor under the same callbacks; no unmetered semantic validation is placed before its ledger. Receipt entry reuses the original immutable validation authority directly.

The additive generated-sheet composition entry receives `bodyID`, its actual immutable exact `ValidatedBRepModel`, and the existing `GeometryConversionAdmission`. Both result self-contact and unordered finite-face contacts borrow that same caller owner; local optional result ceilings may tighten it without resetting or replacing its allowance. Independent source, algebra and spatial capabilities are tightened only by this validator's existing producer policy. Each finite pair is prepared from the original validated model under actual graph callbacks. Original implicit graph cell boxes are classified against both finite outer/hole trims: one whole outside box excludes only that cell, while two whole inside boxes prove forbidden material contact. Boundary-straddling, declared shared-boundary, point and coincident cases remain unresolved until their complete original bounded clip/contact witnesses exist. This composition never routes selected admission through legacy contact validation.
