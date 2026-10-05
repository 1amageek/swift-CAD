# Prepared Boolean Operation

## Purpose and Scope
Own operation-independent intersection preparation, repeated Boolean evaluation, and complete section publication. Parent: [CADKernel](../DESIGN.md). No children.

## Responsibilities and Boundaries
The immutable preparation owns its complete exact input snapshot, operand identities, geometric tolerance, intersections and UV split graph. Evaluation owns material classification, region selection, sewing and history. It never accepts caller-replaced geometry under a previously prepared graph.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADKernel](../DESIGN.md) | parent | BooleanPipeline | Exact production materialization | Preparation is geometric; material classification remains operation-specific. |
| [CADModeling](../../CADModeling/DESIGN.md) | depends on | BRepBooleanEvaluating | Exact sewing and publication | No sampled replacement for exact intersections. |
| [CADCore](../../CADCore/DESIGN.md) | depends on | CurrentTaskCancellationChecking | Cancellation at ownership boundaries | Cancellation aborts before publishing a result. |

## Architecture
```text
Immutable source snapshot + explicit tolerance policy
    -> complete surface intersections -> trimmed UV split graph
        -> union / difference / intersection / slice
        -> section curves + tangent points + coincident faces
```

## Contracts and Invariants
- `PreparedBooleanIntersectionGraph` captures the complete original graph and the identical immutable source validation receipt at the producer factory. Its initializer is confined to that factory; it accepts no caller-replaced graph or second model. Body operand factories retain original body identities; explicit face-pair factories retain their authored FaceIDs with no fabricated body identities. Original material consumers derive their model and tolerance from this receipt, avoiding a second deep support/source equality traversal. Retained original graph cell constructors already bind the supporting source values used during production. This graph-only receipt does not assert UV splitting or material completeness, and no absent positive material witness authorizes separation.
- Carried unsplit face boundaries are subdivided at all original arranged-patch junction points that the original edge subdivider proves belong to their directed spans. This keeps an unsplit neighboring face's shared edge segmentation consistent with split faces at tangent boundary contacts; the original curve, pcurve, face orientation and lineage remain retained. Unsupported original point/span correspondence fails through the existing subdivider rather than inserting approximate sewing twins.
- Caller-admitted graph construction derives its model and tolerance directly from an immutable exact `ValidatedBRepModel`. It charges original operand, face, loop, coedge, contact and residual visits to the supplied work callback; original bounds and curve/surface intersections receive the same allowance and depth ceiling. Surface-pair retained storage is charged in bytes to the supplied storage callback. Already-proved source validation is reused without separately comparing or validating another model. Graph validation traverses actual entries under this same callback. This construction receipt does not cover UV splitting, coincident overlap classification, or material-side proof until their lower producers independently expose and consume the invocation admission.
- Tool-face original spatial bounds are prepared once per graph invocation. Caller-admitted support intersection caches use immutable source surface identities rather than recursively hashing retained geometry coefficients outside the source allowance. Reuse never supplies intersections from another source snapshot.
- Preparation computes the complete graph, bypassing operation-specific empty-intersection shortcuts.
- Every evaluation reuses the exact graph only with the captured model and exactly the prepared ordered operands and tolerance.
- Each configured pipeline retains one immutable preparation-owner identity.
  Value copies retain that identity; independently configured pipelines have
  distinct identities even when their source values compare equal. The public
  compatibility evaluation entry rejects a preparation from a foreign owner
  before material classification. Captured evaluation uses the original owner
  and its injected producer contracts; no runtime provider type discovery or
  guessed provider fingerprint substitutes for configuration ownership.
- Extra distance tolerance is explicit, finite and nonnegative; the original input is never changed.
- Serial preparation has deterministic face-pair/component ordering. Independent target preparations can run concurrently through the async API; results are merged in input order.
- Output section entries retain both source faces and component identity, including zero-dimensional contacts and coincident regions. Curve-only compatibility APIs may omit such entries, while this API does not.

## Runtime Flows
Preparation checks cancellation, validates inputs, constructs intersections and splits, then publishes the immutable preparation. Evaluation checks cancellation before materialization and before result publication. Exceptions preserve the operation's feature identity through the existing production boundary.

## State, Ownership, and Lifecycle
The preparation is a Sendable value with immutable stored state. BRepModel's persistent backing retains the captured source; caller mutations detach from it. No global cache, mutable shared state or unbounded retained history exists.

The preparation-owner reference contains no mutable state. Its lifetime belongs
to pipeline value copies and their immutable preparations, and reference identity
has the same meaning on Native, WASM and Embedded targets. Provider semantics
remain governed by their injected original-source contracts.

## Failure, Concurrency, and Constraints
Invalid policies or changed model/operand/tolerance bindings fail with typed invalidInput. Geometry, classification, sewing, resource and cancellation failures propagate. Preparation does not weaken geometric certificates or input domain admission. Parallelism is bounded by the explicit operand set; it never creates work proportional to tessellation samples.

