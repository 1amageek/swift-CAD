import Testing
@testable import SwiftCAD

@Suite("Curve extend builder")
struct CurveExtendBuilderTests {
    @Test(.timeLimit(.minutes(1)))
    func builderAndNativePackagePreserveExactCurveExtend() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let source = try builder.sketch(on: .xy) { sketch in
            sketch.line(
                from: SketchPoint(
                    x: .constant(.length(0.0, unit: .millimeter)),
                    y: .constant(.length(0.0, unit: .millimeter))
                ),
                to: SketchPoint(
                    x: .constant(.length(100.0, unit: .millimeter)),
                    y: .constant(.length(0.0, unit: .millimeter))
                )
            )
        }
        let extensionID = try builder.extendCurve(
            CurveOutputReference(featureID: source.featureID),
            end: .both,
            distance: .constant(.length(10.0, unit: .millimeter))
        )
        let document = try builder.build(name: "Exact curve extension")
        let pipeline = CADPipeline(tolerance: .standard)
        let evaluated = try pipeline.evaluate(document)
        let output = try #require(evaluated.curves[extensionID]?.first)
        let sink = DataByteSink()
        try pipeline.writePackage(for: document, to: sink)
        let loaded = try pipeline.loadDocument(from: BorrowedBytes(sink.bytes))

        guard case .line = output.exactCurve else {
            Issue.record("Builder curve extension must preserve an exact line.")
            return
        }
        #expect(output.exactParameterDomain == .closed(-0.010, 0.110))
        guard case .curveExtend = loaded.designGraph.nodes[extensionID]?.operation else {
            Issue.record("Native package must preserve curve extend operations.")
            return
        }
    }
}
