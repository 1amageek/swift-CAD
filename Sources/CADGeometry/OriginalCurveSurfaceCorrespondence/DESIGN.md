# Original Curve Surface Correspondence

## Purpose and Scope

Child of [CADGeometry](../DESIGN.md), without children. Owns a source-bound,
whole-use-fraction deviation certificate for original finite native curves and
numeric parameter curves on the bounded Draft support family. This component
is independent of the existing void correspondence validator.

## Responsibilities and Boundaries

Geometry produces an immutable receipt only after proving the complete closed
fraction interval. Modeling/Kernel binds topology IDs and owns publication. This
component owns no fitting, nearest-parameter projection, topology or persistence.
The strict directed map is `t(f) = a + (b-a)f`; the pcurve uses its original
fraction map on `[0,1]`. A successful void validator is never a receipt input.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADGeometry](../DESIGN.md) | parent | original spline values and outward interval arithmetic | Supplies the original geometric values and rigorous arithmetic consumed by this producer. | Receipt success is local to the declared family. |
| [CADKernel](../../CADKernel/DESIGN.md) | used by | geometric evidence before topology publication | Consumes source-bound deviation evidence and separately binds topology identity. | Kernel must check exact source binding. |

## Architecture

```text
original Curve3D + directed trim + pcurve + support + tolerance/options
    -> bounded native admission and immutable coefficient views
    -> original Bernstein curve / original Cox surface interval first jets
    -> rigorous midpoint residual + whole-cell residual derivative hull
    -> all closed cells accepted -> opaque source-bound receipt
                                -> typed failure / cancellation
```

## Contracts and Invariants

- Spatial curves are finite nonperiodic clamped native B-splines of degree 1...6.
  Every interior knot has multiplicity exactly the degree, so each original
  coefficient slice is a Bezier patch without knot insertion or extraction.
  Rational weights are strictly positive. The directed trim must lie
  inside the original closed domain, including its endpoints; it has nonzero
  represented width. Neither domain nor native knots are tolerance-snapped.
- Pcurves are original degree 1...4 clamped degree-fold B-splines with positive
  weights, or original affine/constant-coordinate charts. All pcurve control
  coordinates (or affine endpoint interval images) must be inside the support
  domain. Rational positive-weight convex hull containment independently proves
  containment for all fractions, not only stations. Unproved containment refuses.
- Supports are finite nonperiodic cubic-U/linear-V clamped B-splines with one
  V interval and interior U multiplicity at most three, or planes with a literal
  coordinate-axis unit normal. Original support knots and coefficients are
  evaluated by outward Cox recurrence on each original owning span. No sampled
  controls, rounded extraction, clipping of actual geometry, or pcurve mutation
  are admitted.
- Every original curve/pcurve/support span remains a separate closed record.
  Queries union all intersecting owning sides. C0 joins are continuous by the
  shared native coefficient law. Their one-sided derivative bounds give a
  global piecewise-C1 Lipschitz enclosure; no second-order Taylor expansion
  crosses a derivative jump. A zero-width query retains all owning sides.
- For residual `R(f)=C(t(f))-S(P(f))`, each cell uses interval `R(m)` and the
  whole-cell interval `R'`. The mean-value enclosure is
  `R(cell) subset R(m)+(cell-m)R'(cell)`. Original outward arithmetic encloses
  the midpoint; a raw floating point residual is not evidence. The Euclidean
  upper bound is rounded outward. Every accepted cell's upper bound is at most
  `options.maximumDeviation ?? tolerance.distance`. An independently enclosed
  midpoint lower bound above the request produces topology failure.
- Arithmetic overhang may be intersected with a native closed interval only
  after independent positive-weight/domain/basis support containment proves
  that the actual geometric value belongs there. Empty intersection fails.
- The receipt retains actual source, directed trim, pcurve, support, tolerance
  and options by value/COW. Its initializer is producer-only, no Boolean or
  caller-supplied bound can mint one. Binding verification checks the exact
  retained immutable values; foreign or changed inputs fail explicitly.

### Original coefficient residual laws

Before independent interval subtraction, two admitted coefficient identities can
retain source correlation over the whole directed interval. For a literal-axis
plane, a full native curve/pcurve map with identical original degree, knots and
positive weights has residual equal to the weighted common-basis sum of original
Cartesian control minus original affine-lifted pcurve control. The maximum outward
control-residual norm bounds every native span and the complete use. It is tested
against the caller's requested bound; matching basis never bypasses that test.
For a cubic-U/linear-V spline, a constant-V chart on an exact original V endpoint
reduces the tensor to its original row. If the directed U map, original U knots,
Cartesian row and weights exactly equal the original spatial curve, the whole
residual is identically zero by the native tensor endpoint law. This is a proved
coefficient identity, not a claimed zero from samples or a void validator.

