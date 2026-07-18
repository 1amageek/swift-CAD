import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology
@testable import CADKernel

struct PlanarSheetTestFixture {
    var brep: BRepModel
    var subshapes: SubshapeIndex
    var lineage: [SubshapeID: TopologyLineage]

    static func make(
        featureID: FeatureID,
        tolerance: ModelingTolerance
    ) throws -> PlanarSheetTestFixture {
        let points = [
            Point3D(x: -0.020, y: -0.010, z: 0.0),
            Point3D(x: 0.020, y: -0.010, z: 0.0),
            Point3D(x: 0.020, y: 0.010, z: 0.0),
            Point3D(x: -0.020, y: 0.010, z: 0.0),
        ]
        let surface = Surface3D.plane(Plane3D(origin: .origin, normal: .unitZ))
        let edges = try points.indices.map { index in
            let start = points[index]
            let end = points[(index + 1) % points.count]
            let delta = end - start
            let startUV = try surface.parameterProjection(of: start, tolerance: .standard)
            let endUV = try surface.parameterProjection(of: end, tolerance: .standard)
            return BRepSewingEdge(
                stableID: "planarSheet:edge:\(index)",
                curve: .line(Line3D(origin: start, direction: try delta.normalized(tolerance: 1.0e-9))),
                startParameter: 0.0,
                endParameter: delta.length,
                startPoint: start,
                endPoint: end,
                surfaceParameterCurve: .polyline([
                    SurfaceParameter(u: startUV.u, v: startUV.v),
                    SurfaceParameter(u: endUV.u, v: endUV.v),
                ])
            )
        }
        let sewn = try DefaultBRepSewer().sew(BRepSewingRequest(
            featureID: featureID,
            bodyKind: .sheet,
            shells: [BRepSewingShell(
                stableID: "planarSheet:shell",
                patches: [BRepSewingFacePatch(
                    stableID: "planarSheet:face",
                    surface: surface,
                    orientation: .forward,
                    loops: [BRepSewingLoop(stableID: "planarSheet:outer", role: .outer, edges: edges)]
                )]
            )]
        ), tolerance: tolerance)
        return PlanarSheetTestFixture(
            brep: sewn.brep,
            subshapes: SubshapeIndex(sewn.subshapes),
            lineage: sewn.lineage
        )
    }
}
