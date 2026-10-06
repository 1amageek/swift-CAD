# CADGeometry

Finite selected positive-weight source-valid B-spline curve/tensor queries, including exactly represented periodic transports, are owned by [Native Point Relations](CurveSurfaceOverlap/NativePointRelations/DESIGN.md) and [Native Curve Surface Relation](CurveSurfaceOverlap/NativeRelation/DESIGN.md), children of CurveSurfaceOverlap. Their child contracts determine complete finite requested coverage and original parameter/source-chart identity.

Single-span Native SSI isolated tuples are owned by [Native Surface Surface Point Relations](NativeSurfaceSurfacePointRelations/DESIGN.md). [Native Surface Surface Relations](NativeSurfaceSurfaceRelations/DESIGN.md) owns complete original parameter, image and fiber relations for the bounded rich normal, caller-admitted, domain-pair and retained-session paths. Both consume the original source/domain and caller admission contracts; existing array entries reject positive-dimensional original coverage atomically.

Public arc-length inverse localization accepts CADCore's ScalarInterval. Its
stored closed endpoints enter internal outward arithmetic unchanged; the
package-only OutwardScalarInterval remains an implementation boundary. This
keeps the operation in the public protocol witness table on every target.
Legacy receipts that lack paid original inverse authority still fail explicitly.
Missing original curve variants in numerical projection use the existing
original-curve iterative candidate evaluator, never a fitted surrogate. Optional
intersection support lookup describes retained support metadata only, not absence
of intersections; construction charts forward their unchanged source supports.
Other new constructed variants with no retained support pair return nil and
remain subject to the general original membership producer.
Legacy third-order numerical candidates for original guide chains, guide
corrections and polylines use the retained source's D3 issuer and native limits;
these representatives do not establish source equality or intersection coverage.
Prepared surface owners validate query tolerance against their retained
preparation tolerance through a package contract; consumers do not inspect
private preparation fields. Domain transport propagates finite-interval errors.

The prepared curve owner's existing legacy closed native jet entry is available
to [Original Curve Span Coincidence](../CADModeling/OriginalCurveSpanCoincidence/DESIGN.md)
for its no-admission branch. Its caller-admitted branch uses the existing
bounded overload; the visibility repair changes neither query body nor policy.

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
curved-surface fillets, not their topology or feature publication. The
[OriginalCurveSurfaceCorrespondence](OriginalCurveSurfaceCorrespondence/DESIGN.md)
child owns whole-use source correspondence certificates for its bounded native
curve/support family.

[GeometryConversion](GeometryConversion/DESIGN.md) owns whole-domain approximation and rational conversion guarantees under caller-owned budgets.

## Responsibilities and Boundaries

This module owns the representation and structural validation of analytic
surface parameter curves, including spherical great-circle curves. It does not
own topology identity, feature lineage, evaluation orchestration, or Rupa
measurement policy.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [BSplineCurveCommonBasis](BSplineCurveCommonBasis/DESIGN.md) | child | Caller-paid original common-basis preparation | Supplies shared immutable connector images | Retain original curve laws and the same cumulative allowance |
| [SurfaceProjectionAdmission](SurfaceProjectionAdmission/DESIGN.md) | child | Whole-domain original closest-point projection with caller admission | Owns finite support inverse query coverage | Numerical witnesses carry original residual upper bounds |
| [StructuralGeometryWork](StructuralGeometryWork/DESIGN.md) | child | Precharged original structural geometry payload traversal | Supplies package-only cost admission for source-signature comparison/hash | Consumers own the work allowance; no geometry validation, equality or tolerance policy changes |
| [KnotRemoval](KnotRemoval/DESIGN.md) | child | Bounded immutable knot reduction with full-domain deviation evidence | Owns G3 curve and tensor-axis reduction | Sampling is not a reduction certificate |
| [CurveSurfaceOverlap](CurveSurfaceOverlap/DESIGN.md) | child | Complete isolated points, original native parameter relations and certified continuous intervals | Owns G4 whole-span membership, clipping and correspondence | Unknown membership or incomplete clipping cannot publish a partial result |
| [SurfaceSilhouette](SurfaceSilhouette/DESIGN.md) | child | Original normal zero-contour source and cumulative usage | Retains native source graphs for D1 drawing | Critical and coincident contour exhaustion remain lower-owned completion conditions |
| [GeometryConversion](GeometryConversion/DESIGN.md) | child | Same-chart approximation and continuous error admission | Owns G6 source protocols, candidates and certificates | Point-only mapped consumers still require migration |
| [SurfaceAreaIntegration](SurfaceAreaIntegration/DESIGN.md) | child | Certified area-density/moment and original trim root/jet enclosures | Supplies geometry evidence to CADTopology integration | Nonlinear implicit consumers must provide their own cumulative work callback; derivative order must be valid for the concrete representation |
| [Original Analytic Intersection Sources](OriginalAnalyticIntersectionSources/DESIGN.md) | child | Exact direct-authored plane, cylinder, sphere and torus pullbacks to retained original rational curves | Supplies raw equations, denominators, original frame and closed source domain | Cone coefficient authority, public UV/angular composition and whole analytic-family acceptance remain separate |
| [Original Polynomial Curve-Surface Points](OriginalPolynomialCurveSurfacePoints/DESIGN.md) | child | Complete isolated original Native curve versus ruled surface tuples and closed-domain evidence | Supplies retained original source/parameter receipts through shared public CS dispatch | Positive-dimensional and remaining procedural source composition are separate unfinished scope |
| [Native Surface Surface Relations](NativeSurfaceSurfaceRelations/DESIGN.md) | child | Complete original four-coordinate SSI relations and retained image/fiber receipts | Supplies rich publication beside isolated tuples under one caller ledger | Single-span finite closed nonperiodic Native scope; original parameter dimension is separate from image and fiber dimension |
| [Original Affine Curve-Surface Points](OriginalAffineCurveSurfacePoints/DESIGN.md) | child | Complete isolated original Native curve and rational affine-word Native surface tuples | Supplies source/word/domain receipts through shared public CS entries | Single-span finite aperiodic scope; normalized words and positive-dimensional public relations remain separate |
| [Original Affine Intersection Sources](OriginalAffineIntersectionSources/DESIGN.md) | child | Original rational forward/inverse word applied to retained Native homogeneous surface law | Retains word, source span, domains and transformed world law | Public composition and normalized algebraic words have separate acceptance; intrinsic Native law is not the transformed world law |
| [Original Ruled Intersection Sources](OriginalRuledIntersectionSources/DESIGN.md) | child | Exact original ruled homogeneous law and CS/SSI denominator-guarded equations | Retains both Native boundary sources and unchanged parameters | Public result composition and other procedural families have separate acceptance |
| [Original Coons Intersection Sources](OriginalCoonsIntersectionSources/DESIGN.md) | child | Original Coons homogeneous cell laws and bounded Native CS/SSI equation adapters | Retains original boundary maps, corners, domains and denominator guards; supplies unchanged differential consumers | Public intersection composition and general multi-chart/endpoint families retain separate acceptance |
| [Original Coons Curve-Surface Points](OriginalCoonsCurveSurfacePoints/DESIGN.md) | child | Complete isolated original Native curve and single-cell Coons tuples | Retains boundary maps, original source/domain and exact parameter correspondence through all four public CS entries | Aperiodic single-span scope; positive-dimensional and remaining Coons families retain separate acceptance |
| [Original Native Curve Chart Cover](OriginalNativeCurveChartCover/DESIGN.md) | child | Complete finite exact multi-period original curve chart issuance | Supplies retained original curve laws and closed one-sided owners | Public CS/SSI source composition and legacy prepared jet bounds have separate acceptance |
| [Original Native Surface Chart Cover](OriginalNativeSurfaceChartCover/DESIGN.md) | child | Complete finite exact multi-period intersection chart issuance | Shares original span and cycle authority with the preparation adapter | Public intersection composition and the restricted mesh issuer have separate acceptance |
| [Periodic B-spline](PeriodicBSpline/DESIGN.md) | child | Cyclic curve/surface representation and parameter evaluation | Owns G1/G2 periodic axes and fundamental origins | Downstream closure and editing require separate behavioral evidence |
| [Swift-CAD package](../../DESIGN.md) | parent | package exact-geometry contract | Places geometry below modeling and above core values. | Keep the shared predicate contract authoritative. |
| [CADModeling](../CADModeling/DESIGN.md) | used by | generated primitive pcurve values | Supplies valid sphere seam/pole curves. | Construction cannot rely on a sphere-only validation bypass. |
| [CADIR](../CADIR/DESIGN.md) | used by | signature validation | Validates retained geometry through this module. | Do not loosen Codable/signature rules independently. |
| [Involute](Involute/DESIGN.md) | child | certified flank approximation | Converts analytic involute intervals to bounded B-spline spans. | Does not own gear dimensions or root geometry. |
| [RollingBall](RollingBall/DESIGN.md) | child | local contact section | Resolves source contacts from offset-intersection correspondence. | A local section is not a certified complete blend surface. |
| [GeometryConversion](GeometryConversion/DESIGN.md) | child | certified curve/surface conversion | Owns admitted error bounds and caller-budgeted construction. | Original native-span jets remain local geometry authority; conversion does not change correspondence admission. |
| [OriginalRectangleTessellation](OriginalRectangleTessellation/DESIGN.md) | child | original nonperiodic selected-span differential authority | Supplies source-bound closed panels and owning-side normals for nonclamped rectangle meshes. | Existing whole-query behavior and curve/surface wire representation remain unchanged; Kernel consumes the child contract. |

