# Exact Surface Trim

## Purpose and Scope
Own admission and orientation normalization of authored finite surface trim loops. Parent: [CADModeling](../DESIGN.md). No children.

## Responsibilities and Boundaries
Geometry and Topology own original pcurve law enclosures and area integration. This component composes them into nonintersection, containment, orientation and positive removed-region decisions. Approximate polygons are candidate witnesses inside original boundary tubes, never independent source geometry.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADModeling](../DESIGN.md) | parent | finite authored trim validation | Normalizes accepted loops | Keep original parameter laws |
| [CADTopology](../../CADTopology/DESIGN.md) | depends on | CertifiedSurfaceParameterCurveEncloser and area integrator | Complete trim enclosure and integration | Unresolved bounds fail |
| [Parameter Image](../../CADGeometry/ParameterImage/DESIGN.md) | depends on | original image pcurve jets | Foreign chart original-law authority | No rounded rational materialization |

## Architecture
```text
original authored loops -> rational patches or certified original pcurve enclosures
    -> oriented boundary tubes -> nonintersection / containment / area bounds
        -> normalized original loops
```

## Contracts and Invariants
Original image, original affine operation word and original BSpline continuation pcurves use certified enclosure admission. A word image keeps the original native UV traversal and the retained target word; it is never materialized as a rounded rational patch. Their interval jets and retained source laws remain authoritative; candidate sampled or rounded control points cannot substitute a rational patch. Signed image chart orientation is evaluated in the target UV chart. Positive original region and a nonzero removed parameter region are required by this existing surface-trim contract.

## Failure, Concurrency, and Constraints
Existing subdivision depth 32 and 131,072 flat spans remain unchanged. Missing source laws, unresolved original bounds, selfintersections, invalid containment and exhausted budgets propagate typed failure. State is invocation-local and Sendable values are common across targets.

## Verification and Change Impact
Deferred behavior covers foreign signed-ratio and swapped charts, original spline continuation, reversed loops, holes, tangencies, invalid area and budget exhaustion. Recheck original enclosure and area consumers when pcurve laws change. Source changes do not establish behavioral verification.

## Canonical Geometry API Binding

Existing construction proposals retain their authored formulas. Original trim
membership and flattening require whole-source enclosure under the caller's
execution. The historical rational proposal for a plain harmonic pcurve does not
issue an original UV chord-tube receipt; that validation branch now refuses with
typed unsupported and an incomplete marker. The harmonic construction producer
remains available, but a rational proposal cannot authorize original trim
publication. This binding does not introduce a new harmonic winding proof or
complete that source family.
