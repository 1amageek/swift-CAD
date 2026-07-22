import Testing
import CADCore
import CADGeometry

@Suite("Rational Bezier half-space classification")
struct RationalBezierHalfSpaceClassifierTests {
    @Test
    func certifiesPositiveCurveWithNegativeEuclideanControlValue() throws {
        let result = try DefaultRationalBezierHalfSpaceClassifier().classify(
            controlValues: [0.01, -0.002, 0.02, 0.01],
            weights: [1.0, 0.2, 2.0, 1.0],
            nonnegativeMargin: 1.0e-8,
            tolerance: ModelingTolerance(distance: 1.0e-8, angle: 1.0e-10)
        )

        #expect(result == .nonnegative)
    }

    @Test
    func reportsCurveThatCrossesNegativeHalfSpace() throws {
        let result = try DefaultRationalBezierHalfSpaceClassifier().classify(
            controlValues: [0.01, -0.04, -0.04, 0.01],
            weights: [1.0, 1.0, 1.0, 1.0],
            nonnegativeMargin: 1.0e-8,
            tolerance: ModelingTolerance(distance: 1.0e-8, angle: 1.0e-10)
        )

        guard case let .violates(residual) = result else {
            Issue.record("Expected a certified negative half-space violation.")
            return
        }
        #expect(residual > 0.0)
    }
}
