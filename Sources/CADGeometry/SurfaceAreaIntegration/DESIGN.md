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
closed parameter localizer for one open smooth single-Bezier-span graph cell.
It retains both original supports, the selected role, the trim fraction map
and the invocation's preparation tolerance. Topology supplies a synchronous,
non-escaping work callback; geometry retains no callback or independent budget.

## Contracts and Invariants
- A centered smooth chart query obtains its original range and closed midpoint
  jets through the same prepared owner, support, tolerance and caller work
  callback. Mean-value/Taylor intersections restrict values and first/second
  derivatives using the midpoint jet and the original full-range third
  derivative. The third-order enclosure is retained unchanged. Empty
  intersections are typed certification failures; no sampled point or fitted
  derivative replaces original root authority. Both actual proof operations
  and all lower phases retain their existing work charges.
- On a structurally affine support, the nonlinear caller path may integrate an
  equivalent Green form of the original signed fan. With `a=u-anchorU`,
  `b=v-anchorV`, and constant density `rho`, its area and displacement-moment
  integrands are `rho*a*b'`, `rho*a*a*b'/2`, and `rho*a*b*b'`. Each curve retains
  endpoint corrections `-rho*Delta(a*b)/2`, `-rho*Delta(a*a*b)/6`, and
  `-rho*Delta(a*b*b)/3`. These are exact integration-by-parts identities,
  including for finite rounding-sized gaps between consecutive curves.
  World moments use the same affine support columns and reference-centered
  anchor offset. Entire fan-domain coverage and final interval errors remain
  authoritative. The midpoint proof also tightens range derivatives before
  field construction, reducing quotient dependency without new root work.
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
  Implicit charts outside the exact connected affine or single smooth positive-weight cell families and non-affine
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
  between two single-span, nonperiodic, clamped B-spline supports with finite
  positive weights. Original rational quotient jets certify a positive
  denominator and native derivatives through order three; the lower
  localized Jacobian must remain finite and exclude a singular dependent
  determinant. Equal weights are not a correctness assumption of the
  continuation: original Krawczyk existence/uniqueness and the quotient
  enclosures own that proof. The selected face support is exactly the retained role's source,
  or an already admitted exact rigid/offset chart image. Original trim
  fractions and wrapper fractions remain in [0,1]; their outward affine maps
  are intersected only with that validated source domain. Lower derivatives
  already own native width, direction and intersection fraction powers.
  Composition multiplies by the trim fraction slope through powers one,
  two and three exactly once, then applies existing wrapper chain rules.
  Closed singleton fractions retain their exact identity mapping. A reversal
  mapping retains a singleton only when finite expansion subtraction proves
  that the represented `1-f` is exact; otherwise the outward enclosure remains.
  Stored trim endpoints retain their original values. This removes redundant
  lower endpoint phases without changing the original native root interval,
  derivative authority, shared work accounting or source-domain admission.
  A closed point query uses the same outward proof as a positive interval.
  Numeric anchors, midpoint solutions, sampled chords and analytic fixture
formulas never provide root or derivative authority.
- Nonlinear chart preparation and every lower prepare/advance invoke the
  caller's work callback before doing that work. Endpoint-localization phase
  transitions are advances and consume the same callback; geometry never loops
  without charging the caller. Calling this family without a work owner throws
  an explicit typed invalid-input failure. A lower subdivision-required result
  becomes typed `implicitLocalization` refinement, requesting subdivision of
  the original boundary fraction T rather than a hidden local retry. Periodic,
  multispan, multicell, closed and procedural implicit supports remain incomplete typed
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

### Centered Non-Affine Implicit Fan Pair

For a smooth implicit chart requiring caller work on a non-affine selected
support, the integrand owner prepares one paired original chart enclosure:
`centeredIntervalJets` supplies the whole native boundary-fraction range and
its certified midpoint. The existing original third-derivative bound restricts
value/first/second fields by intersection; no fourth-order authority is added.
The same prepared support, trim, normalized fractions and anchor compose both
members with the existing signed fan map and original radial interval (range)
and radial midpoint (center). Every lower preparation and continuation uses the
same query work callback. No unpaid cache or independent allowance is introduced.

