import Testing
@testable import SwiftCAD

@Suite("Curve match builder")
struct CurveMatchBuilderTests {
    @Test(.timeLimit(.minutes(1)))
    func builderAndNativePackagePreserveVerifiedCurveMatch() throws {
        var builder = DocumentBuilder(units: .millimeters, tolerance: .standard)
        let source = try builder.sketch(on: .xy) { sketch in
            sketch.spline(SketchSpline(controlPoints: [
                point(-30.0, 0.0),
                point(-20.0, 0.0),
                point(-10.0, 0.0),
                point(0.0, 0.0),
            ]))
        }
        let target = try builder.sketch(on: .xy) { sketch in
            _ = sketch.line(from: point(100.0, 100.0), to: point(100.0, 200.0))
        }
        let matchID = try builder.matchCurve(
            CurveOutputReference(featureID: source.featureID),
            end: .end,
            to: CurveOutputReference(featureID: target.featureID),
            targetEnd: .start,
            continuity: .curvature
        )
        let document = try builder.build(name: "Exact curve match")
        let pipeline = CADPipeline(tolerance: .standard)
        let evaluated = try pipeline.evaluate(document)
        let output = try #require(evaluated.curves[matchID]?.first)
        let sink = DataByteSink()
        try pipeline.writePackage(for: document, to: sink)
        let loaded = try pipeline.loadDocument(from: BorrowedBytes(sink.bytes))

        guard case let .bSpline(curve) = output.exactCurve else {
            Issue.record("Builder curve match must return an exact B-spline.")
            return
        }
        let frame = try curve.differentialGeometry(
            at: 1.0,
            tolerance: .standard
        )
        #expect(frame.position.isApproximatelyEqual(
            to: Point3D(x: 0.100, y: 0.100, z: 0.0),
            tolerance: 1.0e-12
        ))
        #expect((frame.tangent - .unitY).length <= 1.0e-12)
        #expect(frame.curvatureVector.length <= 1.0e-9)
        guard case .curveMatch = loaded.designGraph.nodes[matchID]?.operation else {
            Issue.record("Native package must preserve curve match operations.")
            return
        }
    }

    private func point(_ x: Double, _ y: Double) -> SketchPoint {
        SketchPoint(
            x: .constant(.length(x, unit: .millimeter)),
            y: .constant(.length(y, unit: .millimeter))
        )
    }
}
