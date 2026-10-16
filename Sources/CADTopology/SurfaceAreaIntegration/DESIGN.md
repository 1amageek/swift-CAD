# Surface Area Integration

## Purpose and Scope
Child of [CADTopology](../DESIGN.md). Owns certified area and area-centroid
integration over face loops on exact surfaces. No children.

## Responsibilities and Boundaries
Topology owns loop roles, orientation normalization, resource admission,
quadrature and acceptance. CADGeometry owns certified integrand derivatives.
Mesh/display data never enter this path.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADTopology](../DESIGN.md) | parent | face/coedge pcurves | Query routing | Missing trims fail. |
| [Geometry integrands](../../CADGeometry/SurfaceAreaIntegration/DESIGN.md) | depends on | outward bounds of density and centered moments | Exact fan pullback | Unsupported derivatives do not become zeros. |

## Architecture
```text
face loops -> continuous UV chains -> signed fan squares
    -> certified density and centered moments -> bounded adaptive integration
        -> normalize each loop's traversal -> subtract holes -> interval centroid
```

## Contracts and Invariants
Original polyline rails retain their exact adjacent-point clock and original
point count admission. Their complete continuity is C0 unless an owning lower
producer proves more; array adjacency cannot certify a smooth normalized join.
- Original loop winding queries accept an optional cumulative byte admission
  callback. Requested typed capacities for pending ranges, accepted boxes,
  ordering copies and homotopy vertices are admitted before allocation. The
  authored and validated-loop views retain immutable source buffers without
  duplicating curves. A missing callback preserves historical work/depth policy;
  it does not establish bounded storage. Lower chart/enclosure scratch must use
  the same callback before a whole-query byte guarantee can be claimed.
- Exact authored UV closure permits a separate strict winding query without a
  modeling-tolerance corridor. Literal axis endpoints, polyline endpoints and
  clamped positive-weight native UV spline controls prove each exact junction;
  unchanged-UV full word traversals preserve that authority. Complete original
  boxes must exclude the query with zero added clearance before the homotopy
  is formed from their actual intersections. Unsupported endpoint relations
  retain the existing conservative classification rather than inferring closure
  from overlapping endpoint boxes. This does not change modeling tolerance or
  original proof depth/work limits.
- Retained normalized curve construction charts remain original Geometry
  sources. Admission traverses their original child controls under the existing
  nesting/dimension policy; analytic prism shortcuts defer to original generic
  integration. Construction-chart labels never become replacement curve data.
- Affine and constant-axis UV boundary boxes evaluate the original endpoint
  difference and normalized interval with outward operations. Numeric midpoint
  evaluation and a fixed roundoff multiplier do not authorize these boxes.
- Polyline boxes use Geometry's exact original Euclidean arc-length prefix
  chart and every intersected authored segment. Original owning values are
  unioned at joins; an integer segment ordinal or rounded normalized cut never
  becomes the source parameter law.
- A predicate with no periodic chart shifts does not reevaluate a numeric
  start point for alignment. Original boxes already occupy its authored chart;
  only periodic chart selection needs a separate reference receipt. The legacy
  periodic reference branch remains a bounded-source completion dependency.
- Native UV splines and continuations consume Geometry's original order-zero
  value facade. Original owning values are unioned at joins without a C3
  continuity assumption; all lower preparation/coefficients and query bytes use
  the same caller admission. Harmonic values use that facade as well, retaining
  explicit failure when a selected byte ceiling has no lower scratch producer.
- Original image and affine-word UV carriers use that same value facade. They
  forward the selected storage callback into original source validation and
  coefficient transport; missing image scratch admission cannot silently bypass
  a caller-selected byte ceiling.