Both branches follow source/native/domain/hull admission. The comparison scans
are bounded by the previously admitted original scalar payload; one native cell
record is charged per original span and one whole proof cell before publication.
If an identity's structural assumptions do not hold, the ordinary interval proof
runs on the same invocation budget. Errors are never caught to select a fallback.

## Runtime Flows

Admission precedes allocations and validation. One invocation owns the entire
preparation/traversal budget. After the root cell is admitted, unresolved cells
bisect at a representable midpoint. Both children retain closed endpoints.
Publication occurs only after the stack is empty. Cancellation propagates as
`CancellationError`; no receipt is published on any failure.

## State, Ownership, and Lifecycle

All state is invocation-local. Immutable source arrays remain COW owners.
Native patch records hold ranges into original buffers. Degree-limited scratch
is temporary, and the DFS stack is bounded by the depth ceiling. There are no
mutable globals, caches, pointers or target-specific state branches.

## Failure, Concurrency, and Constraints

The caller options must request depth at most 32 and total work at most 65536.
`maximumCellCount` is the aggregate work-record ceiling, not a helper-local reset:
original native-record preparation, queried native-span records and adaptive
proof cells all consume one aggregate cell-record ledger. `consumedCellCount` reports
that ledger and `inspectedCells` separately reports adaptive cells. Original source
scalar admission is a distinct quantity, `sourceScalarCount`, bounded independently
by the same caller maximumCellCount before scanning/growth. Scalar units are not
cell units: using the same caller ceiling couples data-size admission to caller
resource reduction without adding a hidden/default allowance. Row-owner entries
are charged before row scans, then coordinate/weight/knot scalar counts are added.
Binding verification first checks the immutable trim/tolerance/options header,
then admits the caller input scalar payload under that same ceiling before source
equality. The producer-admitted retained immutable source is not newly allocated
or admitted twice. Both source owners have bounded payload and comparison needs
no data copy. A record's degree caps bound its arithmetic/scratch (curve at most seven
homogeneous controls, surface at most eight active controls); no variable-size
unpaid extraction/solve is performed. Checked integer overflow and exhausted
work/depth/finite arithmetic produce resource failure. Invalid domain/options
produce invalid input. Other geometry families produce marked unsupported
capability. Binding checks preflight only caller input records before equality; the retained immutable source was already admitted by the producer.
No default allowance, tolerance increase, sample fallback or partial receipt is
available.

## Verification and Change Impact

[Test owner](../../../Tests/CADGeometryTests/OriginalCurveSurfaceCorrespondenceTests.swift)
executes the real factory via its protocol. Independent original literals cover:
planar offset above a tighter request; exact/within-limit curves; an interior
Bezier bump invisible at endpoints; rational and reversed native trims; C0 joins;
cubic support composition; invalid domain/family; low aggregate work, depth,
cancellation and foreign receipts. Native compile/link/runtime uses an immutable
production snapshot and the actual CADGeometryTests product. General correspondence,
other support families and portable runtime remain outside this bounded proof.

Native verification (Swift 6.4.0, macOS arm64, original production base
`a859522` plus this component only): 10 dedicated declarations / 11 cases
passed in 0.028 seconds. A final receipt-only scalar-prefix correction was
relinked and its 2 affected declarations / 3 cases passed in 0.001 seconds.
The original tighter-distance counterexample now refuses; requested tolerances
and ceilings were not increased. Kernel composition, the actual Draft full
producer fixture and portable execution remain pending their owning verification.

### Original tensor/curve coefficient correlation

The actual Draft packet retains cubic-U/linear-V support with degree-fold native
U spans, degree-six spatial and degree-four parameter curves. The first-jet
route exhausts 65536 work records on all four actual directed uses at requested
1e-6; it independently encloses two nearly equal laws and loses their
coefficient correlation. This does not authorize an increased allowance.

