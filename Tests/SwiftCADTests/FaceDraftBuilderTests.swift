import Testing
@testable import SwiftCAD
import CADTopology

@Suite("Face Draft Builder")
struct FaceDraftBuilderTests {
    @Test(.timeLimit(.minutes(1)))
    func builderAndNativePackageUseSharedFaceDraftCommand() throws {
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
        let target = try builder.stableSubshape(
            generatedBy: extrudeID,
            selector: .generated(role: .sideFace, index: 0)
        )
        let neutral = try builder.stableSubshape(
            generatedBy: extrudeID,
            selector: .generated(role: .startFace)
        )
        let draftID = try builder.faceDraft(
            target: extrudeID,
            faces: [target],
            neutralFace: neutral,
            angle: .constant(.angle(8.0, unit: .degree))
        )
        let document = try builder.build(name: "Face draft parity")
        let pipeline = CADPipeline(tolerance: .standard)
        let evaluated = try pipeline.evaluate(document)
        let sink = DataByteSink()
        try pipeline.writePackage(for: document, to: sink)
        let loaded = try pipeline.loadDocument(from: BorrowedBytes(sink.bytes))

        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(evaluated.brep.bodies.values.first?.kind == .solid)
        #expect(evaluated.brep.faces.count == 6)
        guard case .faceDraft = loaded.designGraph.nodes[draftID]?.operation else {
            Issue.record("Native package persistence must preserve the shared Face Draft operation.")
            return
        }
    }
}
