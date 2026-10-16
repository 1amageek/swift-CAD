# Shared Boundary Face Rebuild

## Purpose and Scope
Parent: [CADKernel](../DESIGN.md). This component owns publication of rebuilt faces having both free and shared boundaries. It has no children.

## Responsibilities and Boundaries
Existing Rebuild owns candidate fitting and original-source position certificates. This component retains exact native pcurves for free boundaries and publishes carried identity through the caller execution. Shared support replacement remains required and explicitly unavailable at the direct boundary until its producer is ported. A fitted surface is not authorized from point samples.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADKernel](../DESIGN.md) | parent | FaceRebuild evaluation | Source feature publication | Preserve original candidate receipts |
| [CADModeling](../../CADModeling/DESIGN.md) | depends on | FaceSurfaceReplacementRebuilder | Joint edges and vertices | Final exact correspondence required |
| [CADGeometry](../../CADGeometry/DESIGN.md) | depends on | surface lifts and source certification | Boundary transport | Native chart must remain unchanged |
| [Finite Face Containment](../FiniteFaceContainment/DESIGN.md) | depends on | prepared original-parameter containment | Known native-chart sample membership | Session must be prepared from the same face and original model |

## Architecture
```text
certified candidates + original face incidence -> complete native boundary proof
    -> retained native edges -> same-execution model validation + carried identity
    -> coarse free boundaries -> original surface lifts -> same-execution sewing
    -> mixed/shared replacement or unavailable fitting -> typed unsupported
```

## Contracts and Invariants
Shared edges are solved once against both final supports. Free boundaries retain their original native law on the new support and continue only by an admitted law to solved joint vertices. A transported vertex is fixed only if every incident face is selected and all transported positions agree. All other vertices remain owned by joint support solving. The exact final BRep controls success; unavailable continuation or incompatible supports remain typed failures.

Native-chart edge retention is authorized by the complete original directed spatial edge against its candidate-supported pcurve, with the existing quarter-distance acceptance. Coedge reversal is transported before certification; holes and seam uses are visited individually. A failed distance certificate selects joint reconstruction, while resource, cancellation and unsupported proof failures propagate. Discrete boundary stations do not authorize keeping an edge. A free boundary that must move is published as the exact lift of its retained directed pcurve on the admitted candidate support, rather than a fitted spatial surrogate. This applies to both coarse free faces and detached Square refit sides; shared edge reconciliation remains separately owned. Given-support native chart coverage is admitted by whole pcurve enclosures before this residual proof; a foreign chart proceeds through its explicit reparameterization path.

For `.given`, known-UV sampling is selected only when both original and candidate supports are native B-spline surfaces with complete original parameter-law equality, after charging both structural payloads. Degrees, knots, control points, weights, periodic flags and origins are compared; coordinate residuals and modeling tolerances do not authorize this identity. The original face's same-execution prepared containment session consumes the generated UV through its existing whole-loop predicate. Its point is still evaluated from that exact original surface at that UV. Missing parameter containment fails explicitly. Foreign charts and injected spatial sampling retain the existing point-containment path; no geometric depth allowance changes.

The shared sampler retains one station/offset traversal with explicit spatial or known-parameter membership. Its known-parameter entry is internal and used with a session prepared from the very same face/model before sampling. It does not infer session provenance from face-ID equality or reproject an already-owned parameter. Mandatory source validation, selected support/trim preparation, retained lifetime readmission and final model validation remain required.

## Verification and Change Impact
Deferred checks must cover a two-panel sheet with one shared boundary and curved free boundaries, mixed selected/unselected incident faces, coarse/native fitting, reversed orientation and failure without partial publication. Recheck offset consumers whenever the shared replacement boundary contract changes.

The candidate binding threads one execution through native boundary enclosures and quantitative fitting callbacks. The existing continuation polynomial and periodic source evaluator retain their original law; source and resource failures propagate before publication. This binding does not change candidate layouts, deviation thresholds or the existing boundary repair algorithm.

## Direct Evaluation Finding Repair
All available geometric source reads, bounds, original position certifiers, pcurve operations, sewing, model validation and carried identity are composed under the entry execution. Ordinary public entry creates that owner once; direct entry borrows it. Existing layouts, sample stations, quarter-distance retention and correspondence thresholds remain unchanged. Typed resource, cancellation and unsupported causes propagate.

Native-chart `.given` retains its live whole-boundary proof and final model validation. Branches that require ordinary-only support replacement, whole-support continuation, Square refitting or the general spatial trace fitter refuse explicitly before publication. These required-family gaps prevent whole Face Rebuild/U1 completion; no independent foundation is imported into the first G01 unit. Coarse free-boundary reconstruction remains the existing original surface lift, with the same pcurve and endpoint stations.

Verification must exercise native `.given` success under one owner, low-work/cancellation refusal and the required unsupported replacement/continuation/Square/shared-coarse boundaries. The finding repair is verified separately from first G01 public geometry runtime.

Focused owner tests: [FaceRebuildDirectExecutionTests](../../../Tests/CADKernelTests/FaceRebuildDirectExecutionTests.swift) covers native given-support topology retention, exact N/N-minus-one native request debits, cancellation and explicit Square-producer refusal. Shared replacement, whole-support continuation and shared coarse reconstruction remain unconverted required branches; their source refusal is not a completion certificate for those families.
