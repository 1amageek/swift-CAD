# Exact Body Transform

## Purpose and Scope
Own original BRep body images for mirrors, pattern instances and selected topology motions. Parent: [CADModeling](../DESIGN.md). No children.

## Responsibilities and Boundaries
Geometry owns original spatial and UV image laws. CADIR owns atomic imported-source images. This component resolves actual target ownership, applies body images, carries subshape identity and publishes exact transformed BRep. Partial vertex displacement remains a distinct existing local reconstruction path; selecting every authored face admits the complete original body image path.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADModeling](../DESIGN.md) | parent | transform evaluators and pattern rebuilder | Public feature transformation | Keep source IDs and lineage |
| [Imported Source Translation](../../CADIR/ImportedSourceTranslation/DESIGN.md) | depends on | ImportedBRepSourceTransforming | Atomic original source model image | Singular maps fail |
| [Parameter Image](../../CADGeometry/ParameterImage/DESIGN.md) | depends on | original spatial image and pcurve binding | Preserve original support and chart laws | Nested original maps are not rounded composition |
| [CADTopology](../../CADTopology/DESIGN.md) | depends on | exact and volumetric BRep validation | Admit final topology | Source images cannot bypass validation |

## Architecture
```text
public motion/mirror/pattern -> actual source body and target ownership
    -> original curve/surface/pcurve images -> exact body replacement/sewing
        -> carried stable topology identity and lineage -> evaluation publication
```

## Contracts and Invariants
Whole-body topology motion requires explicit selection of every original face, not merely proximity or a coincident vertex set. A nonidentity whole-body motion is admitted from its original affine law even when every vertex lies on a fixed axis: unchanged pole vertices do not prove that original seam curves or charts were unchanged. Original images retain all native parameters, source IDs, topology incidence and authored pcurves. Exact original determinant sign governs reflected face orientation. Other source bodies and metadata remain retained. Every publication passes existing exact or volumetric validation and identity generation.

## Failure, Concurrency, and Constraints
Existing feature target limits, caller tolerances, original determinant expansion bounds and lower validation budgets remain unchanged. Cancellation and unresolved original laws propagate failure. Work and source copies are invocation-local; public protocol and Sendable contracts are common across targets.

## Verification and Change Impact
Deferred behavior covers parsed STEP/IGES analytic and NURBS bodies, geometry-bound pcurves, positive/negative affine images, repeated images, uniform/nonuniform scale, selected-face versus whole-body motion, reflection and source lineage. Recheck document fingerprints and source encoding whenever original image schemas change. Source implementation is not behavioral evidence.