- Original C0 rolling-ball measurements consume Geometry's opaque native
  rolling domains and closed center-curve receipts. Surface preparation and
  every lower owning-span evaluation advance the existing query work counter.
  Exact rectangles may eliminate U separately on structurally linear owning
  spans; native initial partition depth, aggregate interval error and all XYZ
  centered moments remain within the original query limits. Cross-knot fan
  cells receive value-only bounds. No sampled support or converted proxy enters
  the acceptance path. The behavioral owner is
  [RollingBallSurfaceAreaIntegrationTests](../../../Tests/CADTopologyTests/RollingBallSurfaceAreaIntegrationTests.swift).
- Structurally admitted C0 ruled supports consume Geometry's retained original
  ruled/tensor identity receipt and its existing native span contract. Original
  face supports, pcurves, loops, holes and traversal remain authoritative;
  native span selection restricts enclosure only. Smooth one-sided density
  bounds and cross-knot value-only bounds feed the same quadrature and final
  four-field acceptance, with one query error/work/depth allowance. No surface
  conversion, sampled normal, or globally smooth jet is substituted across a
  fold. The public behavioral owner is
  [RuledSurfaceAreaIntegrationTests](../../../Tests/CADTopologyTests/RuledSurfaceAreaIntegrationTests.swift).
- Nonlinear implicit queries on structurally affine supports retain each
  original curve's already certified start/end intervals after connection
  validation. They use geometry's paired centered Green fields and add that
  curve's complete endpoint primitive correction to its integrated intervals.
  Corrections are never telescoped across rounding-sized joins or omitted.
  Range and midpoint proofs use the same query work callback as before; their
  fixed-size mean-value contraction introduces no cache, budget, allowance or
  hidden refinement. This route retains the original signed fan measure and
  all final area/centroid acceptance checks. Other families, native joins and
  C0 support paths retain their existing integration route.
- The exact fan map is `a + r(c(t)-a)`; its Jacobian is
  `r det(c(t)-a,c'(t))`. Signed integration permits concave loops and holes.
- Every consecutive pcurve endpoint agrees to parameter rounding precision;
  modeling-tolerance gaps are refused because they leave an undefined domain.
- Each outer loop contributes positive area; each inner loop subtracts area,
  independent of face and chain reversal.
- Area error is at most `distance^2 + relative * areaLower`; centroid
  Euclidean error is at most `distance`, certified by component intervals.
- Acceptance requires strictly positive area lower bound and finite moments.
- Structural affine support authority eliminates the radial integral exactly:
  boundary area density is `det/2`, and centered moments are
  `anchorOffset*det/2 + displacement*det/3`. Exact curved pcurves remain
  the integration source; their boundary fraction still receives certified bounds.
- Exact four-edge iso-parametric rectangular loops may use a geometry-owned
  translation certificate. The translation coordinate is integrated exactly
  at its interval-enclosed midpoint; only the other native parameter receives
  adaptive quadrature. A recoverable singular enclosure on this one-dimensional
  path subdivides only that varying parameter; subdividing the eliminated radial
  coordinate cannot improve the certificate. Other trim/support structures retain
  fan integration and its two-dimensional recoverable-enclosure subdivision rule.
- A conservative UV enclosure extending outside a bounded support requests
  boundary subdivision; it is never clipped to manufacture admission.
- A cell uses a centered Taylor enclosure, with first-derivative mean-value
  bounds when certified second derivatives are unavailable. Midpoint sample
  values themselves are interval bounds. No difference of sampled quadrature
  rules is used as an error proof.
- C0 support partitioning preserves the original signed fan and exact trim
  chart. A single native span permits one-sided smooth Taylor bounds; a cell
  crossing a knot uses only certified integrand value ranges times its full
  fan measure. No derivative of a discontinuous density enters Taylor bounds.
  Translation rectangles partition at exact native knot coordinates; span
  identity owns endpoint derivatives while shared boundaries have zero measure.
- Error targets are allocated once per query and shared across all curves,
  spans, pieces and loops. Range-only cells contribute their complete interval
  uncertainty to the same aggregate error target; they do not receive a new
  absolute tolerance per piece. Final area and centroid interval acceptance
  remains authoritative. Work and depth accounting also remain query-wide.
