# CADTopology

## Purpose and Scope

`CADTopology` owns validated B-rep topology and topology-level queries. It is a
child of the [Swift-CAD package design](../../DESIGN.md) and owns
[OpenBoundaryLoop](OpenBoundaryLoop/DESIGN.md) and
[SurfaceAreaIntegration](SurfaceAreaIntegration/DESIGN.md).

## Responsibilities and Boundaries

The module owns exact topological incidence, adjacency, ownership, and
validation. It does not construct NURBS surfaces, resolve Rupa selection, or
choose display behavior. Open-boundary loop discovery is shared topology
knowledge so feature evaluation and viewport presentation identify the same
eligible boundary components.

The [GenericShape](GenericShape/DESIGN.md) component publishes common operations
for independently selected dimensional roots and heterogeneous compounds. Its
selected snapshot is distinct from a complete body-owned BRepModel.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Swift-CAD package](../../DESIGN.md) | parent | exact B-rep topology | Defines topology's place in the package. | Mesh is not topology authority. |
| [Solid Complex](SolidComplex/DESIGN.md) | child | face-connected cell topology and full-boundary interface validation | Preserves individually owned solids and shared interface identity. | A connected cell graph does not assert Boolean union or global interior disjointness. |
| [GenericShape](GenericShape/DESIGN.md) | child | ShapeRepresenting and ShapeOperating | Owns common dimensional selection and exact rigid-image operations. | Selected closure validation retains the complete-body BRepModel contract. |
| [Non-Manifold Topology](NonManifoldTopology/DESIGN.md) | child | raw snapshot retention, structural diagnosis and explicit admission | Preserves non-manifold topology for inspection without granting modeling permission. | Clean structure must still pass existing exact geometry/body validation. |
| [OpenBoundaryLoop](OpenBoundaryLoop/DESIGN.md) | child | ordered boundary cycles and hole eligibility | Provides shared exact topology and rejects a lone face's outer perimeter as a fill target. | Geometry quality remains a modeling contract. |
| [CADModeling](../CADModeling/DESIGN.md) | used by | loop containing a stable seed edge | Builds a separate surface from an eligible boundary. | Curve conversion and surface quality remain CADModeling responsibilities. |
| [RupaCore](../../../RupaKit/Sources/RupaCore/DESIGN.md) | used by | loop edge membership | Marks the same open loop for viewport affordances. | Display identity comes from generated topology IDs. |

## Architecture

```mermaid
flowchart LR
    Body["B-rep body"] --> Incidence["Count edge uses per face"]
    Incidence --> Boundary["One-face boundary edges"]
    Boundary --> Components["Vertex-connected components"]
    Components --> Loops["Closed non-branching ordered loops"]
    Loops --> Modeling["SurfaceFill evaluation"]
    Loops --> Display["Viewport boundary-loop identity"]
```

## Contracts and Invariants

- An eligible edge has exactly one coedge use in exactly one face owned by the
  requested body.
- A returned loop is connected, closed, has no repeated edge, and every vertex
  has degree two in that boundary component.
- Edge traversal records whether it follows the stored edge direction. A loop
  requested from a seed starts at that edge and follows its stored direction.
- Branches, open chains, non-boundary edges, and malformed components are not
  returned as closed loops. A lone face's outer perimeter is a valid boundary
  cycle but not a fillable hole; both modeling and presentation use the same
  predicate to refuse it.
- Loop discovery reads exact B-rep topology only. It never consults mesh edges
  or geometric endpoint proximity.
- `BRepModel.faceAreaMeasurement` (`TOPO-FACEAREA-001`) measures a face's area
  and area centroid from its coedge pcurves alone, never from a tessellation.
  Analytic supports retain their specialized exact integration paths. Free-surface
  area and centered first moments use the certified error and resource contract
  owned by [SurfaceAreaIntegration](SurfaceAreaIntegration/DESIGN.md).
