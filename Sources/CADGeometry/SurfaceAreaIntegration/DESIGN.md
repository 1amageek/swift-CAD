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
closed parameter localizer for an open same-coordinate/direction graph chain
on smooth single-Bezier-span supports.
It retains both original supports, the selected role, the trim fraction map
and the invocation's preparation tolerance. Topology supplies a synchronous,
non-escaping work callback; geometry retains no callback or independent budget.

## Contracts and Invariants
Original polyline source rails are admitted by raw point count and visits while
retaining their exact Euclidean clock. Whole-rail derivative order is zero
without an original join theorem; no fitted tensor or numeric prefix becomes
their source authority.
- Higher-order offset composition consumes an immutable
  `SurfaceAreaOriginalCoefficientReceipt` issued by the original native-span
  owner. That owner validates original source, exact preparation tolerance,
  closed query containment, periodic lift and selected one-sided support before
  exposing its retained original homogeneous value net through checked accessors.
  The receipt keeps the existing net alive by immutable copy-on-write ownership;
  Q3 never re-extracts or converts a Cartesian net. A bivariate interval Taylor
  provider differentiates that finite-degree homogeneous net by exact Bernstein
  finite differences and native widths, then forms the rational quotient through
  the requested total order. Only derivatives above the homogeneous degree are
  structurally zero; reciprocal composition retains nonzero rational derivatives.
  Normalization uses interval product, square-root and reciprocal recurrences.
  Each genuine offset needs one extra source order; nesting therefore requests
  the actual fourth and higher source derivatives. No numeric point Taylor jet
  supplies interval authority. Preparation and temporary requested-order payloads
  are overflow checked and paid before allocation by the caller's existing work
  owner. Singular normal/denominator and foreign receipts are typed failures.
  Evaluation restricts each derivative Bernstein net to the complete outward
  normalized query rectangle, then uses its convex coefficient hull. Endpoint
  subdivision retains every restricted control, including mixed derivatives;
  the two occurrences of an interval parameter are not treated as independent
  blend weights for a whole-box range. A singleton still evaluates its original
  point. Full native axes need no restriction allocation. Restriction scratch,
  retained row/column slots and every subdivision transition are paid before
  allocation or execution by the same caller; no local work limit is introduced.
  An original degree-one translation authority may retain the exact law
  `S(u,v)=C(u)+T(v-v0)` (or the transposed law), proved from equal original
  positive weight rows and identical expansion-exact control differences. The
  two-control translation axis uses its actual native knot interval, including
  nonclamped exterior knots. Its generating rail is the first row/column of the
  same retained original homogeneous net, not a Cartesian reconstruction.
  Requested-order rail jets and genuine offset normals then depend only on the
  varying native axis; mixed translation derivatives vanish by that whole law.
  Scalar storage and recurrence loops contain only the actual unary coefficients.
  The affine translation term is restored to the original full closed query
  after the entire offset chain. Original constant rail coordinates are exact
  partition-of-unity identities, not assumed zero higher rational derivatives;
  the varying rational coordinate retains its actual fourth and fifth orders.
  A singleton retained weight hull proves a constant homogeneous denominator
  during the already-paid coefficient scan; no source-wide fallback scan occurs.

  A straight generating rail grants a constant-normal rectangle integral only
  after exact constant-coordinate and strict control-order proof on its original
  single Bernstein span. Positive rational Bernstein weights and increasing
  controls prove a strictly monotone physical coordinate: the derivative sign
  is the positive pair sum of `(j-i)(Pj-Pi) wi wj Bi Bj / (W² t(1-t))`;
  strict adjacent endpoint differences certify the closed endpoints as well.
  The physical rectangle area is the cross product of original endpoint
  displacement and translation displacement. Its centroid is their midpoint
  plus the sum of genuine offsets along the certified constant unit normal.
  Endpoint evaluations use the same original coefficient owner and native
  fractions. No sampled normal, changed trim, tolerance-based collinearity or
  parameter-affine assumption grants this integral. Other rails retain the
  original requested-order composition and adaptive integration. Every admission
  read, output/scratch slot and executed recurrence remains caller-paid.
  Existing first-order and third-order contracts remain unchanged.
  The original native owner also issues a paid selected cover; every original
  span/knot scan, periodic lift and retained token slot uses the same callback.
  `SurfaceAreaNativeOffsetTaylorPartition` retains one requested-order provider
  per original base span and reuses it for every validated periodic lift. Its
  preparation admission follows the concrete lower surface basis matrices,
  tensor accumulations, Bernstein scaling and retained third-order nets before
  that lower constructor allocates. Input control-point admission retains its
  existing quantity. Scalar Taylor operations pay each output slot before
  allocation and each convolution/reciprocal recurrence through the same work
  owner. A nonzero offset of an original B-spline, including nesting, consumes
  the genuine higher-order chain from innermost to outermost; zero distances
  retain the same chart without consuming derivative order. Owning native
  rectangles/fans grant smooth third-order density support. A box covering more
  than one selected span has only value authority. Other unproved source families
  retain their existing explicit incomplete branch.
