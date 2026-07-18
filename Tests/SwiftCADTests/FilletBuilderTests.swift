import Testing
@testable import SwiftCAD

@Suite("Fillet builder")
struct FilletBuilderTests {
    @Test(.timeLimit(.minutes(1)))
    func builderAndNativePackageUseSharedFilletCommand() throws {
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
        let selected = try builder.stableSubshape(
            generatedBy: extrudeID,
            selector: .generated(role: .edge, index: 0)
        )
        let filletID = try builder.fillet(
            target: extrudeID,
            edges: [selected],
            radius: .constant(.length(2.0, unit: .millimeter))
        )
        let document = try builder.build(name: "Fillet parity")
        let pipeline = CADPipeline(tolerance: .standard)
        let evaluated = try pipeline.evaluate(document)
        let sink = DataByteSink()
        try pipeline.writePackage(for: document, to: sink)
        let loaded = try pipeline.loadDocument(from: BorrowedBytes(sink.bytes))

        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(evaluated.brep.faces.count == 7)
        guard case .fillet = loaded.designGraph.nodes[filletID]?.operation else {
            Issue.record("Native package persistence must preserve the shared fillet operation.")
            return
        }
    }
}