After the existing small exact-law admissions, `OriginalCorrespondenceComposedResidual`
proves this native tensor family directly. Its spatial, parameter and surface
Bezier controls are views of stored degree-fold original coefficients. No
rounded extraction, producer tag or symbolic producer identity supplies authority.
For parameter homogeneous polynomials `(Xu,Yv,Wp)`, native U interval `[a,b]`
and V interval `[c,d]`, define `A=(Xu-a*Wp)/(b-a)`, `B=Wp-A`,
`C=(Yv-c*Wp)/(d-c)`, and `D=Wp-C`. The support homogeneous polynomial is
`sum(i=0...3,j=0...1) binomial(3,i) A^i B^(3-i) (j==0 ? D : C) H[i,j]`.
Its common denominator is `Wp^4`; its degree is at most sixteen. Constant
stored surface weights permit the exact partition-of-unity weight identity.
The spatial homogeneous numerator/weight are `(Ns,Ws)`. The residual numerator
is `Ns*Wr-Nr*Ws`, of degree at most twenty-two. Its Bernstein hull divided by
independently positive `Ws` and `Wr` bounds the whole residual. Both coordinate
owners subtract the same original spatial control origin before arithmetic.

The directed trim and full parameter native domain retain their exact affine
fraction maps. Outward preimages of every internal spatial/parameter native
break contribute both representable enclosing endpoints to an initial closed
fraction cover. Equal endpoints alone are deduplicated; no epsilon merging or
snapping occurs. For each cell, all original spatial/parameter/support owning
spans whose actual parameter subsets can meet the cell are retained. Their
polynomial extensions are evaluated on the entire cell superset, including
arithmetic overhang. A bound is therefore also a bound on every valid-owner
subset. Extension denominator positivity must be proved; otherwise the cell
refines or refuses. This does not clip any original domain or replace its law.
All closed cells, including both sides of a C0 join, must pass before publication.
An inconclusive coefficient hull refines under the same depth/work ceiling;
there is no failed-proof fallback to successful generic/sampled correspondence.

One invocation retains the already paid source/preparation prefix. Original
native tuple visits, root endpoint storage, sorting comparisons, initial cells
and child storage are charged before work/growth in its existing cell ledger.
Fixed degree twenty-two bounds the arithmetic of each tuple. Numeric temporary
admission uses the same caller maximumCellCount independently of work: the
original source scalar count plus root capacity, depth-bounded stack records,
and a conservative peak of 128 polynomial buffers of at most 23 two-Double
interval coefficients and four owner words per buffer must fit that ceiling.
This transient admission does not change the receipt's original sourceScalarCount
or charge the immutable retained source twice. There is no private allowance.
Non-degree-fold support uses the existing original first-jet algorithm; selection
precedes proof and is never a catch/fallback after failure.

Verification extends the same test owner with independent tensor composition,
rational parameter/curve weights, interior perturbation, reversed/native joins,
low numeric/work budgets and cancellation. The frozen actual four-use packet
is a separate private production diagnostic; success of its Geometry proofs
alone is not publication or Kernel mesh completion. Native verification (Swift 6.4.0/macOS arm64, immutable production base
`29d2a037` plus the exact five owner deltas): 13 dedicated declarations / 14
cases passed in 0.034 seconds. The actual original Draft four-use packet also
passed all four strict correspondence and source-binding checks, at unchanged
requested 1e-6, work 65536 and depth 32. Its conservative achieved bounds were
8.80573173661617e-7, 7.137526800469424e-7, 7.141826115869917e-7 and
9.743946336712563e-7, with consumed work 17113, 3002, 2075 and 388.
The same actual graph input passed Geometry's graph proof after one outward-safe
subtraction of the maximum achieved error from its original linear allowance.
The combined diagnostic (14 declarations / 15 cases) took 26.030 seconds.
This is Geometry proof evidence; Kernel mesh publication, full public Draft and
portable verification remain separately owned and unproved here.

### Original station inverse

`OriginalSurfaceStationCorrespondence` prepares the retained spatial curve and
retained surface lift once. Its package protocol resolves an original native
spatial station against the complete normalized pcurve domain on the caller's
cumulative work ledger. Endpoints use the authored directed use endpoint and an
original closed-point deviation bound. Interior stations use an original
coordinate whose spatial tangent interval excludes zero. Closed subdivision
exhausts every lift cell: complete coordinate separation or spatial separation
excludes it; all other cells must achieve the requested full spatial bound.

The union of possible cells must be one interval. Its original one-sided lift
coordinate derivative must have a strict common sign and its endpoint values
must bracket the original station coordinate interval. This proves a unique
transverse coordinate root and bounds the physical error of every represented
fraction in the receipt. A midpoint is only a publishable representative inside
that proven interval. It is never the station's source authority. Multiple
branches, stationary coordinates, unproved original endpoint jets or exhausted
resources produce explicit failure. The receipt binds original curve, directed
trim, support, pcurve, native station and tolerance. Consecutive receipts expose
orientation for the topology owner to enforce directed monotone use traversal.
This local transverse station proof does not claim a global implicit atlas or
repair a missing pcurve. Those production domains remain separate requirements.

### Reverse original station transfer