- Original C0 rolling-ball supports may use `SurfaceAreaNativeRollingBallPartition`
  when their three nonperiodic B-spline rails have exactly identical degree,
  knots and positive weights, normalized native domain, and exact constant
  control differences from the center. Exact floating-point expansions prove
  the two radial translations independently of tolerance. The original rational
  partition of unity makes each radial constant; the unchanged normalized minor
  circular section is composed with closed native center-curve receipts.
  Receipts retain original source, tolerance, knot index and one-sided domain.
  Cross-knot fields remain value-only; a selected owning span grants smooth
  density derivatives through third source order. No rounded conversion is an
  authority. Native rectangles and exact radial fan cuts retain all original
  measure. Equal-weight degree-one center spans alone permit local U translation
  elimination, never a globally smooth claim about the C0 support. Preparation
  and each closed curve evaluation use topology's same non-escaping work
  callback; no private retry, subdivision, budget or error allowance is created.
  Before lower coefficient preparation allocates, the caller pays for every
  actual homogeneous matrix slot, original-basis recurrence slot and scalar
  recurrence/accumulation transition. Products are overflow checked; charging
  stops at the existing work callback's first refusal. Isolated spans pay only
  their direct control matrices; nonisolated spans pay their actual degree-sized
  original basis matrices and conversion recurrences. Existing lower start/span
  phase charges remain separate. Thus allocated scratch and retained coefficient
  storage are bounded by admitted work, without redefining the control-point
  quantity, inventing a degree ceiling or changing default options.
  Unproved C0 families remain explicitly incomplete. Behavioral ownership is
  [RollingBallSurfaceAreaIntegrationTests](../../../Tests/CADTopologyTests/RollingBallSurfaceAreaIntegrationTests.swift).
- A C0 ruled support may retain a structurally equivalent tensor for native
  span integration only when its original nonperiodic B-spline rails have
  exactly equal degrees, complete knot arrays, native domains and positive
  stored weight arrays. With the same original basis and denominator `W`,
  `(1-v)N0/W + v*N1/W = ((1-v)N0+v*N1)/W`. Two stored control/weight rows and
  the original U knots, with linear V knots `0,0,1,1`, express this identity
  without refinement, fitting, conversion or parameter normalization.
  `SurfaceAreaRuledTensorAuthority` retains the original ruled support and
  this tensor together. The prepared integrand retains the original support
  for trim/source identity; the tensor supplies only native span enclosures.
  Original one-sided spans, cross-knot value-only proofs, control admission,
  query-wide error/work/depth and cancellation remain unchanged. This receipt
  does not admit unequal rail denominators, periodic rails, shortened native
  charts or other unproved non-C1 rail families. Smooth ruled supports retain
  their existing direct prepared route. Tests are owned by
  [RuledSurfaceAreaIntegrationTests](../../../Tests/CADTopologyTests/RuledSurfaceAreaIntegrationTests.swift).
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
  Implicit charts outside the exact connected affine or open same-coordinate/direction smooth positive-weight chain families and non-affine
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
  The package-facing `intervalProof` also supplies retained original wall-chart
  values to Modeling's bridge candidate construction. That caller must provide
  its work callback and retain the same chart/support/tolerance authority.
  A value-only join proof never grants smooth higher derivatives; bridge
  continuity admission remains a separate whole-boundary proof.
  Rigid fraction/UV maps, offset identity and periodic translations propagate
  this proof distinction. Fan enclosure retains the complete original measure;
  native piece intersection restricts chart enclosure only. Preparation is
  bounded by the admitted graph cell count and does not allocate error/work
  budgets. Closed curves, mixed free coordinates/directions, inexact endpoint
  joins, non-affine supports and unresolved constant minors remain typed failures.