- Volume integrates each face loop as one chain on the periodic chart the
  `SurfaceParameterLoopUnwrapper` lifts it to. A great-circle pcurve on a
  sphere keeps the branch of longitude its chart lift starts on — a meridian
  along the seam reads as either end of the period — and a great circle split
  at the seam carries that branch on across it, so the integrated longitudes
  meet the unwrapper's translations. A projected analytic pcurve (a conic on
  a plane or a cone) reads a `Plane3D`'s parameters along the plane's own
  basis (`Plane3D.parameterBasis`, the one `Surface3D` places points by), so a
  hyperbolic edge on a floor or a side wall integrates on the chart its
  neighbouring pcurves share; `DraftFaceTests` own it by a cone-drafted wall's
  volume.

## Verification and Change Impact

`CADTopologyTests` verifies deterministic ordered traversal, seed orientation,
multiple disjoint loops, and refusal to report branched or open boundary
components, and the single-face inner/outer fillability rule.
`FaceAreaMeasurementTests` (SwiftCADTests) prove box, L-shaped, full and half
cylinder areas and centroids against closed forms and the typed refusal.
`FilletShapeTests.everyEdgeOfABoxRoundsIntoARoundedBox` proves the sphere chain
at all eight octants of a box, including those whose meridians lie on the
seam, against the rounded box's closed-form volume. Changes affect
CADModeling Surface Fill and RupaCore body display topology; both consumers
must continue to agree on the exact cycle and whether it is actionable.


### Original Local Active Curve Extraction (PAR.CL9L1)

CertifiedBSplineCurveBezierExtractor may reduce each original active span to its
exact degree+one original control/weight slice and two-degree+two stored knot
slice. No coefficient reconstruction or rounded Cartesian extraction is used.
The lower endpoint's correct original owning span, all derivative orders,
positive weights and existing outward homogeneous derivative/Bernstein operations
must remain authoritative. Repeated knots and closed endpoints retain their
original side; invalid/unsupported source and exhausted work refuse explicitly.
A monotonic original knot cursor avoids restarting a full scan for every span. Each new cursor advance and the checked original local knot/control/weight slice cost is charged to the existing maximumControlOperations before reading or materializing that work. No new private budget is introduced.
Direct independent original homogeneous value/derivative containment at span
endpoints/interiors and repeated-knot rational fixtures must verify the change,
followed by existing profile-moment and rational area/volume integration owners.
The candidate flux endpoint shortcut is not part of this adoption; it has a
separate near-endpoint root and seam-enclosure contract needing direct proof.


### Original Local Active Surface Extraction (PAR.SURFEX1)

The certified surface extractor owns complete native span decomposition for volumetric validation. Each original tensor span may use only the degree-plus-one original control and weight slice in each axis and each axis's two-degree-plus-two stored knot slice, preserving the original chart and outward homogeneous derivative/Bernstein authority. Monotonic original span cursors charge every knot probe before reading it; a U cursor starts once per V row. Checked local knot/control/weight materialization is charged before allocation to the existing cumulative maximumControlOperations. Basis work depends on local degree rather than repeatedly materializing every original global control. No budget increase, rounded Cartesian reconstruction, replacement support, sample authority or volume fallback is introduced. Repeated knots and closed endpoints retain their original owning side, and all span contributions retain positive finite homogeneous weights. Failure and cancellation remain explicit. Independent original tensor homogeneous position/derivative containment on rational repeated-knot span endpoints and interiors, multi-span polynomial extraction under the unchanged allowance, resource refusal and existing volume regressions precede Draft's actual final volumetric validation. Native lower4tests pass.135s, including strict dyadic homogeneous value/first/second derivative containment on every original repeated-knot patch side,178-span admission under unchanged4M allowance and typed resource/cancel refusal. Existing22 parametric/rational volume owner tests pass20.265s on the exact frozen source. Draft public integration remains separately owned.
