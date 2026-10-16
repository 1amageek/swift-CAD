# Original Rectangle Tessellation

## Purpose and Scope

This component is a direct child of [CADGeometry](../DESIGN.md). It owns
selected closed native-span tokens, panel traversal, selected
differential evaluation and the invocation-local proof budget for nonperiodic
original B-spline rectangles. It has no children. Module composition adapters
retain original coefficient preparation, existing basis evaluation, whole-query
enclosures and the unchanged normal regularity gate.

## Responsibilities and Boundaries

The component binds tokens to the original source and tolerance and retains
their closed owners through panel traversal and selected normal evaluation.
The budget counts every visited proof cell across every native panel in one
rectangle. It owns the existing 262,144-cell and depth-32 ceilings and permits
lower internal test ceilings. Mesh allocation and face-run accounting remain
owned by [RectangularBSplineMesh](../../CADKernel/RectangularBSplineMesh/DESIGN.md).

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADGeometry](../DESIGN.md) | parent | original homogeneous native-span jets | Source coefficients and closed owners supply differential authority. | Whole-query behavior and source storage are unchanged. |
| [RectangularBSplineMesh](../../CADKernel/RectangularBSplineMesh/DESIGN.md) | used by | selected original panels and normals | Consumes complete panel bounds. | Native proof ceilings are independent of mesh allocation charges. |

## Architecture

```mermaid
flowchart LR
  Source[Original stored surface] --> Preparation[Closed native-span tokens]
  Preparation --> Traversal[Selected panel subdivision]
  Traversal --> Budget[Invocation-local cell and depth budget]
  Traversal --> Bounds[Certified differential bounds]
  Preparation --> Normals[Owning-span endpoint normals]
```

## Contracts and Invariants

Selected-token validation, coefficient receipts, station-row preparation,
materialization and selected numeric differentiation follow the
[module's direct execution contract](../DESIGN.md#direct-original-query-execution).
They receive the original generic admission, retain immutable source and
one-sided span owners, and debit source comparisons, actual numeric loops and
typed storage through that same owner. Tokens retain no mutable execution or
callback allowance. The admitted interval-jet path keeps its original coefficient
receipt and requested-order Taylor producer; rounded Cartesian patches do not
replace its source authority.

Tokens bind the exact surface value and preparation tolerance. Queries lie
inside the actual closed native knot span; neither tolerance padding nor
canonical endpoint replacement changes ownership. Native bounds use original
homogeneous coefficient intervals, not Cartesian extraction. Panel subdivision
never unions adjacent one-sided jets. Existing normal regularity criteria remain
unchanged. The nonperiodic surface representation and Codable fields remain
unchanged; periodic representation is outside this component.

## Runtime Flows

Preparation retains one token per positive native tensor span. A rectangular
request intersects each token and traverses its positive-width panel. Each
visited cell consumes one shared budget charge. A complete outward jet proves
tangent, second derivative and unit-normal derivative bounds, or the same
selected owner subdivides. Only complete panel aggregates are returned.

## State, Ownership, and Lifecycle

The caller owns one exclusive execution. The native rectangle installs an
immutable contribution with the original 262,144 work/cell ceiling, word-based
allocation contribution and geometric depth 32. The common synchronized budget
owns the cumulative counters; this component owns no duplicate mutable ledger.
Actual cell depth is mapped only as geometric depth, independently of scalar and
source depth. Pending panels and cells admit their real typed replacement
capacity before allocation; no predicted traversal storage is materialized.
No shared mutable cache is introduced.
Tokens and prepared coefficient nets are immutable Sendable values retained for
the operation. Native, WASM and Embedded share these same declarations and
access paths; this component adds no conditional synchronization branches.

## Failure, Concurrency, and Constraints

Invalid source, tolerance or closed-domain ownership throws invalidInput.
Collapsed tangent frames throw singularGeometry during traversal. Finite
arithmetic, cell, depth and representable-subdivision exhaustion throw explicit
resourceLimitExceeded. Cancellation propagates before preparation, span
selection and each cell. No sampled or zero-bound fallback supplies success.

## Verification and Change Impact

[OriginalNativeRectangleGeometryTests](../../../Tests/CADGeometryTests/OriginalNativeRectangleGeometryTests.swift)
checks nonclamped success, C0 endpoint owners, whole-query compatibility,
source/tolerance/domain refusal, collapsed geometry, aggregate budget refusal
and cancellation. Upper [RectangularBSplineMesh](../../CADKernel/RectangularBSplineMesh/DESIGN.md)
tests must verify panel coverage, endpoint mesh normals and cumulative face-run
budgets. Changes to coefficient preparation or selected basis evaluation require
rechecking both token containment and upper mesh fidelity.
