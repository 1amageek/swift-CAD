# Document Drawing

## Purpose and Scope
Child of [SwiftCAD](../DESIGN.md), with no children. Publishes current-document
B-rep drawing geometry through public facade requirements. Complete D1/D3
visibility/material regions and D4 page/annotation composition are separate
source gaps until their algorithms are connected.

## Responsibilities and Boundaries
The facade admits a complete supplied current evaluated source and delegates
to the kernel BRepDrawingProjecting contract. Rupa owns DrawingProjectionPage,
ExportStyle, SavedViewProjection, annotation placement and user interaction.
CADExchange owns DXF/SVG/PDF serialization. No mesh-edge extraction or legacy
visibility fallback is used to implement the geometric drawing facade.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [SwiftCAD](../DESIGN.md) | parent | public document facade | Publishes drawing | Exact source binds evaluation |
| [BRepDrawing](../../CADKernel/BRepDrawing/DESIGN.md) | depends on | retained original projected uses | Owns topology and curve projection | Edge result does not classify visibility |
| [CADExchange](../../CADExchange/DESIGN.md) | used by | geometric result | Owns output formats | SI to output/page conversion occurs once |

## Architecture
```text
CADDocument + current EvaluatedDocument -> exact source equality
 -> BRepDrawingProjecting -> retained geometric projection -> drawing/export
```

## Contracts and Invariants
Source equality covers the complete document; a revision or ID match is
insufficient. The kernel owns fidelity and per-use limits. Errors and cancellation
propagate and the facade never substitutes a mesh drawing result.

## Verification and Change Impact
After all source implementation, exercise the public facade with current/stale
source, original curved/reversed/closed uses, resource refusal and cancellation.
D1/D3/D4 completion requires the connected full algorithms and real application
publication, not this geometry-only facade.

DocumentDrawingSectioner admits complete current source equality and delegates
original geometric plane sections to the BRepDrawing section protocol. Section
frame and original source IDs are retained; page scaling and material-region
assembly belong to subsequent drawing publication, not this source admission.

DocumentDrawingHatcher admits the complete current source and delegates the
retained original section to BRepDrawingHatching. Caller row, boundary, event and
output capacities remain explicit and are forwarded unchanged. Coordinates are
internal SI in the section frame; the facade does not apply page scale.

DocumentDrawingRegionProducer admits full current source before consuming the
section's original B-rep and exact cutting graph. It publishes original material
patch loops through the kernel arrangement contract. Caller boundary/region
capacities and source error semantics remain unchanged.

DocumentDrawingSilhouetteProducer admits complete source equality before original
trimmed silhouette extraction. It forwards explicit face/span/control/boundary
limits and the caller's shared usage without reset. Returned contacts, original
spans and coincident domains do not imply completed hidden-line classification.

The body-scoped section overload retains complete current source equality and
forwards authored original body IDs to the lower section requirement. It preserves
whole-model validation/source-face allowance while isolating original Boolean
targets, and provides a public composition path for placed body sections.

Placed section publication forwards the original occurrence/body affine placement
to the Kernel source/working-model composition. Explicit source-entity and
preparation-work allowances remain caller-owned; original evaluation is never
replaced by a transformed evaluated-document facade. The returned placement
authority is preserved for material-region/hatch export admission. OriginalImage
world-plane complete SSI remains a lower source prerequisite.

The original-cutting-support overload retains authored local plane and exact
original placement words. The supplied projection frame maps output only.
Work, bytes and three distinct source/subdivision/algebra depth capabilities
pass unchanged into Kernel; freshness remains complete current source equality.
Section original cutting UV is retained for downstream regions/hatch/pages and
never inferred from display frame. Lower general SSI/aggregate admission gaps
remain explicit until implemented and behaviorally verified.

The additive original-cutting hatch facade validates the complete current source
then forwards explicit preparation work/bytes and separate source/subdivision/
algebra depths to Kernel. Its returned original UV segments and preparation
receipt preserve the section identity; projection/output frame never replaces
cutting support. Kernel's remaining lower intersection/classifier aggregate
callback gaps propagate without a facade completion claim.

The additive placed silhouette facade forwards one original body/occurrence word
and explicit entity, face, span, control and boundary capacities to Kernel. The
original current evaluation remains source authority; an imaged model is an
invocation-local working source. The same SurfaceSilhouetteUsage owns extraction,
trim partition, projection and shared external accounting, without reset. No
foreground-depth visibility classification is inferred from these contours.

The projected-contact facade requires the current document/evaluation and
retained placed projection/silhouette packets, then forwards the SAME supplied
SurfaceSilhouetteUsage to the Kernel exact pair preparer. It publishes original
event endpoints/fibers and event-free source sectors, not hidden/visible labels.
Visibility requires complete trim/point/overlap and foreground depth coverage
after this preparation.