The prepared station correspondence also resolves an authored lifted fraction onto the complete directed spatial native trim. Its original lifted singleton bounds select a transverse coordinate. Exhaustive native interval exclusion, a strict endpoint sign bracket and a same-sign whole derivative prove one physical station branch; whole XYZ bounds control the requested deviation. The immutable inverse receipt retains both original sources, the lifted fraction, native parameter interval, direction and tolerance. Every preparation, owning-span union and search cell consumes the composing callback. Stationary/critical global atlases remain separately required; no numerical projection or shared normalized fraction proves correspondence.


### Bounded Void Validator Composition

The invocation-aware void facade composes original prepared spatial/lift source
bounds under explicit caller span, subdivision and source-depth limits. Work is
one actual visit per callback; storage callbacks reserve bytes before preparation
and traversal allocations. Legacy void entry points keep their historical policy.
Identical hosted SurfaceLift laws prove zero residual structurally after paid
source comparison. Identical retained affine curve/surface images with the
original image pcurve recurse to the original correspondence, then multiply the
proved residual by an outward original matrix operator upper bound. The original
caller acceptance bound is preserved; no rounded composed transform or chart
inverse becomes authority.

A flat original-word coedge theorem retains the same original curve, support
and hosting pcurve law. Identical word values are compared after paid original
payload traversal. A proved zero source residual stays zero; other source bounds
use the retained exact-word operator upper bound and the same composing byte
allowance, without a rounded matrix or a new acceptance allowance.

Generic fixed-fraction residual cells use complete original position intervals.
A mean-value tightening is permitted only after source C0 continuity is admitted:
validated ordinary native splines, explicit continuous analytic laws, their
retained spatial/parameter images and numeric pcurves on continuous supports.
A hull of higher one-sided jets never independently proves continuity. Unknown
implicit, offset-normal or certificate joins retain rectangular residual bounds
and explicit producer failures. Nonlinear/global correspondence, critical atlas
coverage and lower jet temporary byte accounting remain completion gates of the
new bounded facade; source-authored ports alone do not close those domains.


### Original Continuous UV Endpoint Lift

The bounded continuous-chart facade admits explicit globally continuous original
UV laws and their literal translations/retained exact UV images. It keeps their
original universal chart rather than deriving winding from sampled principal
angles. Start/middle/end are numerical representatives with complete original
closed UV boxes retained in the chart receipt; interpolation between those
representatives remains a candidate only. Whole original UV bounds establish
whether known U-singular roles can be visited. Unknown principal-angle or
implicit branch joins, permuted singular image charts and unmetered lower query
byte allocations remain explicit completion gates. A numerical image period
never authorizes an exact foreign chart translation.


Original surface chart period-shift admission propagates each exact stored shift
through the retained signed image gains and axis permutations before comparing
with the native period. Native spline periods use the exact difference of the
authored fundamental knots; ideal primitive periods use their declared label
period. A reduced exact quotient is integral only when its denominator is one.
The same caller rational ledger pays gain arithmetic and source validation.
This theorem admits representable stored translations without treating a
rounded foreign period as authority. Nonrepresentable translations require an
actual persistent exact shift law and remain a separate incomplete carrier.

Bounded continuous-chart translation preserves the original pcurve/support
binding and translates every retained endpoint UV enclosure outward. The caller
separately proves the stored shift belongs to the original support lattice with
OriginalSurfacePeriodShift. Translation itself makes no periodicity claim.
Numerical interpolation remains candidate generation, and a legacy sampled
receipt cannot be promoted to an original endpoint enclosure by translation.

A zero shift preserves that coordinate enclosure identically. Adding an
outward zero interval must not widen an exact collapsed-boundary singleton.

Bounded directed offset-chart binding admits the retained procedural offset
source itself, its exact pullback to the stored source support, and an exactly
zero-distance identity. It validates the original pcurve on the directed source
and compares retained source graphs under caller work admission. Materialized
analytic/plane radius or origin arithmetic is not an exact offset-source binding
without a separate original arithmetic/normal theorem. Those legacy optimized
targets remain typed incomplete in the bounded relation port.

### Independent Caller Admission for Residual Proof

The bounded correspondence witness forwards optional byte storage unchanged and accepts an optional independently selected algebra depth in 0...32. Source validation, prepared curve and hosted lift preparation, recursive original-word transport and exact C0 admission consume that same invocation. Positional continuity is issued by the original curve traversal producer; native spline type alone does not establish continuity across full-multiplicity knots. A missing lift join issuer disables derivative mean-value tightening while complete original position boxes remain usable. No no-op byte callback substitutes for absent storage admission.
