import Testing
@testable import SwiftCAD
import CADTopology

@Suite("Face Delete Builder")
struct FaceDeleteBuilderTests {
    @Test(.timeLimit(.minutes(1)))
    func builderAndNativePackageUseSharedFaceDeleteCommand() throws {
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
        let face = try builder.stableSubshape(
            generatedBy: extrudeID,
            selector: .generated(role: .startFace)
        )
        let deleteID = try builder.faceDelete(
            target: extrudeID,
            faces: [face]
        )
        let document = try builder.build(name: "Face delete parity")
        let pipeline = CADPipeline(tolerance: .standard)
        let evaluated = try pipeline.evaluate(document)
        let sink = DataByteSink()
        try pipeline.writePackage(for: document, to: sink)
        let loaded = try pipeline.loadDocument(from: BorrowedBytes(sink.bytes))

        try evaluated.brep.validate(level: .exact, tolerance: .standard)
        #expect(evaluated.brep.bodies.values.first?.kind == .sheet)
        #expect(evaluated.brep.faces.count == 5)
        guard case .faceDelete = loaded.designGraph.nodes[deleteID]?.operation else {
            Issue.record("Native package persistence must preserve the shared Face Delete operation.")
            return
        }
    }
}
