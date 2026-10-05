# Natural Curve Join

## Purpose and Scope
Parent: [CADModeling](../DESIGN.md). This component owns shared original parameter-chart continuation for Kernel edge offset joining and Modeling joint support retrimming. It has no children.

## Responsibilities and Boundaries
The spatial curve producer owns the original curve. This component owns continuation of the actual parameter law over an oriented normalized interval. Kernel joining owns intersection isolation inside its existing search envelope; Modeling joint retrimming owns whole spatial curve/support correspondence admission. Geometry owns original homogeneous continuation and differential enclosures. Joining does not replace the curve by an osculating circle, tangent polyline or interpolation.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADModeling](../DESIGN.md) | parent | OriginalOffsetCurveContinuation | Shared original chart continuation | Whole correspondence remains the caller admission. |
| [CADKernel](../../CADKernel/DESIGN.md) | used by | exact trim intersection and imprint | Offset publication | Preserve source parents. |
| [CADGeometry](../../CADGeometry/DESIGN.md) | depends on | OriginalBSplineCurve2DContinuation | Original endpoint-span law | Retained source and requested tolerance |

## Architecture
```text
actual offset pcurves -> original-law continued ranges -> exact spatial lifts
    -> complete trim intersection isolation -> first admitted crossing
        -> original-law subcurves -> imprint
```

## Contracts and Invariants
The continued pcurve retains its original coefficients, source wrappers and oriented native interval. Homogeneous B-spline endpoint spans stay bound to the original source; harmonic curves retain their original center/axes/phase law. Image continuation first continues the original source pcurve, then retains the same source/target image binding. Native support-domain and denominator failures propagate. Kernel [Original Edge Offset](../../CADKernel/OriginalEdgeOffset/DESIGN.md) owns physical search envelopes and complete joining intersections; Modeling joint replacement owns correspondence and finite support admission. Continuation alone grants neither physical distance nor intersection completeness.

## Failure, Concurrency, and Constraints
Unsupported original continuation families remain marked at their callable branch. Denominator singularity, root ambiguity, resource exhaustion and cancellation propagate. Existing root-isolation budgets and requested tolerance remain unchanged.

## Verification and Change Impact
Deferred checks must compare complete resulting loci with the original endpoint-span laws, including rational curves whose osculating circles differ, multiple crossings, missing crossings, reversed charts and shared boundary publication. These checks do not establish the upstream offset distance law; that producer has separate authority.

Original, rigid and original affine operation word chart images continue their retained source pcurve first, carrying the directed source fractions into that original continuation range, then rebuild the same source/target image binding over the new original lift. Foreign UV samples and transformed curve fitting never define the continued law. Directed offset images preserve pullback versus forward transport during continuation. The underlying support-domain and complete intersection failures remain unchanged.

Modeling joint retrimming first checks the unchanged original spatial curve's complete directed parameter-domain admission. Subintervals retain the original pcurve subcurve; extensions consume this component's original harmonic, homogeneous and image laws. The rebuilder's whole original curve/support correspondence validator must admit every continued use before model mutation is published. A supported chart continuation is never by itself a proof that the unchanged spatial curve extends along it.

A polyline pcurve uses the original Euclidean arc-length prefix, not vertex-index fractions. Natural continuation must retain that original prefix and its endpoint segment law. Uniform-knot conversion and rounded length-prefix knots cannot replace this authority. Until the Geometry-owned persistent continuation carrier is available, this family fails explicitly at the production join call and remains an E8 source gap.
