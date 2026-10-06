# Thickened Sheet

## Purpose and Scope
Parent: [CADModeling](../DESIGN.md). Own exact sheet-to-solid thickness request construction and its public feature evaluator. No children.

## Responsibilities and Boundaries
Resolve the signed front/back thickness and prepare two independently solved layers from the same immutable source shell. Preserve layer face, loop and edge incidence; construct walls only for source free boundary uses. Sewing owns exact joint correspondence and closed volumetric publication. Before body replacement, the injected OffsetResultValidating contract admits all distinct result-face contacts through the shared sheet offset contract. This component does not infer global offset feasibility from local regularity.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [CADModeling](../DESIGN.md) | parent | ThickenFeatureEvaluator | Public thickness composition | Preserve injected sewer |
| [Shared Sheet Offset](../SharedSheetOffset/DESIGN.md) | depends on | simultaneous shell offset | Joint lower/upper support solutions | Each layer derives from the original shell |
| [Source Face Patch](../SourceFacePatch/DESIGN.md) | coordinates with | original directed trim publication | Preserve original topology provenance | Rebuilt trim authority differs from unchanged receipt |
| [CADGeometry](../../CADGeometry/DESIGN.md) | depends on | SurfaceLiftCurve3D and RuledSurface3D | Exact boundary walls | No fitted rail becomes source |
| [CADTopology](../../CADTopology/DESIGN.md) | depends on | exact/volumetric validation | Full output incidence | Geometric regularity is not absence of remote intersections |

## Architecture
```text
original sheet shell -> lower simultaneous offset -> retained lower loops
                     -> upper simultaneous offset -> retained upper loops
source free uses + aligned layer uses -> exact lifted rails -> ruled walls
    -> lower reversed caps + upper caps + boundary walls -> injected sewer -> volumetric result
```

## Contracts and Invariants
The generic joint path keeps original face order, loop role/order, and edge identity. Every paired layer loop/use is checked before constructing a wall. Shared source edges receive no wall; free uses, including hole boundaries, each receive one directed ruled wall. Lower cap traversal and orientation are reversed; upper cap traversal and orientation are preserved. Rail law is the exact lift of the actual layer pcurve on its solved support, on normalized fraction zero through one. Layer solving, wall construction and publication failures abort before replacing the source body. The tangent-layer fast selector requires exactly the same retained original support, the same face orientation, and structurally equal original pcurves after directed use reversal. Those identities establish the same complete position and normal law without numerical normal samples or a new private proof ceiling. Other supports or charts proceed through the actual shared joint solver; declining the fast case is not a geometric absence certificate. Existing single-face, planar and prismatic construction contracts remain compatible.

The prismatic layer's outer/inner choice and traversal orientation use signed UV area bounds of complete authored segment laws on their admitted plane. Native line, circle and spline pcurves are constructed from the actual directed trim and admitted by whole correspondence. The existing parameter-area integrator owns the proof ceilings. Area bounds must establish a strict sign and strict absolute-area ordering; sampled arc polygons and midpoint area estimates are not ownership authority.

Planar straight-boundary fast admission requires exact collinearity of every
original control point in all three coordinate projections using zero-threshold
robust orientation. A tolerance tube or arithmetic envelope cannot convert a
curved source into a line; other boundaries use the generic joint layer solver.

## State, Ownership, and Lifecycle
Lower and upper models are local immutable-source copies with independent replacement state. Neither is published independently. Both requests retain original face/edge/vertex provenance and the source body parent identities; all temporary layer topology IDs remain private to construction.

## Failure, Concurrency, and Constraints
The whole source must be one nonempty manifold sheet shell. Incompatible joints, loss of regularity, mismatched original incidence and sewing failures propagate. Remaining global self-intersection/offset-envelope splitting, singular corner sectors and unresolved original intersection families are explicit source gaps; limited-family success does not close general feasibility.

## Verification and Change Impact
Deferred behavioral checks cover nonplanar angled multi-panel sheets, curved free boundaries, holes, zero front/back side, seam uses, incompatible joints, and no partial body replacement on failure. Recheck Shared Sheet Offset and the exact sewer when their original trim correspondence contracts change. No verification is claimed during source implementation.

Original construction chart curves remain original laws in the joint offset path. A retained construction net cannot authorize the optional exact-line prismatic selector.

Existing complete volumetric admission is retained as an immutable `ValidatedBRepModel` receipt and passed directly to the additive feasibility witness. The raw model is not separately compared or revalidated by that receipt entry.
