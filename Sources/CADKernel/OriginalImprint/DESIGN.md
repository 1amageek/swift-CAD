# Original Imprint

## Purpose and Scope
Parent: [CADKernel](../DESIGN.md). Own tool/curve imprint preparation on original finite body faces. No children.

## Responsibilities and Boundaries
Body tools consume complete finite Boolean intersection and original coincident outlines. Curve tools retain original spatial law and native trim through support sweeping and finite clipping. Imprint topology publication belongs to BRepFaceImprinter; original intersection/classification authority belongs to lower Geometry/Topology producers.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADKernel](../DESIGN.md) | parent | imprint feature routes and topology publication | Immutable original body composition | Scratch sweep sheets never enter result source lineage. |
| [CADGeometry](../../CADGeometry/DESIGN.md) | depends on | PreparedCurveDifferentialEncloser original closed owning jets | Complete source sweep reach | Original hulls are position authority; samples are proposals only. |
| [Finite Face Containment](../FiniteFaceContainment/DESIGN.md) | depends on | original finite trims | Whole finite target admission | Preserve source native charts and lower failures. |

## Architecture
```text
original curve/native trim + original target body bounds
    -> whole original position enclosures -> finite sweep support
    -> complete target/tool events + coincident source outlines
    -> finite trim/visibility partition -> original curves/pcurves/parents
    -> face imprint -> exact topology publication
```

## Contracts and Invariants
Every sweep publishes a retained original `RuledSurface3D` with its two original affine-image rails and original native U interval. Analytic supporting-plane/cylinder proposals and rounded spline materializations cannot replace that original sweep law in finite intersections. Its four boundaries are original iso-parameter lifts; any lower analytic specialization must prove correspondence to the retained ruled support before using that proposal as intersection authority.
Sweep reach encloses every original source position and original target bounding coordinate, using outward arithmetic and the actual retained sweep direction norm. A narrow source excursion between stations cannot truncate the tool sheet. Original closed/singular classification governs closed-source splitting; close numerical endpoints do not prove a period. Coincident finite tools retain their source outlines and target boundary identity. Source native trim and every published target/source parent remain retained.

Partial occlusion and normal projection currently retain sampled candidate algorithms; they do not establish complete original visibility/station partitions. Their callable source markers keep E9 open until all visibility transitions, folds and face switches have original whole-interval certificates. Complete tool/target correspondence and global source accounting remain distinct lower contracts.

## State, Ownership, and Lifecycle
Scratch sweep supports, exact candidates and temporary BRep topology are invocation-local. The original body and curve sources remain retained; scratch sheet parents are removed at publication. Original curve preparation is immutable and reused for its complete reach enclosure. This uses existing Geometry convenience caps and claims no new aggregate feature-work ceiling.

## Failure, Concurrency, and Constraints
Missing sources, original source singularity, nonfinite enclosures, failed native bounds, unsupported original loci, exhausted historical lower policies and cancellation propagate. Source position/ray enclosures never enlarge modeling tolerance or replace a failed whole producer by samples.

## Verification and Change Impact
Deferred checks include source spikes between old sample stations, nested original images, closed periodic versus close open trims, partial occlusion narrower than prior sampling, coincident tools with holes, original source/target lineage and no scratch-sheet publication. E9 is incomplete until the visibility/normal source gaps close and behavioral checks run.

The closest-face projection adapter converts the retained SurfaceParameterBox into closed scalar ranges using the same lower and upper endpoints. It does not sample, round or narrow the original authored finite trim extent.

The canonical binding keeps the existing sweep, sampled visibility and normal candidate algorithms unchanged. One entry execution reaches original closed-jet preparation, finite bounds, exact clipping, source readers and publication. Quantitative local callbacks borrow that same execution; their presence never grants intersection authority. The mandatory ordinary-only pattern-placement and healing providers remain required-family gaps: their changed callable entries refuse with typed unsupported before producing partial output.
