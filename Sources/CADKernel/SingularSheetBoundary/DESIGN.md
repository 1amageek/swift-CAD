# Singular Sheet Boundary

## Purpose and Scope
This component owns original Untrim sheet production and admission of geometrically closed and singular sewing boundaries. Parent: [CADKernel](../DESIGN.md). It has no children.

## Responsibilities and Boundaries
The topology classifier owns proof that an original curve span is open, closed, or singular. Sewing owns canonical endpoint identity, face-local singular uses, exact pcurves, and publication. Coincident coordinates alone never establish a closed or collapsed boundary.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADKernel](../DESIGN.md) | parent | feature evaluation | Untrim and exact sewing | Retain source lineage |
| [CADTopology](../../CADTopology/DESIGN.md) | depends on | BRepEdgeGeometryClassifier | Original-law singular and closed admission | An open edge cannot collapse |
| [CADModeling](../../CADModeling/DESIGN.md) | depends on | BRepSewingEdge | Exact boundary request validation | Nonzero parameter span remains required |

## Architecture
```text
Untrim surface domain -> exact iso pcurves -> original-law classification
    -> sewing endpoint unions -> face-local singular edges / paired seams
        -> exact BRep validation -> published sheet
```

## Contracts and Invariants
A proved singular or complete closed span has one canonical endpoint vertex. Singular parameter boundaries remain in the face loop and retain their own UV law; they are not merged merely because they map to the same spatial point. Physical manifold pairing excludes singular uses. Regular seams retain ordinary opposite-use pairing. Every source surface, face orientation, kept trim and lineage remains governed by existing Untrim contracts.

## Failure, Concurrency, and Constraints
Open spans whose endpoints collapse fail with topologyFailure. Cancellation, requested tolerance and existing sewing resource contracts remain unchanged. No singularity is inferred from distance alone.

## Verification and Change Impact
Deferred verification must exercise sphere poles, cone apex, full-period seams, reversed orientation and keepsEdges through Untrim, with exact validation and source lineage. Counterexamples include an ordinary tiny edge collapsed into one vertex and two different singular UV boundaries incorrectly paired. Recheck topology classification and correspondence whenever admission changes; source edits alone do not establish behavioral completion.

A native analytic cone has an unbounded signed generator coordinate. Untrim includes the exact apex coordinate v=0 while retaining the requested finite outward extent: a positive or negative truncated nappe expands to the apex. If the requested chart spans both signs, two patches in separate sheet shells meet at face-local singular apex uses; a chart with an interior singular line is not published as one regular face. Keeping original edges clips each authored boundary against every generated finite patch and retains original source lineage. Sphere native bounds include both exact poles.

Untrim resolves the declared target body and requires its selected face to belong to that body in the original snapshot. A live face from a different body cannot supply the surface or provenance. The original body is retained while all generated patches and kept trim lineage remain derived from the selected original face.

The unbounded or periodic face extent comes from CADTopology FaceParameterExtentResolver, using complete original pcurve enclosures and its unchanged 65,536-cell/relative-overhang contract. A fixed station sample cannot bound the source chart or authorize dropping a kept original trim. Rectangular domain bounds and singular native endpoints remain original Geometry authority.

Foreign original-image charts first map the complete original face extent to their source chart. Untrim constructs native bounded-domain, periodic, and cone-apex patches recursively, then retains every original lift through OriginalImageSurfaceParameterCurve. Signed gains and axis exchange determine UV loop direction; they do not substitute rounded foreign coordinates for original singularity. Model-space endpoints come from the retained lift's original spatial image, never an inverse-UV roundtrip. Nested images preserve this same structural binding at each layer.

Original affine operation word supports have unchanged native UV. Untrim recurses into the retained source support with the same full extent, constructs its native pole/apex/periodic patches, and wraps every original source lift with the identical target word. Word factors never become a rounded support or a foreign inverse chart, and the existing face orientation remains the target face authority.
