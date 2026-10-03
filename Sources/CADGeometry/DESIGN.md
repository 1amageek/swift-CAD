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

[SurfaceBoundaryCertification](SurfaceBoundaryCertification/DESIGN.md) owns
independent whole-boundary position, normal and shape-operator certification.

[SurfaceFitting](SurfaceFitting/DESIGN.md) owns the shared constrained-surface
numerical construction component and its rank/finite-arithmetic contracts.

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

The ruled builder owns common-denominator conversion for aligned rational
boundary columns consumed by Loft. Each distinct positive Bernstein weight
polynomial contributes once to the shared denominator; each curve's homogeneous
numerator is multiplied by the other factors. Degree limits and finite positive
weight checks apply before publishing any converted curve. Existing shared-seam
admission remains independent and unchanged. CurveLoftFeatureTests verifies the
authored middle boundary through the actual evaluator in ruled and smooth modes.

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

Surface-intersection completeness encloses each support separately. A recoverable
enclosure failure subdivides only that support's two parameters under the existing
depth and cell budgets; exhausting those parameters leaves an unresolved cell.
Partner subdivision cannot repair a failed jet. Successfully admitted jets are
consumed by the graph prover without recomputation. Once both jets exist, graph
rank and coverage refinement retain the four-coordinate search policy.
`RollingBallSectionTests.completenessRefinesOnlyTheSurfaceWhoseEnclosureFailed`
checks both surface orders with a seven-cell, depth-one budget and a broad jet
that demonstrably fails. Existing procedural disconnected-component and
parametric contractor checks cover successful graph search after enclosure.

Curve-surface correspondence treats an inconclusive singular interval enclosure
as a request for bounded local subdivision, not a successful proof or a reason
to reject before subdivision. Point-evaluation errors still propagate. Global
lift bounds are optional optimizations; each accepted cell requires a finite
certified local bound under the existing depth/cell limits.

For bounded-parametric intersections with one planar support, the finite
partner's conservative spatial hull bounds the plane's search domain. Positive
rational B-splines use their control hull; signed offsets expand the hull by
the absolute offset distance. Other finite supports use the existing certified
surface enclosure. Outward interval projection through the original planar
frame retains native UV coordinates, including legacy/analytic chart choices.
The hull includes modeling-distance contact uncertainty. Both-unbounded and
nonplanar unbounded pairs remain unsupported by bounded marching. This search
restriction does not trim or replace either source surface, and spatial bounds
must not come from display meshes or samples.
Adjacent implicit graph cells use this same search-domain normalization at
construction and decoding, computed once per connection-validation pass using
the stored certification tolerance. Native surface domains and geometric and
tangent continuity checks remain unchanged.
Surface lifts of implicit intersection pcurves reuse the certified parameter
interval jet for UV bounds and derivatives through order three. Reversed and
trimmed pcurves rescale each derivative by its parameter-span power; closed
seam-crossing spans enclose both sides separately. Offset pullbacks transport
only UV bounds, never the original support's spatial derivative certificate.
At the graph restriction resolution floor, interval jets use a containing
local interval wide enough for certified restriction, not the entire parent
cell. Derivatives are rescaled by that containing interval's actual width.
This preserves conservative bounds without undoing adaptive refinement;
endpoint and interior tiny-interval checks cover prepared and unprepared paths.
Surface-lift position bounds use interval-local UV certificates before a
whole-intersection enclosure. Implicit pcurves retain the requested direction
and trim; below restriction resolution, the shared containing interval keeps
the enclosure conservative. The original support surface owns spatial bounds,
including offset pullbacks; a source intersection's box is not reused as the
destination surface's geometry.
B-spline inverse projection refines candidate stationary points to the same
parameter resolution used to distinguish roots. A small world-space residual
or gradient alone is insufficient for small-scale curves. Self-overlapping
curves retain explicit ambiguous-selection failure; no distance-based root
merging replaces parameter uniqueness.

Interval-local UV bounds may restrict an already validated parameter curve
without constructing a new offset image. Offset images preserve UV coordinates;
their source supplies parameter-space bounds, while the original lift retains
the target surface for spatial chain-rule evaluation. This internal restriction
is not a persistable geometry value or a transferable spatial certificate.
Public offset-image construction and validation retain their admission rules.
The regression uses a short rolling-ball patch whose midpoint enclosure is
narrower than the admitted source-curve span, followed by actual tessellation.

Tessellation differential certification also bounds interval conditioning before
dividing by the normal magnitude: the certified upper normal magnitude may be
at most twice its positive lower bound. This bounds denominator uncertainty by
a factor of two; a merely positive lower endpoint is insufficient for useful
normal-derivative estimates. Cells that cannot establish this condition are
subdivided under the existing depth/cell budgets, never accepted with clamped
derivatives or increased mesh limits.

