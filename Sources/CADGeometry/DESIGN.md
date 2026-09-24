# CADGeometry

Analytic/B-spline intersection retries vary periodic charts only. A plane has
one chart and therefore one attempt, independent of the periodic retry limit;
its original intersection/resource failure propagates without repeating the
same bounded problem. Periodic surfaces retain their existing seam search.
AnalyticBSplineSurfaceIntersectionTests owns chart-selection and failure checks.

Convex-hull separating-plane predicates first enclose the dot product and
distance threshold using outward-rounded scalar intervals. A strict interval
sign decides the result; uncertain signs use the existing expansion predicate.
The search directions, iteration budget and accepted separation are unchanged.
ConvexHullSeparationTests compares filtered signs with the expansion reference.

Surface intersection construction may supply an authored exact pcurve. The
intersection verifier validates whole-span correspondence before retaining it
and constructs its anchor by forward evaluation, without inverse projection.
Plane/B-spline boundary intersections supply their known isoparametric chart
on the B-spline support; the other support retains its existing projection path.

Rational B-spline/analytic-surface intersection evaluates position and parameter
derivatives, not curvature. A nonzero parameter speed is normalized independently
of modeling distance tolerance. At a stationary Bezier endpoint, the first
distinct control point supplies the exact one-sided tangent direction (positive
weights); a constant span or unresolved stationary interior remains an explicit
failure. CurveSurfaceIntersectionTests owns endpoint/reversal regressions.
Plane intersections remove exact zero endpoint factors in Bernstein form
before power conversion, retaining each endpoint once without merging nearby
distinct roots by a widened numerical tolerance.

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

Loft construction may retain a unit-weight clamped bilinear parameter map with
one collinear polygon corner. Exact spatial coplanarity and planar turn signs
must establish a convex, nondegenerate boundary with no repeated vertices.
`BSplineSurfaceEmbeddingValidator.stationaryPlanarSupport` returns the planar
support for this case; it is not a regularity certificate for the tensor chart.
The stationary-boundary embedding option admits this homeomorphic construction
map. Consumers must publish the planar support with exact trims, not the
singular tensor chart. General curved or folded boundaries retain existing checks.

Unit-weight Bezier differential bounds use the polynomial derivative nets for
both interior and boundary cells. The weight polynomial is exactly one, so
rational numerator products are unnecessary. Stationary-boundary requests only
control removal of known boundary factors; they do not select the polynomial
representation. Non-unit weights retain the rational path.

Loft may request stationary outer-boundary parameterization admission from the
existing B-spline regularity and embedding validators. For unit-weight Bezier
patches only, exactly repeated boundary controls identify factors u, (1-u), v
or (1-v) in the corresponding directional derivative. Divide those Bernstein
derivative nets by the known factors with outward arithmetic before bounding
tangents and normals. Factors are removable only at the requested domain's
outer boundary and only in their own derivative direction. Their integrals
define strictly increasing independent parameter changes; the stored surface
and its geometry remain unchanged. Positive bounds for the reduced Jacobian
establish regularity in those coordinates, including the limiting boundary.
Interior singularities, collapsed boundary curves and rational stationary
boundaries do not acquire an exemption. Default validator behavior remains strict.
Failed enclosure still requires subdivision or explicit failure; boundary samples
with declared stationary speed cannot replace a complete reduced-Jacobian proof.

Exact Coons construction owns polynomial and rational transfinite interpolation
for every modeling consumer. Exactly unit-weight boundaries use the common
normalized basis and Greville linear-coordinate coefficients without rational
degree inflation. Any non-unit weight retains the rational construction; an
approximate `isRational` classification cannot discard input weights. Both routes
enforce corner, patch-count and result-degree contracts before tensor allocation.
Construction does not itself certify embedding; feature admission owns that gate.
`ExactCoonsBSplineSurfaceBuilderTests` verifies interior formula agreement,
boundary interpolation, non-unit weights and resource-limit refusal.

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

Common curve-basis resolution preserves already-identical normalized clamped
bases verbatim after validating both curves and counting their positive knot
spans against the existing limit. It must not reconstruct these controls from
derivatives or round-trip their homogeneous coordinates. Different bases still
use the existing normalization, span alignment and degree elevation path.
Degree elevation retains exactly equal homogeneous components during blending.
This preserves constant coordinates and weights instead of introducing a false
variation through two rounded products; unequal components retain weighted blending.

