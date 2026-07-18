import Testing
@testable import SwiftCAD

@Suite("Linear pattern builder")
struct LinearPatternBuilderTests {
    @Test(.timeLimit(.minutes(1)))
    func builderAndNativePackageUseSharedLinearPatternCommand() throws {
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
        let patternID = try builder.linearPattern(
            target: extrudeID,
            direction: .unitX,
            spacing: .constant(.length(60.0, unit: .millimeter)),
            count: 3
        )
        let document = try builder.build(name: "Linear pattern parity")
        let pipeline = CADPipeline(tolerance: .standard)
        let evaluated = try pipeline.evaluate(document)
        let sink = DataByteSink()
        try pipeline.writePackage(for: document, to: sink)
        let loaded = try pipeline.loadDocument(from: BorrowedBytes(sink.bytes))

        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(evaluated.brep.shells.count == 3)
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - 3.0 * 0.040 * 0.020 * 0.010) <= 1.0e-12)
        guard case .linearPattern = loaded.designGraph.nodes[patternID]?.operation else {
            Issue.record("Native package persistence must preserve the shared linear pattern operation.")
            return
        }
    }
}