Numeric affine, constant-coordinate and harmonic UV charts compose directly
with the existing analytic surface interval formulas. Both coordinates retain
one normalized independent curve parameter through third order. Offset-image
and periodic-translation wrappers preserve that UV relation after validation;
they do not transfer the source surface's spatial derivative certificate.
The surface formulas are shared with two-dimensional surface enclosure rather
than duplicated for each lifted curve kind.

Certified implicit UV charts retain signed derivatives through order three in
surface-lift enclosure. The chart interval is mapped outward to its certified
intersection, including reversal and closed-seam union. The existing surface
chain-rule owner composes these derivatives with one support-surface jet; it
does not recompute three independent magnitude bounds. Offset pullbacks reuse
UV coordinates only, and evaluate the original contact support, not its offset.
Finite source-domain and certification failures remain explicit. These values
are request-local and introduce no shared cache or publication authority.

`ProceduralSurface3D.rollingBall` retains the
[RollingBall blend contract](RollingBall/DESIGN.md) without substituting a
plane, analytic quadric or B-spline. It is nonperiodic with normalized U/V
domains. Existing finite-domain projection and differential enclosure consumers
operate on the retained surface. Analytic-only recognizers return no match;
they do not classify a general blend as a cylinder or translational prism.
Native Codable persistence and rigid placement preserve its three rail charts.
This representation does not establish feature feasibility or closed topology.