`BSplineSurfaceEmbeddingValidator.validateSeparation` certifies that two complete
finite spline domains are disjoint using the same outward Bernstein difference
exclusion and subdivision budget as embedding. Parameter coordinates belong to
different charts and never imply adjacency. Failure to prove separation is a
typed resource failure, not a positive intersection certificate. Touching domains
are not admissible to this strict separation contract; topology must separately
own shared-boundary admission. This contract does not establish regularity.
Adjacent spline charts use a separate admission contract: orient the nominated
boundaries into a common rectangular chart, require clamped ends and identical
seam basis, control points and weights, then certify injectivity over both complete
charts with the existing local-cell, touching-region and separated-cell
certificates. A global projection is only an early sufficient certificate.
Sampled coincidence may reject distinct parameters, but never proves admission.
No snapping or sampled
agreement establishes continuity. Incompatible seam representations and an
inconclusive bounded refinement fail explicitly. General basis reconciliation
remains incomplete; this is not general face sewing.
Two opposite shared boundaries are admitted by bisecting both source charts
between those boundaries. Every cross-chart half-pair is checked: matching outer
halves use single-boundary adjacency, and the other pairs require strict
separation. Trimming uses the existing spline trim owner and retains source
coordinates; it does not add topology. Four pair proofs divide the request's
cell budgets, and unmatched or non-opposite boundary declarations fail explicitly.
An arbitrarily oriented straight seam can instead be admitted independently of degree
or parameter speed. Clamped boundary control polygons must share exact endpoints,
be exactly collinear in two independent coordinate projections and monotone
along a nonconstant coordinate. Zero-tolerance robust orientation predicates
establish collinearity; near-collinearity does not authorize snapping.
Positive rational weights then keep each boundary on that same segment. A plane
through that line must weakly separate every non-boundary control point of
the two charts and strictly separate all such controls on at least one chart,
certified with robust spatial orientation predicates. The strict chart meets
the plane only on its shared boundary, even if the other chart has vertices on
the boundary's extension. This excludes any
cross-chart contact away from the seam. Each chart must also pass independent
embedding admission using half the request's local and pair-cell budgets. A candidate plane is
only a search heuristic; inconclusive signs retain the general-chart path.
Point-contact separation may nominate up to four pairs of clamped parameter
corners whose stored positions are exactly identical. Each source corner may
occur only once. Only those tensor-product corner coefficients are exempt from
strict signed difference projection. Any two exempt corners differ in at least
two parameter coordinates, so no tensor-product edge has both endpoints exempt.
Thus no positive-dimensional boundary face can vanish identically. Every other
coefficient must retain the same strict sign, so positive Bernstein weights
exclude zeros everywhere except the nominated corner pairs. Subdivision retains
each exemption only in cells containing that same parameter corner; all other
cells require ordinary separation. No tolerance snapping or whole-face exemption
is allowed. Existing depth and pair-cell budgets bound inconclusive proofs.
Oblique candidate axes from coefficient-box means and crosses of midpoint
derivative columns supplement Cartesian axes.
Only uniform strict signs of outward-rounded projections of every coefficient
box certify separation. The mean is a search heuristic, never proof by sampling;
failure continues bounded subdivision without increasing its budget.

B-spline embedding first certifies local cells with a forward work cursor; a
later split must not repeat local projection proofs for earlier accepted cells.
Touching-region refinement splits only its least-refined cells, so a fine cell
does not exhaust its depth budget while a coarse neighbor still determines the
unresolved rectangle. The complete rectangle retains the same injectivity proof
and cell/depth ceilings.
Touching-region searches build a request-local balanced index over scalar UV
rectangles. Subtree hulls exclude disjoint candidates before reading differential
bounds; closed overlap finds contacts and strict overlap covers region interiors.
The index is rebuilt after subdivision, uses O(cellCount) storage, and preserves
original cell ordering and the complete-region proof.
The same request retains proved rectangle certificates across refinement because
restriction preserves injectivity. Retention is capped by the existing pair-cell
budget; once full, subsequent proofs are recomputed rather than cached. Neither
cache presence nor capacity changes admission, precision or failure conditions.
After that pass, touching-region refinement restricts already injective patches,
so their children retain local injectivity. Region-wide and separated-cell pair
proofs remain mandatory, and all existing depth/cell failure limits remain active.
Each immutable cell retains its three differential interval-vector bounds once;
touching-region checks reuse them instead of rebuilding Bernstein products per
pair. The cache is request-local and bounded by the existing cell-count limit.
Initial count and subdivision growth are checked before materializing cell caches.
Separated-cell pairs first compare retained positive-weight control hulls. A
disjoint hull pair needs no point-coincidence search or four-parameter difference
patch. A coordinate-sorted sweep excludes disjoint ranges before pair creation;
each remaining candidate and detailed subdivision consume the pair budget.
Axis selection minimizes total cell width relative to the covered coordinate
range, a search heuristic only. Sorting uses O(cellCount) index storage; worst-case
overlap remains bounded by the existing pair budget, not a larger configured limit.
After local refinement, a consistent projection certificate over all cells also
proves separation globally. Reuse the same existing projection criterion, covering
the complete parameter rectangle rather than only two disjoint patches. This
certificate finishes the proof without enumerating redundant cell pairs.

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

Curve decomposition preserves existing Bezier spans, including composite curves
whose span boundaries have at least degree-fold knot multiplicity,
after source validation. Trimming preserves source endpoint controls and weights
at unchanged bounds; only newly created endpoints are evaluated by subdivision.
The contract is exact stored identity, not tolerance-based snapping. Rational,
non-clamped and partial-domain regression checks remain in BSplineCurveTrimmingTests.

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
