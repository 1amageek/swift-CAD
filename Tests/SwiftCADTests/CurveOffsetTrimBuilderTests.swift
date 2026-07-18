import Testing
@testable import SwiftCAD

@Suite("Curve offset and trim builder")
struct CurveOffsetTrimBuilderTests {
    @Test(.timeLimit(.minutes(1)))
    func builderAndNativePackagePreserveExactCurveOperations() throws {
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
        let offsetID = try builder.offsetCurve(
            CurveOutputReference(featureID: source.featureID),
            distance: .constant(.length(10.0, unit: .millimeter)),
            planeNormal: .unitZ
        )
        let trimID = try builder.trimCurve(
            CurveOutputReference(featureID: offsetID),
            domain: .closed(0.020, 0.080)
        )
        let document = try builder.build(name: "Exact curve offset trim")
        let pipeline = CADPipeline(tolerance: .standard)
        let evaluated = try pipeline.evaluate(document)
        let output = try #require(evaluated.curves[trimID]?.first)
        let sink = DataByteSink()
        try pipeline.writePackage(for: document, to: sink)
        let loaded = try pipeline.loadDocument(from: BorrowedBytes(sink.bytes))

        guard case .line = output.exactCurve else {
            Issue.record("Builder curve offset and trim must preserve an exact line.")
            return
        }
        #expect(output.exactParameterDomain == .closed(0.020, 0.080))
        #expect(abs(try #require(output.points.first).y - 0.010) <= 1.0e-12)
        guard case .curveOffset = loaded.designGraph.nodes[offsetID]?.operation,
              case .curveTrim = loaded.designGraph.nodes[trimID]?.operation else {
            Issue.record("Native package must preserve curve offset and trim operations.")
            return
        }
    }
}
