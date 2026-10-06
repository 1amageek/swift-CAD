# Shared Sheet Offset

## Purpose and Scope
Own simultaneous surface offset of every face in the selected face's sheet shell. Parent: [CADModeling](../DESIGN.md). No children.

## Responsibilities and Boundaries
Prepare all replacement supports and transported free-boundary laws from the immutable source before changing topology. Reuse FaceSurfaceReplacementRebuilder for joint surface intersections, shared vertex constraints and shared edge replacement. Other shells are independent ownership units and remain intact.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADModeling](../DESIGN.md) | parent | SurfaceOffsetFeatureEvaluator | Published exact sheet result | A selected face anchors its complete connected sheet shell. |
| [CADGeometry](../../CADGeometry/DESIGN.md) | depends on | OffsetSurface3D | Exact chart-preserving offset | Local regularity must hold throughout the source trim bounds. |
| [CADTopology](../../CADTopology/DESIGN.md) | depends on | BRepModel exact validation | Incidence, pcurve and vertex consistency | Input topology is retained only when the joint solution remains valid. |
| [Original Offset Feasibility](../../CADKernel/OriginalOffsetFeasibility/DESIGN.md) | used by | injected OffsetResultValidating witness | Complete original result contact composition | Selected caller admission cannot replay a legacy provider as a bounded witness. |

## Architecture
```text
Source shell -> all offset supports + boundary transports + shared vertex seeds
             -> simultaneous face replacement -> exact pcurve publication
             -> exact sheet validation -> carried identity/history
```

## Contracts and Invariants

Joint endpoint projection results supply their original u/v coordinates to boundary continuation. The projection result is not a parameter value; final lifted endpoint residual checks remain required.

Raw `Plane3D` offset retains its authored `uDirection` together with its original normal. Translation along the face normal changes only the origin; rebuilding a default plane basis would change the native UV law and invalidate retained coedge correspondence.
Every shared edge has one spatial curve and one canonical vertex pair, with independent pcurves on incident supports. Agreeing transported vertex images become exact known constraints; disagreeing images require the joint solver. Free curved boundaries keep their exact transported law. A failed joint solution is an explicit geometric/topology failure and never publishes individually detached faces.

## Failure, Concurrency, and Constraints
All state is local to evaluation. Prepared supports are validated before replacement. Curvature singularity, loss of support intersections, boundary inversion and invalid final incidence abort atomically. Global self-intersection splitting remains owned by the offset feasibility producer and must not be inferred from local regularity.

The injected `OffsetResultValidating` port owns finite result-face contact admission after exact topology validation and before publication. Both Surface Offset and Thicken use it: every unordered distinct result face pair must have only its declared shared edges/vertices in common. The public composition root injects the original finite trim producer. Legacy constructors with no injected validator retain an explicit incomplete global-feasibility branch; local regularity and volumetric closure alone do not close that guarantee. Same-face remote parameter contacts and offset-sector reconstruction remain separate original producer gaps.

## Verification and Change Impact
Deferred verification must cover tangent curved panels, planar corners, holes, multiple shells, shared vertices, boundary continuation and invalid joint solutions. The source phase does not claim these checks ran or claim global feasibility certification.

Spline boundary continuation retains `SurfaceParameterCurve.originalBSplineContinuation`, its original homogeneous endpoint law, oriented native interval and exact tolerance. Newton endpoint values construct a candidate interval; the retained law and full enclosure admission govern the resulting spatial lift and final exact correspondence. No interpolated spline substitutes for the source.

Joint endpoint continuation of an original image first obtains native endpoint proposals from the image's retained gain/offset/swap map, continues the active original directed source chart through NaturalCurveJoin, and rebuilds the identical original target-image binding. Numeric foreign UV proposals do not replace the spatial source law. An original affine operation word has unchanged native UV, so joint endpoint continuation operates directly on its retained source chart and rebuilds the identical target word binding. Directed offset-image continuation preserves forward versus pullback transport. The joint endpoint and final correspondence admissions still govern publication.

The additive `OffsetResultValidating.validate(bodyID:validatedModel:)` requirement consumes the producer's retained immutable exact or volumetric source receipt. Surface Offset constructs this receipt in place of its existing exact validation; Thicken retains its existing volumetric validation as a receipt. The default compatibility witness delegates to a legacy injected provider's original raw operation without asserting new bounded accounting. Kernel's concrete witness derives model and tolerance directly from the receipt; no separately supplied source equality grants authority.

The caller-admitted overload `validate(bodyID:validatedModel:admission:)` also accepts a generated sheet's actual sewn exact receipt and its existing `GeometryConversionAdmission`. It is a non-generic protocol requirement for Embedded existential callers. A conformer must implement original result traversal and contact proofs under that same admission; its default witness fails explicitly instead of invoking legacy validation outside the allowance. This port does not establish source completeness for critical/shared-boundary contact families whose lower original witnesses remain incomplete.