## Verification and Change Impact
Deferred behavioral verification must compare prepared and direct union/cut/intersection/slice, prove graph reuse without a new intersection call, reject changed input bindings, preserve tangent/coincident section entries, and exercise concurrent evaluations and cancellation. These source changes do not claim those checks have run.

Concurrent preparation computes independent intersection graphs first; the complete graph is then split once under the global physical-curve contact registry so shared edge segmentation is operation-independent and deterministic.

`BodySectionCurveEvaluator.components` publishes every dimensional split, including point contacts and common finite-face regions, while its existing `sections` method is explicitly a curve-only projection of those semantics. Neither path accepts the Boolean evaluator empty-intersection shortcut.

The public face-pair preparation overload accepts original face IDs in one validated BRep snapshot, including incident faces of the same body. It computes every requested pair without a Boolean operation shortcut or body ownership duplication, validates the resulting graph, and preserves the same complete-contact registry used by UV splitting. Loft cap validation, wall trimming, and body distance classification consume this producer; neither unrelated faces nor fabricated temporary ownership participate.

Planar finite splitting sorts the complete boundary events along the exact support intersection line and tests every consecutive event-free interval against both authored trim domains. Separate intervals remain separate components, including holes; isolated valid events are retained as tangent contacts. The extreme events alone cannot authorize an interval across a hole or disconnected trim.

The plane-side classification adapter prepares invocation-owned sessions only for target solids and classifies the two tool-face sides of each finite intersection component through the existing original intersection sample and adaptive-clearance algorithm. It cannot demand material from the sheet used as a cutting tool. Coincident and tangent components carry no invented side samples; callers separately compose finite coincident source boundaries and material sectors.

Explicit coincident cap boundaries can use the same plane-sector adapter through immutable PlaneEdgeClassificationBoundary values. Each original edge owns a distinct component reference, a native cutting-plane pcurve, and actual target-body incidence. One target-session set serves the whole invocation; the original curve's midpoint and tangent feed the same inherited adaptive side classifier. Returned samples retain their distinct component identity for halfedge sector decisions.

Retained foreign curve parameters are never substituted by a rounded line law when recovering absent topology trims. Such curves require their original explicit native trim; complete intersection and correspondence producers consume the retained parameter image directly.

Preparation retains the requested source tolerance and explicit policy alongside its effective tolerance. Immutable diagnostics report actual prepared input/pair/contact/component counts and original producer residuals, never estimated performance or uncomputed contacts. Counts describe producer output, not material ownership completeness. No geometric glue assumption bypasses contact preparation. Diagnostics add no global state and cannot authorize a previously rejected operation.

The classification-pair face graph factory derives the immutable source directly from PreparedSolidClassificationPair, retaining the identical session owner for original interior-witness publication. It accepts no replacement model or sessions; the ordinary graph-only factory remains compatible and does not acquire a classification receipt by assertion.

Caller storage admission is optional independently of work/depth admission. An absent byte callback is forwarded as `nil` to every original Geometry producer and supplies no additional cumulative storage guarantee. A selected byte callback reaches actual lower preparations and queries; observing upper retained-value requests cannot substitute for lower physical allocation admission. Historical work/depth callers retain their policy without a no-op byte sink or producer-counter reset.

Caller-admitted UV split publication validation reads the same immutable source receipt and original intersection graph. Each candidate, duplicate-pair comparison, deterministic component ordinal and original residual/sample/trim visit is charged before use. Validation uses in-place scalar scans, creating no mapped ID/sample arrays or temporary sets. This validates the produced graph structure and retained residual contract; it does not substitute for actual lower clipping, correspondence, classification or sewing admission.

Selected graph and original material-witness entries retain caller algebra depth (default32) independently of source and subdivision. The same cap reaches original support preparation, finite trim predicates, SSI admission and numerical proposal localization. Bounds forward optional byte admission directly. Missing lower selected-cap witnesses remain explicit failures; no prepared graph acquires completeness from these scalar policy fields.

Boolean lineage publication consumes already-issued sewing provenance before any geometric compatibility search. Retained entries must bind the current feature/output identity and satisfy parent cardinality and canonical ordering. The unchanged-tool materialization producer binds its outputs to their immediate source subshape while keeping that exact topology reference in the original model. Equal IDs in arbitrary input/result snapshots do not issue this provenance. Compatibility matching applies only to outputs whose producer supplied no parent correspondence; its limited geometric families do not establish whole general face/subspan history.

`lineageAdmission` is an additive, optional live conversion admission for this history phase alone. The same owner pays original identity/provenance visits and requested typed buffers. Dictionary/canonicalization scratch and physical allocator retention remain separately incomplete; this argument does not acquire a Boolean preparation, classification, sewing, or physical allocator guarantee. When selected, an unresolved generated correspondence requires an actual bounded original-span/face producer and cannot delegate to the historical unmetered geometric compatibility branch. Historical callers keep their existing matching behavior and failure semantics.
