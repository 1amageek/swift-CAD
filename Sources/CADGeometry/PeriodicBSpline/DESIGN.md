# Periodic B-splines

## Purpose and Scope

Child of [CADGeometry](../DESIGN.md), without children. Owns the cyclic curve
representation, parameter normalization and fundamental-origin contracts for G1/G2.
Periodic editing and downstream representation closure remain part of this task.

## Responsibilities and Boundaries

Uses the existing BSplineCurve3D homogeneous basis evaluator. A cyclic value stores
N independent controls followed by p repeated controls and N+2p+1 translated
knots. Closure of endpoints alone never grants periodicity. The fundamental
origin selects an interval of representatives without changing C(u).

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADGeometry](../DESIGN.md) | parent | Exact rational curve representation | Uses the existing basis and derivative evaluation | No sampled spline fitting |
| [CADIR](../../CADIR/DESIGN.md) | used by | Curve3D Codable and Hashable | Retains periodicity and origin in source/signatures | Parameter-origin metadata is geometric identity |
| [CADCapabilities](../../CADCapabilities/DESIGN.md) | coordinates with | Source-backed limitations | Publishes periodic inputs and resource failures | Correct refusal does not complete G1 |

## Architecture

```text
Cyclic controls/knots -> structural periodic validation -> BSplineCurve3D
Finite parameter -> representative in the base knot interval -> existing basis
Origin change -> representative interval metadata; curve function unchanged
Curve3D/ValidatedCurve3D -> point and parameter derivatives -> caller
```

## Contracts and Invariants

- Degree p is positive; cycle knots contain N+1 nondecreasing values, N > 0.
- Positive finite weights and repeated controls/weights define one homogeneous cycle.
- Translated knots agree within floating arithmetic resolution, not modeling distance.
- Seam multiplicity m is at most p; the guaranteed seam continuity is C^(p-m).
- Public domain is periodic. The stored base interval remains available for bounded algorithms.
- Normalization rejects nonfinite inputs or an unrepresentable representative interval.
- Choosing another fundamental origin preserves every C(u) and its derivatives.
- The knot interval owns the period; rounded representative endpoints never redefine it.
- Reversal reflects parameters about the chosen fundamental interval and preserves periodicity.
- Rigid and affine transformations retain the cycle and origin.
- Codable and Hashable retain the distinction between a periodic and an open restriction.
- The current serialized schema requires an explicit Boolean isPeriodic; a missing or mistyped field is rejected.

## State, Ownership, and Lifecycle

Curve values own their arrays with Swift value semantics. Prepared curves retain
immutable copies. There is no shared mutable state or target-dependent isolation.

## Failure, Concurrency, and Constraints

Malformed cycles fail with invalidInput; finite arithmetic exhaustion is explicit.
Periodic refinement extends a finite window with ceil(p/N)+2 padding cycles on
both sides. It inserts one exact homogeneous knot copy per interior cycle using
Boehm refinement, then extracts the central cycle. The translated output knot
sequence and repeated controls must agree within arithmetic resolution; controls
are never fitted or averaged. Existing knots use exact equality for multiplicity.
The period and chosen origin are retained. Inserting at the seam is valid until
its multiplicity reaches p; exceeding that multiplicity fails as invalidInput. Exact finite restrictions extend cyclic knots and controls
over a containing finite window, insert the two requested boundary knots in
homogeneous coordinates, and extract a clamped open restriction. No spline fitting
or geometric tolerance snapping is used in the restriction algorithm.

PeriodicBSplineExpansionOptions owns a caller-adjustable positive control-count
budget. The default is 65,536 controls, selecting about 2 MiB for the combined
point and weight buffers before extraction, in addition to knot and algorithm storage. Allocation is checked against this budget and integer
overflow before expansion, including two degree-fold boundary insertions in the workspace.
Larger intervals or degrees may use a larger explicit
budget; exhaustion fails with resourceLimitExceeded.
The same options own maximumKnotInsertionWork: one unit per control processed by
one insertion. The default 1,048,576 selects sixteen passes over the default control
buffer. Both budgets accept any positive representable Int. Total insertion work
and all generated counts are checked before allocation; callers may explicitly
raise either budget without changing geometric semantics. Unrepresentable translated
knots or boundaries fail rather than returning a collapsed restriction.

Bezier bounds consume an exact restriction of the requested interval. A C0 corner
inside that interval has no finite smooth second-derivative certificate; it fails
with singularGeometry and requires splitting at the knot before certification.
Span-wise zero derivatives must never certify an interval crossing a corner,
including when a caller supplies an inherited derivative bound. Projection
uses the chosen fundamental interval by default, or the caller's finite interval;
the existing subdivision-cell budget also bounds expansion. Multiple parameter solutions
inside a multi-period interval remain ambiguous, except equivalent interval ends.

## Verification and Change Impact

