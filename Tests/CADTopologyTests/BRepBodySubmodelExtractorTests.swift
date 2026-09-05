import CADCore
import CADGeometry
import Testing
@testable import CADTopology

@Suite("B-rep body submodel extraction")
struct BRepBodySubmodelExtractorTests {
    @Test(.timeLimit(.minutes(1)))
    func extractionObservesCancellationBeforeNestedTraversal() async throws {
        let model = makeExtractionFixture()
        let bodyID = try #require(model.bodies.keys.first)
        let (gate, opened) = AsyncStream.makeStream(of: Void.self)
        let task = Task {
            for await _ in gate { break }
            return try BRepBodySubmodelExtractor().extract(
                bodyIDs: [bodyID],
                from: model
            )
        }
        task.cancel()
        opened.yield()
        opened.finish()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
    }
}

private func makeExtractionFixture() -> BRepModel {
    let bodyID = BodyID()
    let shellID = ShellID()
    let faceID = FaceID()
    let loopID = LoopID()
    let edgeID = EdgeID()
    let curveID = CurveID()
    let surfaceID = SurfaceID()
    let startVertex = Vertex(point: .origin)
    let endVertex = Vertex(point: Point3D(x: 1.0, y: 0.0, z: 0.0))

    return BRepModel(
        geometry: GeometryStore(
            curves: [curveID: .line(Line3D(origin: .origin, direction: .unitX))],
            surfaces: [surfaceID: .plane(Plane3D(origin: .origin, normal: .unitZ))]
        ),
        bodies: [bodyID: Body(id: bodyID, sheetShellIDs: [shellID])],
        shells: [shellID: Shell(id: shellID, faceIDs: [faceID])],
        faces: [faceID: Face(id: faceID, surfaceID: surfaceID, loops: [loopID])],
        loops: [loopID: Loop(id: loopID, edges: [Coedge(edgeID: edgeID)])],
        edges: [edgeID: Edge(
            id: edgeID,
            curveID: curveID,
            startVertexID: startVertex.id,
            endVertexID: endVertex.id
        )],
        vertices: [startVertex.id: startVertex, endVertex.id: endVertex]
    )
}
