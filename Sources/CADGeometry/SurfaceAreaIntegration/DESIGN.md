# Surface Area Integrands

## Purpose and Scope
Child of [CADGeometry](../DESIGN.md), consumed by topology's
[Surface Area Integration](../../CADTopology/SurfaceAreaIntegration/DESIGN.md).
Owns integral-specific interval enclosures without publishing internal jets.

## Responsibilities and Boundaries
Exact supports and pcurves determine density and first moments. The component
composes certified geometry with the exact signed fan parameter map. Topology
owns tolerance allocation, adaptive work and measurement acceptance.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADGeometry](../DESIGN.md) | parent | prepared interval differential jets | Exact geometry | Derivative order matters. |
| [Surface Area Integration](../../CADTopology/SurfaceAreaIntegration/DESIGN.md) | used by | integrand bounds | Certified measurement | No sampled error estimates. |

## Architecture
```text
prepared support + exact pcurve -> outward UV fan jets
    -> |S_u cross S_v| and reference-centered position moments
        -> pullback value/gradient/Hessian interval fields
```

`SurfaceAreaParameterChartEncloser` owns invocation-local preparation of numeric
trim charts and exact directed offset/affine rigid chart images. It depends on
the existing numeric interval jet contract, rather than changing the shared
boundary-certification implementation. Topology passes the retained original
trim and its prepared chart authority to integrand evaluation.
`SurfaceAreaAffineImplicitChartEncloser` admits an open native implicit graph
chain whose two original B-spline supports have exact affine patch authority.
It solves the constant native-UV correspondence system with outward intervals;
the retained graph certificate and its original free coordinate own traversal.
`SurfaceAreaImplicitParameterChartEncloser` composes the parent's prepared
closed parameter localizer for one open smooth polynomial-span graph cell.
It retains both original supports, the selected role, the trim fraction map
and the invocation's preparation tolerance. Topology supplies a synchronous,
non-escaping work callback; geometry retains no callback or independent budget.

## Contracts and Invariants
- Existing structural affine support authority permits exact radial elimination.
  Boundary density and moments retain exact numeric pcurve derivatives.
- Every published interval contains the entire requested parameter box.
- Mapped trim admission validates the exact destination support and the source
  relation only after all nested input dimensions and nesting depth have been
  bounded. Directed offset images retain source UV exactly. Rigid images require
  the geometry-owned affine parameter transform and retain the original source
  fraction map, including reversed traversal. Fraction endpoints outside [0,1]
  are invalid input; modeling-tolerance clamping does not authorize integration.
  Outward affine UV/fraction arithmetic and the third-order chain rule enclose
  values and derivatives over the complete requested interval. No sampled
  reconstruction or materialized approximation changes the original fan map.
  Implicit charts outside the exact connected affine or single smooth polynomial-cell families and non-affine
  spherical images remain explicit unsupported failures. Preparing a chart does not allocate another query error
  allowance or reset adaptive cell/depth/control admission limits.
- The affine implicit family requires exact selected-support identity, original
  fractions strictly in [0,1], an open certificate, and exact affine
  parallelogram/equal-weight source authority from original controls. Preflight
  bounds both supports and the graph cell count before validation or preparation.
  Native knot spans scale the original source columns. The cell's free UV
  coordinate follows its stored interval and direction, then the trim's stored
  source fraction map; traversal is not arc length. A constant dependent
  determinant must exclude zero over its complete outward enclosure before
  Cramer division. Original affine equations prove the solved coordinates are
  affine in that free coordinate, so their higher derivatives are exactly zero.
  No sampled endpoint fit, graph approximation, shortened chart, implicit
  recursive refinement, or additional error/work allowance is introduced.
  All cells retain the same free coordinate and direction. Consecutive directed
  native free endpoints must be exactly equal; tolerance-based certificate
  connectivity cannot authorize a missing segment. The original intersection
  gives each cell global fraction width `1/N`, independently of its native UV
  width. Enclosure first applies the stored trim fraction, then `N*f-i`, then
  that owning cell's native width/direction. It never substitutes arc length.
  A complete interval strictly inside one owning piece has smooth one-sided
  jets. Any interval touching multiple owning pieces has an explicit value-only
  chart proof containing UV positions and piecewise first tangents; it supplies
  no gradient/Hessian authority for Taylor integration across the join. Exact
  affine equations prove higher derivatives zero only inside a smooth piece.
  Rigid fraction/UV maps, offset identity and periodic translations propagate
  this proof distinction. Fan enclosure retains the complete original measure;
  native piece intersection restricts chart enclosure only. Preparation is
  bounded by the admitted graph cell count and does not allocate error/work
  budgets. Closed curves, mixed free coordinates/directions, inexact endpoint
  joins, non-affine supports and unresolved constant minors remain typed failures.
