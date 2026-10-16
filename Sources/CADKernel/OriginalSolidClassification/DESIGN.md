# Original Solid Classification

## Purpose and Scope
Own original point-in-solid classification and immutable body-bound preparation. Parent: [CADKernel](../DESIGN.md). No children.

## Responsibilities and Boundaries
Compose original body bounds, authored finite face containment and complete original ray events. One borrowed OriginalQueryExecution owns cumulative work, storage and independent depth admission. Geometry owns original intersection/projection completeness; Topology owns finite trim predicates. This component does not use sampled absence to establish solid separation or boundary-only contact.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADKernel](../DESIGN.md) | parent | SolidPointClassifying | Shared Boolean/query original material classification | Source readiness is separate from behavioral evidence |
| [Original BRep Bounds](../OriginalBRepBounds/DESIGN.md) | depends on | original body/face bounds | Finite original ray admission | Forward the same caller work/depth allowance |
| [Finite Face Containment](../FiniteFaceContainment/DESIGN.md) | depends on | bounded prepared containment witness | Authored finite face membership | Threshold exclusion requires complete source coverage |
| [BRep Ray Classification](../BRepRayClassification/DESIGN.md) | depends on | complete original ray events | Original material crossing parity | Missing or unresolved events cannot authorize parity |

## Architecture
```text
point + original body + caller ledger
    -> immutable original bounds / trim preparation
    -> boundary admission / complete finite original ray events
    -> consistent material parity or typed failure
```

## Contracts and Invariants
`OriginalMaterialOverlapProving` consumes a graph produced for the same immutable exact source model and two solid bodies. A nonempty original implicit intersection cell whose whole original UV boxes lie strictly inside both finite trims supplies a positive intersection witness. Closed original first-jet hulls must additionally prove the two support normals nonparallel. Local regular material halfspaces then intersect in an open wedge, establishing positive solid overlap without a vertex sample or a finite collection of offset points. False means this positive proof was not established; it cannot classify boundary-only contact or absence. Tangency, coincidence and nonimplicit witness families retain their separate producers.

The `PreparedBooleanIntersectionGraph` entry consumes the factory-bound original model and graph together. It does not accept another model or repeat deep supporting geometry equality; the private producer binding supplies that exact source relationship. The raw graph compatibility entry retains its explicit supporting-value comparison and the corresponding accounting marker. Original graph preparation and all positive material decisions continue under the supplied caller allowance.

Prepared original support bounds are reused by source face identity inside one invocation. Whole finite trim classification reads original face/loop identity directly through the same exact source receipt and the receipt-bound Topology predicate; its borrowed original coedge view needs no copied curve buffer, patch reconstruction or duplicate endpoint admission. Caller work/depth/storage reach actual original preparations and interval queries. Retained support binding comparisons and lower interval temporary storage currently contain marked accounting gaps; this positive route must not establish whole query resource closure until those owners expose their paid receipts.
The direct classify and prepared-session operations are protocol requirements, preserving witness dispatch on Native, WASM and Embedded. Providers that lack direct original preparation fail explicitly; the component never silently replaces an injected provider or invokes its unaccounted legacy method. The same execution reaches each original body, shell, face, ray, event and nested lower producer. Existing body/face bounds have their independent local depth32 ceiling; the existing ray/trim search ceiling48 is not substituted for that bound ceiling. Source16 and algebra32 remain independent and intersect incoming limits. Diagnostic entry metadata never selects these policies. Prepared sessions retain the exact model, body-owned faces, original supports and tolerance; invocation-local construction owns all mutable dictionaries.

A boundary result requires an original finite-face containment witness. Material parity requires a complete ray event set. Conflicting complete ray results are a classification failure; numerical majority cannot resolve conflicting original evidence. Existing non-discrete ray handling may choose another original ray without publishing a partial event set. Common classification cases, equality and Sendable remain identical on every target; Codable is a Native adapter.

