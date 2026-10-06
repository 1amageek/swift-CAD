# Imported Source Translation

## Purpose and Scope
Transform the authoritative imported exact B-rep source used by CADDocument.translatingSources and original body transformation consumers. Parent: [CADIR](../DESIGN.md). No children.

## Responsibilities and Boundaries
Own the atomic source-model image and all geometry-bound pcurve images. Preserve all topology IDs, native trims, solid-component ownership, source units and feature references. Invertible affine images retain original surface and pcurve laws; an exact negative determinant reverses face orientation while retaining chart traversal. Evaluation, source fingerprinting and history regeneration remain the document evaluator's responsibilities.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADIR](../DESIGN.md) | parent | CADDocument.translatingSources | Source graph translation | The edited graph, rather than an evaluated mesh, remains source authority. |
| [CADGeometry](../../CADGeometry/DESIGN.md) | depends on | RigidTransform3D and RigidImageSurfaceParameterCurve | Exact geometry and chart correspondence | Translation preserves native analytic frames; geometry-bound pcurves require a carrier image. |
| [CADTopology](../../CADTopology/DESIGN.md) | depends on | BRepModel exact validation | Topology incidence and geometry correspondence | IDs never change during source translation. |

## Architecture
```text
ImportedBRepFeature.model -> translated vertices / curves / surfaces
                        -> geometry-bound pcurve carriers
                        -> exact source validation -> replacement source feature
```

## Contracts and Invariants
An invertible affine source image keeps every exact spatial curve's original parameter domain and trim, retaining nested original affine curve and surface images. OriginalImageSurfaceParameterCurve binds every authored pcurve to its original support and target image; XYZ authority uses the original lift rather than an inverse-UV roundtrip. Original column determinant expansion determines orientation, and singular or unresolved maps fail. A translation keeps every exact spatial curve's original parameter domain and trim. Native parameter-only pcurves keep their values because translation preserves their surface frame. Bound implicit, analytic-projection, native parameter-only and prior image pcurves retain the entire original source carrier under the original affine image. Document translation delegates to this same original-source service with identity linear columns. Failure publishes neither a partially changed source nor a partially changed document.

## Runtime Flows
The caller copies the source document, translates each source operation, validates the translated imported source, then validates the entire document before returning it.

Independent shape translation consumes the original document DesignGraph for imported-body member admission, preserving actual feature selectors. Final document validation binds those same selectors to the translated imported feature sources; raw body identifiers never substitute for source graph authority.

## State, Ownership, and Lifecycle
All work occurs in a local BRepModel copy. The original imported source and caller document remain retained and unchanged. The new source owns translated geometry and any immutable retained correspondence carriers.

## Failure, Concurrency, and Constraints
Missing face/loop/surface references and invalid exact correspondence propagate as typed failures. No geometry is approximated, topology is reidentified, or tolerance is enlarged.

## Verification and Change Impact
Deferred source-phase verification must translate an actual parsed STEP/IGES source, reevaluate it, compare translated vertices and exact pcurve/spatial correspondence, retain stable IDs/source units, exercise geometry-bound pcurves, and reject a malformed mixed document atomically. Source implementation is not evidence that these checks ran.

World-space dependent placements are conjugated by translation: their linear map is retained and the translation column becomes `t + v - L(v)`. Rotation/scale origins move by `v`; explicit given Rebuild surfaces move with the original source. References and graph identities remain unchanged, so reevaluation regenerates geometry and lineage from the translated source graph.

Default sketch planes are promoted to an explicit translated Plane3D with their original native U direction, preserving all local coordinate expressions and constraints. Arbitrary translation never rotates or rewrites the sketch's authored coordinate system. Dependent Join, Extrude, Align and Wrap placements follow the same translation conjugation law as Boolean, Match, Imprint and Bridge placements.
