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

[OriginalCurveSurfaceCorrespondence](OriginalCurveSurfaceCorrespondence/DESIGN.md)
owns strict source-bound whole-interval spatial/pcurve/support deviation receipts
for its explicitly admitted original native families. Its requested physical
bound is separate from legacy structural correspondence admission.

[OriginalGraphBand](OriginalGraphBand/DESIGN.md) owns bounded mesh-only original
rational graph certificates and retained join uncertainty; it does not heal
source pcurves or assert exact UV closure.

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
| [StructuralGeometryWork](StructuralGeometryWork/DESIGN.md) | child | Precharged original structural geometry payload traversal | Supplies package-only cost admission for source-signature comparison/hash | Consumers own the work allowance; no geometry validation, equality or tolerance policy changes |
| [KnotRemoval](KnotRemoval/DESIGN.md) | child | Bounded immutable knot reduction with full-domain deviation evidence | Owns G3 curve and tensor-axis reduction | Sampling is not a reduction certificate |
| [CurveSurfaceOverlap](CurveSurfaceOverlap/DESIGN.md) | child | Complete isolated points and certified continuous intervals | Owns G4 whole-span membership, clipping and correspondence | Unknown membership or incomplete clipping cannot publish a partial result |
| [GeometryConversion](GeometryConversion/DESIGN.md) | child | Same-chart approximation and continuous error admission | Owns G6 source protocols, candidates and certificates | Point-only mapped consumers still require migration |
| [SurfaceAreaIntegration](SurfaceAreaIntegration/DESIGN.md) | child | Certified area-density/moment and original trim root/jet enclosures | Supplies geometry evidence to CADTopology integration | Nonlinear implicit consumers must provide their own cumulative work callback; derivative order must be valid for the concrete representation |
| [Periodic B-spline](PeriodicBSpline/DESIGN.md) | child | Cyclic curve/surface representation and parameter evaluation | Owns G1/G2 periodic axes and fundamental origins | Downstream closure and editing require separate behavioral evidence |
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

For correspondence against an original B-spline curve, a finite per-Bezier-span
second-derivative maximum is not a Taylor certificate across an interior native
knot whose multiplicity reaches the degree. Such a derivative jump makes the
second-order certificate unavailable on that requested spatial interval.
Both global and adaptive local Taylor admission must respect this restriction;
local cache keys use the actual adaptive interval when a global smooth-span
certificate is unavailable. Continuous positive-weight piecewise B-spline curves
may instead use the existing first-order Lipschitz path with an outward maximum
of the original Bezier-span first-derivative magnitudes. This changes neither
monotone projection semantics nor the single caller-owned cell/depth ceilings.
A literal degree-one narrow knot bulge exceeding the caller's maximum deviation
must be rejected; below-limit, reversed, boundary, invalid-continuity and resource
fixtures verify the admitted path. Refit composition must pass the same proof
before keeping an original boundary edge. Scalar native B-spline
bounds do not admit translated periodic cycles or seam endpoints without a
separate derivative cover; unavailable bounds never authorize correspondence.


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
Uniform stored B-spline surface weights across the complete owning native basis
support authorize an exact constant homogeneous denominator on that span.
Native first/second jets classify the complete local support; the existing full-net
point evaluator classifies global equality during its current weight reads. Both
retain the original constant denominator, and jets retain its zero derivatives,
instead of re-estimating them from rounded basis partition sums. Original
coordinate numerators, periodic mapping and genuinely unequal active rational
weights retain their existing owners. This matches the interval
owner's exact constant-weight authority and prevents a linear native axis from
acquiring artificial second derivatives. Native periodic strip fixtures on both
axes and nonunit uniform weights compare independent positions, native jets and
interval containment. Stored weights remain mutable source input, so any uniform
classification must be recomputed from the current owning basis support or carried
by a validated immutable preparation; a stale classification cannot be reused.

B-spline inverse projection refines candidate stationary points to the same
parameter resolution used to distinguish roots. A small world-space residual
or gradient alone is insufficient for small-scale surfaces. The stationary
exit requires a finite positive-definite original distance Hessian and its
undamped Newton correction, projected into the owned bounds, within each axis's
existing deduplication resolution. A small damped step alone cannot authorize
that exit. The original iteration budget and failure behavior remain bounded.
Self-overlapping surfaces retain explicit ambiguous-selection failure; no
distance-based root merging replaces parameter uniqueness. Native fixtures
cover a scaled boundary root and distinct regular roots; periodic leaf and
seam authority retain their separate certificates.

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

