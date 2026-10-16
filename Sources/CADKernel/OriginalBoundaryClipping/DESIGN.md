# Original Face Boundary Clipping

## Purpose and Scope
Parent: [CADKernel](../DESIGN.md). No children. Own the immutable original face boundary issuer and public face-bound Native/issued-graph parameter clipping entries. This component does not modify the face, infer pcurves, sew geometry or publish unrefined geometric overlaps.

## Responsibilities and Boundaries
A validated original model, FaceID and retained Native or issued-graph CS/SSI receipt determine the selected source. The issuer verifies its original support/domain authority under the caller ledger, retains every loop/coedge identity and role, and forwards authored directed pcurves unchanged. Geometry owns exact laws, full parameter refinement and raw-cell correspondence.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Topology](../../CADTopology/DESIGN.md) | depends on | Immutable validated face/loop/coedge graph | Original IDs and outer/inner roles are authority | Authored pcurves already express coedge traversal |
| [OriginalGeometryQuery](../OriginalGeometryQuery/DESIGN.md) | coordinates with | Original current face-local pcurve meaning | Uses the same original support and coedge identity | No endpoint projection/reconstruction fallback |
| [Geometry consumer](../../CADGeometry/OriginalBoundaryClipping/DESIGN.md) | depends on | Complete source-bound parameter clipping | Supplies exact cell/component result | Image/fiber strata are not refined by this parameter API |

## Architecture
```text
public Native/issued-graph raw receipt + validated model + FaceID
    -> admitted original support/domain and exact structural comparison
    -> retained loops/coedges/authored pcurves
    -> sealed Geometry boundary domain
    -> complete parameter clipping
    -> original face wrapper retaining model and topology IDs
```

## Contracts and Invariants
The selected face must exist in an exact/volumetric immutable model and its stored support must be the unchanged native B-spline source of the raw receipt's selected surface side. Every original degree, knot, control point, weight, periodic flag/origin and native domain is compared under the same caller work owner. Naming a matching surface side is insufficient. Missing edges, curves, vertices, loops or authored pcurves fail. All loops are retained; omitted inner loops cannot authorize success.

ConstantU/V, affine and authored polyline pcurves are forwarded in their original directed order. Outer and inner roles are forwarded from the original Loop. Coedge orientation remains metadata; it does not reverse an authored pcurve again. Exact closure and nondegenerate segments are checked by the Geometry issuer. Unsupported families are explicit failures, not reconstructed polygons. Strict/closed/boundary selection is an explicit query policy and never a modeling tolerance.

## Runtime Flows
The public entry prepares a boundary with the original caller admission, invokes the Geometry consumer, then retains a face-bound result. The public protocol requires an inout OriginalQueryExecution. The issuer and Geometry consumer borrow that same canonical execution for every work/storage/cell admission; the removed OriginalRelationUsage is not retained as an adapter. Cancellation is checked after final callbacks before every success publication.

## State, Ownership, and Lifecycle
The result retains the immutable validated model, original face and loops, and the complete Geometry parameter receipt. No mutable state, cache, model edit or platform-specific isolation exists.

## Failure, Concurrency, and Constraints
Invalid/missing source binding, unissued pcurve charts, unclosed source loops, caller resource/depth refusal and cancellation remain failures. Periodic/pole, rational/implicit/nonrational boundaries and complete image/fiber clipping are incomplete requirement-4 work; the public result is named and documented as parameter clipping only.

## Verification and Change Impact
[OriginalFaceBoundaryClippingTests](../../../Tests/CADKernelTests/OriginalFaceBoundaryClippingTests.swift) owns direct public issuer/consumer behavior, original topology and raw-cell identity, lifetime, holes/orientation and all failure contracts. Parent integration owns whole source-family acceptance. The existing Q5 and Native proof suites are reused when their source/contract premise remains unchanged.

## M6 Exact Family Handoff

An additive public overload consumes the new complete Native L5 family boundary
source. The issuer validates the unchanged stored B-spline surface against the
selected complete DI cover and retains all original model, face, loop and coedge
owners. Authored pcurves remain in their exact lifted coordinates. Periodic
supports and constant/collapsed source maps use the supplied complete DI cover;
the issuer neither constructs a flattened native rectangle nor guesses lifts.
The Geometry exact consumer returns every raw/refined pair correspondence, and
the Kernel wrapper retains the original model and topology roles alongside it.
All validation and refinement borrow the same caller noncopyable admission.

[M6 public consumer fixtures](../../../Tests/OriginalDomainConsumerVerification/Sources/M6BoundaryFixtures/M6ExactBoundaryFixtures.swift)
build real exact-validated BRep faces and invoke the additive public overload.
They check both SSI roles, holes/nonconvex loops, open/closed selections, complete
empty regions, retained corners/lifted pcurves, supported collapse and owner
lifetime. An injected consumer returning another sealed domain is rejected.
Independent caller failures and cancellation at the final publication allocation
are checked on the same production path. The scoped verification target compiles
the complete actual Topology module and this Kernel component; it does not claim
whole CADKernel or Modeling acceptance.

The face issuer directly imports HashTreeCollections while consuming retained
Topology PersistentMap tables. Kernel declares that direct product dependency;
import visibility does not change face/source comparison or source ownership.
The actual validator's portable cancellation wiring is owned by
[Topology](../../CADTopology/DESIGN.md#m6-portable-validation-wiring).

## Issued graph boundary handoff

The additive issued-graph overload receives a sealed selected surface binding
alongside the complete retained relation. Geometry owns binding factories, source
owner/role checks, metered exact stored-support comparison and graph UV transport.
Kernel owns the validated model, selected face, every original loop/coedge and
the final face-bound result. Both paths use the same complete loop extraction;
authored pcurves are never reversed again or reconstructed when missing.

The Geometry consumer refines the retained lifted cells and preserves every
raw/refined ordinal and incident boundary span. Kernel checks that an injected
consumer returned the issued domain and requested policy before publication.
The original model and topology remain retained after source preparation ends.
The same caller admission covers issuance, comparison, refinement, result storage
and terminal cancellation. This is public parameter/material clipping; full
XYZ/image/fiber output is still M7. The three frozen Coons-hole policy cells own
this end-to-end connection and do not claim general-family completion.
