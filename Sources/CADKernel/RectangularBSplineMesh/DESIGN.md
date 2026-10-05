# RectangularBSplineMesh

## Purpose and Scope

This component is a child of [CADKernel](../DESIGN.md). It owns admission and compatible grid planning for open, nonperiodic B-spline faces with at least one nonclamped basis axis. It has no children. Existing clamped, analytic, procedural and general trimmed mesh routes remain owned by the module composition.

## Responsibilities and Boundaries

The component reads the original source pcurves and native basis without changing geometry, topology, units or tolerance. It admits exactly four connected monotone rectangular side runs, including runs split into multiple source coedges. Geometry owns selected-span regularity and differential enclosures. MeshTessellator owns all-or-nothing caller resource admission, orientation, triangle emission, compaction and face-run provenance.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADKernel](../DESIGN.md) | parent | face preparation and cumulative Mesh admission | Composes the selected native grids with existing routes. | Preserve cancellation, limits and face order. |
| [CADGeometry](../../CADGeometry/DESIGN.md) | depends on | originalNativeSpanTessellationBounds and owning-span normal | Certifies the original native support and evaluates closed-span normals. | No reparameterization or whole-chart continuous normal assumption. |
| [CADTopology](../../CADTopology/DESIGN.md) | depends on | connected source coedge graph | Supplies face-local original pcurves and vertex identities. | UV adjacency and source vertex identity must agree exactly. |

## Architecture

```mermaid
flowchart LR
    Face["Original nonclamped face"] --> Admission["Native rectangle admission"]
    Admission --> Geometry["Selected original-span bounds"]
    Geometry --> Planner["Compatible U/V counts"]
    Planner --> Parent["MeshTessellator preflight and emission"]
```

## Contracts and Invariants

The selected route requires a valid positive-weight surface, at least C0 interior knot continuity, a rectangle within the closed native domain, and no inner loops. Non-rectangular source trims fail with typed unsupported capability. Each native panel retains its owning span; adjacent panels share the maximum retained subdivision count for the corresponding original U or V span. Final counts are rechecked against every panel's bounds at the exact representable stations emission uses. Stored constant-U/V pcurve endpoints are the rectangle admission authority; normalized-fraction interpolation does not replace those represented endpoints. A shared station function returns the original lower and upper bounds verbatim at the first and last station; its exact final gap participates in subdivision admission. Chord error, normal variation and every triangle edge, including its diagonal, meet the caller's bounds.

## Runtime Flows

Admission precedes native-panel enclosure. Per-panel certified counts are reconciled by original axis span index and rechecked without changing stations. MeshTessellator charges the complete retained grid usage before output emission. Vertices use original point evaluation and closed owning-span normals so C0 corners retain both one-sided normals. Compaction changes indices without changing triangle order or face provenance.

## State, Ownership, and Lifecycle

Preparation is invocation-local immutable data. The owning native span retains the original surface and tolerance. No shared mutable state, cache, persistence or source edits are introduced. Output ownership remains with MeshTessellator.

## Failure, Concurrency, and Constraints

Cancellation propagates at traversal, refinement and emission checkpoints. Geometry proof exhaustion and singular panels remain typed failures. Each axis permits at most 65,536 steps; representationally collapsed stations fail. Caller vertex, index, triangle and byte limits retain the module's cumulative atomic refusal. Independent panel ownership does not authorize concurrent mutation of one output buffer.

## Verification and Change Impact

[OriginalNativeRectangularMeshTests](../../../Tests/CADKernelTests/OriginalNativeRectangularMeshTests.swift) owns independent literal polynomial oracles in native parameters 2...3, U/V and two-axis nonclamped cases, C0 one-sided normals, collapsed refusal, exact native boundary coverage under rounded span arithmetic, unchanged exact source, FaceRuns, resource refusal and cancellation. Root integration executes the public native and ordinary WASM mesh paths using the same source. Changing selected-span authority requires geometry tests; changing routing or caller admission requires CADKernel integration tests. Existing clamped and non-B-spline routes require regression checks when composition changes.
