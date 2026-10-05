# Geometry Conversion

## Purpose and Scope

Child of [CADGeometry](../DESIGN.md), with no children. Owns PARG.G6's common
admission contract for approximation, interpolation and conversion of analytic,
NURBS and procedural geometry to B-splines on a caller-specified source chart.
Topology, authoring commands and capability publication retain their owners.

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
| [CADKernel](../../CADKernel/DESIGN.md#original-analytic-rebuild-position-publication-parg6analytic1) | used by | original analytic Rebuild position certificate | Upper publication and retained-state admission | The Kernel owner invalidates historical states that did not run this certificate |

## Architecture

```text
source protocol + parameter domain + allowances + degree/control/work budgets
  -> polynomial interpolant candidate
  -> source/candidate continuous differential enclosure
  -> adaptive full-domain interval admission
  -> complete B-spline + certified error bounds, or typed failure
```

## Contracts and Invariants

`AffineCurveConversionSource` and `AffineSurfaceConversionSource` compose any
conversion source with explicit finite affine chart coefficients. Zero or
nonfinite scales are invalid. Negative scales preserve the declared traversal;
curve derivatives use scale and scale squared, and surface derivatives use
U scale, V scale, their squares and their signed product. Full interval images
and every derivative multiplication are rounded outward. Source domain and
failure authority remain the wrapped protocol's; maps never clip a request or
substitute endpoint samples for an enclosure. Values are immutable Sendable
owners with no shared mutable state. The public converter consumes the adapters
through the existing source requirements, including cancellation and unchanged
position/tangent/geometric-curvature admission. Nonlinear maps remain outside
these affine adapters and full G6 remains separate. Behavioral ownership is
[AffineConversionSourceTests](../../../Tests/CADGeometryTests/AffineConversionSourceTests.swift).

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
- The guarantee reports actual admitted error upper bounds and certified-box count;
  the returned B-spline exposes its actual degrees and control-point count.
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
Nonperiodic native curve adapters prepare decomposition once. Periodic curves,
including rigid and affine images, restrict the actual requested interval before
decomposition, so negative and shifted cycles are never clipped to a fundamental
cycle. Periodic anchor queries are enlarged to a containing interval wider than
the existing parameter-domain resolution before constructing a finite restriction;
they do not require the restriction owner to accept sub-resolution geometry.
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
arithmetic rejects overflow before allocation. Periodic target restriction also
reserves its expanded control and basis work before each request. The separate
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

### Native Position-Only Surface Publication (PAR.G6POS1)

A separate GeometrySurfacePositionCertifying requirement owns certification of an immutable nonperiodic native B-spline source and actual B-spline candidate over one caller-specified SurfaceParameterBox strictly contained in both original supports, on the identical native UV chart. CertifiedNativeSurfacePositionCertifier accepts a finite positive maximumPositionError and caller-owned NativeSurfacePositionCertificationLimits (boxes, cumulative scalar slots and work units) and returns a producer-created NativeSurfacePositionCertificate reporting the covered rectangle, admitted Euclidean position bound and charged conservative cumulative reservations. It does not manufacture tangent/curvature fields or require nonzero speed/normal. Position-continuous piecewise native spans retain both knot sides; unsupported periodic, discontinuous, outside-domain or foreign-chart input fails explicitly. No clipping, replacement Cartesian source, natural continuation, sample acceptance or tolerance relaxation authorizes success.

The certifier owns complete source and target preparation cost before either is prepared. For pairs where either original tensor has nonconstant weights, a PreparedBSplineSurfaceDifferentialCost descriptor in the native preparation owner derives conservative checked reservations from actual original span/local basis/Taylor-to-Bernstein/ten-derivative-net dimensions. The descriptor's original validation/control/knot scans are charged before execution; allocation, source and target preparation, each full-cell and anchor probe (including every original-span scan and localization scratch), and stack storage are charged cumulatively to the same operation. The existing native prepared source remains original homogeneous authority. Costs follow the executed producer loops, not a guessed flat per-box price; all arithmetic overflow and exhaustion produce typed resource failure. Default limits follow the existing conversion envelope (65536 boxes,1048576 scalar slots,16777216 work units); caller limits can change without changing correctness. Admission must be tested under actual defaults rather than increasing them to pass a fixture. Cancellation is checked before preparation, at traversal and immediately before certificate publication.

After complete input/domain validation and charged original structural comparison, exactly equal complete stored source/candidate values may certify zero position error on the requested native rectangle directly; this original coefficient identity proves the whole locus, requires no artificial preparation or probes, reports their actual zero usage and checks cancellation before publication. It does not authorize reparameterization or approximate equality. Varying-weight cases prepare both original supports and every cell uses an outward original source/candidate anchor enclosure plus the complete first-derivative difference times outward UV offsets, bounding position by the fundamental theorem of calculus. The anchor uses the central stored original knot when strictly interior to the cell, otherwise its midpoint; every lower and upper offset uses that actual anchor. Original anchor evidence may establish definite excess before full-cell jets, and cannot admit a successful cell alone. Definite positional excess is GeometryConversionError.toleranceRejected; unresolved subdivision/work/representable precision is an explicit resource failure. Every cell must be admitted before a certificate exists. Independent literal flat/nonregular metric sources, the9-by-9 bump alias, same-source success, repeated-knot coverage, asymmetric domains, strict overshoot refusal, cost-boundary failure and cancellation precede the public native Rebuild integration. Existing three-field conversion APIs retain their semantics and source-cost contract.

Native verification: the9 dedicated declarations/11cases pass with unchanged standard allowances. After the finalCore contract update, these9 and10 existing conversion declarations pass19tests10.133s. The exact staged public Rebuild path and consumer contract are verified independently; this evidence does not cover portable targets or source continuation.

#### Constant-Weight Native Position Preparation (PAR.G6CONT1.N)

After the same complete original admission and stored comparison, source and candidate with exactly common positive stored weights each use a position-only original polynomial path. Partition of unity cancels each tensor's constant weight exactly; the weights need not be equal between tensors. Varying weights retain the existing homogeneous-jet path. No rounded extracted Cartesian surface becomes authority.

The producer merges the actual positive original knot spans with the strictly contained requested endpoints, without tolerance snapping. Each closed common axis cell retains its actual owning source and candidate spans. Original C0 validation supplies consistent position values at adjacent span endpoints; each selected polynomial covers its complete closed cell. For target degree D at least the original degree d, the axis operator is E[j,i] = sum over p=0...min(j,d) of B_i^(p)(a) * binomial(j,p) * (b-a)^p / falling(D,p). Its scale recurrence and selected-original basis derivatives use outward arithmetic on the stored endpoints and knots. This simultaneously extracts and elevates the original polynomial onto the common normalized Bernstein chart. Every U operator and every V operator is constructed once per common axis cell. Original Cartesian controls from both inputs are subtracted from the SAME original source origin before tensor contraction. U contractions are shared across V cells; no separate candidate origin or value-based source replacement is permitted.

```text
validated original tensors + paid admission
    -> common native closed cells / selected owning spans
        -> outward axis extraction and degree elevation operators
            -> same-origin original Cartesian U then V contractions
                -> shared-chart coefficient subtraction
                    -> complete residual hull / paid residual subdivision
```

The native budget's limits and all paid scalar/work/cell counters transfer intact to PolynomialSurfacePositionDifferenceNet.Budget. The same caller limits own axis records and capacity, retained interval fields, basis row-owner buffers and returned net payloads, basis scratch, interval multiplication/division scratch, contraction arrays, difference arrays and cell-stack storage. Charges precede each allocation or traversal and derive from the executed producer loops with checked dimensions. A scale step pays three interval multiplication scratch arrays and one division scratch array (18 doubles); each scalar coefficient product pays its four-double scratch array. The producer reuses immutable axis and U-contraction buffers rather than paying for full mixed Taylor and ten derivative tensors. All common native cells receive their initial paid residual hull check before adaptive refinement. Only initially unresolved hulls receive a paid center lower-bound witness; any definite excess rejects immediately. The remaining unresolved residual nets retain their exact chart and widths in one cumulatively paid global stack, after charging record payload and conservative COW/backing growth before append. Refinement begins only after this complete initial pass, so depth-first threshold-boundary subdivision in an early native cell cannot starve a later already-accessible definite-excess witness. Initial hulls are not recomputed; each popped unresolved cell is subdivided and its children receive their own paid hull/witness admission. Every native cell must satisfy the position bound; definite excess is toleranceRejected, while unresolved arithmetic, scalar/work/cell exhaustion or representable subdivision is a typed resource failure. Cancellation is checked at preparation, contraction, traversal and publication. Defaults, the requested precision and source chart are unchanged.

Independent two-span quadratic-by-linear source and separately authored 128-by-2-span cubic candidate controls use analytical B-spline polynomial coefficients, with a known constant 2e-9 difference. The dedicated owner tests exercise original/asymmetric charts, common positive nonunit weights, a known interior bump, exact reported allowance boundaries and cancellation. Changes to the shared residual net also require the existing continuation lower-owner regression; the unchanged public zero-extension multi-span Rebuild test requires actual relink and runtime verification before upper completion.

Native Swift6.4.0 verification: [NativePolynomialSurfacePositionCertificationTests](../../../Tests/CADGeometryTests/NativePolynomialSurfacePositionCertificationTests.swift) owns five declarations/six cases; these and the unchanged nine native-position declarations/eleven cases pass together. The independent 256-cell fixture reports 737692 scalar slots, 3538442 work units and a finite position bound 2.000000699776224e-9 under unchanged standard allowances. The shared residual-net continuation regression passes fourteen declarations/sixteen cases. The unchanged public zeroExtensionMultiSpanUsesTheOriginalWholeDomainCertificate passes after actual SwiftCADTests relink with this frozen geometry source. This is native evidence for this bounded repair; full G6 consumer migration and portable evidence remain separate.

### Original Polynomial Continuation Position (PAR.G6CONT1.L)

Source admission precedes consumer fitting. The geometry owner provides an immutable prepared continuation request retaining the exact original source, requested rectangle, distance, tolerance, caller limits and paid admission usage. Preparation validates and charges the original source family before the consumer constructs a candidate. Certification accepts this receipt and the actual candidate, resumes the same cumulative budget and publishes only the existing complete certificate. The direct source/candidate operation composes preparation and receipt certification; it must not reset or repeat admission charges. Unsupported varying-weight and periodic sources therefore reach typed refusal without entering adaptive fitting. This request contains no shared mutable state or foreign source substitution.

The protocol requirements are prepareContinuationRequest(source:over:maximumPositionError:limits:tolerance:) and certifyContinuationPosition(preparedRequest:candidate:), alongside the direct source/candidate requirement. PreparedPolynomialSurfaceContinuationPositionRequest has no public initializer and exposes only immutable source, parameters, maximumPositionError, limits, tolerance, admittedScalarCount, admittedWorkUnits and admittedBoxCount. It retains the complete original value through native COW storage; subsequent mutation of the caller's own surface cannot change the receipt. Its producer reserves the concrete receipt payload before construction, including array-owner words without copying original coefficient buffers. Candidate certification copies its paid counters into an invocation-local budget with the same limits, admits only the new candidate, and retains all existing original-law and strict candidate-chart guarantees. Copying or reusing a receipt starts another certification against the same immutable admitted source with the same paid prefix; it does not mutate shared counters or permit any operation to spend a fresh allowance. Receipt creation and certification each check cancellation before publication.

```text
original source + request + limits
    -> Geometry paid source admission
        -> immutable prepared receipt
            -> consumer candidate fitting
                -> Geometry candidate admission + whole-law difference proof
                    -> complete NativeSurfacePositionCertificate
```

For single-Bezier source/candidate pairs, GeometryPolynomialSurfaceContinuationPositionCertifying owns the unique polynomial continuation of an immutable original nonperiodic clamped tensor. CertifiedPolynomialSurfaceContinuationPositionCertifier accepts original source and actual candidate BSplineSurface3D snapshots, a finite positive requested SurfaceParameterBox, a positive maximumPositionError, the existing caller-owned NativeSurfacePositionCertificationLimits and ModelingTolerance. Both tensors must have count equal to degree plus one on each axis, exact repeated endpoint knots and exactly equal finite positive stored weights within each tensor (including omitted unit weights). Their original Cartesian coefficients therefore define a polynomial; the original source law applies over the requested native rectangle even outside its stored domain. The candidate rectangle must be strictly contained in its actual support. Periodic, varying-weight and other unsupported families refuse explicitly; this bounded operation does not weaken GeometrySurfacePositionCertifying's existing source-contained contract. It returns the existing producer-created NativeSurfacePositionCertificate only after complete coverage and reports conservative cumulative charged reservations.

The owner transforms both original polynomial coefficient tensors onto the identical requested native rectangle using outward arithmetic on exact stored coordinates, knots and rectangle endpoints. Each affine ratio is formed from outward differences of original endpoints. Tensor blossom/de Casteljau evaluation with the required lower/upper affine parameters retains the original polynomial even when source parameters lie outside [0,1]. Original-derived interval Bernstein degree elevation then places both tensors on one common U/V degree; public Double collocation elevation and rounded replacement Cartesian source nets are not proof authority. Subtract corresponding two-dimensional coefficients on the shared basis before taking norms, retaining parameter correlation. The complete coefficient convex hull encloses the position difference over every closed requested cell. Only a finite outward Euclidean norm upper bound at or below the request admits a cell. A paid original difference-net anchor norm lower bound strictly above the request establishes toleranceRejected; a large hull alone does not. Unresolved precision or exhaustion is explicit resource failure. If subdivision is required, it subdivides this same original-derived difference tensor, retains all cells and charges the caller's same limits without increasing defaults. No source sample, chart clipping, endpoint equality, tolerance relaxation or new fallback budget authorizes publication.

Original validation/weight/clamping/control/knot scans, checked tensor dimensions and arithmetic, affine normalization, every executed blossom level/output, elevation level, difference tensor, norm/anchor/subdivision work and cumulative storage/stack reservations are charged before execution or allocation by a local invocation budget. Original immutable input ownership and cancellation at entrance, each producer phase/traversal boundary and before publication are retained. Arithmetic overflow/nonfinite output, unsupported input, definite excess, precision/resource exhaustion and cancellation remain distinct failures. The independent lower oracle is the literal arch S(u,v)=(.02*u,.02*v,.02*u*(1-u)) continued to [-.25,1.25]x[0,1], compared against independently authored higher-degree candidate coefficients under unchanged standard limits. Tests must also cover a genuinely displaced candidate's definite rejection, asymmetric/nonunit native charts and equal nonunit weights, unsupported families, exact cost-boundary refusal, immutable inputs and cancellation. Consumer publication and the unchanged original anExtendedSheetReachesPastItsEdgesAndKeepsThem/nominal-trim public oracles remain separately owned after lower evidence passes. Full G6 and portable target evidence remain open.

Native lower verification: all14 declarations/16 cases pass on the frozen Swift6.4.0 source, including original polynomial continuation, independent candidate excess, strict candidate support, source-family admission before fitting, immutable COW source ownership, exact direct/prepared budget equality, paid-prefix reset refusal and cancellation after preparation. This completes the lower contract only; public Rebuild composition, the existing contained multi-span resource counterexample and portable integration remain separate task owners. The tests are [PolynomialSurfaceContinuationPositionCertificationTests](../../../Tests/CADGeometryTests/PolynomialSurfaceContinuationPositionCertificationTests.swift).

### Finite Original Polynomial Continuation (PAR.G6MULT1)

The continuation position owner additionally admits exact-clamped, nonperiodic, finite multi-span tensors with exactly common positive stored weights. Original validation retains internal C0 continuity. Each actual positive native span owns its original polynomial; outside the support, the first or last positive span continues independently on each axis. This is the same end-span law consumed by `BSplineSurfaceNaturalContinuation`, not a new global polynomial through all controls. Candidate tensors obey the same family admission and must contain the entire requested native rectangle. Single-Bezier pairs retain the preceding proof path. No position proof depends on tangent or normal regularity.

A producer-only `PreparedPolynomialSurfaceContinuationLaw` retains immutable actual native axis records in the paid source receipt. Original coefficient buffers remain COW-owned by the receipt source. The producer validates clamping, common weights, dimensions and the complete source before fitting. Candidate certification resumes every paid counter and charges only its additional candidate/coverage/extraction work. Source and candidate original positive spans and candidate knot boundaries form finite common cells; every closed cell is retained, including both internal knot sides. Outside-domain cells select end polynomials without clipping, epsilon shifts or selected-native queries outside their authority.

The unchanged native polynomial preparation extracts each source polynomial on its actual native rectangle using original basis derivatives and Cartesian controls relative to one common source origin. The owner transforms that original-derived interval Bernstein tensor to the requested cell by outward affine ratios and blossom, including ratios outside [0,1]. Candidate coefficients are extracted directly on the same cell. Both use one common U/V degree, then coefficient subtraction precedes a complete residual hull bound. No rounded replacement surface, source samples or fit residual authorize success. Initial cells each receive one paid hull and, only if unresolved, a paid center lower-bound witness before entering the shared pending stack. Only unresolved residual tensors are refined, without repeating their admitted parent probes. All initial and refined cells must be discharged before publication.

Axis enumeration, concrete record payloads, array backing growth, retained coefficient/net owners, affine arithmetic, blossom/elevation, hull/witness arithmetic and refinement reservations are charged before allocation or execution under the same caller scalar/work/box limits. Array capacities use explicit precharges. No allowance is reset per native span, receipt reuse, axis or initial cell. Cancellation is checked during enumeration, coefficient phases, traversal and before receipt/certificate publication. Unsupported family, invalid source/request, definite excess, finite-arithmetic/resource exhaustion and cancellation preserve distinct typed failures. Existing limits and distance remain unchanged.

```text
original finite native span law -> paid immutable receipt
    -> common source/candidate cells -> original-derived coefficients
        -> initial hull/witness admission -> shared residual refinement
            -> whole requested-rectangle certificate
```

Dedicated multi-span tests own independent piecewise-linear tensor controls and analytically authored end continuation, U/V and two-axis corner extension, asymmetric charts and common nonunit weights, different candidate partitions, wrong-end polynomial and interior excess, exact usage boundaries, paid prefix, immutable source and cancellation. Existing single-Bezier continuation tests remain regression evidence. Kernel consumer comment/refusal migration and actual public Rebuild proof are separately coordinated; periodic/rational families, all consumers and portable/full G6 closure remain open.

Native Swift 6.4.0 evidence for this bounded extension: the new [multi-span owner tests](../../../Tests/CADGeometryTests/MultiSpanPolynomialSurfaceContinuationPositionCertificationTests.swift) pass seven declarations/eight cases, and the existing continuation regression passes fourteen declarations/sixteen cases. The initial composed run passes twenty declarations/twenty-three cases; the additional independent quadratic-source/cubic-candidate and single-source/multiple-candidate composition declaration passes after actual relink. No production source changed between those runs. These results prove the lower native contract only; the public Kernel multi-span publication migration and portable/full G6 evidence remain separately required.

### Native-Knot Polynomial Continuation Candidate Construction

`GeometryPolynomialSurfaceContinuationConstructing` owns numerical candidate authoring and composition with the existing continued-law position proof. Its input is the producer-created immutable continuation request, caller-selected degrees from 1 through 3 not below the original degrees, and positive caller span/control ceilings. The Rebuild tolerance consumer selects bicubic degrees and its existing maximum 128 spans and 131 controls per axis; this operation does not change explicit layouts or authorize degree reduction. The prepared source retains the existing nonperiodic exact-clamped common-positive-weight admission. Higher-degree and unsupported families remain outside this construction family. The result owns only the actual candidate and its complete position certificate; an uncertified candidate is never published.

Each target axis clamps the actual requested endpoints with multiplicity D+1 and retains every original internal knot strictly inside that interval, unchanged, with multiplicity m+(D-d). The original C^(d-m) partition is consequently preserved, including C0 knots. Original support endpoints do not invent internal breaks: outside that support, the first or last original positive span owns its polynomial continuation. No endpoint snapping, clipping, uniform replacement chart or continuity promotion is permitted.

For each requested cell, original selected-span basis derivatives are evaluated only at the original span's closed lower endpoint. Their Taylor coefficients determine that complete original polynomial. A finite affine coefficient translation and Bernstein degree elevation carry it to the requested cell, including outside-domain cells. The target's selected-span basis gives its Bernstein extraction matrix on that same cell. The first cell determines D+1 controls. At each subsequent knot, existing overlap controls are retained and the final m+(D-d) Bernstein equations form a lower triangular system for precisely the new controls. This is a change of basis in a containing finite spline space, not point fitting or sampled acceptance. Ordinary floating-point authoring is permitted; its rounded candidate must subsequently pass the unchanged outward whole-law certifier. Zero/nonfinite numerical pivots or nonfinite coefficient arithmetic that cannot establish a usable candidate are `toleranceRejected`, not invented resource exhaustion.

Axis operators are shared across control rows or columns. U-row construction followed by V-column construction uses coordinates relative to one original source origin, then restores that same origin. Exactly constant weights cancel by partition of unity; candidate unit weights are the same polynomial representation and do not alter the original source. Every intermediate control, knot, concrete operator/row owner, backing capacity, basis scratch/COW write, solve operation, returned control and weight buffer, receipt and result payload is charged before allocation or execution. Checked dimensions and caller span/control limits are admitted before growth. Malformed options are invalid input, dimensional/storage/work exhaustion is resource failure, finite numerical failure and definite geometric excess are tolerance rejection, and cancellation propagates.

Construction resumes the original request's paid scalar/work/box prefix. A producer-only receipt carrying the same source, law, rectangle, distance, tolerance and limits plus the paid construction suffix is passed to the existing certification protocol. This preserves every counter without resetting a phase, axis or cell allowance. Construction consumes no fictitious certification boxes; proof visits belong to the certifier. Reusing the original immutable request starts another operation with that same original paid prefix, while certification of each authored result includes its complete construction costs. No shared mutable state or new public receipt initializer is introduced.

```text
original immutable paid request
    -> native-knot coefficient construction -> paid construction suffix
        -> existing complete continued-law position proof
            -> certified actual candidate
```

The dedicated [construction tests](../../../Tests/CADGeometryTests/PolynomialSurfaceContinuationConstructionTests.swift) own independently authored quadratic C1 and two-axis C0 laws, both outer continuations, asymmetric charts, common nonunit weights, actual candidate degrees/multiplicities/control counts, immutable source and analytical output positions alongside complete certificates. Wrong end laws and coefficient excess remain independent certifier refusals. Exact cumulative scalar/work boundaries, span/control ceilings, malformed/unsupported input and cancellation distinguish failure categories. Existing single/multiple-span lower proof tests and the unchanged public Rebuild fixture remain separate composition evidence.

Native Swift 6.4.0 evidence: seven new construction declarations/eight cases and twenty-one unchanged lower continuation declarations/twenty-four cases pass together, twenty-eight declarations/thirty-two cases in 0.025 seconds. The independently authored C1 quadratic source constructs a cubic two-span tensor with 24 controls; its complete authoring-plus-proof usage is 12,785 scalar slots, 71,229 work units and two certified cells under the unchanged standard limits. Unit and common nonunit weights pass the same analytical laws. A test-only usage log addition relinks the actual product and rechecks that declaration's two cases in 0.005 seconds; production is unchanged. This is native lower construction/proof evidence; public Rebuild composition, portable closure and full G6 remain separately required.

Native public composition additionally passes after actual SwiftCADTests relink on the committed production baseline plus exact lower/candidate and consumer overlays. The root-owned [continued-law Rebuild tests](../../../Tests/SwiftCADTests/FaceRebuildPolynomialContinuationCertificationTests.swift) verify both unit and common nonunit source weights against independent piecewise polynomial output positions on the requested [-0.25,1.25] native U chart, alongside original source immutability and whole-law-certified publication. Those two cases pass in 0.083 seconds; the same run includes original budget/cancellation/varying-weight refusals, zero-extension whole-original certification and original extension/nominal regressions, seven declarations/eight cases in 1.777 seconds. The tolerance consumer explicitly selects this native-knot family for eligible degree-at-most-three continued sources, retains the existing higher-degree fitter/proof route and does not certify the returned candidate a second time. Distance, caller control/span bounds and standard certification limits are unchanged. Portable targets, other conversion families and full G6 remain separate obligations.

### Original Analytic Rebuild Position (PAR.G6ANALYTIC1)

The named upper consumer is the non-native `.tolerance` branch of
`FaceRebuildFeatureEvaluator`: it constructs a candidate from the original
`Surface3D.point(u:v:)` law on the requested UV rectangle, but historically
publishes the candidate after sampled fitting/edge checks. Its existing public
contract requests distance alone. This sprint supplies complete position evidence
for original ordinary/analytic planes and cylinders, including negative and
shifted cylinder angular intervals, before the upper owner publishes a candidate.
It adds no tangent/curvature allowance to Rebuild and changes no exact-layout,
shared-edge, continuation or rational-reparameterization semantics.

`GeometrySurfacePositionCertifying` accepts two stored B-splines. It cannot retain
an analytic plane/cylinder as the source authority: converting that source first
would compare against a new rounded representation or change an angular chart.
`GeometryAnalyticSurfacePositionCertifying` therefore accepts the immutable
original `Surface3D`, the actual stored B-spline candidate and the caller's finite
native rectangle/distance/`NativeSurfacePositionCertificationLimits`. It returns
the existing position-only receipt, whose native rectangle and actual cumulative
scalar/work/cell usage remain unchanged in meaning. Unsupported original families
fail explicitly rather than invoking sampled or chart-changing substitutes.

```text
original analytic plane/cylinder + requested native UV + caller distance/limits
  -> original analytic interval jet + original stored candidate preparation
  -> candidate-native knot partition (each Taylor path owns one smooth piece)
  -> outward anchor value/first/second difference + whole-cell third-order remainder
  -> all cells admitted -> position receipt -> root-owned Rebuild publication
```

The original analytic law is evaluated by the existing
`DefaultSurfaceDifferentialEncloser` analytic jet visitor, and the candidate by
`PreparedBSplineSurfaceDifferentialEncloser` original closed owning-span queries.
No fitting, rational chart map or rounded Bezier extraction becomes source
proof authority. The original plane visitor uses `Plane3D.parameterBasis`; an
explicit framed plane remains a dependency on the root-owned framed-plane
runtime sprint, not a borrowed completed proof. Existing nil-frame and analytic
plane/cylinder laws have their own literal tests. Source/candidate validation,
preparation, analytic jet arithmetic, candidate probes, interval differences and
pending-cell storage are reserved before execution/allocation under the existing
three resource ceilings. Every callback boundary and final publication checks
cancellation; inputs retain immutable COW ownership. A complete second-order
Taylor difference uses the original anchor's value/first/second jets and a
third-derivative difference enclosure on that same smooth native cell. Cell
partitions retain C0 knot endpoints without asserting a unique higher derivative
across a join. Position certification does not require a regular metric.

Malformed geometry/domain, unsupported source/candidate families, definite
positional excess, unresolved precision/resource limits and cancellation remain
distinct typed failures. A source arithmetic failure never authorizes refinement
or publication. Requested degree/control/layout semantics remain owned by the
candidate producer; the certifier cannot silently replace the candidate.

[OriginalAnalyticSurfacePositionCertificationTests](../../../Tests/CADGeometryTests/OriginalAnalyticSurfacePositionCertificationTests.swift)
will own literal plane and cylindrical Taylor laws, original/asymmetric/negative
native charts, wrong-chart and interior-bump refusals, exact scalar/work/cell
allowance boundaries, immutable source/candidate values and cancellation. The
upper owner retains the unchanged public plane/cylinder Rebuild volume/radius
oracles. [AnalyticFaceRebuildPositionCertificationTests](../../../Tests/SwiftCADTests/AnalyticFaceRebuildPositionCertificationTests.swift)
owns public literal angular-chart positions, feature-scoped caller-budget refusal,
immutable inputs, cancellation and actual old/current retained-state admission.
The upper owner verifies this composed publication. The Kernel owner also invalidates historical analytic publication
states that bypassed this certificate; an exact B-rep receipt alone cannot make
such retained state reusable. Its epoch contract and old/current public reuse
regression are owned by the linked Kernel design. Native, normal-WASM, Embedded, other source families and full G6
completion require their own evidence; preparation alone is not success.


The original cylinder public regression exposed a reservation mismatch: a
singleton full-jet anchor was charged as four positive-width Bernstein cuts,
although the prepared lower query selects point de Casteljau. The analytic
certifier owns a full-point reservation for all ten retained differentiated nets,
every closed touching native span, original-parameter normalization, coefficient
hull scratch, row/result storage and rational resolution. The value-only point
reservation is insufficient for this anchor. Endpoint shortcuts may consume less
than the conservative point bound; they never authorize omitting a derivative
net. Whole-cell localization continues to use the existing interval reservation.
All reservations precede the corresponding lower query, use checked dimensions
and consume the same aggregate caller ceilings. No lower coefficient arithmetic,
jet enclosure, refinement criterion, requested tolerance or standard limit changes.
The unchanged cylinder public regression and the literal angular-chart publication
test distinguish this correction from budget enlargement. The existing exact
scalar/work/cell boundary test verifies the revised aggregate receipt and its
one-unit-short failures; cancellation and input ownership retain their prior laws.


| Point reservation owner | Bound used before the lower query |
| --- | --- |
| Source inspection | Native control/knots scans, charged before weight-group inspection |
| Each derivative net with dimensions a by b | b*a*(a-1)/2 + b*(b-1)/2 interpolations, 40 scalar slots and 116 work units each |
| Coefficient hulls and point result rows | 24*(a*b+b) scalar slots plus 8*(b+1) result slots, per retained net group |
| Original parameter normalization | 256 scalar slots and 2,048 work units for both bounded two-component ratio witnesses |
| Localized scalar hulls and rational resolution | Full ten derivative fields; additional polynomial nets conservatively retain the same group bound |
| Closed native ownership | Every positive original span touching the singleton is charged separately before evaluation |


The public cylinder diagnostic establishes a second causal gap: third-order
whole-cell residual bounds require parent-and-two-child probes despite actual
half-cell bounds below the unchanged goal. For candidates of U degree at most
three with one exactly common positive original stored weight, partition of
unity cancels that weight and proves that each original native smooth piece is
polynomial in U. Its fourth U derivative is zero. V degree is unrestricted; no
vanishing mixed or V derivatives are assumed. Varying weights retain the generic
third-order method because a rational cubic need not have zero fourth derivative.

For this polynomial family the certifier follows the path (u0,v0) -> (u,v0) ->
(u,v). The first leg uses the original anchor's U derivatives through order three
and a fourth-order integral remainder. Original plane fourth-U is zero; original
ordinary/analytic cylinder fourth-U equals minus its original second-UU law.
The existing whole original second-UU interval jet consequently bounds that
remainder without introducing a fourth-jet API or evaluating another source law.
The second leg is the mean-value bound from the existing whole first-V residual.
The exact coefficients are 1/2, 1/6 and 1/24. Every leg lies in its original
candidate native smooth cell; closed touching one-sided jet unions remain
conservative, and no unique higher derivative across a C0 join is asserted.
The generic tensor third-order path remains for other candidate weights/degrees.
Existing source/candidate probes, checked prepayment, cancellation boundaries and
caller ceilings remain unchanged. The new path performs fewer vector/monomial
operations than the already reserved generic Taylor arithmetic.

The dedicated lower test requires one-cell admission of independently authored
cylindrical cubics at radius .01 and angular half-width .05 under a 3e-9 goal,
with literal fourth-order error radius*h^4/24. A varying-weight cubic with a
zero value/first/second residual at its midpoint but independent endpoint excess
must still be refused; it detects an invalid polynomial assumption from degree
alone. Existing wrong-chart/interior-alias, exact cumulative budget and
cancellation tests retain their behavioral assertions. The two unchanged public
cylinder laws complete the consumer evidence; previously successful public
plane/epoch/refusal/cancellation cases retain their unchanged premises.


Analytic probe reservation is derived from the admitted original visitors,
not from unimplemented source families. In
[DefaultSurfaceDifferentialEncloser](../DefaultSurfaceDifferentialEncloser.swift),
`cylinderJet` invokes four vector-jet products (two in `radialJet`, one radius
product and one axial-V product), while `affinePlane` invokes only two. The
[SurfaceIntervalJet](../SurfaceIntervalJet.swift) product rule executes exactly
45 interval products across its ten fields: 1+2+2+4+4+4+6+8+8+6. Each vector
product applies that rule to three coordinates. Each of the two trigonometric
unary jets uses 41 interval products in `applyingUnaryFunction`: two first-order,
nine second-order and thirty third-order products. Thus the cylinder upper count
is 4*3*45+2*41=622. Each interval product in
[OutwardIntervalArithmetic](../OutwardIntervalArithmetic.swift) constructs four
numeric product scratch slots, totaling 2,488 slots. Eight trigonometric hull
calls each have two endpoints and at most two extrema; their backing growth and
fixed extrema-pair records plus basis/parameter metadata fit within 512 additional
slots. A 3,072-slot prepayment consequently covers both admitted plane/cylinder
visitors with headroom. The existing 65,536 work prepayment remains conservative.
The previous 6,000-slot assumption used five vector products and a 64-product
bound for each scalar operation; replacing that assumption changes only the
reservation model, not any visitor, original-law coefficient or caller ceiling.
Higher analytic/procedural families remain explicit unsupported sources and
cannot borrow this cost model. The exact scalar/work/cell boundary regression
and the two original public cylinder paths verify this bounded correction.


For the common-original-weight cubic path, the invocation retains only two
already proved whole-cell vector bounds: original fourth-U and original-minus-
candidate first-V. An immutable receipt also stores the queried parent rectangle
and the original initial smooth native-piece rectangle. Each initial work cell
comes from one positive original candidate U/V knot pair intersected with the
requested chart. A child inherits that exact piece identity; it must be contained
in both the retained parent query and that piece before the bounds are reused.
The original source, candidate and preparation tolerance are immutable owners
of this invocation. No receipt enters from a caller, another chart/source,
another invocation or another C0 side. The candidate common-weight/degree
admission is fixed once. Generic rational/higher-degree cells retain their
original whole-query and third-order method and never carry this receipt.

Both inherited vector bounds remain valid on every child subset. The U leg still
uses the child's actually queried original/candidate anchor jets; only its fourth
remainder range is inherited. The V MVT range contains the child's complete
vertical segment. Thus inheritance can widen a child's conservative result
relative to a fresh whole query, but cannot weaken its whole-position guarantee.
Unresolved children still subdivide or fail under the same caller ceilings.
Parents, children and retained bounds share one paid aggregate counter; popping
a cell or reusing a bound never resets or refunds it. Cancellation is checked
before receipt validation, all actual lower queries and final publication.

| Immutable storage/work owner | Prepayment before creation/use |
| --- | --- |
| Receipt: two vector bounds plus parent/native rectangles | 20 numeric fields, reserved as 80 scalar slots and 128 work units before vector extraction/record creation |
| Work cell: current/native rectangles plus optional receipt | 28 numeric fields plus discriminator/padding fit 32 slots; 128 slots and 32 work units per append conservatively cover backing growth/moves |
| Two child work cells | 256 scalar slots and 64 work units before their records/stack appends |
| Reuse admission | 32 work units before exact piece equality and closed parent/native containment checks |

The operation-local stack exclusively owns its backing array and immutable value
records; it has no external aliases or shared mutable state. The enlarged work
cell storage is charged for generic cells as well, without changing their math
or probe family. The independent retained-bound fixture shifts the authored
cylindrical cubic by half its literal fourth-order remainder, forcing refinement
while its independently bounded true error remains below the requested goal.
Actual child anchors and exact scalar/work/box ceilings, each one-unit-short
refusal and immutable input assertions verify retention without granting a
private allowance. Original public cylinders remain the required consumer proof.
