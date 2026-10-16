# Curve Parameter Projection

## Purpose and Scope

Child of [CADGeometry](../DESIGN.md), with no children. Owns original-curve inverse, closest and directional numerical projection; retained validated curve readers and native B-spline projection preparation. It does not issue source equality, original intersection identity or repair topology.

## Responsibilities and Boundaries

The existing projection tolerance, residual, candidate ambiguity, endpoint equivalence, global closest-bound, directional line/ray and non-discrete-intersection policies are preserved. Native evaluators and original source validation own source mathematics. Intersection services own their existing discrete/coincident evidence; projection consumes their public result without strengthening it.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADGeometry](../DESIGN.md) | parent | Direct execution and numerical helper contracts | Composes projection APIs | Projection proximity is not source identity |
| [Original Geometry Source Validation](../OriginalGeometrySourceValidation/DESIGN.md) | depends on | Original validation and retained preparation depth receipt | Validates authoritative source once | Independent queries re-admit immutable evidence |
| [Curve Differential Bounds](../CurveDifferentialBounds/DESIGN.md) | depends on | Position enclosure and original derivatives | Supports closest bound and Newton evaluation | Bounded approximation does not prove coincidence |
| [Original Query Execution](../OriginalQueryExecution/DESIGN.md) | depends on | Same execution, cumulative owner, ordered contributions | Owns all work/storage/depth admission | Retained readers preserve actual ancestry and effective policy |

## Architecture

```text
curve + projection options + query execution
    -> original source validation / immutable native preparation
        -> existing point and differential evaluation
            -> Newton / control-hull stack / closest bounds / directional intersection
                -> existing checked projection result
```

## Contracts and Invariants

Actual fallible query entries receive final `using execution: inout OriginalQueryExecution`. Ordinary queries create one root and call the same body. Work, typed source-sized buffers, capacity growth and cell depth are admitted on that original execution before their actual operation. No callback recreates a ledger, no child spendable budget is created, and no numerical failure is converted to a success result.

The immutable validated reader and native projector retain their source, tolerance, effective execution policy, common budget, ordered contribution handles, and operation-local preparation receipt. Same-operation queries borrow the caller execution. Later ordinary reads construct query-local scopes on the retained owner/ancestry. A caller with another budget verifies and re-admits the retained receipt once per execution, without rerunning validation, trimming or decomposition and without replaying their historical work or scratch allocations.

ValidatedCurve3D retains original validation, while native trimming/decomposition belongs to the explicit immutable `makeParameterProjector(options:)` owner. Arbitrary per-call projection options do not introduce a mutable preparation cache. Native candidate sorting uses a stable bottom-up merge with two admitted typed buffers and the unchanged residual/parameter ordering; each actual comparison/move is charged on the current execution.

## Runtime Flows

Inverse projection preserves existing analytical candidates and bounded native root selection. Closest projection preserves its witness/refinement and whole-range lower bound. Directional projection preserves its two-plane and line/ray selection path. Retained native preparation preserves trimming, endpoint equivalence and outward homogeneous control-hull decomposition exactly once.

## State, Ownership, and Lifecycle

Retained sources, policies, patches and receipts are immutable Sendable owners. Numerical seeds, candidate arrays, subdivision stacks and Newton state belong to one query. Cumulative budget/contribution state belongs to the shared common Mutex owners. This component adds no target-specific synchronization or escaping work/storage callbacks.

## Failure, Concurrency, and Constraints

Existing invalid input/domain, ambiguous selection, absent projection, unresolved control-hull coverage, nonfinite arithmetic, singular weight and resource exhaustion remain explicit. Cancellation and admission failures propagate to the caller. Source/spatial/scalar axes remain independent; explicit projection iteration, seed, cell, depth and candidate limits remain authoritative.

## Verification and Change Impact

[CurveParameterProjectionTests](../../../Tests/CADGeometryTests/CurveParameterProjectionTests.swift), [CurveDirectionalParameterProjectionTests](../../../Tests/CADGeometryTests/CurveDirectionalParameterProjectionTests.swift) and [ValidatedCurve3DTests](../../../Tests/CADGeometryTests/ValidatedCurve3DTests.swift) own numerical and policy behavior. Recheck original primitive/native/lifted families, endpoint and multiple-solution policy, closest full-domain bounds, directional coincidence, observed work/storage N/N-1, cancellation, independent retained readmission and ordered contribution lifetime. Modeling, Topology and source-correspondence callers must pass the same execution. Focused syntax parsing is preparatory; semantic and runtime verification remains pending until the shared direct graph compiles.
