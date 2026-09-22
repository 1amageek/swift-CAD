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

## State, Ownership, and Lifecycle

All inputs are immutable value-owned, Sendable geometry. Evaluation retains no
shared mutable state and performs constant-size section construction. Existing
intersection/normal evaluation owns its own resource and failure contracts.

## Failure, Concurrency, and Constraints

Invalid radii and parameters, unrelated intersection data, singular normals,
degenerate contact directions and invalid output geometry throw typed errors.
No nearest-point heuristic, planar substitute, or mesh fallback is permitted.

## Verification and Change Impact

[RollingBallSectionTests](../../../Tests/CADGeometryTests/RollingBallSectionTests.swift)
checks actual sphere/plane offset intersections, radius and source contacts,
endpoint tangency, both surface orders and multiple native curve parameters;
invalid radius, wrong correspondence and degenerate contacts are rejected.
These checks establish only the local section contract. Integration requires
curved-edge helical-part machining, complete trimmed B-rep validity, atomic
failure, Undo/Redo, source round-trip and native presentation.