- The nonlinear implicit family uses only the original lower root certificate
  and the [prepared closed localizer](../DESIGN.md). It admits an open same-coordinate/direction chain
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
  multispan, mixed-coordinate/direction, closed and procedural implicit supports remain incomplete typed
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

Independent tests perturb interior original coefficients without changing endpoint samples, retain genuine rational weights and direction/wrappers, and show that omitted endpoint correction breaks four-field containment. Existing forward/reverse/rigid public area/XYZ centroid cases must pass their unchanged60s limits before this bounded scope is complete. General rational multispan, mixed-coordinate/direction multicell and closed charts remain separate gaps.

Native evidence for the bounded iso-image route: all five new parameter cases pass, including original fractions/reversal/rigid identity, interior-coefficient refusal and independent nonzero endpoint area/XYZ corrections. The unchanged public forward/reverse/rigid rational band cases and work/endpoint refusal pass in1.395s. The complete current73-test face-area suite passes in27.853s; the lower37-test original implicit suite passes in.327s. These measurements describe this Native snapshot and do not certify general charts or other targets.

### Open Nonlinear Original Graph Chains (PAR.Q3MULT1)

The bounded nonlinear chart family additionally admits an open original graph
chain on the same two nonperiodic positive-weight single-span supports. Every
cell retains the same original free coordinate and direction; directed native
free endpoints must agree exactly. Original lower closed endpoint proofs on
both supports must establish complete four-coordinate connection differences
within the existing64-ulp parameter-rounding contract. Certificate-tolerance
connection or midpoint overlap alone cannot authorize a missing segment.

The original intersection remains the immutable authority; no single-cell
replacement certificate is constructed. Its equal global pieces have width
`1/N`. The stored trim fraction map selects original cell indices and local
fractions `N*f-i`; lower native derivatives already include the global `N`
powers. The chart applies only the original trim slope powers. A closed
request intersecting multiple owning pieces publishes a value-only union of
positions and one-sided first tangents, without higher-derivative authority
or a retained root state. A smooth piece retains its own original cell root;
restriction cannot move that state to another cell. The lower endpoint-Taylor
root-cover restriction uses global fraction displacement `localDelta/N`,
consistent with those original derivative powers.

Original chart preparation, every cell's closed-root prepare/advance, joins,
and integration consume the caller's existing query work callback. Counts
are preflight-bounded before preparation; no per-piece error, depth, work or
allocation allowance is introduced. Wrappers preserve fraction/direction,
selected source and smooth/value-only proof kinds. Closed, mixed-coordinate,
mixed-direction, periodic, multispan and procedural chains remain explicit
unfinished families. The iso-image shortcut remains limited to its existing
smooth whole-chart proof, rather than inferring a chain identity from samples.

Independent completion evidence uses the already constructed two-cell
polynomial fixture and its physical area `13/196608`, centroid
`(363/66560,15/1664,0)`, partial/reversed/rigid original fractions, closed
one-sided jet containment, foreign/tolerance/root-cell refusals, exact
connection refusal and shared low-work/depth/cancellation behavior.

### Original Degree-One Translated Ruled Rectangle Integral

The original ruled/tensor receipt may integrate an actual rectangle on one
original degree-one rail span by change of variable. Admission retains the
original two rails, positive original weights, exact full knot/weight identity,
and the existing expansion-proved whole-control V-translation certificate.
The owning prepared native bounds must match a positive original knot span;
its original active control indices, rather than extracted coefficient count,
own the integral. No surface or trim is replaced.

For original span `[a,b]`, controls `P0,P1`, weights `w0,w1` and translation
`T`, the original law is `h(u)=w1*(u-a)/(w0*(b-u)+w1*(u-a))`.
Positive weights prove strict monotonicity. Outward endpoint laws give the
rectangle integral `|cross(P1-P0,T)|*(h1-h0)*(v1-v0)` and centroid
`P0+(P1-P0)*(h0+h1)/2+T*(v0+v1)/2`. The same outward result supplies area
and all three reference-relative moments. Stored endpoint values of h at
original a/b are exactly 0/1; interior arithmetic stays outward. The actual
normalized rectangle fraction and original native bounds retain authority.

