# Original Curve Span Coincidence

## Purpose and Scope
This component proves whole oriented original curve-span correspondence for sewing and finite Loft contacts. Parent: [CADModeling](../DESIGN.md). No children.

## Responsibilities and Boundaries
The existing span matcher owns endpoint pairing, exact rational and structural identity branches. This component owns continuous original-law distance bounds for remaining native curve families and monotonic correspondence subdivision. CADGeometry owns original outward derivative enclosures and projection candidates. Candidate fitting and converted curves confer no coincidence authority.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADModeling](../DESIGN.md) | parent | CurveSpanCoincidenceMatcher | Whole sewing identity | Preserve oriented source intervals |
| [CADGeometry](../../CADGeometry/DESIGN.md) | depends on | PreparedCurveDifferentialEncloser | Original closed owning jets and retained continuity receipts | A union never grants continuity; missing witnesses propagate failure |
| [Loft Finite Cap Contact](../../CADKernel/LoftFiniteCapContact/DESIGN.md) | used by | shared subspan proof | General original intersection spans | Point projection alone is not proof |

## Architecture
```text
oriented original intervals -> paired monotonic interval cells
    -> outward original center/derivative/second-derivative residual bound
        -> certify complete cell or project a subdivision candidate
            -> monotonic children -> all cells proved
```

## Contracts and Invariants
Each cell maps its two source intervals affinely over the same local fraction. Whole original position differences always provide a valid enclosure, including discontinuous owning joins. A closed center residual plus the whole-cell first-derivative residual may tighten that enclosure only when both retained preparations issue original positional-continuity receipts over their complete admitted spans. A derivative hull alone never grants the integral theorem or a smooth second-order Taylor theorem. Rational normalization and Möbius/Boehm images select proposals only: a positive image match still requires whole correspondence of both retained original spans. Exactly identical structural source laws with exactly identical oriented native endpoints can bypass numerical certification because their whole law and traversal are unchanged. The union of monotonic paired cells covers both complete oriented spans. Midpoint projections choose subdivision only; they cannot authorize a cell. Reversed traversal preserves original native parameter semantics. Exact rational/structural branches retain their existing precedence.

The additive caller-admitted matcher prepares each original curve once under the same `GeometryConversionAdmission`, charges original structural payload comparisons, and retains the original continuity witnesses once. It reserves its typed DFS frontier before allocation and forwards independent source, geometric and algebraic capabilities to every original closed-jet/continuity query. Its existing coincidence depth24/cell131072 policy may only tighten under a smaller caller spatial selection. Paired affine fraction subdivision consumes the same live work/BYTES owner. Complete bounded nonlinear projection/correspondence remains a producer gap; this selected path never invokes legacy projection with fresh counters. Failure to certify that correspondence is explicit and cannot become a false absence result.

Angular candidate subdivision follows the retained source through original affine operation words. The transformed candidate remains only a proposal; the original word image and complete oriented source intervals remain correspondence authority.

Original endpoint connectors retain their corrected source law in the whole-interval certifier. The construction control net is not an exact rational representation of that law and cannot authorize coincidence. Polynomial endpoint correction adds no angular subdivision requirement.

Adjacent original revolution patches can retain distinct finite angular domains while sharing the exact same generator, raw axis and authored angular law. Identical pcurves over those source supports establish the same lift law without a rational approximation; domain limits remain admission bounds, not new geometry. Other original lifts use the prepared native whole-jet certifier and do not gain coincidence authority merely from matching endpoint stations.

## Failure, Concurrency, and Constraints
The existing sewing coincidence limits of 24 subdivision levels and 131,072 cells are retained, as are native projection limits. A stalled monotonic map, uncertain native enclosure, cancellation or exhausted budget is a typed failure. No fitted curve or cached approximation replaces the source law. All work state is local to one invocation.

## Verification and Change Impact
Deferred evidence must cover original implicit/lift versus rational spans with nonlinear correspondence, reverse orientation, distinct curves sharing endpoints, partial subspans, cancellation and budget exhaustion through sewing and Loft. Exact span matching callers remain responsible for the semantic use of the distance tolerance. Source construction does not establish behavioral success.

Original construction chart curves retain their normalized original parameter law through whole correspondence. The construction control net does not supply exact native span, harmonic or projected-boundary identity; optional normalization fast paths decline and retain the original source for the whole-curve producer.

Original physical-angle transport remains the whole-span certifier's source. A converted rational proposal cannot replace that phase law for homogeneous coincidence authority, and no binary angular period is inferred for its foreign parameter domain.

Original plane-derivative and drafted curves likewise retain their corrected/traversed original laws. Optional rational normalization declines these families; neither a construction net nor a scalar angular shortcut establishes their complete correspondence. Sewing distance admission is distinct from exact SSI component identity: a within-tolerance match alone never excludes a nearby additional physical intersection component.

Original guide traversal chains retain their complete directed piecewise source in coincidence certification. Their constituent rational nets cannot replace the chain's exact station map or original join authority.

Guide endpoint corrections retain the corrected whole chain law. The underlying guide or an individual piece's control net cannot establish exact coincidence of the corrected source.

Original Euclidean-clock polylines retain their authored adjacent segments and exact clock through the generic original coincidence source. A segment list is neither a single exact rational spline nor an angular source; optional scalar/control-net normalization declines this family. Original joins and whole nonlinear correspondence remain with their owning producers.

## Canonical Proposal Binding

Closest-parameter midpoint projection only proposes subdivision children; each
child still requires the existing whole original-jet certificate and directed
coverage. Both entries use that existing ordinary proposal and margin under the
same [execution](../../CADGeometry/OriginalQueryExecution/DESIGN.md). A failed
proposal, unsupported correspondence, cancellation, or exhausted original cell
ceiling remains explicit failure. This is the component's declared sewing
deviation policy and does not redefine exact intersection identity.
