# Bounded Sewing Validation

## Purpose and Scope
Parent: [CADModeling](../DESIGN.md). Own caller-admitted validation of sewing face/loop/edge value invariants. No children.

## Responsibilities and Boundaries
Validate original support and pcurve source, stable provenance, ordered loop closure and original spatial/lift endpoint distance. Reuse one original support preparation per patch and one original curve preparation per edge. This component does not infer whole nonlinear curve/lift correspondence from endpoints; sewing's correspondence producer owns that independent invariant.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADModeling](../DESIGN.md) | parent | BRepSewingFacePatch additive validation | Modified patch admission | Legacy signatures remain |
| [Source Face Patch](../SourceFacePatch/DESIGN.md) | used by | immutable copied source values | Copy does not imply validation | Same callback owner covers both phases |
| [Sewing Provenance](../SewingProvenance/DESIGN.md) | coordinates with | canonical ancestry | Validate retained IDs | Work depth and bytes are distinct |
| [Original Geometry Source Validation](../../CADGeometry/OriginalGeometrySourceValidation/DESIGN.md) | depends on | bounded original source validation | Original support/curve/pcurve admission | Incomplete family producers propagate failure |
| [Finite Face Containment](../../CADKernel/FiniteFaceContainment/DESIGN.md) | used by | admitted patch premise | Modified finite trim input | Validation is not an immutable original-model receipt |

## Architecture
```text
patch + same caller work/optional bytes + independent capabilities
    -> original support preparation -> paid loop/edge/provenance traversal
        -> original curve endpoint boxes + original UV endpoint boxes
            -> original support position boxes -> ordered closure or failure
```

## Contracts and Invariants
Preserve one outer loop, distinct stable loop/edge identities, valid ancestry, nondegenerate directed trims, proved closed/singular admission for coincident endpoints, original domain containment and modeling-distance endpoint/closure checks. Original interval upper distance replaces a rounded source-point comparison as endpoint authority. Every source or identity visit is charged before comparison; stable-string equality pays original UTF-8 content. No arrays of loop keys or temporary points are synthesized. The support preparation is retained through all edge endpoint queries. Every curve preparation's owning singleton hull includes its original sides; a hull grants no continuity across joins. Spatial, source and algebra ceilings remain independent and unchanged under endpoint query composition. Optional byte absence is passed directly to lower producers and never represented by a no-op byte callback.

## State, Ownership, and Lifecycle
Preparations and scalar scratch are immutable invocation-local values. The composing caller owns counters and cancellation. Native/WASM/Embedded share the same Sendable callback contracts; this component creates no shared mutable state.

## Failure, Concurrency, and Constraints
Callback failure, cancellation, source validation failure and unresolved interval bounds propagate. No hidden cumulative ceiling is added. Existing per-producer caps remain. This validation establishes the legacy patch value invariants, not complete allocator accounting or whole curve/surface correspondence; source-family lower temporary/admission gaps remain explicit.

## Verification and Change Impact
Deferred tests cover original directed trims, pole/closed uses, loop gaps, invalid lineage, exact and transformed supports, original endpoint uncertainty, cancellation and independent capability exhaustion. Recheck the source copier, finite classifiers and sewer's whole-correspondence admission. Source edits provide no behavioral completion evidence.


Endpoint UV queries pass `support.surface`, the same retained original support
already used for edge relation validation and lifted position bounds. The UV
facade does not infer a host from samples or a replacement plane. Its work,
optional bytes and independent capabilities remain the sewing invocation
allowance.

Request-level body ancestry validity visits each original parent under the same
execution before reading its `isValid` predicate. The existing guard order and
short-circuit failure are unchanged; shell validation follows only after every
body parent passes. [CanonicalConstructionAdmissionTests](../../../Tests/CADModelingTests/CanonicalConstructionAdmissionTests.swift)
verifies parent-count work growth, the exact cumulative work ceiling and one
unit less, and cancellation during the parent scan on the actual request path.
