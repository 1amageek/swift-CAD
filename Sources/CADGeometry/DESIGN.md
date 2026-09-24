# CADGeometry

## Purpose and Scope

`CADGeometry` owns exact analytic curves, surfaces, parameter domains, and
surface-parameter curves used by all higher Swift-CAD modules. It is a child of
the [Swift-CAD package design](../../DESIGN.md). Its
[Involute](Involute/DESIGN.md) child owns certified involute flank approximation.
The [RollingBall](RollingBall/DESIGN.md) child owns local contact sections for
curved-surface fillets, not their topology or feature publication.

## Responsibilities and Boundaries

This module owns the representation and structural validation of analytic
surface parameter curves, including spherical great-circle curves. It does not
own topology identity, feature lineage, evaluation orchestration, or Rupa
measurement policy.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Swift-CAD package](../../DESIGN.md) | parent | package exact-geometry contract | Places geometry below modeling and above core values. | Keep the shared predicate contract authoritative. |
| [CADModeling](../CADModeling/DESIGN.md) | used by | generated primitive pcurve values | Supplies valid sphere seam/pole curves. | Construction cannot rely on a sphere-only validation bypass. |
| [CADIR](../CADIR/DESIGN.md) | used by | signature validation | Validates retained geometry through this module. | Do not loosen Codable/signature rules independently. |
| [Involute](Involute/DESIGN.md) | child | certified flank approximation | Converts analytic involute intervals to bounded B-spline spans. | Does not own gear dimensions or root geometry. |
| [RollingBall](RollingBall/DESIGN.md) | child | local contact section | Resolves source contacts from offset-intersection correspondence. | A local section is not a certified complete blend surface. |

## Architecture

```mermaid
flowchart LR
    Surface["Analytic Surface"] --> Curve["SurfaceParameterCurve"]
    Curve --> Structural["Finite/domain/degeneracy checks"]
    Structural --> Signature["CADIR geometry signature"]
```

## Contracts and Invariants

Certified rational 2D curve intersections refine a unique root enclosure until
the consumer's precision condition is met. Padding a refinement stays within
half the remaining distance to the proof-domain boundary, so padding cannot
restore the entire previous domain and prevent precision convergence. The root
enclosure remains contained; depth/cell exhaustion is still an explicit error.
RationalBSplineCurveIntersector2DTests owns the nonlinear/endpoint refinement case;
Loft and exact trim-edge consumers retain their independent spatial admission.

Regularity subdivision bisects the larger fraction of the original parameter
domain. Refinement must not starve the coordinate carrying derivative variation
because another coordinate has a large spatial extent or a midpoint tangent is
small. Acceptance still requires the complete cell's outward interval proof;
depth and cell budgets remain hard failure limits.
Regularity measures the first-derivative interval vectors and their cross product
with the shared IntervalVector3DBounds magnitude bounds. Independent self-dot
products must not introduce negative squared lengths and force unnecessary
subdivision. The proof compares lower tangent lengths with distance tolerance
and the lower normal length with an outward upper tangent-product angle bound;
it does not require higher derivatives merely to test those magnitudes.
The shared vector lower magnitude encloses the Euclidean norm of component-wise
absolute minima, with outward-rounded products, sums and square root. It retains
the largest-component bound when underflow or overflow makes the sum weaker.
This avoids orientation-dependent refusal of short but regular tangents.

B-spline embedding first certifies local cells with a forward work cursor; a
later split must not repeat local projection proofs for earlier accepted cells.
After that pass, touching-region refinement restricts already injective patches,
so their children retain local injectivity. Region-wide and separated-cell pair
proofs remain mandatory, and all existing depth/cell failure limits remain active.
Each immutable cell retains its three differential interval-vector bounds once;
touching-region checks reuse them instead of rebuilding Bernstein products per
pair. The cache is request-local and bounded by the existing cell-count limit.
Initial count and subdivision growth are checked before materializing cell caches.
Separated-cell pairs first compare retained positive-weight control hulls. A
disjoint hull pair needs no point-coincidence search or four-parameter difference
patch. Coarse exclusions and detailed subdivision both consume the pair budget.

At the graph restriction resolution floor, interval jets use a containing
local interval wide enough for certified restriction, not the entire parent
cell. Derivatives are rescaled by that containing interval's actual width.
This preserves conservative bounds without undoing adaptive refinement;
endpoint and interior tiny-interval checks cover prepared and unprepared paths.

B-spline inverse projection refines candidate stationary points to the same
parameter resolution used to distinguish roots. A small world-space residual
or gradient alone is insufficient for small-scale curves. Self-overlapping
curves retain explicit ambiguous-selection failure; no distance-based root
merging replaces parameter uniqueness.

`OffsetSurfaceParameterCurveImage` transports UV correspondence in either
direction across one known offset relation. Forward transport targets the
existing exact chart-preserving offset representation. Pullback validates the
input pcurve on `.procedural(.offset(offset))` and targets `offset.source`
without applying a second geometric offset or changing the UV curve. Position
and spatial derivatives are evaluated on the destination surface by the
existing surface-lift owner. Reversal, trimming and Codable retain direction;
the optional `isPullback` field is omitted for forward images and defaults to
false only when absent, preserving the existing forward encoding. Invalid
field values and unrelated destination surfaces remain errors.

