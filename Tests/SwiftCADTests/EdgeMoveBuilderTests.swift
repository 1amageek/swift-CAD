import Testing
@testable import SwiftCAD
import CADTopology

@Suite("Edge move builder")
struct EdgeMoveBuilderTests {
    @Test(.timeLimit(.minutes(1)))
    func builderAndNativePackageUseSharedEdgeMoveCommand() throws {
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
        let edge = try builder.stableSubshape(
            generatedBy: extrudeID,
            selector: .generated(role: .edge, index: 8)
        )
        let moveID = try builder.moveEdge(
            target: extrudeID,
            edge: edge,
            direction: Vector3D(x: -1.0, y: 0.0, z: 0.0),
            distance: .constant(.length(5.0, unit: .millimeter))
        )
        let document = try builder.build(name: "Edge move parity")
        let pipeline = CADPipeline(tolerance: .standard)
        let evaluated = try pipeline.evaluate(document)
        let sink = DataByteSink()
        try pipeline.writePackage(for: document, to: sink)
        let loaded = try pipeline.loadDocument(from: BorrowedBytes(sink.bytes))

        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - 0.00085 * 0.010) <= 1.0e-12)
        guard case .edgeMove = loaded.designGraph.nodes[moveID]?.operation else {
            Issue.record("Native package persistence must preserve the shared edge move operation.")
            return
        }
    }
}
