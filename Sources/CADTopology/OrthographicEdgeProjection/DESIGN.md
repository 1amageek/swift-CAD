# Orthographic Edge Projection

## Purpose and Scope

Child of [CADTopology](../DESIGN.md); no children. Owns D2's selected-edge
composition. It does not validate unrelated shells, classify visibility,
generate silhouettes, serialize PDFs or complete the full drawing requirement.

## Responsibilities and Boundaries

Resolve exact edge/curve/vertex references and directed trim ownership.
Geometry owns projection and original evaluation. Callers select the EdgeID and
coedge orientation. No mesh edge or nearest-point search supplies authority.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADTopology](../DESIGN.md) | parent | Edge, CurveTrim and references | Retains original identity and direction. | Selected-edge validity is not whole-model validity. |
| [Curve projection](../../CADGeometry/OrthographicCurveProjection/DESIGN.md) | depends on | original projected law and frame | Supplies XY geometry. | No visibility/regularity guarantee. |

## Architecture

```text
BRepModel + EdgeID + orientation
 -> original curve and vertices -> directed trim and endpoint checks
 -> geometry projector -> OrthographicProjectedEdge
```

## Contracts and Invariants

- Retain EdgeID, CurveID, traversal VertexIDs and original parameter endpoints.
  Reversal swaps endpoints and vertices without changing the source curve law.
- Explicit trims use CurveTrim validation. Infer missing trims only for an
  unbounded exact linear source, from its original parameterized line. A rational
  B-spline's linear locus never implies affine parameters.
- Table keys must agree with stored IDs. Both endpoint vertices and the source
  curve must exist. Evaluate original trim endpoints and check agreement with
  vertices under BRepModel's existing eight-distance-tolerance contract; returned
  geometry remains the original curve, without snapping or approximation.
- Results accept finite original parameters inside the exact directed interval,
  including endpoints. A view-direction edge may collapse in XY and keeps its IDs.
- Failures are atomic: no result is published after reference, trim, endpoint,
  arithmetic, source or cancellation failure.

## State, Ownership, and Lifecycle

Immutable Sendable output retains one source curve. The stateless default
projector reads existing COW model maps. No shared mutable storage is introduced.

## Failure, Concurrency, and Constraints

Existing TopologyError reports malformed selected topology. Geometry/source
failures propagate. Resolve a fixed number of references, validate one source
and evaluate two endpoints. No model scan, iterative inversion or mesh allocation
occurs. Check cancellation at entry and before publication.

## Verification and Change Impact

[Public topology tests](../../../Tests/CADTopologyTests/OrthographicEdgeProjectionTests.swift)
verify actual source identity, directed trims, reversal, affine-scaled lines,
collapsed XY output, missing/mismatched references, bad endpoints, absent nonlinear
trims and interval refusal. Geometry changes affect this composition. Native
proof does not establish WASM/Embedded or whole-D2/main completion.

[Cancellation tests](../../../Tests/CADTopologyTests/OrthographicEdgeProjectionCancellationTests.swift) verify cancelled entry and cancellation after the injected geometry constructor; neither returns a projected edge.

### Portable module wiring

This component consumes the unchanged current-task cancellation and direct
collection import contracts owned by [CADTopology](../DESIGN.md#m6-portable-validation-wiring).
Its algorithms, budgets, immutable source owners and existing isolation remain
unchanged on Native, ordinary WASM and Embedded.
