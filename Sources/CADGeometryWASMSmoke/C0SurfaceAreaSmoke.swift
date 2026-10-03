import CADCore
import CADGeometry
import CADTopology
import Foundation

struct C0SurfaceAreaSmoke {
    static func verify() throws {
        let tolerance = ModelingTolerance(distance: 1e-6, angle: 1e-9, relative: 1e-6)
        let knot = 0.37
        let middleX = 0.02 * knot
        let firstLength = middleX
        let secondWidth = 0.02 - middleX
        let secondLength = sqrt(secondWidth * secondWidth + 0.02 * 0.02)
        let firstArea = 0.03 * firstLength
        let secondArea = 0.03 * secondLength
        let surface = Surface3D.bSpline(BSplineSurface3D(
            uDegree: 1, vDegree: 1, uKnots: [0, 0, knot, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [0.0, 0.03].map { y in
                [Point3D(x: 0, y: y, z: 0), Point3D(x: middleX, y: y, z: 0),
                 Point3D(x: 0.02, y: y, z: 0.02)]
            }))

        // Independent model-space rectangle areas and first moments, rather than
        // the support evaluator or its native-span integrand, provide the oracle.
        let wholeArea = firstArea + secondArea
        let wholeCentroid = Point3D(
            x: (firstArea * middleX / 2 + secondArea * (middleX + 0.02) / 2) / wholeArea,
            y: 0.015, z: secondArea * 0.01 / wholeArea)
        let (wholeID, wholeModel) = try fixture(surface: surface, hole: nil, tolerance: tolerance)
        try verifyMeasurement(try wholeModel.faceAreaMeasurement(of: wholeID, tolerance: tolerance),
            area: wholeArea, centroid: wholeCentroid, tolerance: tolerance)

        let hole = rectangle(knot / 2, (1 + knot) / 2, 0.25, 0.75)
        let (holeID, holeModel) = try fixture(surface: surface, hole: hole, tolerance: tolerance)
        let removedFirst = firstArea / 4, removedSecond = secondArea / 4
        let remainingArea = 0.75 * wholeArea
        let remainingCentroid = Point3D(
            x: (firstArea * middleX / 2 + secondArea * (middleX + 0.02) / 2
                - removedFirst * 0.75 * middleX
                - removedSecond * (0.75 * middleX + 0.25 * 0.02)) / remainingArea,
            y: 0.015, z: (secondArea * 0.01 - removedSecond * 0.005) / remainingArea)
        try verifyMeasurement(try holeModel.faceAreaMeasurement(of: holeID, tolerance: tolerance),
            area: remainingArea, centroid: remainingCentroid, tolerance: tolerance)

        do {
            _ = try holeModel.faceAreaMeasurement(of: holeID, tolerance: tolerance,
                integrationOptions: FaceAreaIntegrationOptions(maximumCellCount: 3))
            throw failure("C0 native spans and loops exceeded their shared work budget.", tolerance)
        } catch let error as KernelError {
            try require(error.code == .resourceLimitExceeded,
                "C0 work exhaustion lost its typed resource failure.", tolerance)
        }
    }

    private static func fixture(surface: Surface3D, hole: [SurfaceParameterCurve]?,
                                tolerance: ModelingTolerance) throws -> (FaceID, BRepModel) {
        let surfaceID = SurfaceID()
        var model = BRepModel(geometry: GeometryStore(surfaces: [surfaceID: surface]))
        var boundaries = [rectangle(0, 1, 0, 1)]
        if let hole {
            boundaries.append(try hole.reversed().map { try $0.reversed(tolerance: tolerance) })
        }
        var loopIDs: [LoopID] = []
        for (index, pcurves) in boundaries.enumerated() {
            let vertices = try pcurves.map { pcurve -> Vertex in
                let parameter = try pcurve.parameter(atNormalizedFraction: 0, tolerance: tolerance)
                return Vertex(point: try surface.point(u: parameter.u, v: parameter.v, tolerance: tolerance))
            }
            for vertex in vertices { model.vertices[vertex.id] = vertex }
            var coedges: [Coedge] = []
            for edgeIndex in pcurves.indices {
                let pcurve = pcurves[edgeIndex]
                let curveID = CurveID()
                // The exact retained lift makes correspondence a full-domain
                // identity, including the C0 knot crossed by horizontal edges.
                model.geometry.curves[curveID] = .surfaceLift(SurfaceLiftCurve3D(
                    surface: surface, parameterCurve: pcurve))
                let edge = Edge(curveID: curveID, startVertexID: vertices[edgeIndex].id,
                    endVertexID: vertices[(edgeIndex + 1) % vertices.count].id,
                    trim: CurveTrim(startParameter: 0, endParameter: 1))
                model.edges[edge.id] = edge
                coedges.append(Coedge(edgeID: edge.id, surfaceParameterCurve: pcurve))
            }
            let loop = Loop(role: index == 0 ? .outer : .inner, coedges: coedges)
            model.loops[loop.id] = loop
            loopIDs.append(loop.id)
        }
        let face = Face(surfaceID: surfaceID, loops: loopIDs)
        let shell = Shell(faceIDs: [face.id])
        let body = Body(sheetShellIDs: [shell.id])
        model.faces[face.id] = face
        model.shells[shell.id] = shell
        model.bodies[body.id] = body
        try model.validatePcurves(tolerance: tolerance)
        return (face.id, model)
    }

    private static func rectangle(_ u0: Double, _ u1: Double,
                                  _ v0: Double, _ v1: Double) -> [SurfaceParameterCurve] {
        [.constantV(v: v0, uStart: u0, uEnd: u1),
         .constantU(u: u1, vStart: v0, vEnd: v1),
         .constantV(v: v1, uStart: u1, uEnd: u0),
         .constantU(u: u0, vStart: v1, vEnd: v0)]
    }

    private static func verifyMeasurement(_ result: FaceAreaMeasurement, area: Double,
                                          centroid: Point3D, tolerance: ModelingTolerance) throws {
        try require(result.area.isFinite
            && abs(result.area - area) <= tolerance.distance * tolerance.distance + tolerance.relative * area,
            "C0 surface area escaped its absolute and relative error contract.", tolerance)
        let centroidError = (result.centroid - centroid).length
        try require(centroidError.isFinite && centroidError <= tolerance.distance,
            "C0 surface area centroid escaped its three-coordinate distance contract.", tolerance)
    }

    private static func require(_ condition: Bool, _ message: String, _ tolerance: ModelingTolerance) throws {
        guard condition else { throw failure(message, tolerance) }
    }

    private static func failure(_ message: String, _ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .topology, code: .classificationFailure, tolerance: tolerance, message: message)
    }
}