The caller's existing cell admission pays this bounded original-control
operation; cancellation is checked before publication. Foreign source,
tolerance, span or rectangle receipts fail explicitly. Unproved translation,
higher degree and nonrectangular shapes retain their existing adaptive route.
Nonfinite, singular or contradictory arithmetic cannot publish an integral.
The independent four-field bounds must contain literals with existing64ulp
precision; final query acceptance still owns the original single error budget.
Public original rectangle/hole/reverse/rigid/genuine-weight cases retain their
unchanged geometry, tolerances, work/depth limits and60s test limits.

## State, Ownership, and Lifecycle

| Higher-order state | Native / WASM / Embedded storage | Isolation | Read / mutation entry | Release |
|---|---|---|---|---|
| Original coefficient receipt | Immutable COW source and homogeneous net | Value ownership | Checked coefficient accessor; no mutation | Last retained value release |
| Prepared Taylor derivative nets | Immutable COW interval arrays | Value ownership | Validated original receipt query; no mutation | Prepared invocation release |
| Scalar algebra scratch | Invocation-local COW value arrays | Exclusive local mutation | Checked `set` inside synchronous operation; callback retained nowhere | Return or throw releases local values |
| Work quantity | Caller's original query owner | Same nonescaping callback on every target | No component-local counter or budget reset | Caller query lifetime |

No target condition changes this storage, Sendable, ownership or failure contract.
Higher-order behavioral ownership is
[SurfaceAreaHigherCoefficientTaylorTests](../../../Tests/CADGeometryTests/SurfaceAreaHigherCoefficientTaylorTests.swift)
and [NestedOffsetSurfaceAreaIntegrationTests](../../../Tests/CADTopologyTests/NestedOffsetSurfaceAreaIntegrationTests.swift).
Native, normal WASM and Embedded results are recorded separately; source-only
preparation does not establish target compile/link/runtime success.

### Remaining Public Q3 Completion Boundary

[OCCT requirement Q3](../../../OCCT_REQUIREMENTS.md) requires general
free-surface area and area centroid through `BRepModel.faceAreaMeasurement`.
Higher-order coefficient tests establish their lower contract only. The public
completion matrix below reuses unchanged earlier proofs and names the remaining
consumer gaps; it does not add adjacent intersection-generation features.

| Required input family | Existing consumer evidence | Remaining public completion evidence |
|---|---|---|
| B-spline, including rational, nonclamped, periodic and C0 native spans | Polynomial, periodic and C0 rectangle/fan/hole fixtures exist; ordinary `.spline` now has an original homogeneous coefficient source path, awaiting verification | One independent rational nonclamped area/XYZ case and affected existing native-domain cases on the new original-owner route |
| Genuine and nested B-spline offsets | Native19 proves original requested-order derivatives, rational nested and curved forward/reverse public area/XYZ under unchanged tolerances and shared work; existing single polynomial offset integrals | Periodic lift and C0 owning-span public area/XYZ cases |
| Ruled surfaces | Smooth direct rails and original same-basis/denominator C0 tensor fixtures | Original piecewise unequal denominator or basis rails with independent area/XYZ; current explicit admission marker remains open |
| Rolling-ball surfaces | Smooth rails and original C0 constant-radial same-basis quarter-cylinder proof | Original piecewise varying radial or unequal denominator rails with independent area/XYZ; current explicit admission marker remains open |
| Required trim/support domains | Numeric trims, holes/reversal/rigid fractions, affine and open original implicit graph family proofs; C0/C1 numeric spline trims now have an original one-sided/value-only source route awaiting runtime evidence | New piecewise numeric chart public area/XYZ evidence; periodic/multispan, mixed-coordinate/direction, closed and procedural implicit chart admission remains explicitly incomplete; public integrals must consume original supplied charts |
| Failure and target authority | Shared query work, control admission, depth and cancellation proofs; immutable retained coefficient state | Preserve typed failures and source/tolerance/side/lift ownership; Native, normal WASM, Embedded and main integration are separate terminal obligations |

Native verification of this higher-offset snapshot passes 14 declarations and
19 cases, including all three former shared-work refusals, the unchanged area
and XYZ centroid oracles, and an original rational nonclamped translation law.
The original 262144 query-work ceiling, precision, cancellation and resource
assertions are unchanged. The public nested-offset cases now publish certified
measurements; this evidence does not close the remaining rows or other targets.

### Original Coefficient Authority for Ordinary Spline Integrands

