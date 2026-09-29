# Rolling Ball Contact Sections

## Purpose and Scope

Child of [CADGeometry](../DESIGN.md), with no children. Owns the local circular
cross-section of a constant-radius rolling-ball fillet between regular surfaces.
This is a lower-level step toward machining existing curved B-rep faces; it does
not generate a gear or publish a fillet feature.

## Responsibilities and Boundaries

The intersection owner supplies one component of two signed, equal-magnitude
offset surfaces. This component evaluates its paired parameters; the section
owner evaluates the original surfaces at those parameters and constructs the
minor circular arc between the two contact normals. CADModeling must still
select the correct component, construct and certify the complete blend surface,
trim the original faces, close end conditions and preserve topology lineage.
Local success must not be used as a whole-surface or solid certificate.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADGeometry](../DESIGN.md) | parent | surface evaluation and intersection correspondence | Supplies offset surfaces, normals and rational curves. | Keep geometric truth separate from sampled evidence. |
| [CADModeling](../../CADModeling/DESIGN.md) | prospective consumer | contact sections | Will compose sections into a fillet. | No production feature integration is claimed yet. |

## Architecture

```text
Equal-radius signed offsets + intersection component
    -> paired original-surface parameters and normals
    -> center/contact residual admission
    -> rational quadratic minor arc
```

## Contracts and Invariants

Repeated blend interval queries retain the prepared center and two contact-rail
enclosers in the existing PreparedSurfaceDifferentialEncloser. The preparation
is immutable and request-local; each box still recomputes its interval proof
and uses the blend's construction tolerance. One-shot queries use the same
formula and preparation contract. No persistent cache or tolerance change is
introduced. Prepared/unprepared differential comparisons and domain refusal
remain required, including implicit contact rails.

`crossSectionLiesOnLeft` certifies the sign of
`contactTangent.cross(otherContact - contact).dot(sourceNormal)` throughout
the normalized contact rail. Left/right is relative to the source UV chart,
not world axes or B-rep face orientation. It uses existing curve/surface
interval enclosures, rejects changing signs, and refines inconclusive bounds
within caller budgets. Rigid images transform the source normal consistently.
This relation selects a trim side only after the caller establishes an inward
convex treatment; it does not establish material ownership or end closure.
Unsupported source-chart enclosures fail explicitly, without a sampled vote.

`RollingBallSectionEvaluating` evaluates at the intersection curve's native
parameter, not an assumed normalized parameter. The immutable evaluator retains
the supplied offsets, component and tolerance. Both offset magnitudes must be
exactly the same finite positive radius above modeling tolerance; signs specify
the selected sides and must not be inferred from a display mesh.

The section center is the first evaluated offset contact. The second offset
contact and supplied intersection position must agree within distance tolerance.
Unit radial vectors are the negative signed source normals. For radial vectors
a and b, the quadratic arc has endpoints C+r*a and C+r*b, middle control point
C+r*(a+b)/(1+a dot b), and middle weight sqrt((1+a dot b)/2).
The emitted endpoint residuals against the original surfaces must fit distance
tolerance. Returned source contact parameters retain their original charts.

Coincident or antipodal radial directions do not define one regular minor arc;
they fail explicitly. Nonfinite or ill-conditioned controls fail rather than
returning an arbitrary arc. The returned maximum contact residual is a local
measurement, not an interval guarantee over the spine or the section.

`contactCurve` restricts the intersection pcurve using native curve parameters,
then uses CADGeometry's offset pcurve pullback and existing `SurfaceLiftCurve3D`
to produce a normalized contact rail on the original surface. It does not
reuse the spatial offset intersection as the contact rail, project sampled
points, or claim that the rail alone certifies fillet feasibility. Both contact
rails retain the same requested spine interval and original surface charts.
The caller supplies correspondence validation budgets, but cannot widen the
allowed deviation beyond the evaluator's modeling tolerance. Before transfer, the
existing injected `CurveSurfaceCorrespondenceValidating` service proves the
trimmed interval against the selected offset surface; unrelated correspondence
or exhausted proof budgets must not produce a rail. The default service retains
its own immutable-input cache and synchronization contract; this component adds
no cache or shared mutable state.

### Blend surface evaluation

Contact-boundary correspondence may reuse the original offset certificate only
when the stored center and pulled-back rail have the same chart parameters and
the offset magnitude equals the blend radius. The same offset chart has zero
ideal radial defect. Opposite roles of the identical implicit certificate with
identical trims bound the radial defect by that certificate's residual bound
(reverse triangle inequality). The consumer's deviation limit must admit that
bound; unrelated centers, radii, trims, or certificates retain general proof.

