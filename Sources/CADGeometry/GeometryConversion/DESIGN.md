# Geometry Conversion

## Purpose and Scope

Child of [CADGeometry](../DESIGN.md), with no children. Owns the bounded common
admission contract for approximation, interpolation and conversion of analytic,
NURBS and procedural geometry to B-splines on a caller-specified source chart.
Topology, authoring commands and capability publication retain their owners.
This main integration contains common conversion, unchanged-default admission
and original ruled source authority. Continuation constructors, selected native
span tokens and periodic lift APIs are outside this integration.

## Responsibilities and Boundaries

Source protocols own finite domain admission, point/derivative evaluation and
outward continuous differential enclosures. Native adapters retain immutable
Curve3D/Surface3D values and prepared enclosure work. A mapped source must provide
these same guarantees; a point-only closure cannot authorize certified output.
The converter owns numerical candidates and independent admission against the
source, with position, angular tangent and geometric curvature allowances.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADGeometry](../DESIGN.md) | parent | geometry, parameter charts, differential enclosures | Native source values and interval arithmetic | Enclosures must cover complete boxes and knot sides |
| [SurfaceFitting](../SurfaceFitting/DESIGN.md) | depends on | fixed-basis constrained interpolation | Constructs an interpolation candidate | Discrete equality success does not certify global geometry |
| [Swift-CAD](../../../DESIGN.md) | used by | shared geometry APIs | Public consumers obtain certified geometry | Existing point-only fitting consumers require explicit migration |

## Architecture

```text
source protocol + parameter domain + allowances + degree/control/work budgets
  -> polynomial interpolant candidate
  -> source/candidate continuous differential enclosure
  -> adaptive full-domain interval admission
  -> complete B-spline + certified error bounds, or typed failure
```

## Contracts and Invariants

- All comparisons use the identical source parameter chart, with no implicit
  conic reparameterization. Curve knot-side limits and every surface knot cell
  participate in the certificate. Curvature is evaluated only on continuously
  certified regular spans; inability to establish regularity cannot succeed.
- Position means Euclidean distance in internal length units. Tangent allowance
  is an angle in radians: curve tangent, and surface U/V tangents plus oriented
  normal. Curvature means absolute curve curvature or both ordered signed
  surface principal curvatures, in inverse internal length units. Second
  parameter derivatives alone are not labeled geometric curvature.
- Curve candidates have degree min(3, maximumDegree), interpolate requested
  positions, and use endpoint Hermite derivatives for cubic spans. Interior
  knots retain separate polynomial spans; error guarantees include both sides,
  without claiming unique curvature at a join. Surface approximation
  interpolates a tensor Greville grid with the selected degree. Explicit surface
  interpolation preserves the supplied template's basis and positive weights.
- Numerical construction and point residual checks never establish the global
  allowances. Sources are continuous in position with piecewise-bounded jets;
  outward enclosures include both knot-side limits. Outward interval arithmetic
  bounds entire cells. An enclosed anchor and the complete first-derivative
  difference bound position by the fundamental theorem of calculus, including
  derivative jumps; normalized tangent bounds
  and fundamental-form principal-curvature intervals establish geometric limits.
- The guarantee reports actual admitted error bounds and box count; the returned
  B-spline exposes its admitted degrees and control count.
  No candidate is returned before all cells pass. Exhaustion means this candidate
  was not certified; it does not assert global approximation impossibility.
- Existing MappedBSplineSurfaceFitter/SpatialCurveFitter sampled deviations remain
  candidate diagnostics. Their Wrap, Unwrap, Rebuild and Align consumers must
  supply mapped-source enclosures and invoke the common admission API before
  presenting those diagnostics as complete-domain guarantees.

## Runtime Flows

Approximation constructs successively finer interpolants. Each candidate is
admitted through the same certificate used for explicit interpolation and
caller-provided candidates. Only private candidate-admission rejection may refine within the supplied
budgets. Source failures, including a source-thrown public toleranceRejected,
evaluator failures and cancellation propagate without fallback.

## State, Ownership, and Lifecycle

Inputs and outputs are owned Sendable values. Prepared native source adapters
retain immutable decomposition. Operation-local budgets and traversal stacks
are never shared. There are no callbacks outside synchronous source requirements,
I/O, retained tasks, streams, shutdown operations or platform-specific state.

