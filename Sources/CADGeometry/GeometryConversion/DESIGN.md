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
- The guarantee reports actual admitted upper bounds, degrees and control count.
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
For ruled sources with two B-spline boundaries, the native surface adapter uses
the existing exact chart-preserving tensor representation for its enclosure while
retaining the original procedural value as evaluation authority. This removes
correlation loss from subtracting independently enclosed translated boundaries.
Source implementations retain ownership of their per-request cost.
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
