# Original Face Boundary Clipping

## Purpose and Scope
Parent: [CADKernel](../DESIGN.md). No children. Own the immutable original face boundary issuer and the public face-bound Native parameter clipping entry. This component does not modify the face, infer pcurves, sew geometry or publish unrefined geometric overlaps.

## Responsibilities and Boundaries
A validated original model, FaceID and retained Native CS/SSI receipt determine the current source. The issuer proves the face's support equals the selected raw original source under the caller ledger, checks its original native domains, retains every loop/coedge identity and role, and forwards authored directed pcurves unchanged. Geometry owns exact laws, full parameter refinement and raw-cell correspondence.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Topology](../../CADTopology/DESIGN.md) | depends on | Immutable validated face/loop/coedge graph | Original IDs and outer/inner roles are authority | Authored pcurves already express coedge traversal |
| [OriginalGeometryQuery](../OriginalGeometryQuery/DESIGN.md) | coordinates with | Original current face-local pcurve meaning | Uses the same original support and coedge identity | No endpoint projection/reconstruction fallback |
| [Geometry consumer](../../CADGeometry/OriginalBoundaryClipping/DESIGN.md) | depends on | Complete source-bound parameter clipping | Supplies exact cell/component result | Image/fiber strata are not refined by this parameter API |

## Architecture
```text
public Native raw receipt + validated model + FaceID
    -> original support and native-domain structural comparison
    -> retained loops/coedges/authored pcurves
    -> sealed Geometry boundary domain
    -> complete parameter clipping
    -> original face wrapper retaining model and topology IDs
```

## Contracts and Invariants
The selected face must exist in an exact/volumetric immutable model and its stored support must be the unchanged native B-spline source of the raw receipt's selected surface side. Every original degree, knot, control point, weight, periodic flag/origin and native domain is compared under the same caller work owner. Naming a matching surface side is insufficient. Missing edges, curves, vertices, loops or authored pcurves fail. All loops are retained; omitted inner loops cannot authorize success.

ConstantU/V, affine and authored polyline pcurves are forwarded in their original directed order. Outer and inner roles are forwarded from the original Loop. Coedge orientation remains metadata; it does not reverse an authored pcurve again. Exact closure and nondegenerate segments are checked by the Geometry issuer. Unsupported families are explicit failures, not reconstructed polygons. Strict/closed/boundary selection is an explicit query policy and never a modeling tolerance.

## Runtime Flows
The public entry prepares a boundary with the original caller admission, invokes the Geometry consumer, then retains a face-bound result. The same owners receive all work/storage/cell callbacks. Cancellation is checked after final callbacks before every success publication.

## State, Ownership, and Lifecycle
The result retains the immutable validated model, original face and loops, and the complete Geometry parameter receipt. No mutable state, cache, model edit or platform-specific isolation exists.

## Failure, Concurrency, and Constraints
Invalid/missing source binding, unissued pcurve charts, unclosed source loops, caller resource/depth refusal and cancellation remain failures. Periodic/pole, rational/implicit/nonrational boundaries and complete image/fiber clipping are incomplete requirement-4 work; the public result is named and documented as parameter clipping only.

## Verification and Change Impact
[OriginalFaceBoundaryClippingTests](../../../Tests/CADKernelTests/OriginalFaceBoundaryClippingTests.swift) owns direct public issuer/consumer behavior, original topology and raw-cell identity, lifetime, holes/orientation and all failure contracts. Parent integration owns whole source-family acceptance. The existing Q5 and Native proof suites are reused when their source/contract premise remains unchanged.
