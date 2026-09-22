# Involute Geometry

## Purpose and Scope

Child of [CADGeometry](../DESIGN.md), with no children. Owns positional
approximation of a circular involute flank, not complete gear geometry.

## Responsibilities and Boundaries

The public approximation protocol accepts a base radius, nonnegative roll
interval, positional allowance and caller-owned segment budget. It returns
ordinary cubic B-spline spans with a proven maximum positional error. Gear
dimensions, root transitions, feature identity and UI belong to consumers.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADGeometry](../DESIGN.md) | parent | outward arithmetic, certified trigonometry, B-spline | Existing geometry representation | Preserve refusal on uncertifiable inputs |

## Architecture

```text
radius + roll interval + allowance + segment budget
    -> interval endpoint positions/derivatives
    -> cubic Hermite controls + remainder certificate
    -> B-spline spans and maximum positional bound
```

## Contracts and Invariants

The local XY involute is r(cos(t)+t sin(t), sin(t)-t cos(t), 0).
Its derivative is rt(cos(t), sin(t), 0). Each fourth-derivative coordinate
is bounded by r(3+t); the vector Hermite remainder is conservatively bounded
in L1 by r(6+2b)h^4/384 on [a,b]. Existing outward intervals enclose endpoint
trigonometry and arithmetic. The maximum control-point L1 storage error adds
to that remainder by the nonnegative partition-of-unity Bernstein basis.
Dyadic subdivision retains shared endpoint values and a common roll parameter.
Adjacent stored spans meet exactly; derivative equality is bounded by control
rounding, not claimed bitwise. No exact analytic or C2 claim is made.

## State, Ownership, and Lifecycle

All work is request-local and Sendable. Returned spans own their value storage.
The caller supplies the maximum segment count; no subdivision exceeds it.

## Failure, Concurrency, and Constraints

Radius and allowance must be positive finite values, and 0 <= a < b <= 16
matches the existing certified trigonometry domain. Invalid inputs throw typed
KernelError. Unattainable accuracy, nonfinite arithmetic or segment exhaustion
throw resourceLimitExceeded without returning partial geometry.

## Verification and Change Impact

CADGeometryTests/InvoluteApproximationTests verifies analytic samples, retained
roll endpoints, joined span positions, JSON round-trip and invalid/exhausted
requests. Any future gear consumer must separately verify tooth/root geometry,
dimension reevaluation and composition with Sweep; this contract alone does
not establish manufactured gear accuracy or engineering CAD completion.

`SwiftCADTests/CertifiedTwistSweepSourceTests` also checks a flank-sector through
persisted cubic sketch controls, parameter-driven radius scaling, certified
double-helical Sweep, exact topology and actual tessellation. The evaluated
radial bounds follow r*sqrt(1+t^2) before and after the parameter change.
This confirms the existing downstream route; it does not preserve a complete
gear's design intent. A gear source must retain tooth count, pressure angle,
root conditions and allowance and regenerate geometry after dimension changes,
rather than treating a frozen control polygon as a parametric gear definition.
