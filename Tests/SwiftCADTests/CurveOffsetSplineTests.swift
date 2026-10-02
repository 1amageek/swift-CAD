import Foundation
import Testing
import CADCore
import CADGeometry
import CADIR
@testable import CADKernel
@testable import SwiftCAD

/// Offset Curve on a spline: the offset approximated within a quarter of the modeling distance,
/// on the side asked.
@Suite("Curve offset spline")
struct CurveOffsetSplineTests {
    private func length(_ value: Double) -> CADExpression { .constant(.length(value, unit: .meter)) }
    private func point(_ x: Double, _ y: Double) -> SketchPoint { SketchPoint(x: length(x), y: length(y)) }

    @Test(.timeLimit(.minutes(2)), arguments: [CurveOffsetSide.left, .right])
    func aSplinesOffsetIsWithinAQuarterOfTheTolerance(_ side: CurveOffsetSide) throws {
        var builder = DocumentBuilder(units: .meters, tolerance: .standard)
        let controls: [(Double, Double)] = [(0, 0), (0.01, 0.01), (0.02, -0.005), (0.03, 0.002)]
        let spline = try builder.sketch(on: .xy) { $0.spline(SketchSpline(controlPoints: controls.map { point($0.0, $0.1) })) }.featureID
        let distance = 0.002
        let offset = try builder.offsetCurve(CurveOutputReference(featureID: spline, curveIndex: 0), distance: length(distance),
                                             planeNormal: .unitZ, side: side)
        let evaluated = try DocumentEvaluator(tolerance: .standard, artifactPolicy: .deferred).evaluate(try builder.build(name: "offset"))
        let curve = try #require(evaluated.curves[offset]?.first?.exactCurve)
        let source = BSplineCurve3D(degree: 3, knots: [0, 0, 0, 0, 1, 1, 1, 1], controlPoints: controls.map { Point3D(x: $0.0, y: $0.1, z: 0) })
        for k in 0...40 {
            let t = Double(k) / 40
            let jet = try Curve3D.bSpline(source).differentialGeometry(at: t, tolerance: .standard)
            let left = try Vector3D(x: -jet.firstDerivative.y, y: jet.firstDerivative.x, z: 0).normalized(tolerance: 1e-12)
            let expected = jet.position + left * (side == .left ? distance : -distance)
            #expect((try curve.point(at: t, tolerance: .standard) - expected).length < 2.5e-7 + 1e-12)
        }
    }
}
