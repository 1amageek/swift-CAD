import Testing
@testable import SwiftCAD
import CADTopology

@Suite("Vertex move builder")
struct VertexMoveBuilderTests {
    @Test(.timeLimit(.minutes(1)))
    func builderAndNativePackageUseSharedVertexMoveCommand() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let profile = try builder.sketch(on: .xy) { sketch in
            sketch.rectangle(
                width: .constant(.length(40.0, unit: .millimeter)),
                height: .constant(.length(20.0, unit: .millimeter))
            )
        }
        let extrudeID = try builder.extrude(
            profile,
            distance: .constant(.length(10.0, unit: .millimeter))
        )
        let vertex = try builder.stableSubshape(
            generatedBy: extrudeID,
            selector: .generated(role: .vertex, index: 7)
        )
        let moveID = try builder.moveVertex(
            target: extrudeID,
            vertex: vertex,
            direction: Vector3D(x: -1.0, y: 1.0, z: 1.0),
            distance: .constant(.length(4.0, unit: .millimeter))
        )
        let document = try builder.build(name: "Vertex move parity")
        let pipeline = CADPipeline(tolerance: .standard)
        let evaluated = try pipeline.evaluate(document)
        let sink = DataByteSink()
        try pipeline.writePackage(for: document, to: sink)
        let loaded = try pipeline.loadDocument(from: BorrowedBytes(sink.bytes))

        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(evaluated.brep.faces.count == 9)
        #expect(evaluated.brep.edges.count == 15)
        #expect(evaluated.brep.vertices.count == 8)
        guard case .vertexMove = loaded.designGraph.nodes[moveID]?.operation else {
            Issue.record("Native package persistence must preserve the shared vertex move operation.")
            return
        }
    }
}