Ordinary B-spline and structurally exact ruled-tensor preparation retain the
existing original homogeneous native-span owner rather than Cartesian extracted
patches. This applies to rational, nonclamped and periodic sources as well as
clamped sources. The existing preparation admission runs before lower allocation;
the original closed native cover and each requested-order Taylor provider use
the same caller work callback. Order-three providers consume immutable original
coefficient receipts, including their one-sided span and exact periodic lift.

Selected rectangle and fan domains retain their original source and span index.
Unselected boxes crossing a non-C1 knot publish value-only density bounds;
smooth pieces retain their original derivatives. Closed knot values may include
both one-sided owners, and a periodic seam is never replaced by a rounded patch.
The physical surface and supplied trim are unchanged. Centered fan evaluation
passes the same nonescaping work owner into both source evaluations and their
fallback path. No local budget, tolerance, depth limit or cancellation policy is
introduced. Source implementation alone is not public integration evidence;
affected original rational/nonclamped, periodic, C0, trim/hole/orientation and
area/XYZ centroid paths still require later target-specific verification.

### Piecewise Original Numeric Trim Charts

C0 and C1 B-spline parameter curves retain their original degree, knots,
positive weights and XY coefficients. Their integral-only constant-V tensor
lift uses two identical original rows, so partition of unity proves that its
XY value and every U derivative are exactly those of the supplied trim. No
fit, knot insertion, Cartesian extraction or geometry replacement is used.
The lift's actual scalar/control ownership and original native preparation are
admitted through the query's existing callback before allocation.

The original normalized fraction maps to the complete native U interval with
closed endpoints retained exactly. Each positive-width owning native span
provides a one-sided smooth jet. A box intersecting multiple original spans
publishes only the union of UV values and first tangents, never a Taylor jet
across a knot. Singleton joins retain both one-sided owners. These proof kinds
feed the existing signed fan and area/XYZ first-moment algebra; hasNativeJoins
routes aggregate uncertainty to the same topology adaptive owner. Every original
fraction remains in the integration measure, with original hole/orientation,
absolute/relative/centroid goals, work, depth and cancellation unchanged.
Rigid affine, reversed and translated wrappers compose the retained proof kind
without converting the source curve. Discontinuous or invalid original knots
remain typed input failures. General projected/non-affine mapped charts remain
explicitly incomplete. Build and public runtime evidence are deferred.

## Independent Original Ruled Rail Partitions

Ruled rails with different original degrees, knot vectors or positive rational
weights retain separate prepared curve owners. `SurfaceAreaNativeRuledPartition`
forms the common native U partition from both original rail knots and evaluates
`A(u)+(B(u)-A(u))*v` with each original one-sided jet. It does not author a
same-denominator tensor or change the rail parameterization. Rectangle and
exact constant-U fan domains expose the same partition to the area owner.
On an owning U cell the complete third-order product rule is valid; an interval
crossing a join reports value-only density bounds. Preparation, native knot
lifts, curve queries and every output owner use the caller's existing work
counter. Periodic rails enumerate all lifted knots incident to the ruled
surface's finite actual U domain; seam sides remain separate owners.

## Independent Original Rolling-Ball Rails

General piecewise rolling-ball area preparation partitions U by the union of
all three original rail knot boundaries. Each rail retains its own homogeneous
coefficients and denominator. Every positive native cell obtains its complete
one-sided closed jets before composing the original minor-arc rational section.
The RollingBall owner's explicit-jet contract proves normalized radials, positive
section denominator and complete finite third derivatives. Across unresolved
joins, only density/moment value hulls are exposed; within an owning cell, the
original derivatives authorize density gradients and Hessians. No constant
radial, common basis or shared rail denominator is assumed by this route.

The caller's cumulative work callback owns preparation, span visits and section
composition. Original rectangle and exact constant-U fan partition coverage is
retained. Other fans use complete piecewise value hulls, not a fabricated smooth
jet. Source failure and cancellation propagate to the area integrator.

## Original Monomial Volume Flux

Prepared original surface jets also bound the ten divergence-theorem volume
moment fluxes about a supplied reference point. Exponent order is volume, X, Y,
Z, XX, YY, ZZ, XY, XZ, YZ. Each field is
`(x-reference.x)^(a+1) * (y-reference.y)^b * (z-reference.z)^c *
 (Su cross Sv).x / (a+1)`.
