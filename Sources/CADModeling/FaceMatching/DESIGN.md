# Face Matching

## Purpose and Scope
This component owns the Face Match production evaluator. Parent: [CADModeling](../DESIGN.md). No children.

## Responsibilities and Boundaries
It resolves original face selections and source placement, constructs supporting-surface replacements, selects the oriented landing branch and delegates simultaneous neighboring topology reconstruction and Grow to existing ports. Geometry owns complete original curve/surface events; no station grid authorizes a landing.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADModeling](../DESIGN.md) | parent | FeatureEvaluating | Match feature publication | Existing final exact/volumetric validation applies |
| [CADGeometry](../../CADGeometry/DESIGN.md) | depends on | CurveSurfaceIntersecting | Complete landing events | Continuous overlap and uncertainty must fail |
| [CADIR](../../CADIR/DESIGN.md) | depends on | FaceMatchFeature | Original face references and placement | Preserve source identities |
| [Face Offset](../FaceOffset/DESIGN.md) | depends on | Injected multi-face Push Face | Common parallel reach growth | Unequal reaches retain source replacement. |

## Architecture
```text
selected original faces + placed reference support -> replacements
    -> complete scoped line/support events -> oriented nearest landing
        -> joint neighboring face/edge/vertex reconstruction
            -> Grow port when applicable -> exact publication / lineage
```

## Contracts and Invariants
Parallel planar selections with one identical represented normal reach compose the injected multi-face Push Face port in one operation. All selected faces and their replacements are resolved first; unequal represented reaches retain simultaneous source replacement rather than being rounded to one common displacement. The Push Face child owns staged profile snapshots, growth and final lineage; this route does not authorize generic curved or differently directed Match Grow.
The front branch is selected from every certified original event in the requested finite line range, retaining the candidate's native UV point and residual. The source placement and normal orientation determine the front side. The existing range policy remains a construction constraint; it does not prove absence outside that range. Every final body must pass existing exact or volumetric validation. Fixed, Moving and None retain their existing ownership semantics.

## Failure, Concurrency, and Constraints
Missing references, no oriented event, continuous overlap, uncertain root isolation and exhausted original Geometry budgets fail explicitly. The previous finite reach remains unchanged. Multiple curved/inward Grow collision domains remain incomplete at their marked production branch until general reconstruction is connected.

## Verification and Change Impact
Deferred evidence covers curved multiple crossings, narrow event spacing, tangency, continuous overlap, placement orientation, cancellation and neighboring topology through the public feature path. Full E5 source closure additionally requires the marked general Grow domains; this component's scoped landing algorithm alone does not establish that closure.
