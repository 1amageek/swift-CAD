# BridgeSurface

## Purpose and Scope

Child of [CADModeling](../DESIGN.md), with no children. It creates one exact
G0 ruled or G1/G2 Hermite sheet between two source B-rep boundary edges.

## Responsibilities and Boundaries

The component resolves two stable edge references against the current exact
evaluation, extracts their trimmed curves without tessellation, and delegates
surface construction and sheet topology to the existing ruled builder and
B-spline surface evaluator. It does not own source selection, scene placement,
UI state or source acquisition. Constrained construction owns its candidate
derivative rows and whole-boundary continuity certificates.

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
    -> persisted source-to-output affine maps
    -> persisted second-edge orientation
    -> ExactRuledBSplineSurfaceBuilder
    -> B-spline surface evaluator
    -> separate dependent sheet output
```

## Contracts and Invariants

Hermite control rows translate points by signed derivative vectors. The final row formula preserves the original derivative coefficients and positional/tangent/curvature proof.


- Both stable references name distinct edges and resolve to open boundary edges
  of their respective current source bodies. Each persisted source-to-output
  affine map converts its exact boundary into the output frame. Coincident
  source IDs are allowed only when their maps differ.
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
- Positional requests retain the ruled surface. Tangent-plane and curvature
  requests use quintic Hermite rows, with first derivatives in each source wall's
  tangent plane and second normal derivatives from its original shape operator.
  Width sets derivative magnitude in meters and tension scales it without units.
  Candidate collocation generates coefficients only; publication additionally
  requires whole-boundary position, normal and shape-operator certificates on
  both retained walls, then the sheet evaluator's regularity/topology admission.
  Source walls and source boundaries remain the authority for certification.
  The evaluator retains each original incident coedge's native UV law in the
  authored stored-edge direction, including the explicit second-edge reversal.
  A placed wall is an original affine image with unchanged UV coordinates.
  The final certificate consumes those authored pcurves, not projections of
  fitted candidate boundaries. An explicit nonincident wall requires the same
  whole original spatial-curve/UV correspondence before it supplies a pcurve.
  Native-parameter-preserving candidates use that original traversal directly.
  Nonlinear analytic-to-rational image charts require an original parameter-map
  receipt; a mismatched chart fails the complete boundary certificate rather
  than allowing its sampled projection to become source authority.

## Runtime Flows

The evaluator resolves both references from one `EvaluationContext`, verifies
that each belongs to its declared source body, constructs the exact ruled
surface, and delegates topology creation to the existing B-spline surface
evaluator. No partial result is published.
The delegated evaluator's validated result is returned directly; Bridge does
not discard its validation evidence and validate the same B-rep a second time.
An explicit retained wall or constrained continuity/tension/width request invokes `BridgeSurfaceWallTrimming` on the admitted
candidate. CADKernel owns finite source-face intersection, contact/coincident
classification, region selection and trimmed topology. The port must preserve
unmodified source bodies and candidate ancestry, publish exactly one sheet and
propagate any missing, ambiguous or unproved contact. CADModeling validates the
changed trimmed result before returning; a missing port is dependency failure.

## State, Ownership, and Lifecycle

The feature graph owns the stable references, affine maps and orientation. The evaluation
context owns the immutable B-rep snapshot. The component is stateless.

## Failure, Concurrency, and Constraints

Evaluation is synchronous and request-local. Exact conversion and basis
alignment resource limits are those of their existing builders. Maps must be
finite and nonsingular; rational weights, knot domains and traversal are retained.
Core owns occurrence identities and atomically refreshes these maps when placement
changes. The kernel never reads presentation metadata or guesses a scene occurrence.

## Verification and Change Impact

`SwiftCADTests/BridgeSurfaceBuilderTests` proves rational boundary coincidence
for both orientations, source-body retention, and Codable command replay.
`CADModelingTests/SurfaceFeatureEvaluatorTests` checks missing live topology.
Core tests own selection/occurrence validation,
preview/apply, persistence, and Undo/Redo. Changes require reviewing CADIR,
FeatureNodeFactory/DesignGraph contracts, CADKernel dispatch, RupaCore command
preparation, and the contextual viewport route.

### Original affine wall support

Placed walls retain their original surface chart in
`OriginalImageSurface3D` with unit UV gains and the authored spatial affine map.
The boundary candidate uses the same spatial map; its transformed controls only
propose construction coefficients. B-spline walls also retain the original
image law instead of assigning authority to rounded transformed controls.
Native differential and continuity enclosures consume the original
image jets, so no rigid-only conversion or sampled substitute authorizes an
anisotropic wall. General native pcurve inversion/transfer remains the existing
shared lower chart obligation; a missing chart fails explicitly.

## Borrowed Construction Admission

`BridgeSurfaceFeatureEvaluator` accepts an optional caller-supplied
`sourceAdmission`; constrained construction receives that identical admission.
No aggregate policy is invented for callers without one. When present, original
support/chart preparation, candidate coefficient work, QR factorization and final
boundary comparison borrow its work and byte callbacks. Existing eight attempts,
4096 controls, 1048576 coefficient elements, 65536 boundary cells and spatial
depth 20 remain local ceilings and are only tightened by the caller. Source
recursion and exact algebra retain their independent authorities. The nil route
remains the legacy compatibility path and does not establish caller-admitted
whole-feature resource coverage.

With selected admission, retained wall charts and supports are prepared once for
candidate collocation. Their original closed value/derivative boxes supply
numerical representatives only; every final position, normal and shape comparison
still consumes the original chart and support. No legacy nearest-point projection
supplies selected station authority. Direct builder calls without an authored
chart use the bounded pcurve producer, which may decline an unsupported inverse
family. Native common-basis and degree/knot construction still require their
own actual bounded lower ports before whole-feature accounting can be claimed.
