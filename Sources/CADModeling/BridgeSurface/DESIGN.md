# BridgeSurface

## Purpose and Scope

Child of [CADModeling](../DESIGN.md), with no children. It creates one exact
G0 ruled sheet between two source B-rep boundary edges.

## Responsibilities and Boundaries

The component resolves two stable edge references against the current exact
evaluation, extracts their trimmed curves without tessellation, and delegates
surface construction and sheet topology to the existing ruled builder and
B-spline surface evaluator. It does not own source selection, scene placement,
UI state, gap fitting, or G1/G2 optimization.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADModeling](../DESIGN.md) | parent | exact feature evaluation | Owns construction and typed evaluation failures. | No mesh-derived curve geometry. |
| [CADIR](../../CADIR/DESIGN.md) | depends on | stable source edge references | Persists edge identity and geometry signature. | References must resolve against the live input. |
| [CADGeometry](../../CADGeometry/DESIGN.md) | depends on | bounded exact curve conversion and ruled B-spline surface | Supplies exact supported geometry operations. | Incompatible curve bases fail explicitly. |
| [SurfaceFill](../SurfaceFill/DESIGN.md) | coordinates with | exact edge-trim conversion | Shares the conversion of B-rep trims to bounded B-splines. | Both use the CADTopology open-boundary loop resolver. |
| [CADKernel](../../CADKernel/DESIGN.md) | used by | evaluated input B-rep and subshape index | Supplies the immutable current source snapshot. | No re-evaluation or topology guessing. |

## Architecture

```text
two stable source edge references
    -> current exact topology resolution
    -> exact trimmed B-spline boundaries
    -> persisted second-edge orientation
    -> ExactRuledBSplineSurfaceBuilder
    -> B-spline surface evaluator
    -> separate dependent sheet output
```

## Contracts and Invariants

- Both stable references name distinct edges and resolve to open boundary edges
  of their respective current source bodies, in a common coordinate frame.
- Every distinct source feature is an explicit graph input, in boundary order.
  The output is one `.sheet`; both input bodies and topology remain unchanged.
- Boundary curves come from current exact B-rep curves and trims. Display
  polylines and copied inline curves are never geometry authority.
- The second edge orientation is persisted, so reevaluation does not choose a
  different correspondence silently.
- Exact curve conversion, ruled basis alignment, surface regularity, embedding,
  and B-rep validation must succeed before the sheet is returned. Unsupported
  curves, stale references, degenerate boundaries, incompatible bases, and
  invalid surfaces fail explicitly.
- The operation guarantees G0 boundary coincidence only. It makes no claim of
  G1/G2 continuity, quality optimization, tension, flow, or guide constraints.

## Runtime Flows

The evaluator resolves both references from one `EvaluationContext`, verifies
that each belongs to its declared source body, constructs the exact ruled
surface, and delegates topology creation to the existing B-spline surface
evaluator. No partial result is published.
The delegated evaluator's validated result is returned directly; Bridge does
not discard its validation evidence and validate the same B-rep a second time.

## State, Ownership, and Lifecycle

The feature graph owns the stable references and orientation. The evaluation
context owns the immutable B-rep snapshot. The component is stateless.

## Failure, Concurrency, and Constraints

Evaluation is synchronous and request-local. Exact conversion and basis
alignment resource limits are those of their existing builders. The first
application route requires equal accumulated occurrence transforms so the CAD
source coordinate frame is unambiguous. Different frames are refused by Core.

## Verification and Change Impact

`SwiftCADTests/BridgeSurfaceBuilderTests` proves rational boundary coincidence
for both orientations, source-body retention, and Codable command replay.
`CADModelingTests/SurfaceFeatureEvaluatorTests` checks missing live topology.
Core tests own selection/occurrence validation,
preview/apply, persistence, and Undo/Redo. Changes require reviewing CADIR,
FeatureNodeFactory/DesignGraph contracts, CADKernel dispatch, RupaCore command
preparation, and the contextual viewport route.