PeriodicBSplineCurveTests checks rational/nonrational cyclic basis agreement,
seam derivatives, normalization with nonzero origins, origin changes, reversal,
transform/transport preservation and malformed-cycle refusal through Curve3D and
ValidatedCurve3D. PeriodicBSplineRestrictionTests owns seam-crossing and multi-period restrictions,
projection and interval bounds, malformed ranges and exhausted expansion budgets.
PeriodicBSplineRefinementTests owns rational/polynomial locus and derivative
preservation, seam and interior multiplicities, p>N cycles, translated insertion
parameters and resource failures. SubshapeGeometrySignatureTests verifies the
actual CADIR transport boundary. CADGeometryWASMSmoke executes normalization,
rational and p>N polynomial refinement, seam-crossing restriction, projection,
bounds, exact signature transport and typed refusals on the matching normal WASM
SDK. This evidence does not establish Embedded or whole-kernel compatibility;
those remain in the final integration item. Higher consumers that assume
a closed domain require review under G5; metadata cannot prove their support.

## Tensor Surface Contract

BSplineSurface3D owns rows indexed by V and columns indexed by U. Each axis has
an independent periodic Boolean and optional origin. Periodic axes use the same
translated knot and repeated homogeneous control contract as BSplineCurve3D;
nonperiodic axes retain full knot vectors. The periodic factory takes independent
controls along periodic axes and expands the complete tensor net. Its uKnots and
vKnots arguments are cycle knots for periodic axes, full knots otherwise. At least
one factory axis must be periodic; the ordinary initializer handles open surfaces.

```text
Independent tensor net + U/V knot vectors + periodic flags
    -> checked expansion budget -> translated knots/repeated controls
    -> per-axis structural validation -> owned BSplineSurface3D
Finite (u,v) -> independent base-knot representatives -> rational tensor jet
Origin change -> representative metadata only; S(u,v) unchanged
Fixed coordinate -> normalized basis -> homogeneous isocurve with varying-axis cycle
```

- Surface period comes from its base knot interval, never rounded origin endpoints.
- Tail columns and rows, including weights, equal the original cycle exactly.
- Seam continuity is independently C^(p-m) for each periodic direction; mixed
  partial derivatives obey both independent continuity orders.
- Strict Codable requires both axis Booleans, preserves both origins and rejects
  missing or wrongly typed fields. Validation rejects origins on open axes.
- Point, normal, second/third-order and Taylor jets normalize before basis evaluation. No
  per-point temporary control net or control-line allocation is permitted. The shared
  BSplineCurve3D.validatePeriodicAxis predicate proves translated knots and origins;
  both curve and tensor owners check their own repeated homogeneous controls.
- Isocurves inherit the varying axis cycle/origin and normalize the fixed axis.
- Rigid transforms preserve the cycle and origins. Refinement applies one shared
  cyclic axis plan independently to every homogeneous control line, preserving
  both cycles and origins. Degree elevation of a cyclic axis remains explicit
  typed unsupported until G5/G6 is verified.
- The factory admits the total expanded net against maximumControlPointCount in
  PeriodicBSplineExpansionOptions before allocation. Overflow and budget excess
  return resourceLimitExceeded; malformed inputs return invalidInput/GeometryError.
- Net values own immutable/copy-on-write arrays; no shared mutable state, callbacks
  or platform-dependent isolation are introduced.

PeriodicBSplineSurfaceTests in CADGeometryTests owns tensor basis differential,
seam, origin, isocurve, mixed-axis edit/transform, schema and invalid-cycle fixtures.
PARG.G2.1 proves values/evaluation; G2.2 proves exact editing; G2.3 proves prepared
algorithms/transport/normal WASM. PARI owns Embedded and whole-system integration;
G5 owns every downstream consumer. No partial sprint establishes complete G2.

### Exact Tensor Editing and Resource Admission

Public insertingKnot and trimmed accept PeriodicBSplineExpansionOptions. Cyclic
refinement inserts the same translated parameter into every control line along
the selected axis. Restrictions require finite increasing unwrapped U/V bounds;
open-axis bounds must lie in the natural interval. Restriction first extracts
each U row, then each V column, using exact homogeneous boundary insertion.
The result is open in both directions, clamped at the requested ends, with
original interior knot multiplicities retained. Origin metadata is cleared only
on this explicitly requested finite restriction. Original sources remain values.

```text
Source + request -> shared axis edit plans -> checked tensor resource admission
    -> U row restriction -> intermediate net -> V column restriction -> open net
Source + insertion -> shared cyclic axis plan -> checked tensor resource admission
    -> per-line homogeneous refinement -> periodic net with original origins
```

The shared PeriodicBSplineEditPlan bounds the containing window and insertion
count before allocating controls. Restriction reserves at most 2p insertions;
the work charge is k*n+k*(k-1)/2 for k insertions and n initial controls.
Refinement uses its exact translated insertion count. The same plan is consumed
by the curve and tensor algorithms; neither derives resource costs independently.