For the bounded nonlinear Q3 dependency, a prepared implicit parameter
localizer admits one open original graph cell between two smooth clamped
nonperiodic single-Bezier-span B-spline surfaces with finite positive weights.
Equal or unequal weights retain their original rational quotient jet authority;
admission never substitutes an equal-weight chart. The original full-graph certificate alone owns
existence and uniqueness. Preparation retains that owner, source surfaces,
cell index, original direction and normalized fraction mapping. A closed query
interval may have zero width. Numeric point evaluations provide seeds only;
every returned parameter enclosure follows from outward Krawczyk images
intersected with the known root box. Original surface-span owners provide all
closed-box derivatives; subdivision cannot replace their basis or authority.

For Q3 endpoint composition, the Krawczyk residual is enclosed at the exact
four-coordinate center using original closed-point surface jets, then extended
over the free-coordinate interval by its full-box Jacobian column and outward
free displacement. The mean-value segment stays inside the known convex box.
This encloses every residual at fixed dependent centers without a mixed
point/interval conditioning floor. The same full-box dependent columns,
preconditioner, original root identity and caller-visible step own contraction;
no numeric point solver or new root-existence claim is introduced. Independent
partial endpoint fixtures must contain their exact native answers within the
existing 64-ulp loop-connection requirement before Q3 consumes these bounds. The
original Bernstein point owner also intersects each outward scalar evaluation
with its original normalized coefficient convex hull, including differentiated
nets. Both contain the exact value, so this removes false constant-weight
dependency without changing span scaling or introducing sampled authority. An
empty intersection is a typed contradiction; unequal-weight point fixtures
retain independently derived quotient jets through order three. Original native
point normalization may become a singleton only when an exact expansion proves
the original offset equals the candidate times the original exact span. Every
nonzero product operand is normal, has splitter exponent headroom, and keeps
its lowest possible 104-bit product term normal. Unsafe products retain the
established outward ratio; finite rounded equality alone is not proof. The
subnormal point fixture verifies value and derivative containment on that route.
A closed normalized fraction0/1 retains the exact stored original native
free-coordinate endpoint, including the original direction. Interior fractions
still use the outward affine range. Endpoint identity supplies only the free
coordinate; dependent roots and jets still require the same original certified
localization and caller work. It is not an approximate root seed or tolerance
clamp. Independent whole-endpoint cases require exact native free identity,
dependent containment and the unchanged 64-ulp connection precision.

The localizer exposes a bounded prepare step and one contraction step per
advance. Its state and result distinguish contraction, enclosed parameter jets
through order three, and required caller subdivision. It neither recertifies
existence nor recursively refines, allocates a private work allowance, widens a
query to modeling tolerance, or treats an unresolved dependent minor as success.
A nonzero-width range state may advance through bounded range/lower-endpoint/
upper-endpoint phases while retaining its original closed fraction and range
root box. Each advance performs at most one Krawczyk contraction or one bounded
phase transition, visible to the same caller work counter. Endpoint states are
mapped from the original normalized fractions and native direction into the
already-known range root box; they retain the original existence/uniqueness
owner. When a coordinate's certified range first derivative excludes zero,
its extrema belong to the two endpoints. Only outward endpoint root jets may
then replace that coordinate's value with their hull intersected with its range
value. Nonmonotone coordinates retain their range bounds. Range derivative jets
are retained unchanged, and zero-width queries use the direct point path.
Numeric endpoint evaluation never authorizes this contraction. Endpoint phases
have no internal loop, extra work allowance or independent depth budget.
First derivatives are solved from the localized Jacobian; higher derivatives
use the same local surface jets. Original cell-count, native-span powers and
direction enter the chain rule exactly once. Invalid or foreign state,
nonfinite arithmetic and cancellation remain typed failures. A caller charges
preparation and every advance to its own aggregate work counter; inability to
make certified progress requests caller-owned subdivision under its existing
depth bound. Independent point and interval oracles for a dyadic plane/parabola
intersection reject fixed parent derivative widths and closed-point refusal.
This contract does not establish general joins, closed curves, mixed charts,
knot collars or procedural surfaces. Existing implicit enclosure routes retain
their documented resolution/refinement limits until their callers adopt this
localizer; their evidence is not generalized to the new caller-budget contract.

## Failure, Concurrency, and Constraints

Invalid coordinates, vector lengths, angular spans, wrong surfaces, and
out-of-domain parameters throw typed geometry errors. Representational
tolerance is bounded to the operation's mathematical scale and cannot accept
nonfinite or degenerate data.

### Retained Original Implicit Root Restriction

