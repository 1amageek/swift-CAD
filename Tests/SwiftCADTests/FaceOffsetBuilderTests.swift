import Testing
@testable import SwiftCAD
import CADTopology

@Suite("Face offset builder")
struct FaceOffsetBuilderTests {
    @Test(.timeLimit(.minutes(1)))
    func builderAndNativePackageUseSharedFaceOffsetCommand() throws {
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
            selector: .generated(role: .endFace)
        )
        let offsetID = try builder.offsetFace(
            target: extrudeID,
            face: face,
            distance: .constant(.length(5.0, unit: .millimeter))
        )
        let document = try builder.build(name: "Face offset parity")
        let pipeline = CADPipeline(tolerance: .standard)
        let evaluated = try pipeline.evaluate(document)
        let sink = DataByteSink()
        try pipeline.writePackage(for: document, to: sink)
        let loaded = try pipeline.loadDocument(from: BorrowedBytes(sink.bytes))

        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - 0.040 * 0.020 * 0.015) <= 1.0e-12)
        guard case .faceOffset = loaded.designGraph.nodes[offsetID]?.operation else {
            Issue.record("Native package persistence must preserve the shared face offset operation.")
            return
        }
    }
}