- The nonlinear implicit family uses only the original lower root certificate
  and the [prepared closed localizer](../DESIGN.md). It admits one open cell
  between two single-span, nonperiodic, equal-weight polynomial B-spline
  supports. The selected face support is exactly the retained role's source,
  or an already admitted exact rigid/offset chart image. Original trim
  fractions and wrapper fractions remain in [0,1]; their outward affine maps
  are intersected only with that validated source domain. Lower derivatives
  already own native width, direction and intersection fraction powers.
  Composition multiplies by the trim fraction slope through powers one,
  two and three exactly once, then applies existing wrapper chain rules.
  A closed point query uses the same outward proof as a positive interval.
  Numeric anchors, midpoint solutions, sampled chords and analytic fixture
formulas never provide root or derivative authority.
- Nonlinear chart preparation and every lower prepare/advance invoke the
  caller's work callback before doing that work. Endpoint-localization phase
  transitions are advances and consume the same callback; geometry never loops
  without charging the caller. Calling this family without a work owner throws
  an explicit typed invalid-input failure. A lower subdivision-required result
  becomes typed `implicitLocalization` refinement, requesting subdivision of
  the original boundary fraction T rather than a hidden local retry. Rational,
  multicell, closed and procedural implicit supports remain incomplete typed
  refusals; the parent's lower contract is not generalized to those families.
- Closed endpoint bounds retain the exact original trim endpoint fraction,
  including each rigid wrapper's stored endpoint. They use the same prepared
  root owner and caller work callback as interval integration. No implicit
  `parameterPair`, continuous-chart sampling or numeric root solve precedes
  this proof. Finite endpoint intervals are authority; their midpoints become
  topology anchor hints only after the entire connection interval is certified
  within the existing 64-ulp chart rounding contract.
- An exact rigid parameter map `.identity` with the complete stored fraction
  `0..1` returns its child's original proof verbatim. Identity composition
  preserves values, proof kind and every derivative order; materializing
  affine fraction or chain-rule arithmetic would add gratuitous interval
  rounding. Partial/reversed fractions and other maps retain their chain rule.
- A prepared chart can enclose its signed UV flux `u*v'` over the complete
  original interval using the same chart proof and work callback. This coarse
  bound allocates query effort only; it grants no area or centroid acceptance
  and no additional error allowance. Existing chart families retain their
  previous behavior when they do not request nonlinear localization work.
- C0 spline integration uses prepared native Bezier span domains as its
  partition authority. A smooth proof is valid only when the complete requested
  pullback box belongs to one span, including that span's one-sided boundary
  derivatives. A box crossing a C0 knot has an explicit value-only proof;
  gradients and Hessians are absent, rather than fabricated or reused across
  the density jump. Each intersecting span computes density and centered
  moments before their value ranges are unioned. Intersecting the support box
  restricts enclosure geometry only; it never changes the original fan measure.
- Native span descriptors retain the stored knot coordinates and an opaque
  prepared-span identity. Consumers may partition a translation rectangle at
  those coordinates and request the corresponding one-sided enclosure without
  selecting jets from a neighboring span at a shared boundary. Periodic chart
  normalization retains coverage of every representative piece.
- A constant-coordinate fan boundary may partition its radial parameter at
  native knots when exact expansion arithmetic proves each cut identity and
  the other native coordinate remains inside the selected span. These opaque
  domains retain the original fan map and full radial measure. Unproved cuts
  use value-only cross-span integration. An affine fan with exactly zero
  determinant is structurally zero; sampled area estimates do not authorize
  omitting a boundary contribution.
- Periodic spline axes use the geometry-owned conservative base-chart interval
  normalization before prepared-patch intersection. Each axis returns at most
  two intervals, or one complete cycle; every Cartesian piece contributes to
  the union. Negative and shifted representatives never discard coverage, and
  no control net is copied for a requested cycle. Native derivatives are
  unchanged by a periodic translation; the original parameter map still owns
  pullback scaling and integration measure.
- Genuine offsets normally certify density gradients only. For a single
  constant-weight polynomial Bezier support of total degree at most three,
  every fourth surface derivative is exactly zero. The actual offset interval
  path differentiates source jets into tangent jets whose third derivatives
  are zero; this structural proof makes those tangent third derivatives valid.
  Normalization then certifies the normal through order three, hence the offset
  through order three and the area-density Hessian through order two. Other
  supports retain gradient-only bounds; nested offsets lacking source order
  three remain explicit unsupported failures.
- Translation certificates use exact expansion equality of control differences,
  matching weights and parameter charts. For rectangular trims, density is
  independent of the translation parameter and position is affine in it;
  integration equals band width times density/moments at the exact band midpoint.
  Original chart domains and error tolerances remain authoritative.
- Rolling-ball supports with three normalized linear rails and exactly equal
  control displacements prepare constant contact radials once. Their center is
  affine in U; normalized radials, circular weight and the original native-V
  rational arc are retained with outward bounds. Every U derivative of the
  radial term and every mixed derivative is exactly zero by that structural
  authority, rather than by subtraction of separately enclosed moving rails.
  Constant radial lengths and the regular minor arc are certified before use;
  positive Bernstein denominator bounds cover the complete requested V interval.
  Other rolling-ball supports retain the existing prepared enclosure path.
- Density Hessians require valid third surface derivatives and sufficient knot
  continuity. Insufficient regularity uses gradient bounds or typed refusal.
