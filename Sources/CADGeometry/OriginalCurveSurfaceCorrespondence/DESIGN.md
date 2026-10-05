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

- Spatial curves are finite closed-domain native B-splines of degree 1...6.
  This main-native model has no periodic metadata or cyclic evaluation path;
  its nonperiodic admission rule is the existing exact closed-domain validation
  followed by exact clamped end knots and degree-fold interior multiplicity.
  Every admitted coefficient slice is therefore a Bezier patch without knot
  insertion or extraction. Rational weights are strictly positive. The directed
  trim must lie inside the original closed domain, including its endpoints; it
  has nonzero represented width. Neither domain nor native knots are
  tolerance-snapped.
- Pcurves are original degree 1...4 clamped degree-fold B-splines with positive
  weights, or original affine/constant-coordinate charts. All pcurve control
  coordinates (or affine endpoint interval images) must be inside the support
  domain. Rational positive-weight convex hull containment independently proves
  containment for all fractions, not only stations. Unproved containment refuses.
- Supports are finite closed-domain cubic-U/linear-V clamped B-splines with one
  V interval and interior U multiplicity at most three, or planes with a literal
  coordinate-axis unit normal. As with the spatial curve, the main-native
  representation has no periodic flags; exact closed-domain validation and the
  explicit clamped/multiplicity checks below are the admission authority.
  Original support knots and coefficients are evaluated by outward Cox
  recurrence on each original owning span. No sampled controls, rounded
  extraction, clipping of actual geometry, or pcurve mutation are admitted.
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

Native verification is owned by the affected `CADGeometryTests` product in the
main-native checkpoint. In the bounded `PAR.MAINCORR1` snapshot, the production
graph built with Swift 6.4.0 in 123.99 seconds and all 10 dedicated cases
passed in 0.026 seconds. The cases cover the tighter-distance refusal,
exact/within-limit certificates, all-source binding, aggregate budgets,
native cell traversal, C0 ownership and cancellation. Requested tolerances and
ceilings were not increased. Kernel composition, the actual Draft full
producer fixture and portable execution remain pending their owning
verification; this receipt proves only the lower CADGeometry contract.

### Main-native composed residual extension

For the admitted cubic-U/linear-V support family, the producer may additionally
construct the whole directed-use homogeneous residual from the original spatial
curve, original parameter curve, and original support tensor. This extension
retains coefficient correlation across the complete closed interval and uses
outward Bernstein products, elevation, rational denominator hulls, and closed
subdivision cells. It is an alternative proof representation, not a sample or
tolerance shortcut: if its structural admission or finite positive denominator
proof fails, the existing interval proof remains authoritative.

The extension consumes the same caller work ceiling. Temporary polynomial
storage is checked before materialization, root and span records are charged
before traversal, and cancellation or resource failure propagates as the
existing typed error. It does not change the main-native finite-domain,
clamped-knot, degree, multiplicity, positive-weight, or source-binding rules.
The component test owner supplies independent original coefficient fixtures
for exact composition, reversed rational trims, C0 ownership, an interior
false-positive perturbation, and the bounded resource refusal.
