# GeometryConversionExchange

## Purpose and Scope
Owns explicit certified geometric representation conversion before STEP/IGES publication. Parent: [CADExchange](../DESIGN.md). No children.

## Responsibilities and Boundaries
Geometry owns the original curve/surface laws, candidate fitting and whole-domain position/tangent/curvature certification. Exchange owns caller policy, cumulative conversion/output resource accounting, original SurfaceID correspondence, standard coefficient publication and the returned guarantee. Original evaluated source and receipts are retained.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Geometry Conversion](../../CADGeometry/GeometryConversion/DESIGN.md) | depends on | GeometryConverting, native source and guarantees | actual bounded conversion | No sampled or inferred guarantee |
| [Preservation](../ExchangePreservation/DESIGN.md) | coordinates with | explicit source losses | result reporting | Geometric conversion does not authorize unrelated loss |

## Architecture
```text
Original source -> explicit exact/certified policy -> original-domain certified BSpline
                                             -> real STEP/IGES coefficient writer -> atomic publication + guarantee
```

## Contracts and Invariants
Exact is the default. Certified requirements come from the caller and include position, tangent and curvature ceilings and all lower allocation/work ceilings. Each finite original native parameter box is retained without UV remapping. The original SurfaceID and original source value identify each certificate. Conversion reservations reduce the actual writer's remaining allowance; neither nested conversion nor the writer receives a new budget. Original caller deadline is checked on every source point/enclosure operation and before publication. Failure leaves the downstream untouched. A certified conversion explicitly changes representation and reports geometry loss; all other losses still require the information policy.

## Failure, Concurrency, and Constraints
Invocation-local immutable plans contain certified surfaces. Unbounded domains are not silently clipped. Lower tolerance/resource/ambiguity failures propagate. Guarantees must satisfy all caller limits before a standard writer consumes the coefficient DTO.

## Verification and Change Impact
Actual public STEP/IGES output must retain original UV at authored parameter witnesses, satisfy the returned whole-domain guarantee, and round-trip under the requested physical precision. Tight tolerance, missing finite domain, cancellation, budget and downstream failures must preserve atomicity. Source implementation is not completion evidence.

Conversion also traverses original-image and signed-offset source dependencies; a rolling-ball or original-revolution basis cannot be hidden by a wrapper and accidentally routed to the exact unsupported branch. STEP assembly plans only the local definition geometry actually selected by its writer, rather than reporting conversions of unused instantiated global copies.

Original Coons and revolution source values follow the same explicit certified conversion policy as rolling-ball values: the original complete surface and chart reach NativeSurfaceConversionSource, the caller supplies all three tolerances and the cumulative allowance, and the returned actual spline and guarantee are published together. Exact default retains a marker until a standard producer preserves the original traversal law; a sampled or flattened surface never becomes an exact source value.

Original affine-word surfaces require conversion as a complete retained law, including normalized original factors and inverse operations. The certified candidate preserves the unchanged original UV chart. Parameter encoding therefore retains those original U/V coordinates; it never infers spatial length scaling from a rounded frame. Exact publication requires a proved standard carrier before this branch succeeds.

The additive writeConverting boundary publishes curve and surface receipts together. Each curve receipt retains the original CurveID, item or edge identity, complete original curve and directed start/end parameters. Legacy surface-only APIs refuse conversions that would require an unreportable curve receipt. Body fitting uses position allowance min(caller maximum, original document distance tolerance), leaves caller allocation/work caps unchanged, replaces clamped candidate endpoint controls with the actual directed original B-rep vertices and certifies the final modified curve for all three bounds. Surface conversion first retains the unchanged original UV chart. Each edge on a converted face is converted and its final candidate is directly certified against the lift on the final candidate face with that same original pcurve; a rectangular surface certificate alone does not prove incidence. Native unbounded edges without an authored directed trim require an original endpoint chart producer and retain an explicit incomplete branch.

Conversion callbacks borrow the [shared resource owner](../ExchangeResourceAccounting/DESIGN.md). The ledger creates one immutable GeometryConversionAdmission; every planner, source and final certificate receives copies of that same admission. Work, allocation and source preparation debit the same caller counts and original deadline; writer allowance is the remaining receipt, not a new conversion budget.

Final Body edge certification additionally requires the unchanged original hosted pcurve relation. Original B-rep admission may allow nonzero edge/lift residual; adding an independently certified edge approximation can exceed that boundary allowance. The writer therefore does not publish converted Body edges until final candidate-versus-every-hosted-lift certification consumes the exact directed native-to-coedge chart. The independent source route has no Body incidence premise.

Bounded surface conversion uses NativeSurfaceConversionSource(admission:) and CallerAdmittedGeometryConverting.approximateSurface(admission:). Actual source preparation, sample proposals, Greville fitting storage, elimination and final whole D0/D1/D2 certification debit the shared callbacks. Requirements remain local ceilings; the enclosing Exchange allowance charges actual consumption, without reserving a local maximum and replacing it with a hidden source budget.

Hosted Body certification constructs one paid NativeCurveConversionSource from each original face surface and coedge pcurve. Exchange's hosted chart computes f=(t-originalStart)/(originalEnd-originalStart), reversed precisely for reversed coedges, with original exact rational subtraction/division. Exact source-domain membership is proved before outward bounds are intersected with the original normalized [0,1]. D1 scales by the exact outward signed gain and D2 by its square. Candidate knot labels are unchanged. FINAL curve certification against each complete hosted lift uses the same admission and document distance allowance; the retained face/loop/coedge identity identifies every boundary certificate. Publication checks these immutable invocation receipts rather than accepting an edge-only guarantee.

Certified facade composition forwards the original ExchangeProcessingBudget value through STEP/IGES exact writers and STEP assembly output. The remaining scalar allowance does not restart time at the output stage. Backend table and source-ledger checks use that original deadline, and buffered publication checks it again before reaching the caller sink.

### Final converted-face incidence
Surface planning precedes curve planning. A converted face forces every boundary edge into the final curve plan; all adjacent faces then receive final hosted certificates for that shared edge, using their converted candidate surface if present and their original surface otherwise. Receipts retain the actual hosted surface and unchanged pcurve in addition to face/loop/coedge identity. Output compares that full relation against the surface it will actually emit. Closed native curves without explicit trim use their complete existing closed-domain contract; their directed selection is carried in the immutable curve plan, never written into the original B-rep. An unbounded or periodic nil-trim source has no inferred finite selection. Surface and final edge certificates share one admission and unchanged physical precision.

Original guide traversal chains retain exact root-span endpoint stations and
ordered owning pieces. Exchange dispatches their genuine Native conversion
source under the caller's three error requirements. An unresolved exact owning
cover or join regularity propagates its lower failure; rounded station cuts and
construction nets never replace the original chain during neutral publication.

Original guide endpoint connectors retain their guide RootSpan, both original section endpoint expressions and authored correction basis. The certified route consumes that complete corrected law under the same admission; the uncorrected guide or a construction spline cannot substitute for it. Exact neutral transport and drawing owning-cut admission remain governed by their actual lower producers.

Original Euclidean-clock polylines consume [Original Polyline](../../CADGeometry/OriginalPolyline/DESIGN.md) through the caller-admitted Native curve source. Adjacent original points, closure flag and exact owning stations remain the source law; neither a fitted spline nor a uniform per-segment clock substitutes for it. Exact neutral and legacy support-transfer selectors refuse an unavailable faithful clock producer. Conversion publication retains the original curve and complete directed certificate under the existing invocation. Owning-cut limitations propagate from Geometry instead of smoothing a corner silently.