For a tensor edit maximumControlPointCount admits a conservative upper bound on
simultaneously owned generated control slots, excluding the borrowed source and
knot/index/object metadata. One slot means a position/weight pair or a homogeneous
control. At most eight line-widths cover temporary inputs, old/new insertion
buffers, extracted controls and the line result. Refinement charges its output
net plus eight workspace line-widths. Restriction charges the maximum of (U
intermediate net + eight U workspace widths) and (U intermediate net + V output
net + eight maximum line widths). Counts are upper bounds, so a feasible operation
can require a larger budget than its eventual output cardinality. No full
expanded cyclic tensor is allocated. maximumKnotInsertionWork admits the sum
of all line plans: U work times source V count plus V work times the conservative
U output count, or selected-axis work times the perpendicular control count.
Every sum/product is checked for overflow before processing the first line.
Malformed bounds fail as invalidInput, exceeded or unrepresentable budgets as
resourceLimitExceeded, without a partial surface result. Open-only public edits
retain their existing implementation; tensor admission owns edits involving a
cycle. Curve restrictions now also consume their declared insertion-work budget.

PeriodicBSplineSurfaceEditingTests owns rational/polynomial seam and multi-period
restrictions, both refinement directions, repeated seams and p>N cycles, origin
preservation, mixed open/cyclic axes, independently exhausted tensor storage/work,
and malformed intervals. PeriodicBSplineRestrictionTests owns the shared curve
restriction work refusal. These fixtures must verify positions and mixed jets,
including one-sided boundary semantics at lower-continuity knots.

### Prepared Tensor Bounds and Projection

Bezier decomposition of a cyclic tensor first takes an exact finite restriction.
Default decomposition uses both base knot intervals; interval-specific
decomposition uses the requested unwrapped box. Prepared differential enclosures
retain one decomposition of the base knot intervals, independent of origin
metadata. Each periodic query axis maps to at most two conservative intervals
in that cache; a span covering a complete cycle uses the full base interval.
Mapping expands outward for floating parameter resolution, including the
opposite seam endpoint. Interval endpoints touching a neighboring Bezier span
include that span's one-sided jets. No control net is rebuilt for each box.

```text
Cyclic source -> exact base restriction -> immutable prepared Bezier derivative nets
Unwrapped U/V box -> smoothness certificate -> outward seam split (at most 2 per axis)
    -> cached span enclosures -> union of position and derivative ranges
Base knot intervals -> complete Bezier hull search -> local root refinement
    -> per-axis periodic equivalence -> unique representative or typed ambiguity
```

The shared cyclic knot smoothness predicate requires C1 at every interior knot
crossed by a smooth second-derivative certificate. Crossing a C0 knot fails with
singularGeometry; the caller must split at that knot. A point-only span does not
claim global smoothness. Original controls, weights, periods and origins remain
immutable for the lifetime of preparation. Nonperiodic preparation retains its
existing interval arithmetic and domain behavior.

Inverse projection searches exactly one base knot interval per cyclic axis,
avoiding coverage loss from rounded endpoints at a very large chosen origin.
Root deduplication uses circular distance only on cyclic axes, retaining
distinct interior solutions even when their spatial points coincide. The final
U/V values are normalized to the chosen half-open fundamental intervals; the
reported point is re-evaluated there and the residual must still satisfy the
input tolerance. A selected inverse root must also satisfy the existing B-spline
regular parameter-frame contract; singularSystem refuses collapsed or locally
singular axes rather than reporting an arbitrary unique parameter. This does
not infer global non-discrete topology from local rank alone. Each accepted
periodic inverse leaf also needs an outward positive-definite Hessian enclosure
of squared target distance on the entire original Bezier leaf: a Newton witness
and local chart rank do not establish unique coverage. Original prepared patches
are cached per query and restricted to subdivision boxes; rounded child controls
do not supply this certificate. A leaf without that proof remains unresolved and
returns resourceLimitExceeded when subdivision cannot continue. Closest-point projection retains its complete certified domain
search and returns the same chosen representatives with a fresh residual. If
finite normalization cannot retain the inverse tolerance or the previously
certified closest-point residual (outward by one ULP), it fails explicitly as
resourceLimitExceeded rather than returning a degraded certificate. Cell,
candidate and exact-expansion budget exhaustion stays resourceLimitExceeded.
Periodic degree elevation remains owned by G5/G6 and does not gain support from
these query contracts.

PeriodicBSplineSurfaceQueryTests owns both-axis seam normalization, origin-aware
projection, genuine multiple-root ambiguity, typed resource exhaustion, shifted
and multi-cycle box containment of position and first/second/mixed derivatives,
cache independence across successive queries and C0 rejection. CADIR signature
tests own face transport of exact cycles and malformed source rejection.
CADGeometryWASMSmoke owns matching normal-WASM execution of tensor evaluation,
editing, queries, transport and typed failures. Embedded and all downstream
representation closure remain PARI/G5, independently of this evidence.
