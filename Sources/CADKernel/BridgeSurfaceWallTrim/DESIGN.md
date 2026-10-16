# Bridge Surface Wall Trim

## Purpose and Scope
The component implements the [CADModeling Bridge](../../CADModeling/BridgeSurface/DESIGN.md) finite-wall trim port. Parent: [CADKernel](../DESIGN.md). It has no children.

## Responsibilities and Boundaries
CADModeling owns bridge construction and continuity admission. This component owns finite BRep wall intersection, candidate region partition, source-boundary connection selection, exact sewing and original source lineage. It consumes wall face references, never the wall body's other faces as clipping authority.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADKernel](../DESIGN.md) | parent | composition | Default wall trimmer injection | Exact result required |
| [Bridge Surface](../../CADModeling/BridgeSurface/DESIGN.md) | used by | BridgeSurfaceWallTrimming | Candidate after continuity validation | Trimming must preserve source boundaries |
| [CADGeometry](../../CADGeometry/DESIGN.md) | depends on | original surface intersection | Spatial and native UV intersection | Retained OriginalImageSurface3D is the affine chart authority |

## Architecture
```text
candidate sheet + selected finite wall faces -> complete intersections
    -> wall-only UV splits -> keep/keep partition
        -> unique region connecting both original boundaries and declared walls
            -> sewing -> source-preserving publication
```

## Contracts and Invariants
Candidate edges on the lower and upper V boundaries inherit the original start and end boundary identities. Cut edges inherit their finite wall identity. The selected region must connect both original boundaries and every declared wall. None or multiple valid regions is a typed failure. Source bodies, material, orientation and original geometry remain retained. Unpublished candidate identities are collapsed into original input lineage before publication.

## Failure, Concurrency, and Constraints
Cancellation is checked between wall preparations. Original tolerance, arrangement limits and exact sewing checks are inherited. Placed walls retain OriginalImageSurface3D and AffineImageCurve3D source laws under their original native UV chart. Invocation-only sewn topology is merged only into the partition snapshot, with original wall face/edge/vertex identities mapped through sewn lineage; it is absent from the published body set. Singular affine maps and failed exact correspondence propagate failure.

## Verification and Change Impact
Deferred behavioral evidence includes curved finite walls, internal partition, boundary-coincident contact, holes, ambiguous alternatives, source retention, material, lineage and transformed walls. Recheck the bridge continuity consumer when resulting boundaries change. Recheck the retained affine chart producer and the construction wall authority when image semantics change.

An omitted wall resolves to the unique original incident face of the corresponding source boundary, with its actual retained source identity. Construction and trimming use the same owner rule; requested continuity, tension or width cannot turn an omitted wall into absence of clipping authority.

Each declared wall placement is applied to its resolved original finite face, including inferred incident walls. Reflections change the patch orientation consistently while retaining original native pcurve traversal and source parents. Two different placements of one source face remain distinct invocation faces; an omitted placement consumes the original face directly. Temporary topology IDs never become published source lineage.

Every placed wall retains its original surface through OriginalImageSurface3D,
including native B-spline walls. Its orientation follows the exact determinant
sign of the original stored affine columns, rather than a rounded triple product.
The construction and finite trim consumers therefore bind to the same original
placed support law.

The ordinary wall-trim entry creates one canonical execution and delegates to its direct witness. Stable wall resolution, complete intersections, arrangements, exact sewing and affine source/determinant readers borrow that same execution. The original region selection and source-parent rewrite are preserved. This binding supplies the required Model witness without adding a wall or arrangement family.