- Numeric mapped trims retain their original stored curve and source fraction
  chart. Geometry prepares exact directed offset or affine rigid chart authority
  against the face's exact support, after bounded nested input admission.
  Topology supplies this authority to fan/boundary enclosure evaluation; the
  original signed fan measure, loop winding and whole-query resource/error
  targets are unchanged. Geometry also admits the exact open connected affine
  implicit family under its original native-UV certificate and fraction authority;
  topology uses that prepared chart under the same signed fan and whole-query
  limits. Remaining implicit charts and non-affine rigid images retain typed
  unsupported failures. Invalid source fractions or foreign targets cannot
  become a clamped or approximately equivalent accepted trim.
- An admitted affine implicit chain retains the original equal `1/N` cell
  fractions and unequal native cell widths. Its geometry-owned chart proof
  distinguishes a smooth owning piece from a value-only join enclosure.
  Charts with native joins use the existing aggregate uncertainty integral;
  join-crossing cells never enter higher-order Taylor acceptance and subdivide
  the original boundary fraction T. The existing exact affine radial integral
  remains available on this path; it removes R without changing the signed fan.
  Every contribution, including a join-crossing range, consumes the original
  curve's error target and query-wide cell/depth/cancellation accounting. No
  piece receives a new allowance or silently closes a tolerance-sized gap.
- The initial nonlinear implicit family retains the geometry-owned single
  positive-weight single-Bezier-span, open one-cell chart contract. Query work begins before
  chart preparation and effort estimation. A synchronous non-escaping callback
  charges every lower preparation, contraction and endpoint-phase advance to
  the same processed-work counter used by integration cells. A lower request
  for refinement subdivides the original T interval at depth+1 under the same
  work and depth ceilings; it never refines internally or resets the counter.
- Original trim charts are prepared before any continuous-chart unwrapping.
  If a query contains this nonlinear family, its admitted original B-spline
  pair is nonperiodic and original charts supply closed endpoints under the
  same query work callback. All loops use this proof route, bypassing the
  shared sampled `continuousChartLift` and legacy implicit endpoint solvers.
  Each endpoint must be finite and no wider than 64 ulps at its chart scale;
  the complete outward difference between consecutive endpoints must lie
  inside that same rounding limit. Overlap or midpoint agreement alone does
  not certify connectivity. A certified finite first endpoint midpoint is
  cached as the fan anchor, avoiding `startParameter`. Queries without this
  family retain the existing unwrap and endpoint route.
- Queries containing this family estimate effort from the complete loops'
  prepared signed UV flux bounds. Coarse intervals are sufficient for effort;
  they do not authorize numerical midpoint acceptance. Estimator refinement
  uses the same T stack depth/work limits, and the older independently budgeted
  UV area integrator is not called on these queries. Smooth fan evaluation
  passes the non-escaping callback directly while owning the inout counter;
  no evaluation closure captures a counter already lent to an adaptive owner.
  The native aggregate evaluator explicitly lends that same counter into its
  synchronous evaluation callback for nonlinear chart operations. Whole-query
  area/moment goals and the final area/centroid interval tests remain unchanged.

## State, Ownership, and Lifecycle
Queries containing nonlinear charts retain two certified UV endpoint pairs per
admitted boundary curve. Their storage is bounded by the original query's
boundary-curve admission count; no endpoint or interval cache outlives the query.
Each invocation owns immutable prepared geometry. Smooth domains retain their
depth-first cell stack. C0 support and native-join chart domains own a balanced outward-sum tree and a heap of
refinable leaf uncertainties; at most `2*processedCells-1` tree records and
`processedCells` heap entries exist. Native initial partition depth counts
toward the original query depth limit. No shared mutable state or cache is
introduced.
Each retained boundary curve additionally owns one immutable prepared source
chart for its adaptive integration call. Chart preparation uses the original
query admission limits and never creates an independent adaptive budget.

