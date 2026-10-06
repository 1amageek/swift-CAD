# Face Drafting

## Purpose and Scope
Parent: [CADModeling](../DESIGN.md). Own FaceDraftFeatureEvaluator's original drafted supports and planar Grow wedge construction. No children.

## Responsibilities and Boundaries
Resolve every selected source face and its neutral hinge before changing topology. In-place support replacement remains the first route. If original planar walls need Grow, construct every selected wedge from the same immutable original body, then compose material operations with the injected sewer and Boolean applicator. Curved-hinge support production, joint support reconstruction and Boolean intersection completeness remain their respective lower contracts.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADModeling](../DESIGN.md) | parent | FaceDraftFeatureEvaluator | Public draft publication | Whole feature failures remain atomic. |
| [Polygon Prism](../PolygonPrism/DESIGN.md) | depends on | exact wedge prism request | Finite planar material tools | Retain original wedge geometry and existing tolerances. |
| [CADKernel](../../CADKernel/DESIGN.md) | depends on | injected BooleanOperationApplying | Exact material composition | No failed Boolean stage becomes success. |

## Architecture
```text
original selections + neutral hinges -> all replacement supports -> in-place rebuild
                                      -> all original planar Grow wedges
                                          -> additive tools -> subtractive tools
                                              -> one final feature publication
```

## Contracts and Invariants
All Grow wedges are prepared against the original context before any material composition. Selection ordering is deterministic by original FaceID; additive wedges precede subtractive wedges so a later additive tool cannot refill material removed by a drafted inward wall. A multi-face request cannot silently omit an unconstructible selected wall. Every tool stage uses the existing deterministic draftGrowWedge namespace and is discarded at final publication. Source faces, body identity, source ancestry and unselected bodies retain the composition contracts of FeatureEvaluationStages and BooleanOperationApplying. The one-face route is the same preparation/composition algorithm with one selected wall.

## State, Ownership, and Lifecycle
Immutable evaluator dependencies are shared safely. Replacement dictionaries, complete wedge lists, sewn tools and FeatureEvaluationStages belong to one invocation. Preparation failure leaves the original context unchanged; intermediate stage identities never escape final feature publication.

## Failure, Concurrency, and Constraints
Missing references, invalid hinges, exhausted original geometric producers, cancellation, sewing and Boolean failures propagate. Existing straight-edged-body, finite wedge and backing-thickness admission remain authoritative. Adjacent Moving selections with an additive wall need a coupled corner envelope: independent original finite prism spans cannot authorize the missing doubly-outward corner. The fallback rejects that case before any material stage. General curved-wall Grow, complete curved-body material envelopes and Moving pivot-interior cases remain explicit source gaps; multi-face planar composition alone does not close E3.

## Verification and Change Impact
Deferred behavioral evidence must cover two neighboring outward draft walls, mixed inward/outward walls, all Grow modes, tool identity removal, source ancestry, retained unrelated bodies and a selected wall whose original wedge cannot be constructed. Lower sewing/Boolean failure must leave no published prefix. Verification and commits remain the later task phase.
