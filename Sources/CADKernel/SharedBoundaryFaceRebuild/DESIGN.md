# Shared Boundary Face Rebuild

## Purpose and Scope
Parent: [CADKernel](../DESIGN.md). This component owns publication of rebuilt faces having both free and shared boundaries. It has no children.

## Responsibilities and Boundaries
Existing Rebuild owns candidate fitting and original-source position certificates. This component supplies exact transported native pcurves for free boundaries, jointly resolves shared boundaries through CADModeling face replacement, and publishes carried identity. It does not authorize a fitted surface from point samples.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADKernel](../DESIGN.md) | parent | FaceRebuild evaluation | Source feature publication | Preserve original candidate receipts |
| [CADModeling](../../CADModeling/DESIGN.md) | depends on | FaceSurfaceReplacementRebuilder | Joint edges and vertices | Final exact correspondence required |
| [CADGeometry](../../CADGeometry/DESIGN.md) | depends on | surface lifts and source certification | Boundary transport | Native chart must remain unchanged |

## Architecture
```text
certified candidates + original face incidence -> free boundary native charts
    -> simultaneous replacement of every selected face
        -> shared spatial intersections + joint vertices
            -> exact pcurves -> exact/volumetric publication + carried history
```

## Contracts and Invariants
Shared edges are solved once against both final supports. Free boundaries retain their original native law on the new support and continue only by an admitted law to solved joint vertices. A transported vertex is fixed only if every incident face is selected and all transported positions agree. All other vertices remain owned by joint support solving. The exact final BRep controls success; unavailable continuation or incompatible supports remain typed failures.

Native-chart edge retention is authorized by the complete original directed spatial edge against its candidate-supported pcurve, with the existing quarter-distance acceptance. Coedge reversal is transported before certification; holes and seam uses are visited individually. A failed distance certificate selects joint reconstruction, while resource, cancellation and unsupported proof failures propagate. Discrete boundary stations do not authorize keeping an edge. A free boundary that must move is published as the exact lift of its retained directed pcurve on the admitted candidate support, rather than a fitted spatial surrogate. This applies to both coarse free faces and detached Square refit sides; shared edge reconciliation remains separately owned. Given-support native chart coverage is admitted by whole pcurve enclosures before this residual proof; a foreign chart proceeds through its explicit reparameterization path.

## Verification and Change Impact
Deferred checks must cover a two-panel sheet with one shared boundary and curved free boundaries, mixed selected/unselected incident faces, coarse/native fitting, reversed orientation and failure without partial publication. Recheck offset consumers whenever the shared replacement boundary contract changes.
