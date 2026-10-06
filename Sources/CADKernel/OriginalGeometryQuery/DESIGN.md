# Original Geometry Query

## Purpose and Scope
Child of [CADKernel](../DESIGN.md), with no children. Owns bounded original geometry and native parameter preparation for measurement queries.

## Responsibilities and Boundaries
Curve preparation admits original evaluated source under the caller's work/storage/depth contract. Native knot/span queries inspect original spline knots through parameter-preserving image families without constructing transformed control nets. Surface preparation resolves current stable topology and validates its original support; no construction surface replaces a retained procedural law. The invoking measurement owns complete current evaluation/source admission.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADKernel](../DESIGN.md) | parent | evaluated document | Supplies current source | No new encoding or query ceiling |
| [OriginalEvaluatedCurveGeometry](../../CADModeling/OriginalEvaluatedCurveGeometry/DESIGN.md) | depends on | original receipt | Excludes display caches from authority | Does not certify document freshness |
| [StableTopologyReference](../../CADModeling/StableTopologyReference/DESIGN.md) | depends on | paid current identity resolution | Supports direct and lineage references | Unported signature comparisons remain explicit failures |
| [OriginalGeometrySourceValidation](../../CADGeometry/OriginalGeometrySourceValidation/DESIGN.md) | depends on | same callback source validation | Preserves original laws | Algebra and source/subdivision limits stay independent |

## Architecture
```text
Selection + current evaluation -> original source receipt -> native knot/span -> measurement same ledger
Stable face -> original surface source validation -> native knot/span -> same-ledger face bounds
```

## Contracts and Invariants
Raw scans and identity lookups pay depth-zero work. Image traversal pays each source visit and enforces remaining source depth. Native span ordinals preserve the existing positive-span threshold. Algebra capability is retained from the original source unless the caller explicitly supplies a separate cap. Bytes and work are never copied into a new private budget. Missing original law or unsupported chart correspondence is a typed failure.

## Failure, Concurrency, and Constraints
All values are immutable Sendable; callbacks belong to the caller's synchronized ledger. No mutable counter is stored in these providers. Cancellation is observed between source/parameter visits. Failed preparation publishes no partial receipt.

## Verification and Change Impact
Verify lowered caller budgets encompass resolve and parameter scans, image knot/span preservation, foreign feature keys, stable direct/lineage resolution, exact periodic/unbounded intervals, failure and cancellation. Native/WASM/Embedded verification belongs to the later phase. No source-only change claims runtime closure.

Original trim preparation retains the current face-local coedge pcurve directly. It validates original support/chart descendants and native source IDs on the same callbacks, without the legacy endpoint projection or seventeen-point generated polyline. The receipt is a selection-law receipt, not a complete B-rep correspondence certificate; the enclosing distance invocation owns complete model admission. A missing original pcurve fails explicitly. Native trim-span bounds retain original B-spline knot endpoints and domain; converting those exact native values into normalized traversal endpoints is a separate lower law contract, never a rounded source replacement.

Original edge preparation resolves current stable identity on the same callback,
validates the retained source curve and authored trim, then retains the original
native interval. Edge parameter measurements consume that original curve at a
singleton authored native station, without evaluating a point midpoint or tangent.
`contains(parameter:tolerance:)` preserves the existing EdgeParameterRange admission.
Untrimmed direct linear endpoint projections use original binary coefficients and
exact rational arithmetic; only exactly represented native stations are published.
General nonrepresentable projected endpoints or image-linear source laws require a
retained exact endpoint carrier and remain explicit lower gaps, not rounded intervals.


Original plane-derivative curve and surface families retain their correction law
through the generic original closest/directional query producer. Construction
control nets do not become native control-point, knot, span or center authority.

Original drafted curves and ruled supports retain the original drafted section
law in generic closest/directional queries. Construction spline nets remain
candidates and do not grant native control, knot, span or conic-center selection.

Original angular transport laws use the generic original closest/directional
producer. A nonlinear angular transport does not inherit primitive-center or
construction-native control/knot/span shortcuts.

Original guide traversal chains retain their actual source/native normalized law
through general closest/directional queries; no construction control net or
primitive-center shortcuts are asserted.

Original guide endpoint connectors retain their corrected guide source law in
general original queries, without native control/knot/span or center shortcuts.

Current generated-edge lookup is a separate authority from historical stable
signature resolution. It requires the current index entry, matching lineage
output and a live source feature, then validates actual curve/trim/vertices on
the supplied admission. Its immutable receipt retains SubshapeID and the original
native interval; a closed circle does not need distinct signature endpoints.
Historical signature schema and validation remain unchanged. The invoking drawing
publication owns complete evaluated-model and occurrence freshness admission.

The package raw EdgeID preparation route composes the same original edge/trim
issuer with a caller that already owns complete current BRep source admission.
It does not fabricate a generated ID or historical lineage. It retains actual
curve ID, curve law and directed native endpoints; external current/generated
binding remains the caller's separate invariant.
