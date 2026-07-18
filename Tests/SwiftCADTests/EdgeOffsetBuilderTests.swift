import Testing
@testable import SwiftCAD
import CADTopology

@Suite("Edge Offset Builder")
struct EdgeOffsetBuilderTests {
    @Test(.timeLimit(.minutes(1)))
    func builderAndNativePackageUseSharedEdgeOffsetCommand() throws {
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
            selector: .generated(role: .edge, index: 0)
        )
        let supportFace = try builder.stableSubshape(
            generatedBy: extrudeID,
            selector: .generated(role: .startFace)
        )
        let offsetID = try builder.edgeOffset(
            target: extrudeID,
            edge: edge,
            supportFace: supportFace,
            distance: .constant(.length(2.0, unit: .millimeter))
        )
        let document = try builder.build(name: "Edge offset parity")
        let pipeline = CADPipeline(tolerance: .standard)
        let evaluated = try pipeline.evaluate(document)
        let sink = DataByteSink()
        try pipeline.writePackage(for: document, to: sink)
        let loaded = try pipeline.loadDocument(from: BorrowedBytes(sink.bytes))

        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - 0.040 * 0.020 * 0.010) <= 1.0e-12)
        guard case .edgeOffset = loaded.designGraph.nodes[offsetID]?.operation else {
            Issue.record("Native package persistence must preserve the shared edge offset operation.")
            return
        }
    }
}
