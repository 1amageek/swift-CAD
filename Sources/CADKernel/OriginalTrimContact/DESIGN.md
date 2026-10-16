# Original Trim Contact

## Purpose and Scope
Parent: [CADKernel](../DESIGN.md). Owns finite original sewing-edge contact reduction for Boolean arrangements, Imprint and Natural offset joins. No children.

## Responsibilities and Boundaries
This component retains original spatial curve and authored directed trim while selecting structural, rational and original supporting-surface reductions. Geometry owns complete original roots and projection; Modeling owns whole curve-span coincidence. Returned numerical points are contact publication values, not replacement source laws.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADKernel](../DESIGN.md) | parent | ExactTrimEdgeIntersector | Finite arrangement contacts | Preserve whole trim coverage |
| [CADGeometry](../../CADGeometry/DESIGN.md) | depends on | original curve/surface roots | Complete isolated contact events | Endpoint and critical completeness remains required |
| [Original Curve Span Coincidence](../../CADModeling/OriginalCurveSpanCoincidence/DESIGN.md) | depends on | whole directed span match | Coincident contact admission | Projections alone never authorize coincidence |
| [Natural Curve Join](../../CADModeling/NaturalCurveJoin/DESIGN.md) | used by | continued original trim roots | Native offset joins | No sampled endpoint margin exclusion |

## Architecture
```text
original directed edges
    -> whole-span coincidence / structural component proof
    -> complete authored range and supporting chart reductions
    -> original roots + finite span admission
    -> contact points or typed failure
```

## Contracts and Invariants
An endpoint contact never authorizes dropping an adjacent parameter prefix. Sampling a first separated station does not prove that the skipped interval contains only that endpoint: another isolated crossing may lie inside it. Curve projection failure cannot become a separation witness. Both original curve and plane-chart search retain the complete authored range until an original event partition supplies an explicit covered exclusion receipt. Original construction chart curves retain their source law; their candidate knots/control net cannot become exact rational contact authority.

## State, Ownership, and Lifecycle
Search arrays are local to one invocation. Original immutable curves remain owned by input edges. Canonical direct entries forward one borrowed OriginalQueryExecution through the actual original coincidence, projection and contact producers. Ordinary operation entries create one execution; no nested call creates a replacement allowance. Existing local source, algebra and geometric ceilings remain independent.

## Failure, Concurrency, and Constraints
Endpoint/critical and continuous contact families require their actual complete lower producers. Those causal gaps remain marked at the production entry. Unresolved roots, singular charts, source admission, cancellation and resource failures propagate; they never become empty contacts. Complete same-caller projection and contact accounting remain required for bounded Boolean/fillet publication.

## Verification and Change Impact
Deferred behavior must include an endpoint contact followed by a distinct nearby polynomial crossing, tangency, coincidence, reversed trims, holes, original image/normalized chart curves, resource exhaustion and projection failure. Recheck Boolean UV arrangement, coincident overlap, Loft/fillet contact and Imprint callers. Source-only edits do not establish those behaviors.

Structural stations for additional original source families remain endpoint proposals for the existing whole-span/root paths. They do not supply complete enclosure authority. Exact-rational pcurve specialization returns nil for these source families so their retained source is never reinterpreted as an exact cached rational locus.

The harmonic-to-rational restriction branch refuses with unsupportedCapability: the existing constructive builder has no whole original harmonic/native-clock transport authority. A rounded rational conic image is not an original parameter proof. Retained other-support lookup accepts structural host identity under the same execution; lookup absence is capability absence and continues the other original reductions or explicit failure, never empty intersection.