## Failure, Concurrency, and Constraints

GeometryConversionError distinguishes invalid input, resource exhaustion
and a candidate that cannot satisfy admission. A nonregular
box is subdivided; an unresolved singularity consumes the enclosure budget and
fails instead of publishing undefined tangent or curvature values.
Cancellation remains CancellationError. Structural geometry failures retain
their original typed errors. Callers own geometric allowances. Positive budgets
bound candidate count, output control points, cumulative scalar scratch charges,
work units and enclosure-box visits. Checked arithmetic charges storage and
construction work before candidate allocations; every traversal checks cancellation.
Source implementations own the cost and correctness of each enclosure request.
The composed main B-spline curve and surface types expose closed native domains
and have no periodic construction fields or APIs. Native curve adapters prepare
original outward homogeneous coefficients once, including both closed owning
knot sides and native derivative scaling. Nested rigid/affine images retain the
same original preparation. No rounded authoring extraction becomes source
authority. Periodic representation and requested-cycle proof remain full G6
obligations in the parity implementation, outside this bounded main composition.
Ruled sources retain the original two boundary laws as enclosure authority.
Structurally admitted original polynomial boundary coefficients may share one
outward tensor calculation; other families use the original prepared ruled law.
Source implementations retain ownership of their preparation and per-request cost.
Converter-owned target preparation and every full-box and anchor probe are
charged separately before execution. The target cost owner counts intersected
knot spans and bounds generated Bezier extraction basis arrays, homogeneous
controls, de Casteljau triangular levels, derivative arrays and surface tensors.
Probe charges sum actual derivative dimensions through third order. They include
homogeneous split triangular levels, both split outputs, scalar derivative arrays,
projections and the four-slot scratch arrays produced by interval multiplication.
Surface tensor dimensions shrink with each U/V derivative; polynomial coordinate
groups are reserved only when rational weights can require them. A one-patch
clamped tensor uses its actual preparation and locus-verification dimensions;
general extraction retains its conservative degree-dependent reservation.
Preparation reserves 32 work units per scalar; probe arithmetic reserves eight,
plus knot scans. These bound loop operations and interval arithmetic rather than
multiplying an unrelated flat visit count. Checked
arithmetic rejects overflow before allocation. The separate
512 scalar/4,096 work visit allowance covers certificate arithmetic and stacks;
it does not stand in for target enclosure allocations. Defaults allow
4,096 output controls, eight candidate layouts, 65,536 enclosure visits,
1,048,576 cumulative scalar slots and 16,777,216 work units. Each independent
budget may terminate the operation earlier than another; changing a budget
does not relax the geometric admission conditions.

## Verification and Change Impact

[GeometryConversionTests](../../../Tests/CADGeometryTests/GeometryConversionTests.swift)
owns actual analytic/NURBS/procedural conversions, discrete interpolation,
continuous geometric checks, malicious sampled aliases, domain/degree/control
limits, independent budget exhaustion, cancellation and immutable inputs.
The package task owns native/WASM runtime and consumer migration evidence.
Changes affect the CADGeometry parent index and mapped fitting consumers; their
claims must match the common certificate before G6 can close globally.

### Default-Budget Curved Conversion and Publication Cancellation

The common converter must execute curved analytic, positive-weight NURBS and
procedural source construction and full three-field admission under its existing
default scalar/work/control/box limits. Candidate refinement retains one cumulative
budget and the original source chart and allowances; increasing defaults or
substituting sampled source authority cannot establish this contract. A definite
candidate violation may request a finer layout, while source failures and unresolved
resource exhaustion retain their typed failure contract.
Resource-admission diagnostics identify the requested and remaining scalar/work
charges and visited certification boxes, so an actual exhaustion can be traced
to construction, preparation or traversal without weakening its allowance.

The final source enclosure callback is a cancellation boundary. Curve and surface
certification must check cancellation after complete admission and immediately
before publishing a guarantee, including a source callback that returns valid
evidence while cancelling the current task. Dedicated public-protocol tests own
this failure path together with unchanged-default curved conversion evidence.
These proofs close only this common conversion boundary; mapped consumer migration,
periodic/rational continuation and portable consumer evidence remain G6 work.

