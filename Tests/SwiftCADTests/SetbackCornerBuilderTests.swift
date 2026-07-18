import Testing
@testable import SwiftCAD

@Suite("Setback corner builder")
struct SetbackCornerBuilderTests {
    @Test(.timeLimit(.minutes(1)))
    func builderAndNativePackageUseSharedSetbackCornerCommand() throws {
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
            selector: .generated(role: .vertex, index: 0)
        )
        let cornerID = try builder.setbackCorner(
            target: extrudeID,
            vertex: selected,
            radius: .constant(.length(2.0, unit: .millimeter))
        )
        let document = try builder.build(name: "Setback corner parity")
        let pipeline = CADPipeline(tolerance: .standard)
        let evaluated = try pipeline.evaluate(document)
        let sink = DataByteSink()
        try pipeline.writePackage(for: document, to: sink)
        let loaded = try pipeline.loadDocument(from: BorrowedBytes(sink.bytes))

        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(evaluated.brep.faces.count == 10)
        guard case .setbackCorner = loaded.designGraph.nodes[cornerID]?.operation else {
            Issue.record("Native package persistence must preserve the shared setback corner operation.")
            return
        }
    }
}
