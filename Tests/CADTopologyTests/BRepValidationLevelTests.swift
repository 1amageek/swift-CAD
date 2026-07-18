import Testing
import CADCore
import CADGeometry
@testable import CADTopology

@Suite("B-rep validation levels")
struct BRepValidationLevelTests {
    @Test
    func exactValidationRequiresFaceLocalPcurves() throws {
        let model = makePlanarSheet(includePcurves: false)

        try model.validate(level: .modeling, tolerance: .standard)
        #expect(throws: KernelError.self) {
            try model.validate(level: .exact, tolerance: .standard)
        }
    }

    @Test
    func exactValidationAcceptsConsistentPlanarPcurves() throws {
        try makePlanarSheet(includePcurves: true).validate(level: .exact, tolerance: .standard)
    }

    private func makePlanarSheet(includePcurves: Bool) -> BRepModel {
        let points = [
            Point3D(x: 0.0, y: 0.0, z: 0.0),
            Point3D(x: 1.0, y: 0.0, z: 0.0),
            Point3D(x: 1.0, y: 1.0, z: 0.0),
            Point3D(x: 0.0, y: 1.0, z: 0.0),
        ]
        let vertexIDs = points.map { _ in VertexID() }
        let edgeIDs = points.map { _ in EdgeID() }
        let curveIDs = points.map { _ in CurveID() }
        let surfaceID = SurfaceID()
        let loopID = LoopID()
        let faceID = FaceID()
        let shellID = ShellID()
        let bodyID = BodyID()
        let directions = [Vector3D.unitX, Vector3D.unitY, -Vector3D.unitX, -Vector3D.unitY]
        let pcurves: [SurfaceParameterCurve] = [
            .constantV(v: 0.0, uStart: 0.0, uEnd: 1.0),
            .constantU(u: 1.0, vStart: 0.0, vEnd: 1.0),
            .constantV(v: 1.0, uStart: 1.0, uEnd: 0.0),
            .constantU(u: 0.0, vStart: 1.0, vEnd: 0.0),
        ]

        let vertices = Dictionary(uniqueKeysWithValues: vertexIDs.enumerated().map { index, id in
            (id, Vertex(id: id, point: points[index]))
        })
        let curves = Dictionary(uniqueKeysWithValues: curveIDs.enumerated().map { index, id in
            (id, Curve3D.line(Line3D(origin: points[index], direction: directions[index])))
        })
        let edges = Dictionary(uniqueKeysWithValues: edgeIDs.enumerated().map { index, id in
            (id, Edge(
                id: id,
                curveID: curveIDs[index],
                startVertexID: vertexIDs[index],
                endVertexID: vertexIDs[(index + 1) % vertexIDs.count],
                trim: CurveTrim(startParameter: 0.0, endParameter: 1.0)
            ))
        })
        let coedges = edgeIDs.enumerated().map { index, edgeID in
            Coedge(
                edgeID: edgeID,
                surfaceParameterCurve: includePcurves ? pcurves[index] : nil
            )
        }

        return BRepModel(
            geometry: GeometryStore(
                curves: curves,
                surfaces: [
                    surfaceID: .plane(Plane3D(origin: .origin, normal: .unitZ)),
                ]
            ),
            bodies: [bodyID: Body(id: bodyID, shellIDs: [shellID], kind: .sheet)],
            shells: [shellID: Shell(id: shellID, faceIDs: [faceID])],
            faces: [faceID: Face(id: faceID, surfaceID: surfaceID, loops: [loopID])],
            loops: [loopID: Loop(id: loopID, role: .outer, coedges: coedges)],
            edges: edges,
            vertices: vertices
        )
    }
}