#### Original Polynomial Target Jets

Converter-owned degree-at-most-three, common-positive-weight targets select an
immutable polynomial target adapter when a curve's stored knots isolate complete
Bezier polygons or a surface is one exactly clamped Bezier tensor. Family selection
precedes preparation; failure in the selected adapter propagates. Other target
families retain the native differential adapter and its existing cost owner.
Partition of unity cancels the common stored weight exactly. The adapter retains
the actual candidate and derives outward power coefficients directly from its
stored Cartesian controls, relative to each original polygon's first point:
`A[i,j] = C(p,i) C(q,j) sum(a<=i,b<=j) (-1)^(i+j-a-b)
 C(i,a) C(j,b) (P[a,b]-origin)`.
Exact native endpoint differences normalize the requested chart; outward Horner
evaluation and exact falling-factorial differentiation enclose value and all
first/second derivatives. Closed overlapping curve spans retain both knot sides.
No rounded extracted Cartesian polygon replaces original target authority.

```text
actual candidate stored controls + admitted structural family
  -> paid outward power coefficients retained once
    -> paid scalar Horner value / first / second jet queries
      -> unchanged complete-domain three-field admission
```

Preparation reservations count retained coefficient payloads, array owners,
coefficient contractions and interval multiplication scratch. Per-probe reservations
count each executed derivative polynomial term and native chart scaling, returned
jet payloads and span scans. Third derivatives and homogeneous split arrays are
absent from this selected path and are not charged as if they were generated.
Surface refinement prioritizes the larger outward first-derivative-difference
contribution to the position bound; either selected direction still requires
complete cell coverage and all three original allowances before publication.

Native Swift 6.4.0 verification on the frozen original production dependency
graph passes seventeen declarations/nineteen cases, including the unchanged ten
conversion regressions, four default-budget curved public conversions, two
independent literal polynomial jet oracles and three curve publication cancellation
cases. A test-only addition relinks the same production objects and passes all
three surface publication cancellation cases in a targeted run. The default
analytic circle/cylinder, varying-weight rational curve and procedural ruled
surface retain their original position, tangent and principal-curvature allowances.
The dedicated owners are [default admission tests](../../../Tests/CADGeometryTests/GeometryConversionDefaultAdmissionTests.swift)
and [publication cancellation tests](../../../Tests/CADGeometryTests/GeometryConversionPublicationCancellationTests.swift).
This evidence covers the common native conversion boundary; normal WASM,
Embedded, mapped consumers and full G6 completion remain separate obligations.


### Original Ruled Source Authority

`NativeSurfaceConversionSource` always retains and evaluates the original
`Surface3D`. Its enclosure storage selects the original polynomial ruled adapter
only when both actual boundaries are nonperiodic degree-at-most-three B-splines
with identical complete stored degree/knot arrays and exactly degree-fold internal
knots isolating original Bezier polygons. Each boundary must have exactly constant
positive stored weights; the two constants may differ because partition of unity
cancels each independently. Complete original geometry validation precedes selection.
Selection uses no tolerance matching, extraction, basis conversion, trimming,
degree elevation or constructed replacement surface.

For each original closed U polygon, its original start/end Cartesian controls are
the two rows of the ruled law's U-by-linear-V tensor. The existing outward
polynomial coefficient and jet calculation consumes those rows directly, retaining
original native U endpoints and V in [0,1]. This retains correlation before
interval evaluation and includes both closed sides of every original U knot.
The complete requested rectangle must be contained in the original ruled chart;
no clipping or parameter replacement authorizes an enclosure. Families outside
this structural selection retain `PreparedSurfaceDifferentialEncloser` on the
original procedural value, including varying weights, differing knots or degrees,
and general boundary geometry. A selected preparation failure propagates without
retrying a different authority. Cancellation is checked at entrance, preparation,
span traversal and publication. Adapter ownership remains immutable and Sendable.

```text
original ruled value + validated actual boundary coefficients
  -> exact structural family selection
    -> original two-row outward coefficients / original prepared boundary law
      -> complete original-chart enclosure -> common conversion admission
```