Rectangle and signed boundary-fan pullbacks retain the existing original native
cell and chart authority. Source third derivatives establish flux Hessians;
lower-order/join receipts publish only the derivatives they actually own.
The shared caller work callback pays algebra before composition. No sampled
surface normal, fitted chart or unsigned area density supplies volume authority.

### Original volume fan measure ownership

Volume fan bounds consume the same geometry-issued native fan domain as area
bounds. The retained original pcurve, anchor and radial subinterval must match
before evaluating any flux. Issuance proves that the complete fan measure lies
in the owning native rectangle; the exact radial cuts form the whole original
fan without overlaps or gaps. Owning-jet restrictions only choose its original
one-sided polynomial and never shorten or reinterpret the integration measure.
A general fan without this receipt uses the complete piecewise value enclosure
and receives no smooth Taylor authority across native joins.

### Requested original offset Taylor order

Offset Taylor composition accepts a requested result order of at least three.
The retained original source must provide exactly that order plus one genuine
normal differentiation per retained offset layer. Every layer reduces the
actual Taylor order by one; no omitted source derivative is padded. Existing
area callers retain the default order three. Silhouette callers supply order
four and the same cumulative work owner.

### Original higher-jet value port

Package Taylor scalar/vector values expose immutable coefficient reads and their
original tolerance/order to sibling lower algorithms. Coefficient storage and
construction remain owned here; visibility does not introduce a new budget or
a numeric source authority.

Original image parameter charts prepare their original child chart once, retain
its root restrictions and derivative-join authority, and apply exact inverse
ratio/axis mapping to that child proof. Value-only original joins stay value-only;
spatial image coefficients never supply a pcurve authority by sampled inversion.

### Original Signed Flux Integration Port

`SurfaceAreaParameterChartEncloser.signedFluxIntegrationBounds` exposes the
original value interval of `u*v'`, its same-owner closed midpoint interval,
and its second derivative `u''*v' + 2*u'*v'' + u*v'''`. Smooth original
chart cells permit midpoint quadrature with a whole second-order remainder.
Native joins publish value-only bounds and no midpoint derivative authority.
The caller owns interval subdivision, depth and cumulative work; this port
retains no separate allowance and all nested image source admission recurses
through the original pcurve and support values.

### Caller-Admitted Original Native Partitions

Native rectangle and fan domain producers accept the composing depth ceiling and
one original visit callback. Fixed native-owner scans, exact radial cut checks,
allocation publication, sorting comparisons and gap-free coverage comparisons
admit a depth-zero visit before work. They introduce no subdivision or new
allowance. Retained owner/domain/radial receipts and existing maximumCount are
unchanged; facade remapping to the original trim is charged per retained domain.
Legacy convenience entries retain their existing cancellation-only policy.

### Original Unique Pole Offset Normal

Offset Taylor composition may consume an explicit first source normal Taylor
jet only after the caller has admitted the whole original collapsed boundary's
unique oriented normal authority. Its order is exactly one less than the raw
source order. That jet replaces the first cross-product normalization alone;
subsequent offset layers must establish their own original normal regularity.
A nonzero quotient on one selected panel does not establish uniqueness or
authorize a cone-like apex offset. All coefficient work uses the same callback.


### Selected Native Taylor Byte Admission

The original coefficient Taylor encloser forwards an optional synchronous byte
callback through derivative-net retention, Bernstein restriction scratch/output,
scalar Taylor result construction and quotient arithmetic. The checked reservation
precedes each concrete array allocation/COW scratch copy; work and bytes are
separate units. Legacy nil callbacks preserve the previous contract. Selected
native closed-jet callers may provide a nonescaping byte callback borrowed only
for the synchronous query, without storing it in immutable source receipts.
These ports do not establish complete allocation accounting for unrelated
implicit, image or general surface-composition queries.

Vector Taylor arithmetic accepts the same optional byte callback as scalar arithmetic. Every allocating scalar result in addition, scaling, multiplication, cross products, normalization, truncation and differentiation forwards that callback before allocation; vector wrappers retain no independent byte policy.

Retagging a Taylor field changes only validated tolerance metadata and shares the existing immutable coefficient array. It performs no coefficient transformation, allocation, or geometric acceptance. A spatial image retags transported fields with target physical tolerance after evaluating the source with its local calculation policy. Subsequent allocating arithmetic retains its normal byte admission.

