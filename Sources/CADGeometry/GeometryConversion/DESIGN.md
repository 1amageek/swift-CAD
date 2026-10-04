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

The certifier owns complete source and target preparation cost before either is prepared. A PreparedBSplineSurfaceDifferentialCost descriptor in the native preparation owner derives conservative checked reservations from actual original span/local basis/Taylor-to-Bernstein/ten-derivative-net dimensions. The descriptor's original validation/control/knot scans are charged before execution; allocation, source and target preparation, each full-cell and anchor probe (including every original-span scan and localization scratch), and stack storage are charged cumulatively to the same operation. The existing native prepared source remains original homogeneous authority. Costs follow the executed producer loops, not a guessed flat per-box price; all arithmetic overflow and exhaustion produce typed resource failure. Default limits follow the existing conversion envelope (65536 boxes,1048576 scalar slots,16777216 work units); caller limits can change without changing correctness. Admission must be tested under actual defaults rather than increasing them to pass a fixture. Cancellation is checked before preparation, at traversal and immediately before certificate publication.

After complete input/domain validation and charged original structural comparison, exactly equal complete stored source/candidate values may certify zero position error on the requested native rectangle directly; this original coefficient identity proves the whole locus, requires no artificial preparation or probes, reports their actual zero usage and checks cancellation before publication. It does not authorize reparameterization or approximate equality. All other cases prepare both original supports and every cell uses an outward original source/candidate anchor enclosure plus the complete first-derivative difference times outward UV offsets, bounding position by the fundamental theorem of calculus. The anchor uses the central stored original knot when strictly interior to the cell, otherwise its midpoint; every lower and upper offset uses that actual anchor. Original anchor evidence may establish definite excess before full-cell jets, and cannot admit a successful cell alone. Definite positional excess is GeometryConversionError.toleranceRejected; unresolved subdivision/work/representable precision is an explicit resource failure. Every cell must be admitted before a certificate exists. Independent literal flat/nonregular metric sources, the9-by-9 bump alias, same-source success, repeated-knot coverage, asymmetric domains, strict overshoot refusal, cost-boundary failure and cancellation precede the public native Rebuild integration. Existing three-field conversion APIs retain their semantics and source-cost contract.

Native verification: the9 dedicated declarations/11cases pass with unchanged standard allowances. After the finalCore contract update, these9 and10 existing conversion declarations pass19tests10.133s. The exact staged public Rebuild path and consumer contract are verified independently; this evidence does not cover portable targets or source continuation.
