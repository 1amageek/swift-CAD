import CADCore
@testable import CADTopology
import Testing

@Suite("B-rep shell reference point")
struct BRepShellReferencePointResolverTests {
    @Test
    func referencePointUsesGeometryBoundsInsteadOfTopologyOrder() throws {
        let firstVertex = Vertex(point: Point3D(x: -10.0, y: 2.0, z: 4.0))
        let secondVertex = Vertex(point: Point3D(x: 6.0, y: -8.0, z: 12.0))
        let firstEdge = Edge(
            curveID: CurveID(),
            startVertexID: firstVertex.id,
            endVertexID: secondVertex.id
        )
        let secondEdge = Edge(
            curveID: CurveID(),
            startVertexID: secondVertex.id,
            endVertexID: firstVertex.id
        )
        let firstLoop = Loop(role: .outer, coedges: [Coedge(edgeID: firstEdge.id)])
        let secondLoop = Loop(role: .outer, coedges: [Coedge(edgeID: secondEdge.id)])
        let surfaceID = SurfaceID()
        let firstFace = Face(surfaceID: surfaceID, loops: [firstLoop.id])
        let secondFace = Face(surfaceID: surfaceID, loops: [secondLoop.id])
        let model = BRepModel(
            faces: [firstFace.id: firstFace, secondFace.id: secondFace],
            loops: [firstLoop.id: firstLoop, secondLoop.id: secondLoop],
            edges: [firstEdge.id: firstEdge, secondEdge.id: secondEdge],
            vertices: [
                firstVertex.id: firstVertex,
                secondVertex.id: secondVertex,
            ]
        )
        let resolver = BRepShellReferencePointResolver()

        let forward = try resolver.referencePoint(
            for: Shell(faceIDs: [firstFace.id, secondFace.id]),
            in: model,
            context: "Test"
        )
        let reversed = try resolver.referencePoint(
            for: Shell(faceIDs: [secondFace.id, firstFace.id]),
            in: model,
            context: "Test"
        )

        #expect(forward == Point3D(x: -2.0, y: -3.0, z: 8.0))
        #expect(reversed == forward)
    }
}
