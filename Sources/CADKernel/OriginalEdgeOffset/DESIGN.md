# Original Edge Offset

## Purpose and Scope
Parent: [CADKernel](../DESIGN.md). Own directed selected-edge offset construction for EdgeOffset and FaceLoopOffset public feature routes. No children.

## Responsibilities and Boundaries
Retain selected original spatial curves, authored finite face supports, loop direction and source parents. Modeling owns the native planar offset whole-interval conversion certificate; Geometry owns original derivative enclosures. Natural joining owns retained endpoint-span continuation. Sewing and imprint publication remain kernel composition responsibilities.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADKernel](../DESIGN.md) | parent | feature evaluation and imprint | Atomic publication | Complete resulting topology must pass validation. |
| [Drafted Section](../../CADModeling/DraftedSection/DESIGN.md) | depends on | PlanarCurveOffsetApproximator | Original native offset position/tangent/curvature certificate | Candidate interpolation alone never admits an offset. |
| [Exact Face Pcurve](../../CADModeling/ExactFacePcurve/DESIGN.md) | depends on | whole original curve/support correspondence | Retains actual spatial offset with its authored face chart | Numeric projection is only a proposal. |
| [Natural Curve Join](../../CADModeling/NaturalCurveJoin/DESIGN.md) | depends on | original endpoint-span continuation | Directed natural gap closure | Does not establish the upstream distance law. |

## Architecture
```text
selected original directed edge + original finite face
    -> planar native offset candidate -> whole original offset certificate
    -> original face pcurve correspondence -> retained spatial curve + trim + parents
    -> complete chain joins -> face imprint -> exact topology publication
```

## Contracts and Invariants
A native B-spline on an authored plane uses the original plane normal and retained native trim. Candidate basis construction covers that original interval; whole original-law position, tangent and curvature admission precedes pcurve construction. The signed shift includes face orientation and source trim direction, preserving the face's left side. The returned spatial law is the certified candidate, with its own native trim; a surface lift does not replace it. Complete original pcurve bounds determine the finite projection envelope.

Other original planar curve families consume the original PreparedCurve-based PlanarOffsetCurveSource through CertifiedGeometryConverter over the retained native trim, after whole original source/support correspondence admission. Original position, tangent and curvature certificates govern every published candidate. On admitted planes, Round fillers retain a native Circle3D centered on the original corner, the requested radius, a directed shortest native angular interval, and a whole original face-pcurve correspondence. Endpoint projection proposes native angles and must satisfy the existing distance tolerance; projected sample chains never define the round law. Linear meeting proposals use the original directed endpoint derivatives, with robust nonzero tangent determinant admission, rather than finite differences. Both neighboring source parents and the corresponding endpoint ancestry survive filler publication. General surface metric offsets and whole nonlinear tangent/closest-join completeness remain explicit source gaps. Four projected displacement steps or sampled interpolation are not an original surface-distance certificate and cannot authorize their offset publication. Natural joins preserve the original endpoint law but do not promote a partial offset into a complete distance proof. The existing sixteen-gap reach factor remains the finite construction seed; complete original intersection isolation and directed crossing admission determine the join within that envelope, rather than asserting a global nearest crossing or expanding limits after failure.

## State, Ownership, and Lifecycle
Each invocation owns its source patch, candidate coefficients and resulting directed edges. Source topology and source parents remain immutable. No shared mutable preparation or target-specific synchronization exists.

## Failure, Concurrency, and Constraints
Original planar conversion retains its existing control/span/storage caps and requested tolerance. Source singularity, fold, whole correspondence failure, cancellation and exhausted conversion budgets propagate. Unsupported metric producers fail explicitly, without fitting or a changed offset distance.

## Verification and Change Impact
Deferred checks cover reversed native trims, both face orientations, rational planar curves, folded offsets, arbitrary finite holes, source parents and failed general surface metric proofs. Full E8 remains open until all mandatory metric families and complete gap laws have actual producers and behavioral evidence.

Offset-chain periodic subdivision is admitted only by BRepEdgeGeometryClassifier's original closed-law receipt. Numerically close endpoints do not prove a periodic traversal. The midpoint splits an already proved closed original law; a singular curve remains governed by the offset regularity producer and is not inferred from endpoint proximity.

The additive offset entry accepts one optional `GeometryConversionAdmission` from its composing invocation and forwards that identical immutable admission through all original planar offset basis/candidate certificates. Supplied admission uses the original Curve3D and retained directed trim, never a converted candidate as source; absence preserves historical per-proof behavior. This conversion port does not certify the complete copy/join/contact/imprint ledger; those lower dependencies remain explicit. Native endpoint continuation remains supported by its historical producer and requires its dedicated bounded endpoint admission before the selected bounded route may publish beyond native support.

`EdgeOffsetConversionLimits` is an additive public caller-selected policy: native span, source recursion, subdivision and algebraic depth are independent explicit selections; optional cumulative work/BYTES ceilings add no hidden defaults. Nil policy preserves legacy conversion behavior. The feature evaluator creates one `EdgeOffsetConversionInvocation` per evaluation and shares its `GeometryConversionAdmission` across every group and segment. Counters check overflow even when their optional ceiling is absent. The same admission reaches actual source-patch copy/provenance visits, original finite face bounds and original spatial-curve/support correspondence before candidate construction. Correspondence retains its historical depth32/cell65536 ceilings and tightens them by smaller caller selections. Source and algebra capabilities remain independent. Copy dictionary metadata, pcurve construction, chain joins and downstream imprint still need their producer admission; these connected phases do not issue a whole-feature bounded receipt.

| Logical state | Native / WASM / Embedded storage | Read / mutation | Release |
|---|---|---|---|
| Conversion work and bytes | Same immutable owner of `Mutex<State>` | Short arithmetic admission under `withLock`; no external callback or await under lock | Invocation owner release |
| Policy and source caps | Immutable Sendable value | Same scalar validation on all targets | Value lifetime |

Recheck selected cumulative exhaustion across multiple groups/segments, counter overflow, cancellation and independent concurrent invocations during deferred target verification. No target-specific raw-state branch is permitted.

Selected planar offset candidate pcurves consume the caller-admitted direct-plane native-spline builder. Complete raw candidate coefficients and original directed endpoints remain bound through the Geometry continuation carrier; its whole correspondence proof uses the same conversion admission. Candidate pcurve construction no longer invokes unmetered Boehm trim/reversal or the legacy correspondence facade. Chain joins, numeric endpoint proposal queries, metadata storage and imprint retain their separately tracked lower dependencies.

Selected candidate endpoint proposals prepare one retained NativeCurveConversionSource for the completed spatial candidate and reuse it for both original native singleton queries. The same live admission owns preparation and query work/BYTES. A finite numerical midpoint is admitted only when the complete original singleton position box lies within the requested distance of it; that representative never changes the stored curve or native endpoints. Failure to prove the original box radius propagates instead of invoking the legacy point evaluator.
