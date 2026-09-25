# SurfaceFill

## Purpose and Scope

SurfaceFill is a `CADModeling` component. Its parent is
[CADModeling](../DESIGN.md); it has no child components. It evaluates a
source-referenced open boundary into a distinct exact sheet. Coplanar loops
retain their exact boundary curves on a planar face; non-planar loops use the
existing four-sided Coons builder.

## Responsibilities and Boundaries

SurfaceFill owns exact bounded curve conversion, planar-face recognition,
four-side grouping, and delegation to exact sewing or the existing sheet
evaluator. It delegates loop resolution to
[CADTopology OpenBoundaryLoop](../../CADTopology/OpenBoundaryLoop/DESIGN.md). It does not
own source selection, feature history, scene placement, rendering, or UI state.
It does not claim G1/G2 fitting, interior guide constraints, or XNURBS quality
optimization.

Planar recognition delegates to `DefaultPlanarSurfaceResolver` over the
boundary control points. Its arithmetic-envelope planarity check and
area-scaled normal threshold are shared with B-spline surface recognition;
SurfaceFill does not maintain a separate plane-fitting algorithm.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADModeling](../DESIGN.md) | parent | validated exact feature evaluation | Owns B-rep evaluation rules. | Failure remains typed. |
| [CADIR](../../CADIR/DESIGN.md) | depends on | `SurfaceFillFeature` source and edge references | Supplies persistent source identity. | Stable references resolve against live topology. |
| [CADGeometry](../../CADGeometry/DESIGN.md) | depends on | bounded analytic conversion, exact composite curves, Coons surface | Provides exact supported geometry construction. | Unsupported curves refuse; no mesh fallback. |
| [OpenBoundaryLoop](../../CADTopology/OpenBoundaryLoop/DESIGN.md) | depends on | ordered one-face boundary cycle | Identifies the complete loop from one seed edge. | Topological connectivity, not mesh proximity, is authoritative. |

## Architecture

```text
source body + stable seed edge
        -> live edge resolution
        -> shared exact open-boundary cycle
        -> exact edge B-splines
           -> coplanar loop: exact planar trim + B-rep sewing
           -> non-planar loop: four exact sides + Coons sheet evaluator
```

## Contracts and Invariants

- The seed must resolve to exactly one edge of the declared source body.
- The shared `OpenBoundaryLoop` resolver returns only a complete connected
  cycle whose edges each have one incident source face and whose vertices have
  degree two.
- The shared loop resolver also admits one- and two-edge cycles. Planar
  loops use their exact boundary curves and an exact plane trim. Non-planar
  loops with four or more edges choose corners at existing vertices; a
  three-edge loop uses certified arc-length inversion to split its curves.
- Non-planar Coons evaluation guarantees G0 boundary coincidence only. It does
  not claim G1/G2 fitting, quality optimization, boundary-flow controls, or
  guide-curve constraints.
- The source body is retained. Output is one separate `.sheet` feature.
- Stale references, branching/open chains, unsupported exact curve kinds,
  failed corner closure, and invalid B-rep results return explicit errors.

## Runtime Flows

The evaluator resolves its `.target` input and stable seed edge against the
current `EvaluationContext`, discovers the boundary component, orients the
exact curves by vertex connectivity, groups the ordered cycle into four sides,
builds the Coons surface, and delegates sheet topology construction to
`BSplineSurfaceFeatureEvaluator`. No partial evaluation is published.

## State, Ownership, and Lifecycle

The component is stateless. The feature graph owns the persistent source
reference; the evaluation context owns the current immutable B-rep snapshot.

## Failure, Concurrency, and Constraints

Boundary discovery is linear in the source body's edge incidence. Curve
conversion and Coons construction use their existing geometry resource limits.
No work runs on pointer motion; the editor requests evaluation through Preview.

## Verification and Change Impact

`CADModelingTests/SurfaceFillFeatureTests` verifies non-planar loop boundaries
and rejects duplicate outer-perimeter filling. `CADKernelTests/FaceDeleteFeatureTests`
verifies source preservation, exact planar circular-cap filling, small planar
openings, and deterministic reevaluation with the real sewer.
`CADExchangeTests/NativeOperationSchemaTests` verifies source-graph persistence. Changes to
the source or output contract require rechecking CADIR, CADKernel, Core and UI.