## Failure, Concurrency, and Constraints
Admission limits boundary curves, input and expanded Bezier control points, processed cells and subdivision
depth. Cancellation is checked during preparation and between cells.
Resource exhaustion, singularity, unsupported charts and nonfinite/indeterminate
arithmetic throw typed KernelError. An uncertified value is never returned.

### Pending Original Root-Cover Continuation

The [Geometry retained original implicit root restriction](../../CADGeometry/DESIGN.md#retained-original-implicit-root-restriction)
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
[`SurfaceAreaIntegrationTests`](../../../Tests/CADTopologyTests/SurfaceAreaIntegrationTests.swift) owns exact planar and
curved fixtures, hole/reversal, boundary and typed resource/cancellation tests.
`FaceAreaMeasurementTests` proves public query routing and analytic regressions.
Changes require rechecking geometry derivative validity and capability claims.
Nonlinear implicit fixtures retain literal area `13/196608`, centroid
`(363/66560,15/1664,0)` and rigid-image centroid
`(193/1664,17003/66560,1/2)`, with an actual nonzero implicit signed fan.
Original fractions, both source roles, reversal, query work/depth/cancel and
truthful unsupported-family/foreign-support behavior own separate assertions.
The partial implicit endpoint anchor fixture has literal area `49/1572864`
and centroid `(4323/1003520,51/6272,0)`; its rigid image has centroid
`(733/6272,255203/1003520,1/2)`. Its loop starts with the partial implicit
edge and therefore exercises closed endpoint localization before anchor use,
with a nonzero signed fan. Endpoint work 2 under a one-cell query limit and
sub-modeling-tolerance gap rejection prove budget and connection ownership.
Rational single-cell fixtures retain unequal positive weights `[4,2,1]`,
the original Krawczyk graph and rational native-coordinate jets through order
three. The public area/centroid oracle selects the affine first support and
retains the same literal region and rigid image above. This proof is not
generalized to area integration on the rational selected support, periodic
or multispan supports, multiple nonlinear cells, closed or procedural charts.

The next bounded verification selects that original rational second support
itself. It must exercise the existing non-affine two-dimensional signed fan,
with implicit native edge `r=1/2`, `t=3/8..5/8` (native
`s=6/11..10/13`), upper edge `r=1` and two constant-U edges. The loop order is
upper, left, implicit, right; its anchor `(sHigh,1)` gives the implicit fan
determinant `s'(fraction)/2`, so the implicit contribution is nonzero.
Independent antiderivatives of `sqrt(1+16*t*t)`, `t*sqrt(1+16*t*t)` and
`t*t*sqrt(1+16*t*t)` define area `I0/4096` and centroid
`(I2/(32*I0),I1/(64*I0),1/128)`. Tests must retain original rational support,
source fractions, reversal and rigid image, with one aggregate four-field
error/work/depth/cancellation owner and unchanged 64-ulp joins. One-cell
exhaustion, foreign support and a real endpoint gap must refuse explicitly.
The original numeric fan path previously exceeded the three positive60s limits. The bounded iso-image route below now passes these original public oracles without relaxing their limits or error goals.

For the smooth non-affine implicit caller-work path, topology may consume the
geometry owner's centered fan range/midpoint pair under the existing T/R cell.
All other fan routes retain their contracts. This change is justified by the
three original positive curved-support cases exceeding their 60-second limits;
it must pass those same public oracles and limits before completion. See the
[geometry owner](../../CADGeometry/SurfaceAreaIntegration/DESIGN.md) for paired
chart authority and charging; topology continues to own the signed integral
and whole-query acceptance.

The existing integration DFS cell may retain the geometry owner's immutable
original chart proof for its exact T interval. R children share that proof;
T children retain it only as restriction input: the geometry owner validates
closed containment, proves the actual child midpoint with the same caller
work callback and mints a new exact-child-T token. A parent token cannot
directly enter the exact-T consumer. Existing per-cell
work, T/R depth/error rules and bounded stack remain authoritative. Accepted or
popped cells and query completion release their tokens; geometry internals and
jets remain behind the public package proof contract. The same original positive cases now pass through the bounded iso-image route; reuse alone previously did not complete them.

### Source-Centered Fan Pair Consumption

Numeric nonrectangular fan integration and retained original implicit fan
integration consume Geometry's same-owner range/midpoint pair. Topology keeps
its original four-field Taylor error goals, actual UV connectivity, original
fractions, shared work/depth/cancellation and midpoint fields. It does not
reconstruct native-span authority or infer a missing fourth derivative.
[Geometry](../../CADGeometry/SurfaceAreaIntegration/DESIGN.md#original-single-span-source-centered-fan-pair)
owns original source restrictions and all admission/failure conditions.


### Corrected Original Implicit Iso-Image Rectangle

Topology consumes [Geometry's original iso-image proof](../../CADGeometry/SurfaceAreaIntegration/DESIGN.md#original-implicit-iso-image-area-authority) to recognize an original boundary image in the existing translation rectangle route. It retains the actual original trim/chart and adjacent side coordinates rather than substituting a constant-axis pcurve. Complete monotone image and original endpoint authority must be present for rectangle admission. The source's existing64ulp connectivity check remains mandatory.

Every endpoint signed triangle correction is included in the area and reference-relative XYZ integral intervals. Correction uncertainty consumes the existing query-wide four-field error allowance before adaptive 1D integration; final area/centroid admission uses unchanged original tolerances. Preparation, root phases, correction evaluation, 1D cells, depth, cancellation and receipt release share the original query counters/lifetime. Nonrectangular or unproved images stay on the existing original fan path. All unchanged Native forward/reverse/rigid public cases now pass in1.395s; the current73-test face-area suite passes in27.853s. This bounded success leaves general Q3 and other targets open.

### Open Nonlinear Original Graph Chain Composition (PAR.Q3MULT1)

Topology consumes the [original nonlinear chain chart contract](../../CADGeometry/SurfaceAreaIntegration/DESIGN.md#open-nonlinear-original-graph-chains-parq3mult1).
The original loop, signed fan and each trim's normalized fraction remain
authority. Native chart joins use the existing value-only aggregate integral
route; the complete fan measure is retained and no Taylor gradient/Hessian
is admitted across a join. Every chart operation, including effort, endpoints
and native integrand range/midpoint operations, receives the same query work
callback initialized before chart preparation. All loops and original cells
share the existing control, boundary, work, depth and final four-field error
allowances. Source cell ownership does not create an independent integration
budget.

The independent public two-cell fixture has area `13/196608` and centroid
`(363/66560,15/1664,0)`, unchanged under chain reversal. Partial original
fractions and rigid images must retain physical oracles and endpoint
rounding authority. Exact connection, foreign support, resource/depth and
cancellation failures supplement the positive behavior; refusals alone do
not complete this family. Native evidence and portable evidence remain
separate, and this contract does not complete full general Q3.

### Original Translated Ruled Native Rectangle Consumption

Only an actual rectangular native cell may consume Geometry's
[original degree-one ruled rectangle integral](../../CADGeometry/SurfaceAreaIntegration/DESIGN.md#original-degree-one-translated-ruled-rectangle-integral).
The original ruled support, pcurves, native receipt and reference remain the
same. After the existing adaptive cell work/cancellation admission, the caller
requests all four integral intervals for its T subinterval and complete R
band. These are already integrals and receive no second cell-measure factor.
The existing global uncertainty accumulator and final area/centroid acceptance
remain unchanged. Holes and orientation retain original signed loop ownership.
A nil admission keeps the original native range/midpoint adaptive route;
invalid authority or numerical failure propagates. No new allowance or
geometric sampling is introduced, and full Q3/portable remain open.

### Caller-Paid Original Higher-Order Offset Fields

The existing translated rectangle range and midpoint calls both forward the
same invocation's nonescaping `consumeWork` callback to the
[Geometry integrand owner](../../CADGeometry/SurfaceAreaIntegration/DESIGN.md).
Original native cover preparation, requested-order coefficient storage and
nested offset recurrences therefore consume the existing shared cell/work
quantity before their allocations. Topology retains the same error goals,
cell/depth/control admission, cancellation, reference and final XYZ centroid
acceptance. It neither reconstructs coefficients nor supplies missing source
orders. Behavioral ownership is
[NestedOffsetSurfaceAreaIntegrationTests](../../../Tests/CADTopologyTests/NestedOffsetSurfaceAreaIntegrationTests.swift).
Native, normal WASM and Embedded proof remain distinct; source changes alone
do not establish the runtime contract.

The original native centered-fan range/midpoint and affine endpoint correction
calls also forward this same
nonescaping callback. It cannot create an independent work allowance while
consuming original homogeneous span receipts. The existing T/R cell, reference,
signed-loop measure and final four-field acceptance remain the upper owner.
This newly connected source path has not yet been verified.

Original offset translation authority may return complete physical rectangle
area and all three reference-relative moments after its original monotone
straight-rail proof. The shared query owner pays this invocation and its
original endpoint evaluation work; unchanged per-field goals decide whether
that complete interval is accepted. Missing moment fields or nonfinite integral
fields are explicit classification failures; they do not select another algorithm.
Finite intervals wider than the unchanged goals, and other rectangles, retain
the existing adaptive path. The geometry [child contract](../../CADGeometry/SurfaceAreaIntegration/DESIGN.md)
owns the exact whole-law and monotonicity proof, rather than this caller.

Original parameter-image and endpoint-continuation UV orientation integrals consume Geometry-owned original flux intervals and closed-root midpoint/second derivative bounds. Smooth spans use the integral midpoint Taylor remainder; native joins retain full value intervals. The complete signed gain and axis swap remain original chart authority. No sampled derivative, rounded inverse gain or unbounded refinement authorizes orientation.

Original native rectangle and radial fan partition producers receive this invocation’s subdivision ceiling and synchronous work callback. Every original owner scan, exact cut, coverage comparison and retained partition visit advances the same counter before integration; depth-zero partition work never receives an independent allowance.

### Immutable Original Loop Predicate Admission

A loop predicate can consume one loop directly from an exact or volumetric
`ValidatedBRepModel`. The receipt supplies both original pcurves and tolerance;
caller-admitted copying visits every coedge, and finite chart shifts plus the existing
48-depth ceiling are retained. Its constructor does not repeat opaque curve endpoint
validation because the unchanged original source has already passed that contract.
This entry does not accept independently copied or modified patch curves by assertion;
new patch curves still require their own complete bounded source admission. Signed
winding and exclusion consume the same caller work/depth policy afterward.

Receipt-bound loop predicates retain a read-only collection over the immutable
original coedge buffer. Construction validates each optional pcurve before retaining
that buffer; subsequent collection access cannot observe mutation or absence. It
allocates no copied parameter-curve array. Equality and hashing retain the preceding
curve-sequence semantics. Query enclosure/workspace allocations belong to their actual
lower producers and require separate caller storage admission.

A bounded authored-chart loop constructor receives its original owning support and caller source/subdivision caps. Each retained curve consumes Geometry's original continuous-chart lift with endpoint boxes under the same callback; sampled endpoint candidates are not admission authority. The resulting immutable authored view retains the original curves without a second source array. This path composes translated original volume trim loops, while the validated-loop constructor borrows unchanged original topology directly.

The support-bound constructor retains that actual support in an immutable optional
host field alongside its original curve view. Every later enclosure query forwards
this retained host without changing source, subdivision, algebra or byte admission.
Standalone 2D and validated-loop constructors retain nil: a loop-only receipt does
not supply an owning face-support contract. Nil can authorize only the lower
standalone 2D value law; hosting-dependent relations retain the lower typed refusal
until their actual support is supplied. No inferred plane or topology lookup may
manufacture that relation. The host is part of the immutable predicate's equality
and hashing, with the same Hashable and Sendable ownership on all targets.

Endpoint-corrected connector boundaries retain their original construction spline and both retained section root spans. Area admission traverses all three sources under the existing control-point and nesting policy before the generic original closed-jet integrand is prepared. Construction endpoints alone are not geometric endpoint authority.

Bounded loop preparation passes the caller-selected optional byte callback directly
into Geometry's continuous chart lift. Source validation, original UV value bounds
and retained sample/box buffers use that same choice; an absent ceiling stays nil
through the lower producer rather than becoming a no-op byte receipt.

### Original Euclidean Polyline Chart Admission

Normalized polyline fractions follow the original Euclidean prefix/total length
law. Integer segment indices are not normalized parameter authority. The generic
parameter encloser consumes Geometry's exact prefix producer under an explicit
independent algebra depth (default 32, caller range 0...32); source nesting and
geometric subdivision do not choose that cap. The same work and optional requested-byte callbacks cover prefix/root
preparation and value hulls. A missing algebra capability refuses the exact route;
no index-uniform or sampled prefix surrogate may publish a certified enclosure.

Directed homotopy crossing signs consume Geometry's bounded original rational
orientation producer under the same work and optional byte callback. Exact source
coordinate differences and determinant sign remain authoritative even when a
rounded product underflows; a floating expansion scratch call outside admission
cannot publish signed winding accounting.

Original chart enclosure and loop preparation retain the caller's independent
source-depth ceiling (at most the historical 16) through every D0 query. Lower
subdivision receives only its remaining geometric depth; algebra remains its
independent default 32. Receipt-bound loops skip repeated source authority
validation but do not reset query source traversal to a larger ceiling.

Signed UV flux integration accepts optional caller byte admission alongside its
existing work/depth policy. The owned depth-first frontier reserves its actual
typed capacity before allocation and reuses it across subdivision. Selected byte
admission must also reach Geometry original chart preparation, endpoint and flux
queries; opaque legacy chart buffers cannot authorize a complete bounded result.
Nil preserves historical allocation policy without asserting a byte guarantee.

Affine, constant-axis and authored polyline signed UV flux has an exact original
rational Green-integral path. It integrates each directed line as
(uStart+uEnd)*(vEnd-vStart)/2, summing exact original coefficients before outward
publication. The polyline integral is independent of its Euclidean speed clock;
no approximate prefix parameter enters this geometric line integral. Exact
coefficient work and limb bytes use the same invocation admission. Original
support-bound validation precedes this path, and finite result width must meet
the unchanged requested accuracy. Other chart families retain their generic
signed-flux issuer and its concrete byte/depth completion dependency.

The support-bound UV flux route consumes Geometry’s bounded original chart constructor and forwards the same selected BYTE callback through closed endpoints and signed-flux queries. Native numeric charts retain one-sided original knot owners; actual implicit root preparation and advances keep their original state on this ledger. General inverse images, implicit certification admission and specialized source charts remain explicit lower dependencies. Surface-area flux preparation receives the composing subdivision ceiling and independent source/algebra policies rather than legacy opaque source preparation.

### Portable module wiring

This component consumes the unchanged current-task cancellation and direct
collection import contracts owned by [CADTopology](../DESIGN.md#m6-portable-validation-wiring).
Its algorithms, budgets, immutable source owners and existing isolation remain
unchanged on Native, ordinary WASM and Embedded.

### Canonical area API binding

The existing Green/flux callers pass one original inout execution into the
[Geometry integrand and chart producers](../../CADGeometry/SurfaceAreaIntegration/DESIGN.md).
Typed temporary/output storage and actual work consume that owner. Original
formula evaluation, native partitions, orientation and local refinement limits
remain unchanged. Removed callback proof allowances are not a compatibility path.

Adaptive integration passes its original execution explicitly into the cell
evaluator alongside the unchanged local work count; the evaluator does not
capture an outer inout owner or create another allowance.