A nested immutable geometry-owned `CenteredFanChartProof` retains the exact
original curve/support, boundary interval T, tolerance and range/midpoint jets;
its initializer is unavailable outside its owner. The factory performs the
same charged original chart work once. A fan consumer verifies exact authority
matches before composing the retained jets with an R interval. It performs
surface-density operations without claiming a new lower root proof.
Topology retains this value in its existing DFS cell: R children inherit it;
T children may use it only as input to the original parent-chart restriction
contract below, which mints an exact-child-T token. A failed initial factory
retains no token. Each cell keeps its
existing work charge and subdivision rules; proof reuse never bypasses a lower
operation that is actually executed. Lifetime ends with the cell/curve/query,
with fixed-width jets and original COW geometry references only. The existing
DFS depth/cell ceilings bound retained tokens; no global cache or new queue or
allowance is introduced. Same-T R-child literal field containment, no repeated
lower work, T/curve/support/tolerance mismatch refusal and original public
60-second cases must verify this contract. The first centered composition
passed independent fields but still exceeded both public positive-case limits;
a sampled active stack confirms repeated root work during integration.

Topology consumes this pair only on that smooth non-affine caller-work path.
Numeric/value-only C0/native-span, affine Green, exact-radial and rectangle
routes retain their contracts. Fan Hessians and density derivatives remain
bounded by their existing original geometry owner; no synthetic zero third
integrand field is promoted to a proof. Empty intersections are typed failures;
inconclusive localization and singular native boxes retain existing T/R
subdivision. Whole-query four-field error, work/cell/depth/cancellation,
signed fan winding and 64-ulp joins remain required. Independent literal
fan density and XYZ moments plus the unchanged public curved rational band
area/centroid tests must establish correctness and completion within their
original limits. The preceding plain fan path exceeded each original 60-second
positive-case limit; a tighter pair is a proposed fix, not success evidence.

### Pending Original Root-Cover Continuation

