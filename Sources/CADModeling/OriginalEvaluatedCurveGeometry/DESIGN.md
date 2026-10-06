# Original Evaluated Curve Geometry

## Purpose and Scope
Child of [CADModeling](../DESIGN.md), with no children. Owns the bounded immutable original-law receipt of an EvaluatedCurve. This receipt does not certify its display cache.

## Responsibilities and Boundaries
The receipt retains the original exact curve, native domain, directed finite selection interval, feature ID and source category. CADKernel owns complete current document/cache provenance and checks the queried output key against the original feature ID. When exactCurve is present, points are display metadata and never construction authority. When exactCurve is absent, the original points are the authored Euclidean segment-length clock polyline, preserving the existing public query contract; plane remains metadata.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADModeling](../DESIGN.md) | parent | EvaluatedCurve | Supplies immutable query source | Native DTO fields remain compatible |
| [OriginalGeometrySourceValidation](../../CADGeometry/OriginalGeometrySourceValidation/DESIGN.md) | depends on | bounded original validation | Pays actual source visits on caller callbacks | Typed lower gaps propagate |
| [OriginalGeometryQuery](../../CADKernel/OriginalGeometryQuery/DESIGN.md) | used by | original geometry receipt | Resolves current query identity | Display validation remains a separate operation |

## Architecture
```text
EvaluatedCurve original fields -> caller-bounded source validation -> immutable original receipt
exactCurve present: display points -> legacy display validation (independent)
exactCurve absent: authored adjacent points -> exact Euclidean clock -> original receipt
```

## Contracts and Invariants
Source/subdivision/algebra depth are distinct. Work callbacks use actual proof depth; raw source visits have depth zero. Optional storage callbacks receive bytes before owned allocations. No allowance is created or reset. Closed authored trim must lie in the original native domain, and periodic trim retains the legacy one-turn rule. Unbounded curves need original finite directed endpoint parameters; their full parameter sequence is checked without consulting display points. No rounded image control net is constructed.

## State, Ownership, and Lifecycle
The receipt is immutable Sendable with original copy-on-write source retention. There is no shared mutable state or asynchronous lifetime. Native Codable conformance of the legacy DTO is an explicit adapter; all targets retain identical common fields and Sendable contracts.

## Failure, Concurrency, and Constraints
Invalid domain, foreign feature identity, exhausted source depth and nonfinite/invalid directed parameters fail. An absent exactCurve selects the authored polyline law, not a fitted replacement. Adjacent authored segments are the whole source: no implicit last-to-first segment is appended, and the closed flag preserves the endpoint-distance condition without snapping endpoints. A join selects the preceding segment tangent. Original lower failures propagate.

## Verification and Change Impact
After source implementation, verify original curve/domain success with invalid display cache, authored nil-exact polyline with unequal segment lengths and preceding join tangent, invalid native trim, unbounded missing/foreign parameters, lowered work/storage/depth, cancellation and Native payload compatibility. Kernel composition additionally owns stale document/output identity tests. No behavior evidence exists from source alone.

A new exact Euclidean-clock issuer requires the public caller's explicit algebra
cap. Nil does not select a private intrinsic32 policy; the legacy numerical
candidate route remains separate. Custom nil-exact domain metadata retains the
legacy clamp-selector dependency and cannot yet publish a source receipt by
changing authored labels to canonical fractions.