The dedicated original-authority tests use the independently authored law
S(u,v)=(t,2v,t*t+t*v), t=(u+2)/5, with literal original controls and different
constant positive boundary weights. They check value, both tangents and all second
jets, including closed multi-span sides and asymmetric charts. Varying-weight and
different-basis boundary laws exercise the original general path; invalid charts,
malformed geometry, cancellation and immutable source ownership exercise failure
contracts. Public conversion retains unchanged scalar/work and geometric allowances.
These tests do not establish unrelated continued laws or portable consumer proof.

Native Swift 6.4.0 evidence: the old source adapter fails the unchanged asymmetric
original-chart oracle with a U-domain refusal and the degree-33 constant-law oracle
with an unrelated replacement-authoring degree ceiling. Replacing only that adapter
on the same frozen dependency graph passes all seven
[original-authority tests](../../../Tests/CADGeometryTests/OriginalRuledConversionAuthorityTests.swift)
and six affected existing public conversion tests, thirteen declarations/cases in
0.239 seconds. The latter retain original procedural/analytic/NURBS construction,
explicit interpolation, default budgets, geometric allowances and source failure/
cancellation behavior. The general closed-owning native-curve lower contract,
portable targets, other consumers and full G6 remain independently required.


### Main Composition Verification Boundary

The committed common conversion sources are composed with the existing main
package graph. Native runtime evidence above belongs to the parity source
snapshot; it does not establish this composed main target. The composed target
must execute the four dedicated test owners, selected public conversion paths
and unchanged shared-geometry regressions before integration can succeed.

| Lower owner | Contract used | Integration boundary |
|---|---|---|
| `BSplineBasis` | Original selected-span interval basis derivatives | No scalar point derivative API is added. |
| `BSplineSurfaceBezierDecomposer` | Original homogeneous coefficients and native knot bounds | Authoring decomposition remains a separate producer. |
| `RationalBezierSurfaceJetEncloser` | Original common-weight identity and native endpoint jets | No first-order-only or value-only selected-span API is added. |
| `PreparedBSplineSurfaceDifferentialEncloser` | Original nonperiodic preparation and closed owning intersections | Only the actual main closed-domain representation is composed; no selected lift API is added. |

The existing strict original correspondence curve admission, modeling normal
floors and unrelated consumers retain their contracts. An unchanged contract
does not acquire broader completion evidence from this bounded conversion cut.
The public consumer proofs remain owned by
[common conversion tests](../../../Tests/CADGeometryTests/GeometryConversionTests.swift),
[default admission tests](../../../Tests/CADGeometryTests/GeometryConversionDefaultAdmissionTests.swift),
[publication cancellation tests](../../../Tests/CADGeometryTests/GeometryConversionPublicationCancellationTests.swift)
and [original ruled tests](../../../Tests/CADGeometryTests/OriginalRuledConversionAuthorityTests.swift).

### Causal Main Type and Original Curve Projection

The first composed build rejected unavailable `isUPeriodic`/`isVPeriodic`
members. The main representation itself has no periodic curve or tensor
construction capability. The projected common cost and structural selectors
therefore operate on its actual closed domains; they do not introduce false
periodic fields or alter the existing original correspondence guards.

`PreparedCurveDifferentialEncloser` and `RationalBezierCurveJetEncloser` retain
original curve Bernstein interval coefficients derived directly from original
stored controls/weights or the selected original outward basis. Every closed
owning span keeps its original native scaling. This lower contract is required
by native conversion and ruled boundary enclosures; the prior rounded Cartesian
authoring decomposition cannot establish these guarantees.

The full periodic negative-cycle fixture remains in the committed parity test
owner. This bounded main type cannot construct that input. The coverage record
explicitly retains that obligation; removal from the main build is not a pass,
a supported periodic result or full G6 completion.

The one-shot B-spline dispatcher delegates to the same original prepared native
owner on the actual main closed representation. The prepared native branch
never re-enters that dispatcher. Exact endpoint normalization preserves stored
native endpoints; both public evaluation entries must return bitwise-identical
interval receipts. The existing `preparedEvaluationIsExactlyEquivalentToOneShotEvaluation`
regression is included in the composed main behavioral proof.
