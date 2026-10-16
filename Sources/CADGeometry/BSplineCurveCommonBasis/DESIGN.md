# B-Spline Curve Common Basis

## Purpose and Scope

This component constructs two curve images in a common normalized clamped
basis. Its parent is [CADGeometry](../DESIGN.md); it has no children.

## Responsibilities and Boundaries

The resolver owns normalization, span alignment, degree elevation and immutable
result storage. Original curve parameter and contact authority remain with the
original source owners; common-basis images do not create correspondence receipts.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADGeometry](../DESIGN.md) | parent | Original curve and basis contracts | Defines source truth | Image construction does not replace original laws |
| [Loft](../../CADModeling/Loft/DESIGN.md) | used by | Bounded common preparation | Retains one shared connector image for adjacent sides | Work is charged to its existing invocation allowance |

## Architecture

```text
caller allowance -> bounded resolver
    -> paid source scans and native decomposition
    -> paid aligned spans and degree elevation
    -> immutable shared basis pair
```

## Contracts and Invariants

The existing resolve signature preserves its numerical behavior and limits.
The direct protocol requirement receives `using execution: inout OriginalQueryExecution` and sends it to actual native validation, decomposition, trimming and construction. Original loop work and concrete typed allocation bytes reach its sole cumulative budget. Independent span/count policy remains local; no callback allowance, refund or reset is constructed. All dimension arithmetic checks overflow. Already-identical normalized bases retain original
arrays without reconstructing controls. The same ordered arithmetic, original
span association, tolerance and maximum-span failure contracts are retained.

## Runtime Flows

Validation and reservations precede decomposition. Each aligned positive span
retains its selected source patch, trims it, elevates homogeneous controls and
assembles the result. Cancellation or execution failure propagates before the
charged operation. Legacy conformers without bounded preparation do not silently
invoke an uncharged implementation through the bounded requirement.

## State, Ownership, and Lifecycle

Preparation arrays and pair values belong to one invocation. Arrays retain COW
owners. There is no shared mutable cache, target-dependent state or new unsafe
boundary. Consumers retain canonical images instead of independently preparing
the same original connector for each side.

## Failure, Concurrency, and Constraints

Finite positive domains, valid source coefficients and positive span limits are
required. Invalid inputs, nonfinite homogeneous arithmetic, ambiguous source span
association and exhausted caller reservations propagate typed failures.

## Verification and Change Impact

Deferred behavioral verification must exercise unequal degrees/knots/weights,
original normalized fast paths, endpoint alignment, cancellation and exhaustion
before lower allocation. Native, WASM and Embedded protocol dispatch must use
the direct execution requirement. Loft must check the actual shared-boundary and complete
embedding publication paths. This source batch has not been built or tested.

Ordinary resolution creates one independent execution and delegates to the same body. Work estimates formerly covering opaque native routines are removed when those actual routines charge the same execution; structural output and maximum-span ceilings remain unchanged.