The [Geometry retained original implicit root restriction](../DESIGN.md#retained-original-implicit-root-restriction)
owns the lower four-coordinate state. The area chart transports its opaque whole-range state through
the exact existing curve-role/wrapper/source-fraction mapping. Child midpoint
queries restrict that containing state and still execute and charge the
original prepare/advance phases. The chart's two-coordinate Taylor/MVT fields
never manufacture a native root box; a child singleton state never becomes a
whole parent for another interval. The bounded parent box is only a starting
cover, and actual lower rank/derivative/endpoint certification remains required.
The current child-field test passes but all3 original public60s cases still
fail; continuation work reduction and public success remain unverified.

## Verification and Change Impact
`rationalImplicitSingletonFractionsRetainLowerPointWorkAndAuthority` compares
actual singleton chart work and original value/third-jet authority against the
same lower direct proof in both roles and directions; inexact reversal and
partial trim retain the original outward interval and independent literal jets.
Its unchanged expectations reject the old redundant endpoint phases.
`centeredRationalChartsRetainOriginalThirdOrderAuthority` checks both original
roles against independent value/first/second/third derivative formulas, actual
second-order tightening and unchanged third-order interval authority.
`affineGreenCorrectionsDoNotTelescopeAcrossRoundingSizedJoins` uses actual
numeric pcurve endpoint proofs with a 48-ulp gap: retaining the two curve
primitives gives the independent nonzero correction, while telescoping loses it.
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
jets, foreign supports, required caller work, multicell refusals and
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
Rational single-cell evidence uses the original unequal weights `[4,2,1]`
and source `S2=((s/(2-s))^2/32,s/(2-s)/64,(2r-1)/64)` with denominator
`(2-s)^2`. Its inverse native correspondence `s=2t/(1+t)` has independently
derived nonzero second/third jets, and the original constructor must certify
the full graph before continuation. Closed/range jets retain both roles,
direction, 64-ulp endpoint precision and the same caller work/cancellation.
The public area oracle selects the affine first support on `3/8..5/8` and
retains area `49/1572864` and the literal original/rigid centroids above.
This evidence does not complete area integration when the rational second
support is itself selected; its general two-dimensional signed fan integral
remains a separate full-Q3 proof gap.

### Original parent-chart restriction for T children

Same-T/R reuse alone previously failed the unchanged public limits. The retained original parent contract reuses a minted original
whole-T smooth range only for a closed contained child T. The geometry owner
validates the original curve/support/tolerance and containment before reuse.
It obtains the actual child midpoint from the existing exact singleton lower
operation, charging preparation and every continuation through the same caller
callback. No parent Taylor prediction substitutes for that midpoint root.

The original parent's third-derivative enclosure remains valid on the child.
The existing centered Taylor/MVT restriction intersects child-midpoint-based
value/first/second ranges with the parent's original ranges; third derivatives
retain their original bounds without fourth-order assumptions. Nonfinite or
empty intersections fail explicitly. Original closed-domain existence,
uniqueness and smoothness justify restriction; sampled roots do not. An
unresolved midpoint returns the existing refinement requirement, never a fake
certificate. The newly minted child token owns exactly child T. The exact-T
consumer guard, support identity and original-work contract remain unchanged.

| Evidence owner | Required observation |
|---|---|
| Geometry | Literal partial/reversed/rigid chart and four fan-field containment; charged work equals the actual original singleton operation |
| Geometry failure | Foreign support/curve/tolerance, noncontained T and inconsistent envelopes cannot mint a token |
| Topology | Existing work/depth/cell and endpoint authority; original analytical area/XYZ centroid completes under unchanged limits |

The source localization implementation and shared Bezier enclosure owner are
unchanged by this restriction. It introduces no global cache, queue or new
resource ceiling. Native source-centered field, ownership and failure tests pass. Public completion additionally depends on the bounded original iso-image decomposition below; this restriction alone previously retained the time failures.

### Original Single-Span Source-Centered Fan Pair

The new bounded pair uses the existing range and midpoint original source
queries exactly once each, with the same immutable support/native prepared
owner and caller tolerance. It may tighten only a nonperiodic single original
smooth order-three native span when both complete closed UV boxes lie inside
that span and midpoint box is contained in range box. The authority must come
from original stored coefficients, never an arbitrary extracted Double patch.
Multiple spans, periodic lifts and C0 joins keep their existing original path.

Each Cartesian source component intersects its original value/first/second
ranges with multivariate Taylor/MVT enclosures formed from the actual midpoint
source jet, displacement `rangeBox - midpointBox`, and the original complete
range third jet. The displacement retains midpoint UV uncertainty. Convexity
of the same closed span justifies every segment. The range third remains
unchanged, midpoint fields use their actual source jet unchanged, and no field
third or fourth source derivative assumption is introduced. Empty/nonfinite
intersections fail explicitly; no lower/root evaluation, private allowance or
option relaxation is added. The paired source/field composition must be used
by both numeric fan and retained implicit fan consumers.

Independent literal area/XYZ value and Hessian oracles must be contained by
both old/new field bounds. A same-input before/after source pair comparison
must establish actual reduced field-Hessian width and unchanged lower work,
plus third retention/foreign span/owner failure. Public original forward,
reverse and rigid area/centroid assertions must pass their unchanged each60s
limits before Q3 publication. The bounded trace establishes top anchor-iso
zero fan already accepts at depth0; its elimination is not a timeout remedy.


### Original Implicit Iso-Image Area Authority

For the bounded original single open cell, Geometry may prove a whole constant selected native coordinate from exact original support coefficients and the retained intersection existence/uniqueness contract. The admitted case is an original constant Cartesian-coordinate first support and original degree-one tensor extrusion in the corresponding second-support native axis, with equal positive weight rows and original row coordinates constant across the other axis. The constant plane value must be an exact certified affine combination of the two original row values; uncertain binary64 identities cannot authorize it. Original whole selected-chart jets must prove strict monotonicity in the other native coordinate. Original endpoint root enclosures, source support, role, fractions, reversal, preparation tolerance and wrapper identity remain retained in a separate immutable image proof. No replacement curve is put into exactIsoBoundary and no root/point criterion is weakened.

The image proof is usable only for the actual prepared chart, original source and caller work lifetime. It enables the existing translation rectangle integrand, while original endpoint intervals bound every discrepancy from numeric adjacent side endpoints. Signed fan differences at each endpoint are enclosed as triangles of UV area at most abs(anchorAxis-fixedAxis)*abs(originalEndpointOther-sideOther)/2. The original support density and reference-relative XYZ bounds enclose all four correction fields over the entire triangle cover. These original coefficient scans, whole-chart proof, endpoints and correction evaluations consume the caller callback before expansion; no inferred fourth derivative, geometry replacement, arbitrary private allowance or uncharged certificate is introduced. Unadmitted cases retain the existing original fan path; contradicted source/tolerance/domain authority fails explicitly.

Independent tests perturb interior original coefficients without changing endpoint samples, retain genuine rational weights and direction/wrappers, and show that omitted endpoint correction breaks four-field containment. Existing forward/reverse/rigid public area/XYZ centroid cases must pass their unchanged60s limits before this bounded scope is complete. General rational/multicell/closed charts remain separate gaps.

Native evidence for the bounded iso-image route: all five new parameter cases pass, including original fractions/reversal/rigid identity, interior-coefficient refusal and independent nonzero endpoint area/XYZ corrections. The unchanged public forward/reverse/rigid rational band cases and work/endpoint refusal pass in1.395s. The complete current73-test face-area suite passes in27.853s; the lower37-test original implicit suite passes in.327s. These measurements describe this Native snapshot and do not certify general charts or other targets.
