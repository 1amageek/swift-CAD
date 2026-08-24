import CADCore
@testable import CADGeometry
import Foundation
import Testing

@Suite("Rational Bezier Curve Jet Encloser")
struct RationalBezierCurveJetEncloserTests {
    private let tolerance = ModelingTolerance.standard

    @Test
    func narrowIntervalDerivativesRemainCertifiedAndStable() throws {
        let weight = sqrt(0.5)
        let points = [
            Point3D(x: 1.0, y: 0.0, z: 0.0),
            Point3D(x: 1.0, y: 1.0, z: 0.0),
            Point3D(x: 0.0, y: 1.0, z: 0.0),
        ]
        let weights = [1.0, weight, 1.0]
        let patch = RationalBezierCurvePatch3D(
            controlPoints: points,
            weights: weights,
            lower: 0.0,
            upper: 1.0
        )
        let curve = BSplineCurve3D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: points,
            weights: weights
        )
        let interval = try ScalarInterval(
            lower: 0.5 - 1.0e-10,
            upper: 0.5 + 1.0e-10
        )
        let enclosure = try RationalBezierCurveJetEncloser().enclosure(
            of: patch,
            over: interval,
            tolerance: tolerance
        )
        let expected = try curve.parameterDerivatives(
            at: 0.5,
            tolerance: tolerance
        )

        expectContains(enclosure.x.value, expected.position.x)
        expectContains(enclosure.y.value, expected.position.y)
        expectContains(enclosure.z.value, expected.position.z)
        expectContains(enclosure.x.derivativeU, expected.firstDerivative.x)
        expectContains(enclosure.y.derivativeU, expected.firstDerivative.y)
        expectContains(enclosure.z.derivativeU, expected.firstDerivative.z)
        expectContains(
            enclosure.x.secondDerivativeUU,
            expected.secondDerivative.x
        )
        expectContains(
            enclosure.y.secondDerivativeUU,
            expected.secondDerivative.y
        )
        expectContains(
            enclosure.z.secondDerivativeUU,
            expected.secondDerivative.z
        )
        #expect(enclosure.x.derivativeU.upper - enclosure.x.derivativeU.lower < 1.0e-6)
        #expect(enclosure.y.derivativeU.upper - enclosure.y.derivativeU.lower < 1.0e-6)
        #expect(enclosure.x.thirdDerivativeUUU.isFinite)
        #expect(enclosure.y.thirdDerivativeUUU.isFinite)
    }

    private func expectContains(
        _ interval: OutwardScalarInterval,
        _ value: Double
    ) {
        #expect(interval.lower <= value)
        #expect(interval.upper >= value)
    }
}
