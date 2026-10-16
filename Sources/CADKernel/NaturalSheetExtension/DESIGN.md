# Natural Sheet Extension

## Purpose and Scope
Own Sheet Extend publication, original iso-parameter distance solves and finite rectangular support shortening. Parent: [CADKernel](../DESIGN.md). No children.

## Responsibilities and Boundaries
Keep the original surface as spatial authority. Determine exterior direction from the actual loop traversal and oriented surface normal. Convert physical extension distance into a surface-parameter reach and publish the exact four-side strip. B-spline continuation beyond its native support remains BSplineSurfaceBoundaryExtender's responsibility.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADKernel](../DESIGN.md) | parent | SheetExtendFeatureEvaluator | Exact natural strip composition | Existing sewing joins strips to the source sheet. |
| [CADGeometry](../../CADGeometry/DESIGN.md) | depends on | Surface3D differential geometry | Physical distance and exact chart support | Native finite domains remain authoritative. |

## Architecture
```text
Directed source iso-edge -> loop exterior -> distance/reach solve
                        -> same exact support + closed parameter rectangle -> sewing
```

## Contracts and Invariants
The source boundary stays an identical exact curve on the strip. Extension follows the support's parameter direction measured by its physical differential speed. The actual computed distance must converge within the requested distance tolerance; solver exhaustion is failure. Closed domains and full-period aliasing are explicit bounds, not bypassed by sampled curves.

## Verification and Change Impact
Deferred verification must cover cylinder/cone/sphere/torus iso boundaries, ruled supports, reversed faces, physical distance, finite-domain exhaustion and source-edge correspondence. Arbitrary non-isoparametric boundaries and non-natural laws remain source gaps owned by the general extension producer.

Fixed Gauss quadrature and Newton iteration construct a candidate parameter endpoint only. Before publication, exactly one original CurveArcLengthResolving enclosure over the retained SurfaceLift iso law must place the entire arclength interval within the requested distance tolerance. The existing Geometry arclength depth/interval limits remain unchanged and its failures propagate. Repeated sampled closeness cannot authorize an endpoint, and the numerical candidate is never substituted for the original source law.

The same whole original arclength admission applies to B-spline boundary extension and shortening. Finite rectangular faces retain their original support during inward trimming; changed native iso bounds create new original lifts rather than fitted replacement surfaces. Every selected side must cover its complete original rectangular interval. Selected faces may have heterogeneous supports and are composed with unchanged source face patches, then re-sewn through the shared original span matcher. Modified face/edge parents and other source bodies survive publication. This rectangular producer does not establish arbitrary curved-boundary, body-limit or general corner continuation completeness.

Inward reach candidates use frame-free original parameter derivatives, so an authored pole with a noncollapsed inward tangent does not require a regular surface normal. Whole original arclength bounds remain the publication authority. Rectangular shortening requires exact complete selected-side interval coverage; neither tolerance gaps nor sampled endpoint agreement authorize moving an unselected side segment.

## State, Ownership, and Lifecycle
`NaturalSheetExtensionLimits` is immutable public evaluator configuration. Existing per-proof arclength policy owns depth 48 and interval count 131072; callers may only lower these ceilings. `maximumWork` is an optional caller-selected cumulative ceiling. Its default absence preserves the existing per-proof policy without inventing a whole-feature ceiling. One invocation-local `Mutex` counter on every target admits candidate reach evaluations and original arclength proof work, checks overflow, and observes cancellation outside its lock. It does not claim accounting for sewing, Boolean cutting or the entire feature evaluator.

Optional `remainingSourceDepth` selects the independent original source capability for physical reach proofs; optional `maximumAlgebraicDepth` selects the separate existing 0-through-32 algebra capability. Selecting algebra requires an explicit source capability. When neither is selected, the existing arclength facade retains its historical policy. Selected proofs call the original independent-capability arclength requirement with the same reach counter; spatial integration splits preserve source depth, and no byte accounting guarantee is added by these scalar selections. These fields govern reach proofs only, not every construction, Boolean or sewing stage.

