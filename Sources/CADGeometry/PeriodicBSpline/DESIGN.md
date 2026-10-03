# Periodic B-spline Curves

## Purpose and Scope

Child of [CADGeometry](../DESIGN.md), without children. Owns the cyclic curve
representation, parameter normalization and fundamental-origin contract for G1.
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
| [CADCapabilities](../../CADCapabilities/DESIGN.md) | coordinates with | Source-backed limitations | Reports unfinished periodic edits | Correct refusal does not complete G1 |

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
parameters and resource failures. G1 remains open until
portable runtime evidence close the remaining gaps. Higher consumers that assume
a closed domain require review under G5; metadata cannot prove their support.
