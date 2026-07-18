import Testing
@testable import SwiftCAD

@Suite("Curve-driven pattern builder")
struct CurveDrivenPatternBuilderTests {
    @Test(.timeLimit(.minutes(1)))
    func builderAndNativePackageUseSharedCurveDrivenPatternCommand() throws {
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
        let path = try builder.sketch(on: .xy) { sketch in
            sketch.line(
                from: SketchPoint(
                    x: .constant(.length(0.0, unit: .millimeter)),
                    y: .constant(.length(0.0, unit: .millimeter))
                ),
                to: SketchPoint(
                    x: .constant(.length(0.0, unit: .millimeter)),
                    y: .constant(.length(120.0, unit: .millimeter))
                )
            )
        }
        let patternID = try builder.curveDrivenPattern(
            target: extrudeID,
            path: path.featureID,
            anchor: .origin,
            referenceDirection: .unitX,
            count: 3
        )
        let document = try builder.build(name: "Curve-driven pattern parity")
        let pipeline = CADPipeline(tolerance: .standard)
        let evaluated = try pipeline.evaluate(document)
        let sink = DataByteSink()
        try pipeline.writePackage(for: document, to: sink)
        let loaded = try pipeline.loadDocument(from: BorrowedBytes(sink.bytes))

        try evaluated.brep.validate(level: .volumetric, tolerance: .standard)
        #expect(evaluated.brep.shells.count == 3)
        #expect(abs(try evaluated.brep.volume(tolerance: .standard) - 3.0 * 0.040 * 0.020 * 0.010) <= 1.0e-12)
        guard case .curveDrivenPattern = loaded.designGraph.nodes[patternID]?.operation else {
            Issue.record("Native package persistence must preserve the shared curve-driven pattern operation.")
            return
        }
    }
}