## State, Ownership, and Lifecycle
| State | All-target storage | Read entry | Mutation / release |
|---|---|---|---|
| Original model, bounds and face maps | Immutable Sendable prepared session | Classification requirement | Local construction, value-owner release |
| Caller owner and selected contributions | Immutable budget and contribution handles | Same-execution preparation and retained readers | Mutable ledger remains in OriginalQueryBudget Mutex |

Ordinary entries create one operation execution. Retained readers resume their
issuing budget and selected contribution handles; direct readers preflight the
attained independent depths before any paid reattachment. Payload construction
captures effective limits and preparation depth. No session stores a callback
adapter, raw mutable ledger or diagnostic-dependent numerical policy.

## Failure, Concurrency, and Constraints
Missing source, foreign body ownership, incomplete lower events/projections, conflicting material parity, invalid depth, resource exhaustion and cancellation propagate typed failure. Legacy convenience entries preserve their historical lower policy. General original trim reconstruction/validation accounting and unresolved lower join authority remain causal source gaps until their producer ports are complete; outer item charging is not their proof.

## Verification and Change Impact
After all source work, verify analytic/native/image/procedural solids, cavities, boundaries, finite holes, grazing rays, caller work/depth exhaustion, cancellation and injected provider failure. Recheck Boolean region selection and Q2/Q7 query publication after lower contract changes. No source-only snapshot establishes runtime completion.

The bounded immutable-receipt entry derives its model and tolerance directly from ValidatedBRepModel and requires exact or volumetric validation. It accepts no second model or tolerance requiring an uncharged equality traversal. The retained receipt establishes source admission only; actual classification, bounds and trim work remain in the same caller allowance. Lower trim-preparation validation accounting remains a separate producer dependency and is not erased by this entry.

The public immutable `PreparedSolidClassificationPair` derives both original sessions from one exact validation receipt and an injected classifier, preparing a repeated body only once. Its read-only first/second session access serves the caller's ordinary membership queries. The graph factory accepting this pair derives its source solely from the pair and retains the same owner; an interior witness never accepts unrelated sessions or a second model requiring deep equality. No extra numeric resource ceiling is introduced. Classifier lower byte admission remains a distinct marked dependency.

The positive `interiorWitness` route first requires a whole finite-trim transverse cell under the same original normal bounds as the wedge proof. The original SSI point and numerical normal samples propose an inward bisector station. Success requires that exact proposed finite point be classified `.inside` by both retained original sessions. An adaptive halving sequence is candidate search only; absence of an accepted station is inconclusive. All visits share the caller work/depth allowance, and every original prepared support/SSI/trim allocation forwards caller bytes. Numerical anchors, signs or a fixed offset set never prove material membership or absence.

The incoming execution selects storage accounting independently of work and depth. Every actual lower producer borrows that execution; observing upper retained-value requests cannot substitute for lower allocation admission. No callback adapter or producer-counter reset represents this owner.

Containment and identical-body witness search reuses each prepared session's original spatial-bound receipt through a non-generic protocol requirement. It intersects these finite search boxes and bisects candidate cells under the caller depth/work policy; candidates are numerical proposals only. A returned point requires both retained sessions to classify exactly that finite value inside. Exhausted candidate search or empty search box means no positive witness, never separation or boundary-only contact. The DFS frontier reserves typed byte capacity before allocation when bytes are selected. Existing classifier lower byte and combined source/search-depth dependencies remain explicit. Providers without original bounds expose no receipt and cannot substitute sampled extents.

Pair preparation forwards the same execution through both original sessions and prepares identical bodies once. Independent source16 and algebra32 local ceilings intersect incoming limits; spatial depth does not select either. Missing admitted curve-surface/projection producers remain explicit lower failures before resource publication.

Original graph overlap/interior witnesses forward the selected independent algebra cap through retained support preparations, source localization and unchanged-face trim predicates; the generated graph and sessions keep the same source owner. The incoming allocation policy remains unchanged throughout.