Offset Taylor composition accepts the composing optional BYTE callback and forwards it to every scalar coefficient constant, differentiated tangent, cross product, normal normalization, truncation and scaled sum allocation. Supported original higher providers remain responsible for their own preparation and query bytes. This allocation contract changes no offset distance, translation premise, unique-pole normal authority or requested source order.

Taylor constant-term replacement admits the actual retained coefficient count and visits before COW mutation. The immutable input backing remains shared until that mutation; the replacement allocation is charged through the composing optional byte callback. Metadata retagging remains a shared immutable operation.

### Bounded Area Preparation and Native Chart Storage

Prepared area and UV-chart producers compose independent source, algebra and subdivision ceilings and optional original BYTE requests. Native chart preparation retains one-sided original coefficient owners; no derived tensor is promoted to authored support authority. Conversion rows, native-span buffers and retained Taylor providers reserve their concrete typed payload before allocation. Query Taylor scratch forwards the same BYTE callback, while callbacks remain invocation arguments rather than retained geometric identity. Generic implicit and inverse-chart producers remain responsible for their original root localization and source admission; unsupported lower policies cannot become successful integration receipts.

### Original Translation Preparation Admission

Selected integration preparation proves common control displacements with exact
rational original coordinates. Each coefficient operation and retained limb
allocation borrows the composing work and optional BYTE callbacks. Source
recursion and algebra depth are separate; a proof cannot inherit an algebra
ceiling from spatial subdivision. Weight, knot and control comparisons visit
the original buffers without manufacturing translated row arrays. A successful
translation receipt changes neither original rails nor physical tolerances.

Original plane-derivative supports use the generic corrected closed-jet path.
Their raw construction, final boundary root spans and constraint supports remain
part of dimension admission. Adding the smooth correction never certifies a
smooth raw native join; the original rail continuity remains the prerequisite.

Original drafted curves and walls retain the directed generator, raw normal,
axis, pull, physical angle and authored heights. Generic original closed jets
are their geometry authority; analytic and native construction shortcuts
decline this family. Source dimension admission visits the generator under the
existing nesting ceiling. Area smoothness uses the original drafted first-order
continuity issuer over the complete query and never infers higher continuity
from a derivative hull or a fitted native candidate.

General rolling-ball fixed jet composition receives the same invocation work
and optional BYTE callback as its original owning-rail queries. Its composition
scratch consists of fixed value fields; no dimension-derived nominal work or
allocation fee substitutes for the lower operation visits. Original rail-query
buffers and returned partition records remain separately caller-admitted.

The ordinary fan-bound entry accepts optional BYTE admission and forwards it
through chart proof, original surface ownership and returned four-field buffers.
Value-only native joins use fixed component expressions rather than temporary
coordinate arrays. Returned and merged field payloads are admitted before
allocation; this is requested typed storage, not allocator-capacity evidence.

Native rectangle/fan partition methods receive optional BYTE admission through
the prepared integration facade; original domain outputs and chart-bound
remappings are separately admitted. Nested offset preparation visits every
source layer, including zero-distance layers, and applies the existing source
nesting ceiling independently of its retained exact algebra capability.

Original guide traversal chains retain their exact station partition and every
raw directed root traversal in area preparation. Dimension admission traverses
the raw sources under the existing nesting/work policy. Derivative-order
selection consumes only the constructor-retained exact continuity order; a hull
across distinct pieces does not improve that order.

Iso-image endpoint corrections and exact rectangular translation elimination
forward the composing work and optional BYTE callback into every original
surface query. Endpoint choices are fixed fields rather than temporary arrays;
returned four-moment and union buffers are admitted before allocation. This
retains the original fan measure and translation authority and does not certify
physical allocator capacity or unresolved chart/source-family accounting.

Original guide endpoint corrections retain their raw guide RootSpan and both
section endpoint RootSpans in area preparation. Their smooth correction basis
does not improve continuity across a guide join. Dimension admission descends
each original source rather than a candidate native construction.

The exact affine implicit-chart solver retains its three dependent columns and
cross products as fixed value fields. It computes selected U/V coefficient pairs
without dynamic column/index/coefficient arrays. Each original subtraction,
product, sum, quotient and coordinate read invokes the composing work owner
before evaluation; the fixed value composition has no dynamic scratch BYTE
request. Original graph/source admission and complete non-affine, closed or
mixed-coordinate graph charts remain separate producer obligations.