The next composition is an immutable `RollingBallBlendSurface3D`, constructed
by the section evaluator from the two admitted contact rails and the first
offset rail as center spine. All three rails use the same normalized U domain;
V traverses the minor circular section. For normalized radial vectors a and b,
w=sqrt((1+a dot b)/2), s=1-v, the radial surface is
`r * (a*s*s + (a+b)*s*v/w + b*v*v) / (s*s + 2*w*s*v + v*v)`.
Adding the center spine gives the surface position. Normalization handles
intersection evaluation residuals only after both contact distances fit the
modeling tolerance; it must not make invalid contact geometry admissible.

Point evaluation uses scalar arithmetic. Mixed derivatives through total order
three use existing bivariate Taylor jets and curve derivatives; box enclosures
use existing outward interval jets and curve enclosers with the same formula.
Unprovable nonzero radial vectors or minor-arc denominators fail explicitly;
the caller owns subdivision. No sampled derivative is used as an enclosure.
These evaluations do not certify global fillet feasibility, source tangency
between finite checks, end conditions or self-intersection. Complete
feature admission and feature topology integration
remain required before a fillet can publish this surface.

The blend value persists its center spine, both source contact rails, radius
and construction tolerance. Decoding validates structural inputs and normalized
spine coverage, rejects unknown fields, and does not deserialize any proof or
claim regularity, contact feasibility or solid validity. Derived jets and
validation results are not stored. `Surface3D.procedural(.rollingBall)` owns
the native surface representation. Point, differential and interval operations
delegate to the same blend value; inverse projection uses the existing bounded
procedural projector. Kernel closest-point queries use its existing finite-domain
closest-point certification, not inverse projection's on-surface acceptance.
The stored construction tolerance governs rail admission;
consumer tolerance governs projection acceptance and topology validation.
No exact analytic or B-spline equivalent is advertised for a general blend.
The contact rails are stored as normalized `Curve3D` values: initial rails
retain `surfaceLift` charts, and rigid images retain those sources through the
existing curve transform representation. Rigid placement transforms all three
rails together and preserves radius; it does not reinterpret UV coordinates
on a newly oriented analytic support surface.

`validateRegularity` reuses `DefaultSurfaceRegularityValidator`'s bounded cell
subdivision and interval tangent-frame admission. The blend supplies its own
interval and point differentials; no second regularity algorithm is introduced.
Success proves nondegenerate parameterization only, not contact correspondence,
self-intersection absence, end closure, or solid validity. Caller-supplied depth
and cell limits fail explicitly when the proof cannot be completed.

Contact-minus-center interval jets retain correlation by intersecting their
direct bounds with a mean-value enclosure anchored at a certified interval
around the cell midpoint, wide enough for existing normalized-pcurve trim
admission and clipped to the original cell. Each derivative uses the
next derivative's full-cell bound; the third derivative remains unchanged.
The anchor is an interval evaluation, never an uncertified sampled point.

The section denominator has Bernstein weights `[1, w, 1]`. On the normalized
section domain its value is bounded by their convex hull, even when independent
interval products lose the correlation between `t` and `1-t`. Intersect this
bound with the arithmetic value enclosure; retain all derivative enclosures.

## State, Ownership, and Lifecycle

All inputs are immutable value-owned, Sendable geometry. Evaluation retains no
shared mutable state and performs constant-size section construction. Existing
intersection/normal evaluation owns its own resource and failure contracts.

## Failure, Concurrency, and Constraints

Invalid radii and parameters, unrelated intersection data, singular normals,
degenerate contact directions and invalid output geometry throw typed errors.
No nearest-point heuristic, planar substitute, or mesh fallback is permitted.

## Verification and Change Impact

Constant-U blend sections admit algebraic rational quadratic normalization for
curve coincidence. This preserves the native V parameter and does not replace
stored surface lifts or certify a complete blend as a rational surface. Reversed
sections reverse the controls and weights; bounded spans use existing B-spline
trimming. General non-isoparametric lifts remain unsupported by this conversion.
Curve-surface correspondence uses the same section conversion and existing
homogeneous-control distance bound, including reversed edge trim orientation.
Only a bound within consumer distance tolerance admits correspondence; endpoints
alone never establish coincidence or correspondence.

[RollingBallContactSideTests](../../../Tests/CADGeometryTests/RollingBallContactSideTests.swift)
checks independently known source-chart sides, reversed rail direction,
reflection, and explicit degenerate/budget refusal. Native helical integration
must use the certified side and exclude the original selected edge from the
retained flank, rather than accepting either partition because it can sew.

[RollingBallSectionTests](../../../Tests/CADGeometryTests/RollingBallSectionTests.swift)
checks actual sphere/plane offset intersections, radius and source contacts,
endpoint tangency, both surface orders and multiple native curve parameters;
invalid radius, wrong correspondence and degenerate contacts are rejected.
These checks establish only the local section contract. Integration requires
curved-edge helical-part machining, complete trimmed B-rep validity, atomic
failure, Undo/Redo, source round-trip and native presentation.