```text
immutable evaluator limits -> one invocation counter
    -> every selected boundary reach candidate
    -> each original arclength proof using retained per-proof caps
    -> exact support patches -> sewing (separate resource owner)
```

## Failure, Concurrency, and Constraints
Invalid configuration, counter overflow, a supplied cumulative ceiling, depth/cell exhaustion and cancellation fail explicitly. Independent evaluator calls retain independent counters. The counter remains `Mutex` storage on Native, WASM and Embedded; callbacks and source evaluation occur outside the lock.

Modify of a complete native rectangular B-spline sheet attempts whole-support continuation after all requested reaches are determined and before independent strip/corner composition. Its adjacent selected sides therefore share the continued native corner law and publish one rectangle; a planar-only corner adapter cannot reject this already-admitted whole-support route. Separate extension sheets and partial/native-foreign boundaries retain their own composition contracts.

For Natural Modify without a body limit, complete original rectangular iso sides on analytic/procedural supports are resized outward as one face before strip/corner composition. Reaches remain original physical proofs at each source-side midpoint. The unchanged original support supplies the entire corner rectangle and every adjacent boundary continuation; retained source faces compose in the same invocation. Native B-spline outward continuation remains a different producer. Partial sides and non-isoparametric boundaries do not admit whole-side resizing.

Complete original affine operation word pcurves preserve native UV. After the Topology rectangular-domain resolver admits their exact source/target binding, selected-side coverage unwraps only exact whole source fractions 0-to-1 or 1-to-0. Partial fraction wrappers require their own retained chart-domain proof and cannot be replaced by rounded native endpoints. The support image remains the physical arclength authority.

Body-limit ray candidates retain one complete original target-body bounding box in the target frame. Its inherited bounded source producer shares the reach invocation callback and the stricter of its historical depth 32 and the caller depth. A ray window is the outward L1 bound from its original stored origin to this box plus the existing distance margin, never a fixed world-distance cutoff. This only proves the search window covers that candidate ray; complete station-wise crossing and reach extrema remain the general body-limit producer gap. The existing counter still does not claim ray crossing, trim, Boolean or sewing-wide accounting.

Natural strip construction also consumes a retained original affine operation-word boundary directly. It requires exact original pcurve/source/target support binding and whole directed fractions 0-to-1 or 1-to-0, recursively reads the unchanged original iso coordinates, and preserves reversal. The resulting strip retains the target original word surface as physical/arclength authority. A rounded inverse chart or converted curve does not authorize this dispatch.

Both strip-axis selection and rectangular selected-side coverage consume Topology's `ExactRectangularPcurveAxisEndpoints` receipt. The issuer binds the actual retained support and original directed pcurve, resolves full image/word traversals and exact gain/swap endpoints, and refuses an unrepresentable singleton instead of rounding its inverse. Natural extension reads only the certified fixed axis and directed endpoints; the image support remains the physical reach authority. The reach invocation pays these source visits when configured, without claiming a Boolean/sewing resource ledger.

## Canonical Native Binding
The SheetExtend operation creates one immutable contribution with its existing
NaturalSheetExtensionLimits. Reach candidates, exact rectangular endpoints,
original arclength certification and downstream clipping/sewing borrow the same
execution; the private invocation Mutex counter and copied evaluator are removed.
Natural/soft/linear/reflective formulas, sixteen-piece quadrature, iteration32,
source/subdivision/scalar policy and retained topology order are preserved.
The component still refuses missing original source capabilities.

## Required Provider Binding Boundaries
The candidate's direct entry refuses planar inward cuts and B-spline boundary extension while their shared Modeling producers have only ordinary witnesses. Refusal retains the caller's checkpoint and contribution, issues no partial topology and does not invoke a child budget. Other shared ordinary callers and producer mathematics remain unchanged; these required families remain incomplete.

Variable provenance filter/sort and carried-identity traversal are charged at their Modeling owner through direct requirements. Pure metadata operations do not imply zero dynamic work or storage. Rectangle patch construction evaluates the same native isoparametric curves and four original corners using the caller's execution.