Circle intersections retain harmonic UV curves on planes and affine longitude
curves on coaxial spherical latitudes, including chart-preserving analytic
offsets. The common intersection verifier admits these structural cases before
cubic UV fitting. Their first through third derivatives must retain the native
angular parameter; a positional fit alone is not equivalent for blend geometry.
Curve differential enclosures preserve an exact normalized ruled-boundary lift
by evaluating the original boundary curve. Admission requires an endpoint V
and the identical U parameter span, so no approximate surface substitution or
unaccounted parameter scaling is introduced.
Affine UV lifts on analytic cylinders compose the angular and axial interval
jets directly, preserving their common normalized curve parameter through third
order rather than independently reconstructing derivative magnitudes.
A closed B-spline pcurve (a circle's, from a surface intersection) is trimmed as its periodic
curve runs: a span past its domain's end carries on from its start, the two pieces joined C0 at
the seam with the parameters kept (`BSplineCurve2D.trimmedAcrossSeam`), so an edge on a closed
intersection whose arc crosses the seam keeps its exact pcurve.
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

Correspondence of an offset-image pcurve against a separately represented
spatial rail uses the existing bounded spatial proof. Its certified implicit
UV source supplies parameter derivative enclosures, not an automatic mismatch
when structural identity is unavailable. Enclosures scale to the pcurve's
oriented trim and split at original graph-cell boundaries, including periodic
seams. Direct certified pcurves still require their original spatial source;
this does not weaken source-certificate identity or admit endpoint-only matches.

Implicit spatial correspondence prepares its immutable curve enclosure once per
request and reuses it for adaptive second-derivative bounds. Each interval still
receives its own enclosure; original graph proofs and surface preparation are
not repeated for each cell. No cross-request cache or relaxed tolerance is used.

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

`BSplineSurface3D.elevatingDegree(direction:tolerance:)` raises one clamped
direction's degree by one and gives every distinct knot one more multiplicity,
so continuity at each knot is kept and the surface is represented exactly. Each
control line is interpolated in homogeneous coordinates at the Greville
abscissae of the raised knot vector, factored once per direction; a raised line
over 1,024 control points, an unclamped direction or a nonpositive raised weight
throws. `BSplineSurfaceDegreeElevationTests` proves a rational surface with a
doubled interior knot is unchanged in both directions.

`MappedBSplineSurfaceFitter` fits a clamped, uniformly knotted B-spline, bicubic
unless given other degrees, on a parameter rectangle to a smooth map of it (Wrap
carries a face's support this way, on the face's own parameters, so its trimming
curves stay valid; `fit(layout:…)` fits one given layout of degrees and spans and
reports its deviation, for Align Surface's and Rebuild Face's explicit layouts). It
interpolates the map at the tensor grid of Greville abscissae, one direction at a
time through one factored collocation matrix per direction, checks the distance
at the quarter points of every knot cell and along the far edges, and from one
span each way doubles one direction at a time — the one whose doubling brings the
fit closer by a tenth or more — until within the deviation, so a map bending one way
is not split the other way (fewer patches to draw and measure); when neither
doubling helps (a first split of a smooth map can stray further before the next
close in) both double, so a direction that does not matter is never refined in its
place; it fails (`resourceLimitExceeded`) when neither direction can double past
`maximumSpanCount`.
`MappedBSplineSurfaceFitterTests` own the cylinder wrap (split along its bend
only), the exact one-span cubic and the refused budget.

## Runtime Flows

An evaluator constructs the analytic curve, validates it against its surface,
and passes it to topology/signature owners. Signature validation calls this
same contract rather than reimplementing a sphere-specific rule.

## State, Ownership, and Lifecycle

Geometry values are immutable value types after construction. Validation does
not retain external state or mutate the source/evaluation model.

`Curve3D` consumes an implicit intersection through its immutable certification
contract. Construction and decoding prove the graph; numerical preparation and
point evaluation check the requested tolerance, without recursively replaying
the graph proof through nested blend supports. Explicit certificate validation
remains available for audits. Stricter tolerances are still rejected.

Implicit curve differentiation shares one second-order solve and dual-surface
residual checks. Position/tangent/curvature consumers request only second order;
the third-order API extends that solve with the cubic terms. Nested rolling-ball
supports must not compute third-order rails for a second-order request. The
lower-order result has no third-derivative field, rather than a fabricated zero.

Prepared surface enclosures own the coordinates that can resolve recoverable
regularity failures. Rolling-ball contact radials, weights and their derivatives
depend on U only; subdividing V cannot repair those bounds. Other supports,
including offsets whose normal regularity depends on both axes, permit both axes.
Completeness maps these local coordinates to the corresponding surface of the
four-dimensional search; it never spends refinement on unrelated coordinates.
Root admission, interval bounds and resource limits remain unchanged.

Implicit graph point refinement continues through sub-tolerance residuals until
floating-point progress stops. At stagnation or the iteration limit, both the
spatial residual and the Newton correction relative to the cell's parameter
spans must satisfy the requested tolerance. Stopping on spatial residual alone
introduces evaluation noise that prevents a surrounding blend's Newton solve
from converging. The iteration/line-search limits and typed failure are retained.

## Failure, Concurrency, and Constraints

Invalid coordinates, vector lengths, angular spans, wrong surfaces, and
out-of-domain parameters throw typed geometry errors. Representational
tolerance is bounded to the operation's mathematical scale and cannot accept
nonfinite or degenerate data.

## Verification and Change Impact

General curve/surface correspondence for an implicit intersection uses its
existing certified spatial derivative enclosure. A B-spline pcurve is not
rejected merely for differing from the intersection's native UV representation;
it must pass the same bounded spatial correspondence proof, including reversed
trims and rejection of displaced curves. This does not waive chart ownership
for native certified pcurves or imply successful machining reconstruction.

`CertifiedImplicitIntersectionCurve.transferredParameterCurve` constructs a
cubic UV candidate on a finite target chart, partitioned at the certified graph
cells. Each cell supplies its own one-sided endpoint derivatives; derivative
scales from adjacent cells are not mixed. Candidate controls are restricted to
the target chart, then the existing spatial correspondence validator must
certify the complete original implicit edge against that target. Clamping or
sampling alone never admits a transfer. The caller supplies span and proof
budgets; unsupported charts, exhausted budgets and failed correspondence throw.
Original face geometry and the implicit spatial edge remain unchanged.
On geometric correspondence refusal, the candidate doubles subdivisions within
each original graph cell, subject to the span limit. One-sided derivatives stay
within their owning cell. Each attempt has the supplied correspondence proof
budget; at most `1 + floor(log2(maximumSpanCount / cellCount))` attempts occur.
Other failures propagate immediately; no uncertified candidate is returned.

Gauge root refinement requires both spatial residual admission and a Newton
correction within the normalized parameter tolerance. A small spatial residual
alone cannot establish an accurate boundary parameter on a small-scale surface.
Iteration exhaustion returns no root; the caller retains failure ownership.
Implicit graph point refinement requests only first-order surface jets for
its Jacobian and positions for line-search acceptance. Curvature is computed
only by differential consumers, not by numerical point refinement.

`BSplineSurface3D.continuedBezierSupport` constructs a temporary continuation
of one clamped rational Bezier chart over a containing parameter rectangle.
It does not replace source faces. Homogeneous de Casteljau/blossom evaluation
uses outward arithmetic; positive denominator controls and a whole-domain
stored-surface error bound are mandatory. The returned error is charged to the
caller's allowance. Non-Bezier inputs, poles, nonfinite results and exhausted
allowances fail explicitly. Original UV coordinates are retained, and the
original surface remains the authority for retained face geometry.

Surface-lift derivative ranges reuse the differential encloser's direct
coordinate jet when available. The magnitude-bound path remains for unsupported
parameter representations; calling the public enclosure from that fallback
would recurse through the derivative resolver and is not permitted.
For implicit pcurves, the existing operation-owned prepared curve retains the
immutable implicit jet encloser through offset-image and periodic-translation
wrappers. Each interval still evaluates its own bounds; preparation is tied to
that exact curve and does not outlive the requesting operation.

Curve-surface root-certification sessions retain a `ValidatedCurve3D` for
midpoint and boundary-witness evaluation. Full curve admission occurs once at
session preparation, not once per subdivision cell. Calls with a different
tolerance revalidate at that tolerance; parameter-domain checks remain active.

Adaptive curve-surface cells reuse the derivative range computed with their
curve bounding jet. Surface-only subdivision retains both immutable bounds;
curve subdivision drops both. Recentered witness cells recompute their bounds.
The pending-cell budget also bounds retained derivative storage; no shared cache
or mutable session state is introduced.

Implicit curve-surface searches partition at the stored graph-cell boundaries
before reusing second-derivative magnitude bounds. Inside each smooth cell,
the existing midpoint/Taylor position and derivative bounds replace repeated
third-order interval construction. Bounds never propagate across graph-cell
parameterization changes. Initial cells count against the search budget;
admission and failure conditions remain those of the root certifier.

Completeness search may align subdivisions to a certified atlas cell only when
the search box intersects that cell in every parameter coordinate. Disjoint
cells cannot cover any part of the box; their boundaries must not multiply its
subdivisions. This changes search ordering only, not exclusion or coverage proof.
Among intersecting cells, subdivision boundaries come from the single cell
with the greatest normalized overlap. Combining boundaries of unrelated cells
into a Cartesian partition is unnecessary; uncovered children still undergo
the same exclusion, contraction, and coverage proofs.

Prepared B-spline differential enclosers own immutable homogeneous derivative
control nets through third order for each Bezier span. Preparation occurs once
per surface operation; requested boxes only restrict those same nets. The direct
path prepares transiently and follows identical interval arithmetic. No result
cache, shared mutation, tolerance change, or cross-request lifetime is introduced.
Prepared/direct interval equality, disjoint successive boxes and invalid span
rejection verify this reuse contract.

Rational interval jets use a stored control point as a local spatial origin.
Control-point subtraction occurs inside outward interval arithmetic before
homogeneous weighting. Only the position jet restores that constant origin;
derivatives retain translation-invariant local coordinates. This removes
world-origin dependent cancellation without changing surfaces or tolerance.
Translation regression and point/derivative containment checks own this contract.

When weights are identical across rows and a coordinate is constant within each
row, that coordinate's common rational profile factor cancels exactly. The
transposed condition handles column-only coordinates. Preparation recognizes
only exact stored equality and retains the resulting polynomial derivative net;
other coordinates keep the rational path. This is not a fitted approximation.
An already-clamped single Bezier span retains its original controls and weights
during decomposition; reconstructing them through floating-point derivatives
would unnecessarily destroy these exact stored relationships.

Curve decomposition preserves existing Bezier spans, including composite curves
whose span boundaries have at least degree-fold knot multiplicity,
after source validation. Trimming preserves source endpoint controls and weights
at unchanged bounds; only newly created endpoints are evaluated by subdivision.
The contract is exact stored identity, not tolerance-based snapping. Rational,
non-clamped and partial-domain regression checks remain in BSplineCurveTrimmingTests.

Rational seam-normal comparison removes the common positive homogeneous weight
factor before polynomial products. The reduced numerator
`W*(Pu cross Pv) - Wv*(Pu cross P) - Wu*(P cross Pv)` preserves normal direction
and uses the existing product-degree limit without widening tolerances.
Rational cubic smooth and creased seams are covered by `BSplineBoundaryNormalTests`.

Isoparametric single-Bezier B-spline boundary normals are compared through the
existing correlated Bernstein product owner. The result bounds the sine of the
angle between tangent planes over the entire normalized boundary, with explicit
second-boundary reversal. Polynomial patches use unweighted tangent numerators;
rational patches retain homogeneous numerators. The existing product-degree
ceiling is unchanged. A missing bound means unresolved capability or regularity,
never proof of a crease. Callers must separately establish shared-boundary
position and topology; this calculation neither changes nor joins surfaces.

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

### Plane / isoparametric B-spline intersections

When the weighted signed-distance control coefficients are identical along one surface parameter, `PlaneBSplineIsoparametricIntersector` reduces the complete intersection problem to the existing certified curve/plane root solver. Each root yields the exact surface isocurve and its constant-parameter pcurve, verified by `SurfaceSurfaceIntersectionVerifier`. Other surfaces retain the general analytic/B-spline solver. The mirror sheet-cut regression exercises this dispatch with an interior curved-sheet section.