- Ruled and rolling-ball source curves independently determine available
  derivative order; surface lifts over genuine offsets provide no Hessian.
- Unsupported pcurve derivatives are explicit failure; zero substitution is
  forbidden. UV endpoint rounding is clipped only to the exact support domain.

## Failure, Concurrency, and Constraints
Prepared state is immutable and invocation-owned. Unsupported derivatives,
singular frames and nonfinite interval arithmetic produce typed KernelError.
Topology owns geometry-size admission and subdivision bounds.
Chart preparation additionally preflights nested source/destination geometry
before recursive validation or transform materialization. Prepared charts are
immutable and retain source ownership for the invocation; no shared cache or
platform-dependent state is introduced.

B-spline lift rails consume the shared prepared closed-box and point contract
owned by [CADGeometry](../DESIGN.md). Their original UV jets and native-span
authority remain intact; interval localization has machine conditioning only.
The previously observed modeling-tolerance position floor must be closed by the
literal B-spline-lift ruled rectangle regression under its original default
query allowance. The separate analytic-plane caller/depth fixture continues to
own exact support/depth forwarding. Neither proof completes the remaining
procedural/implicit domains of full Q3.

## Verification and Change Impact
[`SurfaceAreaIntegrationTests`](../../../Tests/CADTopologyTests/SurfaceAreaIntegrationTests.swift)
validates composed behavior, including independently differentiated polynomial
offset density bounds through the actual offset-normal enclosure path,
piecewise C1 support, and admission of both endpoints of an eliminated band.
Periodic-strip fixtures independently evaluate uniform cubic polynomials and
their density derivatives on negative, shifted and seam-crossing intervals,
then compare public face area and moments with a physical-coordinate integral.
Rolling-ball fixtures retain the quarter-cylinder area and centroid contract,
exercise a translated diagonal spine with independent native rational-section
derivatives, and reject the translation certificate for unequal rail motion.
Changes to procedural
jets, pcurve jets or knot smoothness require rechecking derivative-order routing.
C0 verification owns folded rectangles and their three centered moments,
cross-fold triangular trims, holes and reversal, non-dyadic knot coordinates,
the smooth/value-only proof distinction, and whole-query resource/cancellation
failures. Successful C0 support integration does not authorize higher-order
offset derivatives or any other incomplete procedural/trim path.
Mapped-chart verification compares public rigid/offset area and all centroid
coordinates with independent geometric integrals, checks source-fraction
restriction/reversal and interval derivative containment, and rejects foreign
targets, unsupported charts, malformed dimensions and nesting/work exhaustion.
Affine implicit verification retains partial/reversed original native fractions,
both surface roles, independently calculated tilted-plane area and all centroid
coordinates, complete interval derivative containment, exact support/non-affine
family refusal, and unequal three-cell native widths with non-dyadic `1/3` and `2/3` joins.
The owning-piece/join fixtures check smooth derivative scaling, all owning
endpoint ranges and absent Taylor authority across a join, including reversed
rigid fraction maps, offset identity and translation wrappers. Public area
fixtures retain literal area/centroid oracles through face reversal and rigid
images. Their boundary order starts opposite the implicit edge, so that edge's
signed fan is nonzero and query-depth refusal exercises its native join integral.
Valid modeling-tolerance gap chains and mixed-coordinate chains are explicitly
refused. Closed traversal evidence is limited to the lower certificate rejecting
an attempted forward/reverse affine-line closure for incompatible tangent
orientation in [CertifiedImplicitIntersectionCurve](../CertifiedImplicitIntersectionCurve.swift).
Two regular affine supports with an invertible dependent minor intersect on a
straight line, so this family has no proper closed regular intersection fixture.
The integral's closed/non-affine guard remains incomplete and is not claimed
verified for a valid curved closed certificate. Graph-count, query-work/depth
and cancellation fixtures retain the original whole-query limits.
Nonlinear composition verification uses an independently constructed dyadic
plane/parabola graph with native equations `S1=(u/32,v/64,0)` and
`S2=(s^2/32,s/64,(2r-1)/64)`. The region `1/4 <= v <= 3/4`,
`0 <= u <= v^2` has literal area `13/196608` and centroid
`(363/66560,15/1664,0)`. The implicit boundary has a nonzero signed fan.
Partial/reversed fractions, both selected roles, rigid images, closed point
jets, foreign supports, required caller work, rational/multicell refusals and
whole-query work/depth/cancellation are separate behavioral evidence.
The public partial-trim region `3/8 <= v <= 5/8`, `0 <= u <= v^2`
retains source fractions `1/4..3/4`, literal area `49/1572864` and centroid
`(4323/1003520,51/6272,0)`. Its boundary begins at the implicit edge, so
the fan anchor requires a certified partial endpoint; its signed fan is
`(t-5/8)^2/4`. Original/reversed graph directions and rigid images retain
the same area and literal mapped centroid `(733/6272,255203/1003520,1/2)`.
Separate closed endpoint tests retain both source roles and reversed rigid
fractions under the 64-ulp connection width. A one-cell query limit refuses
at work 2 when endpoint preparation follows chart preparation; a real
sub-modeling-tolerance chart gap remains a topology failure.
