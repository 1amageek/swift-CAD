import CADCore
import CADGeometry
import CADTopology
import HashTreeCollections

/// Authored finite inputs shared by the ordinary counterexample and direct repair checks.
enum BRepRepairExecutionFixture {
    struct Sheet {
        var model: BRepModel
        let vertexIDs: [VertexID]
        let edgeIDs: [EdgeID]
        let curveIDs: [CurveID]
        let surfaceID: SurfaceID
        let loopID: LoopID
        let faceID: FaceID
        let shellID: ShellID
        let bodyID: BodyID
    }

    static func square() -> Sheet {
        let points = [Point3D(x: 0, y: 0, z: 0), Point3D(x: 1, y: 0, z: 0),
            Point3D(x: 1, y: 1, z: 0), Point3D(x: 0, y: 1, z: 0)]
        let vertexIDs = points.map { _ in VertexID() }
        let edgeIDs = points.map { _ in EdgeID() }
        let curveIDs = points.map { _ in CurveID() }
        let surfaceID = SurfaceID(), loopID = LoopID(), faceID = FaceID()
        let shellID = ShellID(), bodyID = BodyID()
        let directions = [Vector3D.unitX, .unitY, -Vector3D.unitX, -Vector3D.unitY]
        let charts: [SurfaceParameterCurve] = [
            .constantV(v: 0, uStart: 0, uEnd: 1), .constantU(u: 1, vStart: 0, vEnd: 1),
            .constantV(v: 1, uStart: 1, uEnd: 0), .constantU(u: 0, vStart: 1, vEnd: 0)]
        let model = BRepModel(
            geometry: GeometryStore(
                curves: Dictionary(uniqueKeysWithValues: curveIDs.enumerated().map { i, id in
                    (id, Curve3D.line(.init(origin: points[i], direction: directions[i]))) }),
                surfaces: [surfaceID: .plane(.init(origin: .origin, normal: .unitZ, uDirection: .unitX))]),
            bodies: [bodyID: Body(id: bodyID, sheetShellIDs: [shellID])],
            shells: [shellID: Shell(id: shellID, faceIDs: [faceID])],
            faces: [faceID: Face(id: faceID, surfaceID: surfaceID, loops: [loopID])],
            loops: [loopID: Loop(id: loopID, role: .outer, coedges: edgeIDs.enumerated().map { i, id in
                Coedge(edgeID: id, surfaceParameterCurve: charts[i]) })],
            edges: Dictionary(uniqueKeysWithValues: edgeIDs.enumerated().map { i, id in
                (id, Edge(id: id, curveID: curveIDs[i], startVertexID: vertexIDs[i],
                    endVertexID: vertexIDs[(i + 1) % 4], trim: .init(startParameter: 0, endParameter: 1))) }),
            vertices: Dictionary(uniqueKeysWithValues: vertexIDs.enumerated().map { i, id in
                (id, Vertex(id: id, point: points[i])) }))
        return .init(model: model, vertexIDs: vertexIDs, edgeIDs: edgeIDs, curveIDs: curveIDs,
            surfaceID: surfaceID, loopID: loopID, faceID: faceID, shellID: shellID, bodyID: bodyID)
    }

    static func polylineSquare() -> Sheet {
        var result = square()
        let points = [SurfaceParameter(u: 0, v: 0), .init(u: 1, v: 0),
            .init(u: 1, v: 1), .init(u: 0, v: 1)]
        var loop = result.model.loops[result.loopID]!
        for i in points.indices {
            loop.coedges[i].surfaceParameterCurve = .polyline([points[i], points[(i + 1) % 4]])
        }
        result.model.loops[result.loopID] = loop
        return result
    }

    static func polylineTriangle() -> Sheet {
        let points = [Point3D.origin, Point3D(x: 1, y: 0, z: 0), Point3D(x: 0, y: 1, z: 0)]
        let charts = [SurfaceParameter(u: 0, v: 0), SurfaceParameter(u: 1, v: 0), SurfaceParameter(u: 0, v: 1)]
        let vertexIDs = points.map { _ in VertexID() }
        let edgeIDs = points.map { _ in EdgeID() }
        let curveIDs = points.map { _ in CurveID() }
        let surfaceID = SurfaceID(), loopID = LoopID(), faceID = FaceID()
        let shellID = ShellID(), bodyID = BodyID()
        // Every normalized Native source and two-point chart have the same exact affine law.
        let model = BRepModel(
            geometry: GeometryStore(
                curves: Dictionary(uniqueKeysWithValues: curveIDs.enumerated().map { i, id in
                    (id, Curve3D.bSpline(.init(degree: 1, knots: [0, 0, 1, 1],
                        controlPoints: [points[i], points[(i + 1) % 3]], weights: [1, 1]))) }),
                surfaces: [surfaceID: .plane(.init(origin: .origin, normal: .unitZ, uDirection: .unitX))]),
            bodies: [bodyID: Body(id: bodyID, sheetShellIDs: [shellID])],
            shells: [shellID: Shell(id: shellID, faceIDs: [faceID])],
            faces: [faceID: Face(id: faceID, surfaceID: surfaceID, loops: [loopID])],
            loops: [loopID: Loop(id: loopID, role: .outer, coedges: edgeIDs.enumerated().map { i, id in
                Coedge(edgeID: id, surfaceParameterCurve: .polyline([charts[i], charts[(i + 1) % 3]])) })],
            edges: Dictionary(uniqueKeysWithValues: edgeIDs.enumerated().map { i, id in
                (id, Edge(id: id, curveID: curveIDs[i], startVertexID: vertexIDs[i],
                    endVertexID: vertexIDs[(i + 1) % 3], trim: .init(startParameter: 0, endParameter: 1))) }),
            vertices: Dictionary(uniqueKeysWithValues: vertexIDs.enumerated().map { i, id in
                (id, Vertex(id: id, point: points[i])) }))
        return .init(model: model, vertexIDs: vertexIDs, edgeIDs: edgeIDs, curveIDs: curveIDs,
            surfaceID: surfaceID, loopID: loopID, faceID: faceID, shellID: shellID, bodyID: bodyID)
    }
}