Parameter derivatives of unit-weight, single-span clamped cubic B-splines
use scalar de Casteljau interpolation and quadratic/linear derivative
polynomials. This path allocates no basis tables and retains domain validation,
parameter scaling, finite-result refusal and stationary endpoint behavior.
Polynomial tessellation derivative certificates require weights exactly equal
to one, not the approximate `isRational` display classification. Stationary
endpoint certificates are considered only on intervals touching a repeated
endpoint control point; interior intervals perform no knot-array construction.
Single-span clamped quadratic basis evaluation uses Bernstein polynomials
through derivative order two, avoiding recursive basis-table construction for
analytic conic spans in both 2D and 3D. Rational weight accumulation and finite
result validation stay with the existing curve evaluator. Other knot structures
and higher derivative orders retain the general basis path.
Differential tests compare against equal non-unit rational weights on
non-unit parameter domains; tessellation tolerances are not changed.

Surface-lift derivative magnitudes use certified interval derivatives of their
support surface, not tessellation's tangent-frame admission and subdivision.
The consuming ruled-surface certifier owns subdivision and its existing cell
budget. An unprovable source interval throws its typed certification failure;
it never supplies sampled or zero derivative bounds. This prevents nested
tessellation certification when thickened sheet walls lift offset boundaries.
Third-order surface-lift jets retain the existing certified coordinate-wise
position enclosure. An isotropic speed radius must not replace that support
enclosure and introduce artificial uncertainty in a constant coordinate;
derivative magnitudes remain outward bounds, independently of position bounds.
Tessellation's tangent/normal norm bounds use IntervalVector3DBounds length
bounds. A self dot-product with independent interval factors can introduce a
negative squared-norm lower bound and must not drive regularity subdivision.

Bounded rotation coefficients use outward interval arithmetic and a Taylor
remainder, rather than treating rounded libm values as exact trigonometry.
Their consumer is [CertifiedTwist](../CADModeling/CertifiedTwist/DESIGN.md).
Inverse tangent for finite nonnegative intervals up to 16 uses five applications
of atan(x)=2*atan(x/(1+sqrt(1+x²))), outward square-root endpoints, and twenty
alternating-series terms. The reduced argument is checked against 1/16;
the omitted term is below 2^-164 before rescaling by 32. Gear dimension-to-angle
construction consumes this enclosure rather than certifying a rounded libm angle.

1. Validation first checks finite values, correct surface kind, non-degenerate
   curve extent, and parameter-domain membership.
2. A spherical great-circle curve requires finite unit basis vectors and a
   non-degenerate angular span. A valid orthogonal basis is accepted despite
   unavoidable IEEE-754 representational residuals; malformed or non-orthogonal
   input remains rejected by the shared structural predicate.
3. Periodic seam and pole endpoints remain represented by their analytic
   parameterization and are never omitted to avoid validation.
4. Model tolerance controls modeling decisions; it is not a blanket substitute
   for structural validity.

## Runtime Flows

An evaluator constructs the analytic curve, validates it against its surface,
and passes it to topology/signature owners. Signature validation calls this
same contract rather than reimplementing a sphere-specific rule.

## State, Ownership, and Lifecycle

Geometry values are immutable value types after construction. Validation does
not retain external state or mutate the source/evaluation model.

## Failure, Concurrency, and Constraints

Invalid coordinates, vector lengths, angular spans, wrong surfaces, and
out-of-domain parameters throw typed geometry errors. Representational
tolerance is bounded to the operation's mathematical scale and cannot accept
nonfinite or degenerate data.

## Verification and Change Impact

Prepared B-spline differential enclosers own immutable homogeneous derivative
control nets through third order for each Bezier span. Preparation occurs once
per surface operation; requested boxes only restrict those same nets. The direct
path prepares transiently and follows identical interval arithmetic. No result
cache, shared mutation, tolerance change, or cross-request lifetime is introduced.
Prepared/direct interval equality, disjoint successive boxes and invalid span
rejection verify this reuse contract.

Tests cover valid sphere great-circle curves at seam and pole endpoints,
slightly perturbed valid floating-point bases, non-orthogonal bases,
nonfinite/degenerate values, and wrong surfaces. Changes require rechecking
primitive B-rep generation and CADIR signature round-trips.
Surface-lift changes also require offset-boundary derivative enclosure tests
and the application's complete Thicken reevaluation/tessellation path.
Offset chart pullback is checked by `OffsetSurfaceParameterCurveImageTests`
against a bilinear curved surface's analytic position and first/second
derivatives, direction-preserving reversal/subdivision/JSON and invalid targets.
The existing kernel offset-image integration test retains forward behavior;
`RollingBallSectionTests` checks the offset-intersection-to-contact-rail path.