The existing opaque `ImplicitCurveIntervalJetEncloser.ParameterEnclosureState`
retains original intersection, cell, tolerance, closed source interval and a
four-coordinate root cover. Every existing contraction retains all certified
original roots; endpoint phases additionally save the whole parent `rangeBox`.
A new package overload `prepareParameterEnclosure(restricting:
overClosedInterval:tolerance:)` may initialize a child only after exact
prepared-intersection/cell/tolerance checks and closed child containment. It
uses the existing original native free-coordinate mapping and intersects it
with the parent's whole cover. In a range phase this is `parameterBox`; in
either endpoint phase it is the saved whole `rangeBox`, never the endpoint
point box. Actual singleton phase traces show that this cover alone retains
the same dependent coordinate widths and contraction counts (28/28 forward,
29/29 reversed), so whole-cover reuse does not establish work reduction.

Only an upper-endpoint phase already retains the actual original lower-endpoint
four-coordinate jet, together with the complete parent range jet. For each
coordinate, Geometry may intersect the starting cover with the rigorous
outward Taylor enclosure
`lower.value + lower.first*delta + lower.second*delta^2/2 + range.third*delta^3/6`,
where `delta` is the outward global intersection-fraction displacement. The
retained state stores cell-local fractions: for an original `N`-cell intersection,
the local child-minus-parent displacement is divided by `N` exactly once to
match the lower jet's already global `N^order` derivative scaling. The `N=1`
arithmetic path is unchanged. The original smooth owning-cell authority and
complete range third derivative justify this remainder on the same root branch.
An explicitly supplied owning cell must equal the retained state's cell; a
restriction never transfers root authority between cells. The area child owns
[open nonlinear chain admission and value-only joins](SurfaceAreaIntegration/DESIGN.md#open-nonlinear-original-graph-chains-parq3mult1).
All four coordinate fields come from the lower owner, never a projected chart
or sampled/predicted point. The original free-coordinate mapping remains a
mandatory separate intersection. Range/lower-endpoint phases retain their
whole-cover path because they have no certified lower-endpoint jet. Empty or
nonfinite intersections are typed failure. This fixed-size initialization is
charged by the existing prepare operation and adds no solver or private budget.

The result starts the existing range phase. No root, rank, derivative, endpoint,
64ulp or success criterion is skipped: every actual prepare and advance is
charged by the existing caller. Empty intersections, nonfinite/domain/identity
errors and cancellation retain typed failure. This is root-cover continuation,
not a predicted root or reuse of an endpoint's subset as a whole parent.
The area chart must transport this opaque lower state without projecting its
role's two coordinates back into a four-coordinate box. A child singleton's
state cannot replace the containing whole-range state for sibling/grandchild
queries. All retained state has the immutable query's bounded DFS lifetime.
Independent original four-coordinate/first-third derivative fixtures must
match direct localization, preserve source/tolerance/domain/reversal refusals,
and measure actual prepare/advance fees. The Native lower suite verifies original coordinate/jet containment and charged work reduction. The bounded iso-image consumer now passes the unchanged public forward/reverse/rigid 60s tests; this evidence does not complete general implicit chart support. Geometry owns the lower state, and the area children own its exact
source-fraction mapping and invocation transport.

### Invocation-Owned Native First-Derivative Reuse

The current correspondence validator's native B-spline first-derivative helper
constructs every full native span and returns one maximum independent of the
child interval after native-domain admission. A validation invocation may retain
that same result once for its immutable source, original admitted interval and
caller tolerance. Rigid and affine source wrappers preserve this first-order
interval invariance; periodic seam/translated-cycle refusal remains unchanged.
This first-order predicate is separate from the existing second-order predicate:
second-order child restriction and its cache must keep their existing behavior.
Only the existing helper may create the retained value, including nil and typed
failure; no new decomposition, certificate, source rounding, interval
restriction, acceptance deviation, cell/depth limit or fallback is introduced.
The retained result has invocation lifetime, introduces no shared mutable state,
and child lookup does not reconstruct all derivative certificates.
The observed second-order path likewise rebuilds every native span after each
child's native-domain and interior-derivative-jump admission. It may retain the
same numerical full-native maximum per invocation through rigid/affine source
wrappers, but every child must still pass its own existing domain/jump gate
before reuse. C0 crossings remain nil; a cached value cannot authorize them.
The existing second-order global-invariance predicate and local key cache keep
their semantics. Only the first admitted child may compute the retained numeric
value with the existing helper; subsequent admitted children reuse exactly that
value. Other curve families retain their existing interval-dependent path.
The original first-order change passes17 Geometry cases1.558s but both exchange
cases still exceed60s; a bounded post-change profile locates repeated second-
order certificate construction. The final original Geometry17 declarations pass1.068s, original IGES import
passes0.283s and original STEP offset import passes3.444s under unchanged60s
limits. No acceptance, precision or domain/refusal condition was widened. The measured
IGES surface-lift import must pass its original60s test, with the existing C0
mismatch/positive/budget fixtures and STEP offset import unchanged. Geometry
owns this bounded computational correction. General exchange deadline hooks and
new cancellation API contracts remain a separate authority decision.

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
For an actual B-spline lift support, the internal prepared closed-box entry
retains the original UV jet ranges, including constant coordinates. It validates
the exact support domain and composes the original third-order chart jets;
other procedural lifts retain their existing nondegenerate-box path.
`SurfaceLiftDifferentialBounder.closedRange` retains the existing validated
source-chart domain intersection only for outward arithmetic endpoint overhang
within 64 machine epsilons at the support-domain scale. A disjoint range or
larger overhang fails as invalid input. It adds no modeling-tolerance domain
permission or enlargement. The prepared point entry itself validates strictly.

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
control nets through third order for each Bezier span. Stored finite positive
weights enter this arithmetic boundary as exact singleton inputs, just like
stored Cartesian coordinates. Outward rounding begins at subtraction and
homogeneous multiplication; preparation does not invent independent uncertainty
in a model weight. A decomposed or trimmed patch remains the stored patch model
it supplies; this input rule adds no guarantee about upstream conversion error.
Preparation occurs once per surface operation; requested boxes only restrict those same nets. The direct
path prepares transiently and follows identical interval arithmetic. No result
cache, shared mutation, tolerance change, or cross-request lifetime is introduced.
Public surface boxes continue to require positive U/V widths. The internal
`intervalJet(overClosedBox:tolerance:)` additionally admits zero-width axes;
`pointJet(u:v:tolerance:)` evaluates a requested point. Both retain every owning
native span and the existing conservative periodic representative coverage.
At a native knot, all containing spans contribute their one-sided jets; the
consumer owns derivative-identity admission. Interval localization conditions
only with its existing machine-resolution pad, not modeling-tolerance widths.
Point localization evaluates each already differentiated homogeneous net by
outward tensor de Casteljau using original finite positive span widths and exact
0/1 endpoint coordinates. It never divides by a newly shortened remaining span.
Weight reciprocals require a positive complete enclosure; nonfinite arithmetic,
invalid domains and unresolved numerical conditioning fail explicitly. A
periodic point with a nonzero representative uncertainty retains a closed-box
range proof rather than pretending its rounded representative is exact.
Prepared/direct interval equality, disjoint successive boxes and invalid span
rejection verify this reuse contract. Curve Bernstein derivative evaluation
intersects interval de Casteljau bounds with the coefficient convex hull only
after the requested patch interval proves that its exact normalized parameters
lie in [0,1]. This removes artificial dependency width for constant derivatives;
an empty intersection is an explicit numerical failure. G6's exact line
certificate and the existing rational curve jet containment tests own regression
evidence for this shared bound.
[`PreparedBSplineSurfacePointJetTests`](../../Tests/CADGeometryTests/PreparedBSplineSurfacePointJetTests.swift)
owns independent polynomial and rational quotient value/third-order derivative
oracles on original knot coordinates, endpoint and knot-point coverage,
narrow-box convergence, periodic point/seam coverage and strict invalid-domain
failures. Topology's B-spline-lift ruled rectangle test owns the unchanged public
area/centroid/default-budget regression.
Periodic tensors use the base-cache, seam mapping and smoothness contracts owned
by [Periodic B-spline](PeriodicBSpline/DESIGN.md#prepared-tensor-bounds-and-projection).
Their chosen origins affect query representatives rather than cached ownership.

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

### Original native-span tessellation authority (PAR.M1R3)

The bounded nonperiodic clamped positive-weight C0 rectangle extension uses
the independently verified selected-span contract. Geometry owns immutable authority
for one original nonempty native U/V knot-span pair. The prepared owner mints
it only from its original validated surface/decomposition and retains original
span indices, exact native bounds and preparation tolerance. Its closed-box
and point jets select only that owning polynomial/rational span, including its
one-sided endpoint limits. A request outside that span, with another support
or preparation tolerance, fails explicitly. Existing all-owning closed-box and
point-jet APIs keep their union semantics at knots.

Original selected-span basis derivatives evaluate the actual knot endpoint,
without epsilon shifts or trimmed/reconstructed support. One-sided normals
are computed from the same original native homogeneous controls and the
existing strict regularity law. The ordinary right-selected public normal and
parameter-derivative APIs retain their semantics. The token cannot be minted
by Kernel and does not expose mutable prepared patches.

| Contract | Assumption | Guarantee / refusal |
|---|---|---|
| Original span factory | Valid nonperiodic clamped positive-weight surface and actual nonempty native knot intervals | Immutable original ownership; no synthetic or neighboring span |
| One-sided closed jet / normal | Finite ordered request within retained span, same preparation tolerance | Entire requested one-sided value/derivative enclosure or typed failure |
| Tessellation bounds | Retained original span and existing normal-conditioning law | Finite regular tangent/Hessian/normal-path bounds; unresolved regularity refuses |
| Aggregate proof work | One rectangle invocation | Existing depth32/cell262144 ceiling shared across all original spans, never reset per span |

Subdivision consumes the selected-span enclosure throughout; it must not call
an all-owning knot jet during a one-sided proof. Cancellation checkpoints
surround preparation and occur during bounded span/cell traversal. There is no
new hard cancellation response-time guarantee. Singular geometry, nonfinite
arithmetic and exhausted work retain explicit typed failures.

CADKernel consumes these immutable contracts for grid composition; it owns
mesh counts, storage and topology provenance. Geometry tests own literal
left/right degree-one and degree-two knot derivatives, U/V transpose and
four-sided tensor-corner jets, original support/tolerance/domain refusal,
aggregate work and cancellation. Kernel's public fidelity fixtures own the
actual mesh behavior. Six original Geometry declarations/11cases pass, including
one-sided rational/linear/quadratic/corner and aggregate-budget/cancellation
refusal. Changing basis selection requires existing sparse-basis,
prepared all-owning jet and surface differential regressions.

### Original homogeneous extraction enclosure (PAR.ORIGJET1)

The literal original Greville tensor `S=(u,v,u*v)` exposes a concrete lower
failure: at U/V `[0.3103448275862068,0.3103448275862069]`, a prepared jet
returns `X_V=[1.1122032083287393e-17,8.158357065688177e-17]`, excluding
its original exact zero. Differential preparation must therefore retain
outward original homogeneous coefficient authority, rather than interpreting
a rounded Double Bezier extraction and Cartesian quotient as exact geometry.
The unchanged literal RED reported56 value/derivative containment violations;
the corrected producer passes the original Greville, rational quotient,
incident-knot, source/tolerance/domain and cancellation fixtures. The prepared
surface owner and all86 G4/continuous-overlap declarations also pass on the
same original homogeneous implementation.

For nonperiodic original native spans, the differential-only producer encloses
basis derivatives, original homogeneous accumulation and native Taylor-to-
Bernstein scales with directed interval arithmetic. Stored controls/knots/
weights are exact singleton inputs. Native knot differences and derivative
scale denominators are enclosed before division; no rounded span width is
reinterpreted as exact. Prepared raw jets consume the homogeneous interval
net directly, with an original stored origin, without Cartesian quotient
roundtrip. Exact original single-Bezier inputs retain their current direct
path. The public Double geometry decomposition keeps its separate construction
contract and supplies no proof authority to this new path.

Original common positive owning weights may use partition of unity to retain
an exact constant denominator and zero denominator derivatives. Optimizations
must be justified by original control/basis identities, never by approximate
extracted-net equality. Nonuniform positive weights retain the complete
rational denominator and its finite positive enclosure. Empty/inconsistent
jet intersections remain failures at their consumers.

The prepared owner alone mints an immutable original native-span token,
retaining source, preparation tolerance, original U/V span indices and full
native bounds. Its closed-box/point jet selects only that span; all-owning
nonperiodic requests union every incident original span, including zero-width
knot ownership. C0 tessellation consumes these same selected-span tokens;
ordinary right-selected scalar basis behavior remains unchanged. A separately
validated internal selected-span scalar derivative entry supports original
one-sided normals without shifting UV or reconstructing geometry.

| Invariant | Rejection evidence |
|---|---|
| Original coefficient/derivative containment | Literal Greville position and derivatives, exact zero/one/mixed fields at the actual failing closed box and point |
| Native span ownership | Left/right knot jets and token source/tolerance/domain refusal |
| Existing consumers | All-owning prepared/surface differential/basis, G4 original endpoint/knot/rational graph and existing periodic route regressions |
| Resource/lifecycle | Existing preparation limits and query proof fees retained; immutable per-invocation storage, finite arithmetic, cancellation and typed failure |

Periodic preparation remains on its existing separate original-cycle route;
this nonperiodic correction does not establish new periodic extraction
provenance or full-G4/M1 completion. G4 and C0 owner designs consume this
contract and must not separately repair rounded output fields or mint
independent competing original-span authority.

The corrective package contract is
`PreparedBSplineSurfaceDifferentialEncloser.OriginalNativeSpan`, minted by
`originalNativeSpans(over:tolerance:)`. Immutable fields retain the original
surface/tolerance, original native `uSpanIndex`/`vSpanIndex`, and full
`uBounds`/`vBounds`. A span index is the original knot interval index with
`degree <= index < controlCount` and `knots[index] < knots[index+1]`.
All incident spans are retained for a nonempty closed intersection, including
constant-UV and knot-point requests. Periodic requests cannot mint this new
token; their existing prepared route retains its separate contract.
Internal token `validate(on:over:tolerance:)`,
`intervalJet(overClosedBox:on:tolerance:)` and `pointJet(u:v:on:tolerance:)`
check exact source/tolerance and closed native containment. Raw storage and
minting remain private; Kernel receives no jet or patch mutation authority.
The checked internal scalar `BSplineBasis.nonzeroDerivativeValues` overload
adds `owningSpan` and caller `tolerance`; its selected side remains fixed at
actual closed endpoints. The lower-only outward derivative overload shares
native-index validation and provides original coefficient authority.

The C0 aggregate bounds owner also exposes a Geometry-internal overload with
an explicitly lowerable cell ceiling for focused contract verification.
`maximumCellCount` must be in `1...262144`; the package entry always delegates
with the existing262144 ceiling and existing depth32. The same production
traversal owns and charges all panels for either entry, never a separate test
algorithm. Two independent regular linear panels with ceiling1 must exhaust
work and ceiling2 must succeed, detecting a per-panel reset. This internal
control cannot increase the resource ceiling or change regularity/fidelity.

### Original Periodic Homogeneous Preparation (PAR.ORIGJET2)

The original cyclic surface stores its tail controls and weights explicitly.
For cycle counts n/m and degree p/q, stored counts are n+p/m+q. Existing
periodicity validation checks exact repeated tail coefficients; ordinary basis
evaluation consumes this stored original net. Therefore the same directed
native-span producer may enumerate `(p..<storedUCount)` and
`(q..<storedVCount)` and form their nonempty Cartesian span product using
original knots/controls/weights. It requires no virtual net, modulo owner,
Cartesian Double trimming, new basis implementation or reconstructed support.

The periodic prepared branch must consume these original outward homogeneous
patches directly. Conservative independent U/V wrapped interval covers and
the union of every Cartesian piece retain their existing contract. Original
common-weight partition-of-unity, exact native differences, derivative scaling,
finite/count/workspace/cancellation and immutable invocation lifetime remain
mandatory. Nonperiodic preparation and all-owning knot semantics are unchanged.
The package selected `OriginalNativeSpan` factory continues to refuse periodic
surfaces; this sprint grants no one-sided periodic/C0 seam normal authority.

| Owner | Assumption | Guarantee / evidence |
|---|---|---|
| Original producer | Valid original cyclic stored knot/control/weight net | Outward value and first/second/third original native derivatives on each span |
| Prepared periodic consumer | Original homogeneous patches and conservative independent axis covers | Complete union through one/both seams, shifted boxes, closed points and whole cycles |
| Public consumers | Same original geometry/tolerance and typed failure contract | Existing periodic jet/projection/tessellation/persistence regressions preserve behavior |

Independent cardinal periodic tensor fixtures must verify original analytic
positions and first-through-third derivatives for single axes, both axes,
seam endpoints/crossing and non-dyadic local boxes; rational original quotient
fixtures must detect loss of weight authority. Existing source/domain/count/nonfinite/cancellation failure and valid caller
ModelingTolerance semantics remain explicit. Whole prepared queries gain no
periodic-only exact preparation-tolerance restriction; selected native tokens
keep their separately defined exact tolerance ownership. Actual Native evidence passes all5 declarations/9 cases through the original cardinal polynomial and rational quotient oracles, plus27 existing Geometry, two periodic Mesh and one Native persistence declarations. The polynomial oracle uses its exact partition of unity and zero third derivative rather than rounded denominator recurrence. Portable evidence remains separately owned.

This preparation change does not strengthen current approximate knot-translation
validation into exact mathematical seam continuity. A future new double-C1
mesh admission must separately prove exact original translated knot differences
on both axes and apply each original period-width TwoDifference check. Existing
single-periodic semantics are not silently changed by this lower scope.

### Original Double-Periodic C1 Mesh Admission (PAR.M1R4)

Geometry owns the new double-periodic C1 admission before existing whole-span
`tessellationBounds` is consumed. Both stored axes must prove finite positive
period `K[N]-K[p]` with zero error-free TwoDifference residual; each stored
translation `K[i+n]-K[i]`, n=N-p, must prove this same exact period by zero
residual rather than a rounded addition comparison. Every seam/internal knot
multiplicity must be at most p-1. Existing validation retains exact original
U/V control/weight tails, including tensor corners, and positive weights.
These original homogeneous conditions prove position/first-derivative seam
continuity; second-derivative continuity is not assumed. Approximate periodic
source validation alone supplies no new authority.

The original homogeneous lower owns first-through-third whole periodic bounds;
this admission does not mint periodic selected-side tokens or reconstruct a
support. Existing finite, regularity, invocation-local cell/depth limits and
cancellation remain unchanged. Independent literal cardinal tensor Geometry
and public Mesh fixtures must reject approximate translated knots, C0 seams,
malformed tails, nonfinite/resource conditions and cancellation, and verify
original position, normal and both-seam covers. Single-periodic semantics remain
unchanged; Native runtime is required before this new admission is complete.

Native verification passes Geometry five declarations/thirteen parameter cases
and Kernel five declarations/sixteen parameter cases, plus forty-three existing
Kernel tessellation tests and six original native-span Geometry tests. Literal
source positions/normals, both seam identities, full periods, exact-width refusal,
aggregate reservations and cancellation execute through the original production
path. Full M1 and portable closure remain separately owned.


### Original Prepared Point-Value Evaluation (PAR.POINTVALUE1)

The original implicit localizer uses exact-center source values only for its
Cartesian residual; its original range jets still own Jacobian, root existence,
rank, contraction and final first-through-third derivatives. A point-value path
may therefore return only IntervalVector3DBounds and must not construct a
synthetic full jet with missing or zero higher derivatives.

RationalBezierSurfaceJetEncloser owns shared exact/outward normalization and
Bernstein evaluation/hull intersection of original prepared coefficient nets.
Both point consumers reuse the same value operation order. The value-only path
evaluates the original value net and each existing polynomial-coordinate value
net only; it preserves original common-positive-weight authority or the same
outward reciprocal and Cartesian origin addition. Finite values and positive
weight are mandatory; unavailable value authority fails explicitly. A point-only
value contract does not promise finite unrequested higher derivatives.

PreparedBSplineSurfaceDifferentialEncloser validates finite point/domain,
original preparation tolerance and cancellation, applies the existing periodic
lift covers, and unions values from every original closed owning native span,
including knot sides/seams. PreparedSurfaceDifferentialEncloser delegates only
its existing B-spline storage to that owner; other representations retain typed
unsupported closed-point composition. No source replacement, resampled support,
new root criterion, budget or global cache is introduced.

The implicit exact-center residual consumes these values. Its range/full/final
jets, phase transitions, free-coordinate mean-value segment and every caller
prepare/advance fee remain unchanged. Independent original polynomial/rational,
unequal-weight, translated, native-knot and periodic fixtures compare point-value
bounds bit for bit with successful original full point jets; invalid domain,
foreign preparation tolerance, cancellation and unresolved finite weight refuse.
Original implicit four-coordinate existence, derivative, endpoint64ulp and actual
work oracles are required. Public Q3 area/centroid performance remains a separate
completion gate; this lower contract alone makes no speed/completion claim.


### Scale-Aware Original Principal Direction Candidate (PAR.CL9L1)

The original B-spline differential geometry principal-direction candidate is a
product of shape-operator row coefficients and original tangent vectors. Its
finite refusal threshold scales with their actual maximum magnitudes, existing
relative tolerance and binary64 rounding, without an arbitrary unit floor on
those factors. Existing curvature-gap/umbilic handling, finite candidate and
unit-direction checks remain unchanged. Independent metre-scale non-umbilic
fixtures must establish valid finite principal axes and rescaling invariance;
near-umbilic fallback and unresolvable/singular candidates must retain explicit
failure. This lower change does not authorize a sampled fitted Draft law.

### Immutable Interval Vector Composition

`IntervalVector3DBounds` owns immutable three-coordinate outward interval arithmetic and norm bounds. Its package initializer retains the supplied scalar intervals verbatim so modeling admission can compose these bounds without duplicating geometry arithmetic. Construction creates no finite/regularity certificate: consumers remain responsible for finite, tangent and residual acceptance. Stored components and Sendable/value ownership are identical on every target; no state, synchronization or numerical rule changes. PolySpline admission tests execute the shared interval norm owner through the actual modeling producer.


Native position-only Rebuild publication uses [Geometry Conversion](GeometryConversion/DESIGN.md#native-position-only-surface-publication-parg6pos1). Original prepared B-spline differential cost belongs to its native preparation owner; the new position certifier charges both supports and every probe before use. Native lower and public behavior are verified; portable closure remains task integration. This path does not extend common three-field conversion or procedural continuation authority.

The separately explicit [original polynomial continuation position contract](GeometryConversion/DESIGN.md#original-polynomial-continuation-position-parg6cont1l) belongs to the same Geometry Conversion child. It composes original stored single-Bezier polynomial laws on a shared native rectangle and supplies evidence to tolerance Rebuild; it preserves the contained certifier and does not establish general rational, periodic or procedural continuation. The lower14 declarations/16 cases have Native evidence; public consumer and portable integration remain separate task owners.


### Original Periodic C0 Selected Span Authority (PAR.M1PC1)

The original prepared B-spline owner extends its selected-native-span contract to connected rectangles crossing at most one exact represented period in each periodic axis. A periodic span token retains the original immutable source/tolerance, original base span indices and closed bounds plus explicit U/V cycle translation and corresponding lifted requested bounds. Translation is proved from the original stored period/knots; an approximate knot shift, unrepresentable lift or inconsistent token cannot be admitted by epsilon or ordinary periodic normalization. Requested widths retain the existing exact TwoDifference period-excess refusal. Open axes retain clamped admission. Existing original cyclic homogeneous patches, positive weights, exact position-continuous tails and both closed owning sides supply geometry; no copied/trimmed replacement surface is authority. Ordinary all-owning enclosures and ordinary public normal retain their existing semantics.

The selected normal/derivative path verifies the complete original token and query inclusion, resolves a lifted native station to its proven original base station and evaluates that explicitly selected original span without canonical-right normalization. Thus the lifted seam upper/left owner is not silently evaluated on the lower/right span. Enclosures cover each actual original positive span, retain native derivative scaling and finite regular one-sided frames, and reject discontinuous or invalid source/tolerance/lift authority. Original aggregate preparation/proof budgets and cancellation are retained; checked span/lift enumeration and allocation charge before execution. Immutable source and token ownership are identical on all targets. Independent degree-one diamond cycles and double periodic bilinear diamond tensors prove positions/tangents/normals on base, negative/positive seam-crossing, shifted and full-cycle boxes, including both closed seam/corner sides. Invalid tails/translation, exact period excess, singularity, foreign source/tolerance/lift and resource/cancel refuse explicitly. Lower behavioral evidence precedes upper periodic-C0 panel publication; full M1 and portable integration remain open.

## Original Closed Native Curve Jets

`PreparedCurveDifferentialEncloser.closedNativeJets(over:tolerance:consumeWork:)`
owns an immutable original B-spline, its preparation tolerance and all closed
native span receipts. `RationalBezierCurveJetEncloser.originalNativeSpans`
forms outward homogeneous Bernstein coefficients from the original selected
`BSplineBasis.nonzeroIntervalDerivativeValues` and stored controls/weights.
Degree-fold isolated spans use the original coefficients directly. Rounded
Cartesian Bezier extraction, insertion and trimming are not proof inputs.

Each returned `ClosedNativeJet.OwnedSpan` retains the original native span
index, requested closed intersection and its one-sided value/first/second/third
jet. Every touching owning side is included, including singleton knots and
domain endpoints. Derivative scaling uses the original positive knot width,
never the query width. Positive common active weights establish a constant
denominator by partition of unity. Unequal positive weights retain rational
quotient derivatives; degrees below an order establish zero homogeneous
derivatives, not zero rational derivatives.

A union of one-sided derivative ranges does not certify differentiability
across a knot. Consumers must retain individual owning spans and establish
their own continuity before applying higher-order Taylor formulas. The
existing positive-width entry remains compatible and returns their union
without adding a global smoothness guarantee. The new closed entry rejects
unsupported periodic lifts and other unadmitted curve families explicitly;
the existing periodic positive-width path is unchanged.

The one-shot nonperiodic B-spline branch delegates to this same original
prepared owner. Both positive-width entries therefore return bitwise identical
bounds, including rigid/affine composition, and retain every touching native
side. The prepared native branch invokes only the original coefficient
provider, never the one-shot dispatcher; this dependency direction prevents
recursion. The periodic one-shot branch retains its established chart path.

Preparation accepts a synchronous non-escaping caller work callback and charges
before each original span payload/basis allocation. Closed queries require
this callback and charge each actual owning-span evaluation. Repeated proof
consumers supply the same aggregate query counter to both operations. No
callback, mutable cache or private allowance is retained. Arithmetic count
overflow, finite coefficient/denominator failure, exact preparation tolerance
mismatch, invalid/disjoint domains and cancellation remain explicit failures.

Tests are owned by
[PreparedCurveClosedNativeJetTests](../../Tests/CADGeometryTests/PreparedCurveClosedNativeJetTests.swift).
The C0 three-control quarter-cylinder rails provide literal native speeds and
one-sided jets; genuinely unequal weights provide independent rational
derivatives through order three. This lower contract does not publish a
rolling-ball area result or complete the higher-order nested-offset obligation.
