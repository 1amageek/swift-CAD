import CADCore
import CADGeometry
@testable import CADTopology
import Testing

@Suite("Rational revolution profile moments")
struct RationalRevolutionProfileMomentBuilderTests {
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func multiSpanProfileRetainsEveryExactMomentSpan() throws {
        let profile = BSplineCurve2D(
            degree: 1,
            knots: [0.0, 0.0, 0.5, 1.0, 1.0],
            controlPoints: [
                Point2D(x: 1.0, y: 0.0),
                Point2D(x: 2.0, y: 1.0),
                Point2D(x: 1.0, y: 2.0),
            ]
        )

        let patches = try RationalRevolutionProfileMomentBuilder().patches(
            for: profile,
            tolerance: tolerance
        )
        #expect(patches.count == 2)

        let total = try CertifiedAnalyticPcurveFluxIntegrator()
            .parameterAreaBounds(
                for: patches,
                requestedWidth: 1.0e-12,
                tolerance: tolerance
            )
        let expected = 7.0 / 3.0
        #expect(total.lower <= expected)
        #expect(total.upper >= expected)
        #expect(total.width <= 1.0e-10)
    }

    @Test(.timeLimit(.minutes(1)))
    func rationalMultiSpanMomentMatchesProfilePointwise() throws {
        let profile = BSplineCurve2D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 0.5, 1.0, 1.0, 1.0],
            controlPoints: [
                Point2D(x: 1.0, y: 0.0),
                Point2D(x: 1.8, y: 0.4),
                Point2D(x: 2.2, y: 1.6),
                Point2D(x: 1.1, y: 2.0),
            ],
            weights: [1.0, 0.75, 1.25, 1.0]
        )

        let patches = try RationalRevolutionProfileMomentBuilder().patches(
            for: profile,
            tolerance: tolerance
        )
        #expect(patches.count == 2)

        for patch in patches {
            for fraction in [0.0, 0.2, 0.5, 0.8, 1.0] {
                let parameter = patch.lower + (patch.upper - patch.lower) * fraction
                let source = try profile.point(
                    at: parameter,
                    tolerance: tolerance
                )
                let moment = evaluated(patch, at: fraction)
                let momentX = moment.x / moment.weight
                let momentY = moment.y / moment.weight
                let expectedX = 0.5 * source.x * source.x
                #expect(momentX.lower <= expectedX)
                #expect(momentX.upper >= expectedX)
                #expect(momentY.lower <= source.y)
                #expect(momentY.upper >= source.y)
            }
        }
    }

    private func evaluated(
        _ patch: CertifiedHomogeneousBezierCurvePatch,
        at fraction: Double
    ) -> CertifiedHomogeneousBezierCurvePatch.HomogeneousPoint {
        typealias Scalar = CertifiedHomogeneousBezierCurvePatch.ScalarBounds
        var level = patch.controls
        let parameter = Scalar.exact(fraction)
        while level.count > 1 {
            level = (0..<(level.count - 1)).map { index in
                level[index].interpolated(
                    to: level[index + 1],
                    parameter: parameter
                )
            }
        }
        return level[0]
    }
}
