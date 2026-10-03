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
Until exact periodic refinement and bounded restriction are implemented, those
editing entries must reject periodic inputs as unsupportedCapability. Their
markers are tracked by the public domain catalog and cannot be removed without
success and failure evidence. This temporary boundary is not final completion.

## Verification and Change Impact

PeriodicBSplineCurveTests checks rational/nonrational cyclic basis agreement,
seam derivatives, normalization with nonzero origins, origin changes, reversal,
transform/transport preservation and malformed-cycle refusal through Curve3D and
ValidatedCurve3D. G1 remains open until editing, prepared bounds/projection and
portable runtime evidence close the remaining gaps. Higher consumers that assume
a closed domain require review under G5; metadata cannot prove their support.