## Architecture

```mermaid
flowchart LR
    Surface["Analytic Surface"] --> Curve["SurfaceParameterCurve"]
    Curve --> Structural["Finite/domain/degeneracy checks"]
    Structural --> Signature["CADIR geometry signature"]
```

## Contracts and Invariants

### Intersection, Coincidence, and Proximity Authority

The [workspace CAD policy](/Users/1amageek/Desktop/3D/AGENTS.md#cad-intersection-and-proximity-policy)
is the decision authority for separating original intersection from tolerance
proximity. This module owns their geometric evidence; topology and modeling
operations own explicit repair and connection decisions. The detailed result,
failure, and migration obligations are specified in the
[Intersection Algebra foundation contract](IntersectionAlgebra/DESIGN.md#intersection-classification-and-proximity-boundary).
Legacy tolerance-based coincidence is not evidence of migration completion.

### Canonical Ideal Angular Primitive Authority

[Canonical Sphere Chart](CanonicalSphereChart/DESIGN.md) owns the shared phase producer.

The original analytic sphere is the ideal closed sphere defined by its stored
center and radius. Conventional binary64 longitude and latitude labels encode
symbolic full-turn and quarter-turn roles, rather than an independently authored
binary angle law. Its continuous physical phase is mathematical pi multiplied
by the normalized label: longitude `pi * (u / Double.pi)` and latitude
`(pi / 2) * (v / (Double.pi / 2))`. One shared phase producer owns numerical
representatives, certified mathematical-pi angle enclosures, exact canonical
seam/pole roles and every derivative chain-rule scale. Whole chart evaluation,
closed original jets, pcurves, inverse projection and collapsed-boundary receipts
must consume that producer. Endpoint-only snapping cannot establish this law.
The same continuous intrinsic-turn law owns original Circle3D and analytic
circle, ellipse and circular arc harmonics. Their original frames, radii and
authored arc labels remain source identity; every derivative includes the phase
scale. Native rational angular charts, hyperbolas and unrelated analytic
surfaces keep their existing source contracts. Native serialization retains
primitive source fields, never numerical angle enclosures. Point, closed jets,
higher jets and inverse angular projection must agree before adapter closure;
rational conic station correspondence, directional roots and angular pcurve
transport remain explicit completion gates until connected to this law.



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
Shared vector magnitude bounds scale component-wise absolute extrema by their largest finite component before outward-rounded division, products, sums and square root, then rescale outward. Zero vectors retain an exact zero upper bound. The lower bound also retains the largest-component bound. Direct endpoint quotients avoid overflowing reciprocal intermediates for finite tiny denominators; invalid or zero-containing divisors fail explicitly. Scalar interval midpoints use stable finite candidate arithmetic and never serve as original proof stations.

[Common curve-basis resolution](BSplineCurveCommonBasis/DESIGN.md) owns original
normalized preparation and immutable common-basis image construction. Its bounded
requirement forwards preparation work/storage to the caller before evaluation or
allocation. Shared connector tuples are prepared once by the composing Modeling
caller; that caller retains original curves and directed native parameters.

`BSplineSurfaceEmbeddingValidator.validateSeparation` certifies that two complete
finite spline domains are disjoint using the same outward Bernstein difference
exclusion and subdivision budget as embedding. Parameter coordinates belong to
different charts and never imply adjacency. Failure to prove separation is a
typed resource failure, not a positive intersection certificate. Touching domains
are not admissible to this strict separation contract; topology must separately
own shared-boundary admission. This contract does not establish regularity.
Adjacent spline charts use a separate admission contract: orient nominated
clamped boundaries into the same finite seam parameter domain. Their original
homogeneous XYZ laws must be exactly equal on every positive interval in the
union of both original knot partitions. Identical degree, knots, controls and
weights are an early sufficient path; general representation differences use
whole cross-denominator polynomial identities under the same pair allowance.
Injectivity over both complete charts retains the existing local-cell,
touching-region and separated-cell certificates. Original coefficient rounding
is not tolerance equality; sampled coincidence never proves admission. Exact
algebra work/storage is prepaid and the remaining pair allowance continues into
embedding refinement. This contract does not establish general face sewing.
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
the stored certification tolerance. Native surface domains and geometric
continuity keep their specified tolerance. Angular continuity requires the
original closed endpoint tangent enclosures to prove consistent orientation
and the specified angle bound. A positional gap or sampled endpoint curvature
does not enlarge that angle bound. The existing subdivided-procedural
intersection regression remains a verification target for this admission.

Connection admission compares the unique closed gauge-root enclosures in all
four original parameter coordinates. Each enclosure is normalized through the
original search-domain endpoint differences using outward arithmetic; rounded
anchor values or rounded domain widths cannot certify a connection. The same
gauge receipt supplies both source-surface position and tangent bounds under
the composing caller's work and storage allowance.
After initial unique-root admission, endpoint enclosures are contracted with
the same fixed gauge and original normalization. Each Krawczyk iteration uses
closed jets over the retained root box and intersects with that box, preserving
the admitted root. The existing root-refinement ceiling of 32 iterations bounds
this work; unchanged bounds stop refinement. No root iteration consumes source
nesting or curve subdivision depth, and unresolved width cannot admit a join.
Surface lifts of implicit intersection pcurves reuse the certified parameter
interval jet for UV bounds and derivatives through order three. Reversed and
trimmed pcurves rescale each derivative by its parameter-span power; closed
seam-crossing spans enclose both sides separately. Offset pullbacks transport
only UV bounds, never the original support's spatial derivative certificate.
A lift's position box restricts the pcurve to the requested cell, widened only
to the width a trim needs (four relative tolerances), not to the derivative
certificates' minimum width, so a closest-point search refining toward a root
sees its boxes shrink (`ProceduralSurfaceKernelIntegrationTests.closestPointUsesExactEdgesForANonRectangularTrim`).
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
A planar harmonic pcurve corresponds to its circular edge when its start sits within the
distance tolerance of the edge's and its span within the angle tolerance: its start derivative
may turn and stretch by as much (`CylinderFlushNotchTests`, where a slot's arcs and their
trimming curves are found apart by a hair's turn).
Cylinder–cylinder bounded-branch bounds hold over any positive stretch of the curve's fraction and
over a stretch that is a single angle (a cell at the phase's end, where the angle turns), the
endpoint bounds covering it.
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

### Original closed curve-span differential authority

`PreparedCurveDifferentialEncloser` retains immutable original homogeneous coefficients for closed native-span queries. A C0 knot is queried on each owning original span; higher derivatives are never presented as a globally smooth jet. The one-shot B-spline differential route delegates to the same prepared authority, with identical normalized endpoints, original budgets, and cancellation. `PreparedCurveClosedNativeJetTests` and `CurveDifferentialEncloserTests` verify owning sides, finite/resource failures, and prepared/one-shot equality. A native span's values over a parameter interval intersect the interval de Casteljau evaluation with the hull of the Bernstein coefficients restricted to that interval, which shrinks with the interval's square (the spatial Revolve's orbit separation, `RevolveSheetConstructionTests.nonmonotoneSpatialGeneratorProducesExactRegularSheet`). [GeometryConversion](GeometryConversion/DESIGN.md) composes this lower contract without widening original correspondence admission.

### Polynomial B-spline surface derivatives

Where the weights a B-spline surface evaluation reaches are all equal, the surface is polynomial
there: `BSplineSurface3D` derivatives through second order, and through third order in
`parameterDerivativesThroughThirdOrder`, are the homogeneous sums over the weight sum without
quotient-rule terms, so derivatives that vanish (a degree-one direction's second derivative) are
exactly zero rather than a roundoff residue outside their certified enclosures
(`SurfaceDifferentialEncloserTests.affineBSplineEnclosureRemainsConditionedOnNearlyConstantParameter`,
`CurveThirdOrderCertificationTests`).

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

The original prepared B-spline owner extends its selected-native-span contract to connected rectangles crossing at most one exact represented period in each periodic axis. A periodic span token retains the original immutable source/tolerance, original base span indices and closed bounds plus explicit U/V cycle translation and corresponding lifted requested bounds. Translation is proved from the original stored period/knots; an approximate knot shift, unrepresentable lift or inconsistent token cannot be admitted by epsilon or ordinary periodic normalization. Requested widths retain the existing exact TwoDifference period-excess refusal. A nonperiodic axis retains its original native domain knots[degree]...knots[count] and admits finite legal nonclamped or clamped knots with active internal multiplicity no greater than degree. Its only selected lift is cycle0/translation0; all original closed incident spans, including native endpoint and zero-width query ownership, remain retained. The periodic axis retains the unchanged exact width, translation, Cartesian cover and aggregate count contracts. Existing original cyclic homogeneous patches, positive weights, exact position-continuous tails and both closed owning sides supply geometry; no copied/trimmed replacement surface is authority. Ordinary all-owning enclosures and ordinary public normal retain their existing semantics.

The selected normal/derivative path verifies the complete original token and query inclusion, resolves a lifted native station to its proven original base station and evaluates that explicitly selected original span without canonical-right normalization. Thus the lifted seam upper/left owner is not silently evaluated on the lower/right span. Enclosures cover each actual original positive span, retain native derivative scaling and finite regular one-sided frames, and reject discontinuous or invalid source/tolerance/lift authority. Original aggregate preparation/proof budgets and cancellation are retained; checked span/lift enumeration and allocation charge before execution. Immutable source and token ownership are identical on all targets. Independent degree-one diamond cycles and double periodic bilinear diamond tensors prove positions/tangents/normals on base, negative/positive seam-crossing, shifted and full-cycle boxes, including both closed seam/corner sides. Invalid tails/translation, exact period excess, singularity, foreign source/tolerance/lift and resource/cancel refuse explicitly. Lower behavioral evidence precedes upper periodic-C0 panel publication; full M1 and portable integration remain open.

### Selected Original Native First-Order Queries

The immutable selected-span differential owner supplies closed original value
and first-tangent queries for mesh station admission, in addition to its full
third-order and value-only queries. Source/tolerance/lift and knot-side guards
are identical. The result has no higher derivative fields. The consuming
contract and behavioral evidence are owned by
[OriginalGraphBand](OriginalGraphBand/DESIGN.md#original-station-first-order-materialization).

### Immutable selected-native station rows

`OriginalNativeSpan.prepareStationRow(u:on:tolerance:consumeWork:)` admits the
original source, preparation tolerance, exact selected side and closed U once,
then returns an opaque immutable evaluator. It retains the original global U
point basis and selected U derivative basis without regrouping numeric sums.
Materialization computes the original global point accumulation in its existing
V-then-U order and the original selected-side normal accumulation in its existing
local V-then-U order. The two laws remain distinct at a C0 boundary.

The row also retains original U-localized first-order homogeneous nets, with
separate singleton and closed-interval laws matching the existing enclosure
paths. Every V query stays inside the token's original closed V support. Caller
work is consumed before preparation and every retained numeric slot; existing
station and facet charges remain owned by the consumer. No mutable cache or
fresh budget is introduced. [OriginalGraphBand](OriginalGraphBand/DESIGN.md)
owns receipt/cell/U provenance and connection to actual station error admission.
These new paths are source-only until subsequent native and portable execution.

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

## Original Framed Infinite Plane

The module's existing primitive representation owns `Plane3D`; it has no
separate primitive component directory. An optional stored `uDirection` retains
an explicitly authored native chart. Its absence preserves the existing
origin/normal initializer, two-field Codable representation and legacy basis
selection. Its presence defines the infinite law
`S(u,v) = origin + uDirection*u + normal.cross(uDirection)*v`, with unbounded
U/V domains. The authored X is never projected, normalized or replaced during
evaluation. Exchange owns deriving a valid orthonormal X/Z pair and converting
length units before constructing this value.

```text
authored origin / normal / optional X
  -> primitive finite / unit / perpendicular validation
  -> one retained U/V basis
  -> point / projection / first-through-third / Taylor / interval jets
  -> original-chart conversion and retained signature transport
```

| Owner | Contract |
|---|---|
| `Plane3D` | Retains original axes, synthesizes optional Codable storage and validates geometry. |
| Surface differential visitors | Use `parameterBasis`; second and higher plane derivatives are zero. |
| Rigid and offset surface images | Preserve the explicit chart; the legacy nil branch retains its prior behavior. |
| Analytic chart map and harmonic lift | Interpret native U/V through the same retained basis. |
| CADIR and CADExchange | Retain the complete geometry value; native strict optional-field admission belongs to exchange. |

An explicit X must be finite, unit length under the existing vector validation
and perpendicular to the unit normal within the angular tolerance. Invalid axes
produce typed geometry/input failures. Y is the stored normal crossed with X,
so its handedness follows the actual authored normal. Optional storage does not
introduce a task, callback, shared mutable owner or platform branch.

Rigid transforms permit determinant +1 and -1. For explicit charts, U transforms
as a vector and the oriented normal transforms as determinant-sign times the
normal vector, preserving the original Y and UV law under reflections too.
Offset changes the origin along the source normal and retains X. No bounded
spline or newly selected analytic chart becomes source authority.

[Original framed plane tests](../../Tests/CADGeometryTests/OriginalFramedPlaneTests.swift)
own literal point/projection, all differential visitors, interval containment,
rigid/reflected/offset charts, old/new Codable, invalid-axis refusal and the
public G6 approximation path.
[Signature tests](../../Tests/CADIRTests/OriginalFramedPlaneSignatureTests.swift)
own retained surface identity and native UV evaluation after signature transport.
Exchange owns independent STEP and strict Native package transport proofs.
Native, normal WASM and Embedded behavioral evidence remain target-specific.

### Original native coefficient retention

Selected original native spans may issue an immutable package-only coefficient receipt after exact source, tolerance, closed-domain, and periodic-lift admission. Receipt issuance charges the caller before retention and preserves the existing original homogeneous value net through immutable COW ownership. It performs no extraction or global weight scan and adds no smoothness guarantee. [SurfaceAreaIntegration](SurfaceAreaIntegration/DESIGN.md) owns higher-order construction and its allocation/arithmetic work; the source owner retains token validation authority. Native first-order and full third-order entry points retain their existing contracts. For a singleton receipt query, an error-free subtraction with zero expansion tail retains the exact represented original station after periodic translation; a nonzero tail retains the admitted outward cover. This does not narrow a non-singleton query or change other selected-span visitors.

### Caller-paid original cover enumeration

The additive `originalNativeSpans(over:tolerance:consumeWork:)` entry charges the supplied synchronous caller allowance before original span scans, knot recurrences, exact axis-lift enumeration, and token append. It uses the same original source, closed boxes, lifted sides, and aggregate262144 cover ceiling as existing entry points. Existing callers retain their own admission and budgeting policies; the new entry retains neither the callback nor mutable shared state. [SurfaceAreaIntegration](SurfaceAreaIntegration/DESIGN.md) composes this paid entry with coefficient retention and higher-order work.

The [original analytic Rebuild position owner](GeometryConversion/DESIGN.md#original-analytic-rebuild-position-parg6analytic1) supplies the complete original-chart certificate consumed by [Kernel analytic publication](../CADKernel/DESIGN.md#original-analytic-rebuild-position-publication-parg6analytic1). The new source-family and retained-state guarantees require their own public evidence; prior Native spline proofs do not establish this analytic path.


### Allocation-Free Ordered Interval Product

`OutwardScalarInterval` multiplies the same four binary64 endpoint pairs in the same order, reduces extrema with the same ordered comparisons as the previous Sequence reduction, and applies the same final outward `nextDown`/`nextUp`. Stack scalar storage removes the per-product temporary array on the repeated original-limit-normal materialization path. Signed zero, overflow, infinity and NaN ordering remain unchanged; this is not a new finite-input certificate or a relaxed enclosure. The immutable storage, isolation and target contract are common to Native/WASM/Embedded. [OutwardIntervalArithmeticTests](../../Tests/CADGeometryTests/OutwardIntervalArithmeticTests.swift) compare endpoint bits against the previous independent reduction and preserve endpoint enclosure and typed division refusal. The affected normal receipt validates the actual public corner and guided mesh consumers at unchanged budgets.

- [Orthographic curve projection](OrthographicCurveProjection/DESIGN.md): original parameter-preserving projection law and frame.

The general tessellation-bound traversal exposes a package overload receiving
`remainingCells: inout Int`. All faces/triangles in one upper invocation debit
that same counter before visiting a cell. The existing convenience operation
creates the historical 262,144 ceiling once and composes the same traversal;
sharing a counter does not change derivative, normal or depth admission.

Original periodic native position publication is owned by
[GeometryConversion](GeometryConversion/DESIGN.md#original-periodic-native-position-publication).
Its source/candidate periodic lift covers and point reservations share the same
caller accounting and preserve the original contained-chart contract.

Prepared internal closed surface boxes retain the same original analytic,
B-spline, ruled or rolling law used by positive-width queries. The internal
closed operation validates finite domain containment independently of public
positive-width admission and preserves both owning sides at native joins.

## Native Codec Boundary

Foundation imports follow the same capability boundary as the existing codec
witnesses. Native and normal WASM retain their original Foundation import;
Embedded imports the actual target C math module (Darwin, Glibc or WASILibc).
The source algorithms, arguments, floating-point functions, geometry state,
Sendable and Mutex owners remain unchanged. Missing C math is a compile-time
capability refusal, never a substitute numeric implementation. The complete
CADCore and CADGeometry production modules are the portability proof unit.
Existing cancellation checkpoints call CADCore's immutable typed current-task
checker at the same locations on all targets. It observes the same current
Task.isCancelled and preserves CancellationError without conditional failure
mapping or new cancellation policy. Optional derivative-bound diagnostic
payloads use explicit some/nil formatting on Embedded, where reflective
String(describing:) is unavailable; Native and normal retain their existing
reflective formatting. Internal field projections use explicit property getter
closures instead of runtime KeyPath objects on all targets. These nonescaping
getters select the same field, invoke it at the same location and preserve
iteration order, admission checks and short-circuiting. The local spatial-axis
sweep stores the same three getter operations; it owns no shared state or
cross-target isolation difference. Embedded diagnostic interpolation uses Core's
existing structural error-presentation boundary and retains its stated
reflection limitation; Native/normal diagnostic payloads remain unchanged.

Original geometry values, associated source graphs, immutable fields, Hashable,
Sendable and shared Mutex ownership remain common to native and Embedded targets.
Native Codable conformances, keyed schemas and decoder/encoder implementations
are compiled only outside Embedded. They preserve the native field schema and
validation path. Embedded consumers use the explicit original-source writer
owned by CADIR; they do not obtain a default, empty codec or a different geometry
representation. Codec helpers do not own geometry evaluation or mutable state.

```text
common original geometry value
  -> native Codable adapter (!Embedded)
  -> explicit original-source writer (all targets, CADIR owner)
```

Verification after the source phase must exercise native schema round trips and
fixed-toolchain Embedded compile/link for the complete reachable source graph.
Source separation alone does not establish either runtime behavior.

Original B-spline surface preparation can bind a caller-owned cumulative work
callback before any new homogeneous patch storage is allocated. The shared
callback covers actual native-span basis recurrence, homogeneous coefficient conversion
and prepared derivative nets; checked allocation byte counts refuse overflow.
The same callback and caller span ceiling then own periodic lift enumeration.
The legacy convenience initializer retains its established operation ownership.

- [Parameter Image](ParameterImage/DESIGN.md): persistent signed foreign parameter laws and original spatial surface images.

- [Surface Pole Geometry](SurfacePoleGeometry/DESIGN.md): original clamped collapsed-boundary one-sided normal authority.

- [Curve Curve Contact](CurveCurveContact/DESIGN.md): original native curve pair contact and continuous ambiguity evidence.
- [Rational Bivariate Algebra](RationalBivariateAlgebra/DESIGN.md): exact original dyadic/rational coefficient equality and polynomial algebra.
- [Intersection Algebra](IntersectionAlgebra/DESIGN.md): original three/four-variable rational intersection equations and exact ideal preparation; real component coverage remains a separate required obligation.

- [Original Line Incidence](OriginalLineIncidence/DESIGN.md): exact original point/parametric-axis incidence.

- [Original Higher Curve Jets](OriginalHigherCurveJets/DESIGN.md): caller-owned original requested-order curve and implicit-chart derivative authority.

- [Original Root Span](OriginalRootSpan/DESIGN.md): exact original incidence endpoints and normalized retained traversal authority.

- [Original Revolution](OriginalRevolution/DESIGN.md): persistent original root-generator revolution law and closed source jets.

- [Curve Surface Query Admission](CurveSurfaceQueryAdmission/DESIGN.md): same invocation admission across original query preparation, coverage and root proof.



Bounded original arc-length requests consume closed source-owning curve jets,
partition native joins before midpoint Taylor integration and preserve every
original parameter span. Validation, preparation and each integration cell debit
the same caller callback; nested source work inherits the active cell depth.
The admitted depth is the minimum of caller and existing option ceilings.
Rounded Bezier decompositions and numerical chords do not establish an original
bound. Legacy entry points keep their historical policy. This contract does not
infer continuity across unresolved implicit or offset source joins.

[Original Geometry Source Validation](OriginalGeometrySourceValidation/DESIGN.md)
owns caller-admitted native validation. Curve, surface and pcurve composition
forwards the same admission into every original source descendant; immutable
certified graph construction/decode witnesses can be consumed without replaying
an unrelated default proof allowance.


`OriginalPeriodicCurveTraversal.normalized` composes the retained original scalar
selectors and exact integer-period translation into a persistent nested parameter
image on normalized [0,1]. It binds the translation to the original deepest
periodic source and exact gain product under caller admission. Its difference
gain retains the directed selector/translation source values. Foreign `Double`
period estimates remain conveniences; they cannot authorize chart displacement.
The traversal does not infer geometric endpoint closure from a numerical period.
Nonrepresentable original first selectors require a separate exact endpoint
carrier before they can enter this scalar-selector producer.


[Original Coons](OriginalCoons/DESIGN.md) retains four directed original boundary
traversals and exact corner incidence. The module dispatches its actual Coons
source jets through procedural evaluation, prepared queries and conversion;
whole original embedding remains an independent publication requirement. A
rounded rational tensor embedding receipt cannot certify the retained Coons law.


Original arc-length Taylor tightening requires an individually smooth original
native owner. A synthetic single owner containing several lifted source pieces,
or a hull of their one-sided derivatives, is not a continuity receipt. Such
pieces retain whole original speed integration until a source join partition
and the required derivative continuity have been supplied.

Bounded arc-length parameterizations retain original preparation and the paid
native partition once. Total and prefix enclosures reuse that immutable authority;
arbitrary admitted subintervals recompute only their boundary cells through the
same callback and remaining depth. Retained partition storage belongs to the
composing invocation. No aggregate lifted jet grants smooth Taylor authority.

OriginalRevolution's intrinsic angular orbit uses the same continuous symbolic
full-turn phase as Canonical Sphere Chart. Its authored label interval remains
unchanged; pure and mixed derivatives include the original phase scale. Other
analytic angular and native rational sources retain their separate contracts.

[Surface Surface Query Admission](SurfaceSurfaceQueryAdmission/DESIGN.md) owns the shared original surface-pair traversal admission. Public dispatch forwards its caller depth, source depth, span ceiling and callback into prepared source queries and retained graph construction. The bounded protocol witness retains optional storage selection and an independent algebra-depth capability; concrete and existential admitted calls forward the same owner without replacing nil storage with a no-op witness.

Bounded arc-length parameterizations expose original differential enclosures from the same retained preparation. Every owning-span union is charged to the original callback; a union provides derivative bounds without granting continuity or smooth Taylor authority.

The retained arc parameterization can report smooth native interval authority only from the original family admission and exactly one positive-width owning span. Closed zero-width neighbors do not invalidate that one-sided owner; aggregate lifted or implicit derivatives alone do not establish continuity. Original endpoint connectors add a globally smooth exact polynomial correction to their retained native construction; exactly one positive-width construction owner can therefore supply the same local smoothness authority. The construction alone never supplies corrected position, speed or endpoint authority.

Caller-admitted surface-pair protocol requirements distinguish work visits from retained byte reservations. Explicit source depth, subdivision depth and span ceilings are forwarded to the same original finite parametric producer. Legacy specialized entry points preserve their historical dispatch. The injected bounded route cannot authorize unmetered analytic/unbounded proof helpers or claim unresolved critical/coincident contact completeness.

[Native Surface Embedding](NativeSurfaceEmbedding/DESIGN.md) owns original native local injectivity, pair separation and adjacent boundary admission, including caller work/depth/storage forwarding. Parent descriptions of these proofs refer to this child authority.

Original Bernstein evaluation may intersect interval de Casteljau with the
convex hull of its outward restricted original coefficient net. Both retain the
original polynomial. Local surface-lift position bounds use a containing UV
subinterval sized only for chart admission; a derivative certification minimum
width must not prevent positional bounds from converging. Equal original tensor
weights remove quotient corrections in numerical third derivatives because the
original denominator is constant. These changes preserve all source tolerances;
endpoint curvature samples do not authorize a wider implicit connection angle.

Closed implicit localization preparation accepts explicit span, subdivision and
source-depth admission and forwards original preparation work and retained bytes
to the same caller. Each restriction and contraction accepts the work callback.
The retained original source graph and tolerance bind every state; whole source
Jacobians and closed original center positions bound Krawczyk residuals. A
center representative selects only a preconditioner. Nested surface queries
use the remaining caller depth, without a private recursion allowance.

Bounded arc-length parameterization retains the explicit caller byte callback
alongside its existing work and depth contract. Native coefficient preparation,
integration heap/cell capacity growth, retained final partitions and owned query
temporaries reserve actual checked bytes before materialization. Preparation
and all prefix queries use the same immutable source and allowance. Lower Taylor
query temporaries remain incomplete until their actual allocation sites forward
that callback; an outer estimate is not complete storage admission.

[Original Affine Operation Word](OriginalAffineOperationWord/DESIGN.md) owns flat
retained forward/inverse affine operations and exact normalized STEP frame
composition. Image adapters consume its immutable prepared action without
rounding it into a replacement source matrix; factor count is independent of
source-graph recursion depth.

[Original Affine Image](OriginalAffineImage/DESIGN.md) owns distinct retained-word
curve, surface and pcurve families. Existing single-affine image source meaning
is unchanged. Exhaustive dispatch consumes original word action and unchanged
native charts rather than reading an approximate matrix cache.


Finite ScalarInterval midpoint candidates use separate endpoint halves for
opposite signs and a same-sign endpoint difference otherwise, avoiding overflow
for admitted finite endpoints. This numerical representative supplies no exact
source station, interval width or residual authority; original proofs retain
outward endpoint differences and quotients.


Intrinsic ideal cylinder/cone U and torus U/V use the shared continuous
[canonical angular chart](CanonicalSphereChart/DESIGN.md), consistently with
sphere, ideal conics and original revolution. Their declared full-turn label
period is an exact chart identity. The cone halfAngle is a nonperiodic physical
slope scalar and is not interpreted as a chart turn. Rational native angular
laws retain their original knots and source meaning.

The original endpoint connector curve family is owned by [the Coons endpoint connector](OriginalCoons/EndpointConnector/DESIGN.md). Curve composition preserves its original section endpoint expressions, exact correction basis and retained construction. Closed prepared queries keep native one-sided construction owners and apply the correction law per owner; higher queries prove only requested continuity.

[Original Curve Construction Chart](OriginalCurveConstructionChart/DESIGN.md) owns persistent normalized root traversals and exact directed construction parameter-law carriers. Publication consumes the retained original chart rather than a rounded native endpoint difference or fitted control net.

Retained arc-length inverse fraction queries compare original total/prefix integral enclosures against the exact requested fraction interval. Only certified inequalities exclude native cells; queries reuse the retained preparation and cumulative work/byte/depth admission. Returned native bounds localize the station and do not replace its original fraction law with a midpoint or authored Double.

The certified rotation trigonometry adapter accepts a composing work callback. Each actual range-reduction, Taylor recurrence and double-angle step debits that callback before evaluation; the historical angle domain, term count and certified remainder remain unchanged. The default legacy entry checks cancellation and introduces no caller ceiling.

Bounded rigid curve-image construction validates its authored transform once and descends into the original curve with the same work and optional byte callbacks. It decrements source recursion once, forwards independent subdivision/algebra capabilities, and introduces no private ceiling; legacy construction retains its historical policy.

Original construction-chart arc-length queries retain their original parameter law. Constant-speed and legacy scalar-third-derivative shortcuts decline this family. Smooth-native queries require the chart producer’s selected native side or exactly one positive-width mapped original owner; a synthetic derivative hull does not establish continuity.

Caller-owned SSI work admission and optional byte admission are independent. A nil byte callback preserves the caller’s work/source/subdivision policy without claiming retained-storage accounting or reverting to a legacy allowance.

Implicit graph restrictions can retain the original SurfaceSurfaceQueryAdmission with both prepared support owners. The prepared-only restriction derives its graph source from that receipt, queries parent derivatives under the same admission, and delegates the retained gauge-root contraction to GraphSubcell. It does not prepare a second pair or use rounded anchors as new existence evidence. Legacy restriction retains its prior policy.

Polyline pcurves retain the exact Euclidean segment arc-length fraction law of their original UV points. Rounded hypot/prefix values are numerical evaluator candidates, not persistent chart coefficients. Exact zero-length segments contribute no traversal, and the original positive total length has no tolerance floor. Exact trim/iso producers must retain square-root length expressions or certified station receipts under independent algebra/work/byte admission.

Generic original SurfaceLift closed jets forward optional query bytes through the actual UV Taylor producer and prepared support interval query. Each lower source family retains its explicit unsupported cases. The composed derivative hull supplies no smoothness or native join partition receipt.

Native iso owning covers also admit authored affine UV sides with an exactly zero fixed-coordinate direction. Original origin/direction/endpoint label arithmetic is evaluated as exact rationals; representable native stations retain the same directed linear support law and one-sided owning metadata. Nonrepresentable affine endpoints require a retained rational UV chart carrier and fail explicitly until supplied. Polyline and nonlinear native UV sides retain their separate exact inverse/segment requirements.

Bounded continuous UV chart lifts and translations accept optional byte admission independently of work admission. They forward the supplied byte callback through original source validation, value-only Taylor bounds and actual retained sample buffers; nil does not select legacy work counters or establish a storage receipt.

Hyperbolic interval evaluation uses scalar endpoint/extremum accumulation and charges each actual visit through the composing work callback. It preserves the existing endpoint enclosure and derivative law without transient value arrays.

The original boundary-corrected surface family is owned by [Coons Boundary Correction](OriginalCoons/BoundaryCorrection/DESIGN.md). Its native Hermite construction and four retained original boundary traversals jointly define the source law. Shared surface dispatch forwards retained coefficient/capability queries; the native construction alone is not an equivalent surface.

Caller-admitted planar orientation compares the original binary coordinate determinant as an exact rational, including the exact determinant threshold. It charges original arithmetic and retained bytes through the same callback and returns zero only for an exact zero determinant; expansion underflow or a rounded estimate is not sign authority. The existing legacy expansion entry retains its distinct policy.

Authored foreign physical-radian parameter laws use the persistent symbolic
transport contract in [Canonical Sphere Chart](CanonicalSphereChart/DESIGN.md).
Untrimmed primitives retain intrinsic periodic charts; physical-radian gain and
offset do not constitute a binary full-turn period witness.

Arc-length queries on original angular transport retain the direct ideal conic
physical-phase law. This admitted analytic law is smooth on each original
parameter interval; synthetic owner count does not prove other joins. Constant
speed and legacy scalar third-derivative shortcuts decline this family; bounded
original jets and the existing one-positive-owner receipt remain authoritative.

For a Plane3D with authored U direction, original closed jets retain raw U and
V as the exact cross product of the original normal and U. Numerical
parameterBasis results are candidates for this law. The nil-U legacy basis
selection retains its separate original normalization contract; no STEP frame
policy is substituted. Exact SSI boundary incidence may consume the authored-U
coefficient law, not a rounded basis.

Prepared curve and surface owners retain an optional independently selected
algebra depth. Bounded source validation and nested preparation forward this
same value; lifted Euclidean-polyline queries consume it separately from
source recursion and geometric subdivision. Nil retains legacy policy and
does not invent a coefficient field allowance.

- [Original Native Plane Contacts](OriginalNativePlaneContacts/DESIGN.md): complete original native-owner plane incidence, retained isolated parameter roots and positive owning intervals for public curve-surface publication.

### Original Plane Derivative Sources

The [Original Coons plane derivative child](OriginalCoons/PlaneDerivatives/DESIGN.md) owns generated endpoint and transverse derivative correction laws. Curve and procedural surface composition retain distinct `originalPlaneDerivative` families, complete raw traversals and support constraint arrays. Shared evaluation forwards original owning partitions and caller admission; a construction spline is not the corrected position law. Symbolic curve endpoint incidence descends the retained source traversal.

The [Original Drafted Section](OriginalDraftedSection/DESIGN.md) child owns retained tangent-dependent draft curve and ruling laws used by generated walls. Shared family integration waits for its actual requested-order producer.

- [Original surface embedding](OriginalSurfaceEmbedding/DESIGN.md): prepared
  original self-contact and projection-contraction sessions shared by callers.

Prepared continuous-partial receipts distinguish requested C1 and C2 authority
from the positional C0 receipt. Both facades share the same retained source
proof traversal: native higher continuity, exact image chart transport and
offset support-order/normal premises. Unknown procedural joins return no
receipt, so boundary normal or shape mean-value tightening must use another
whole-domain proof instead. Each receipt retains its exact requested box and
order under the preparation's independent caller algebra policy.

Prepared offset continuity derives from the original support's complete C2
partial law and a finite closed normal-field cover. Native joins consume the
[original higher surface continuity](SurfaceSilhouette/DESIGN.md) contract;
analytic smooth laws and exact parameter-preserving images compose that
premise. Adaptive normal exclusion uses the same selected span/subdivision,
source, coefficient and byte admission. Positional C0 alone does not authorize
normal continuity or the offset line-integration theorem.

- [Original Circular Measurement](OriginalCircularMeasurement/DESIGN.md): original
  circular-plane conformality and immutable center/radius/normal/boundary query
  receipts under the caller's independent source, subdivision and algebra policy.

Offset composition of a previously admitted fixed surface jet charges each actual
scalar-jet differentiation, product, sum, square root and reciprocal through the
composing work callback. The composition retains fixed value fields and allocates
no coefficient array; an optional byte callback remains optional. This contract
does not admit the original support or prove normal continuity.

- [Original Guide Traversal Chain](OriginalCoons/GuideTraversalChain/DESIGN.md):
  persistent normalized guide chains retaining original traversals and exact
  rational station partitions. Common curve evaluation consumes the actual
  D0-D3 source producer; higher orders and unproved joins fail explicitly.

Guide closed derivative covers retain each declared traversal, exact rational
aggregate lower/upper station and its actual one-sided D0-D3 jet. A declared
traversal ordinal is not a native B-spline index. Native index/domain metadata
comes only from the retained original traversal; absent native ownership uses
an explicit nonnative index and cannot authorize control-net extraction.
Outward parameter intervals localize exact cuts; they do not replace exact
station authority or prove smoothness across guide joins.

Arc-length speed and higher derivative magnitudes use the fixed-field,
scale-before-squares outward vector norm of original interval components.
This avoids square overflow/underflow without changing tolerance or caps.
Guide-chain speed Taylor tightening consumes its original selected-domain smooth
receipt. A single positive selected traversal delegates to that original
RootSpan's smoothness issuer; crossing positive joins requires declared
`provenContinuityOrder >= 2`. Corrected guide connectors delegate the same
original source issuer because their polynomial correction adds no join.
One synthetic hull owner cannot grant this theorem.

Bounded affine curve-image construction forwards original source visits,
optional byte admission and independent algebra policy through the same
validator as its spatial/source policies. It retains the authored affine type
and parameter law without a private preparation allowance.

Selected arc-length enclosure and parameterization overloads take an explicit
source depth and optional independent algebra depth. Their original preparation
retains those values; integration subdivision changes only the spatial cell
depth. Parameter/spatial wrappers decrement source recursion only when descending
the original source. Existing overloads retain their historical coupled policy
as a compatibility facade. Both routes retain the same total/prefix receipt,
work callback and optional byte callback without replenishing an allowance.

Strictly directed axis polylines use the original exact Euclidean UV length law.
When every positive segment has one fixed coordinate and the same varying
direction, its lengths telescope to the exact endpoint difference, proving the
endpoint-affine clock without rounded prefix stations or uniform vertex knots.
Native iso metadata may use that proved equivalent clock; nonbinary inverse
knot stations still require retained exact station authority.

Original guide endpoint connectors retain the original guide traversal, both
original endpoint traversals, directed endpoint flags and correction basis.
Their correction changes the geometric law while preserving its declared
piecewise parameter partition. Owning derivative covers retain original guide
station expressions; native indices never authorize extraction of uncorrected
control coefficients. Literal endpoints peel to the retained boundary receipts.

Original direction normalization divides interval components by one finite
positive maximum magnitude before forming squared norms. This positive common
scale cancels symbolically from the normalized direction. Direct outward
quotients and the scaled norm preserve tiny/huge finite authored components;
fixed-field arithmetic pays the caller's actual work and allocates no arrays.
A box containing zero or an unresolved positive norm fails explicitly.

- [Original Polyline](OriginalPolyline/DESIGN.md): retained authored XYZ points, exact Euclidean-length clock and one-sided original segment jets under explicit caller algebra admission.

Bounded [surface boundary certification](SurfaceBoundaryCertification/DESIGN.md) composes the same caller preparation and closed queries. Position uses C0, normal mean-value bounds require C1 and shape bounds require C2 receipts; byte admission retains the existing UInt32 bridge.

Original Euclidean-polyline arc queries use the selected-domain smooth issuer. Exact incident segment owners and corners never gain smoothness from a synthetic derivative hull; each positive-width original segment retains its own clock law.

Prepared original axis-isoline covers retain the native support owner, canonical
physical iso traversal and a cached exact native pcurve inverse. A spline UV
clock never uses the affine endpoint fraction as its source station. Exact
native UV targets yield source-bound scalar roots and normalized fraction
localization from [Native Axis Inverse](ParameterImage/NativeAxisInverse/DESIGN.md).
The proved monotone orientation permits the canonical support tangent factor to
replace a zero scalar clock derivative for physical direction admission. This
receipt does not grant a whole D3 jet across pcurve joins. The initial cover
facade admits whole normalized clamped native axis clocks; other charts keep
their existing explicit capability boundary.

- [Original Spatial Point](OriginalSpatialPoint/DESIGN.md): immutable authored Point3D plus original spatial word, exact bounded D0 position and checked numeric localization for topology vertices.

- [Original Normal Angle Bounds](OriginalNormalAngleBounds/DESIGN.md): exact physical-radian normal-angle/chord proof under caller admission, distinct from intrinsic angular parameter labels.

At the stopped-checkpoint integration boundary, numerical third-order curve
queries delegate guide chains and corrected guides to their existing original
requested-order providers, with retained source and query caps. Original
polyline point queries additionally require exact first-derivative agreement
on all incident closed segment owners; segment-local zero higher derivatives
do not establish a smooth corner. Prepared closed owning-span queries retain
their separate piecewise authority.
