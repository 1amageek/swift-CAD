import Foundation
import Testing
import CADCore
@testable import CADGeometry

@Suite("Surface parameter curve periodic evaluation")
struct SurfaceParameterCurvePeriodicEvaluationTests {
    private let sphere = Surface3D.analytic(.sphere(center: .origin, radius: 2.0))

    @Test
    func periodicCurveParameterWrapsIntoBSplinePcurveDomain() throws {
        let pcurve = SurfaceParameterCurve.bSpline(BSplineCurve2D(
            degree: 1,
            knots: [10.0, 10.0, 20.0, 20.0],
            controlPoints: [
                Point2D(x: 0.0, y: 0.0),
                Point2D(x: 1.0, y: 2.0),
            ]
        ))
        let period = 2.0 * Double.pi

        let positive = try pcurve.parameter(
            atCurveParameter: 2.5 * Double.pi,
            curveDomain: .periodic(period: period),
            tolerance: .standard
        )
        let negative = try pcurve.parameter(
            atCurveParameter: -1.5 * Double.pi,
            curveDomain: .periodic(period: period),
            tolerance: .standard
        )
        let boundary = try pcurve.parameter(
            atCurveParameter: period,
            curveDomain: .periodic(period: period),
            tolerance: .standard
        )

        #expect(abs(positive.u - 0.25) <= 1.0e-12)
        #expect(abs(positive.v - 0.5) <= 1.0e-12)
        #expect(abs(negative.u - positive.u) <= 1.0e-12)
        #expect(abs(negative.v - positive.v) <= 1.0e-12)
        #expect(abs(boundary.u) <= 1.0e-12)
        #expect(abs(boundary.v) <= 1.0e-12)
    }

    @Test
    func closedCurveParameterRetainsDirectBSplineParameterization() throws {
        let pcurve = SurfaceParameterCurve.bSpline(BSplineCurve2D(
            degree: 1,
            knots: [10.0, 10.0, 20.0, 20.0],
            controlPoints: [
                Point2D(x: 0.0, y: 0.0),
                Point2D(x: 1.0, y: 2.0),
            ]
        ))

        let parameter = try pcurve.parameter(
            atCurveParameter: 12.5,
            curveDomain: .closed(10.0, 20.0),
            tolerance: .standard
        )

        #expect(abs(parameter.u - 0.25) <= 1.0e-12)
        #expect(abs(parameter.v - 0.5) <= 1.0e-12)
    }

    @Test
    func periodicConstantPcurveTrimRetainsUpperEndpointLift() throws {
        let period = 2.0 * Double.pi
        let pcurve = SurfaceParameterCurve.constantV(
            v: 0.25,
            uStart: 0.0,
            uEnd: period
        )

        let first = try pcurve.trimmed(
            from: 0.0,
            to: Double.pi,
            curveDomain: .periodic(period: period),
            tolerance: .standard
        )
        let second = try pcurve.trimmed(
            from: Double.pi,
            to: period,
            curveDomain: .periodic(period: period),
            tolerance: .standard
        )

        #expect(first == .constantV(
            v: 0.25,
            uStart: 0.0,
            uEnd: Double.pi
        ))
        #expect(second == .constantV(
            v: 0.25,
            uStart: Double.pi,
            uEnd: period
        ))
    }

    @Test(.timeLimit(.minutes(1)))
    func exactPeriodicTranslationPreservesLiftAndDifferentials() throws {
        let base = SurfaceParameterCurve.sphericalGreatCircle(
            cosine: .unitX,
            sine: .unitY,
            startParameter: 0.2,
            endParameter: 2.4
        )
        let translated = SurfaceParameterCurve.periodicTranslation(
            base: base,
            uShift: 2.0 * Double.pi,
            vShift: 0.0
        )
        try translated.validate(on: sphere, tolerance: .standard)

        for fraction in [0.0, 0.2, 0.5, 0.9, 1.0] {
            let baseDifferential = try base.differentialGeometry(
                atNormalizedFraction: fraction,
                tolerance: .standard
            )
            let translatedDifferential = try translated.differentialGeometry(
                atNormalizedFraction: fraction,
                tolerance: .standard
            )
            #expect(abs(
                translatedDifferential.parameter.u
                    - baseDifferential.parameter.u
                    - 2.0 * Double.pi
            ) <= 1.0e-12)
            #expect(abs(
                translatedDifferential.parameter.v
                    - baseDifferential.parameter.v
            ) <= 1.0e-12)
            #expect(translatedDifferential.firstDerivative == baseDifferential.firstDerivative)
            #expect(translatedDifferential.secondDerivative == baseDifferential.secondDerivative)

            let basePoint = try sphere.point(
                u: baseDifferential.parameter.u,
                v: baseDifferential.parameter.v,
                tolerance: .standard
            )
            let translatedPoint = try sphere.point(
                u: translatedDifferential.parameter.u,
                v: translatedDifferential.parameter.v,
                tolerance: .standard
            )
            #expect(basePoint.isApproximatelyEqual(
                to: translatedPoint,
                tolerance: 1.0e-10
            ))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func periodicTranslationRetainsIdentityAcrossCodableTrimAndReverse() throws {
        let base = SurfaceParameterCurve.sphericalGreatCircle(
            cosine: .unitX,
            sine: .unitY,
            startParameter: 0.2,
            endParameter: 2.4
        )
        let translated = SurfaceParameterCurve.periodicTranslation(
            base: base,
            uShift: -2.0 * Double.pi,
            vShift: 0.0
        )

        let encoded = try JSONEncoder().encode(translated)
        let decoded = try JSONDecoder().decode(
            SurfaceParameterCurve.self,
            from: encoded
        )
        #expect(decoded == translated)

        let subcurve = try decoded.subcurve(
            fromNormalizedFraction: 0.25,
            toNormalizedFraction: 0.75,
            tolerance: .standard
        )
        let expectedStart = try decoded.parameter(
            atNormalizedFraction: 0.25,
            tolerance: .standard
        )
        let expectedEnd = try decoded.parameter(
            atNormalizedFraction: 0.75,
            tolerance: .standard
        )
        #expect(try subcurve.startParameter(tolerance: .standard) == expectedStart)
        #expect(try subcurve.endParameter(tolerance: .standard) == expectedEnd)

        let reversed = try subcurve.reversed(tolerance: .standard)
        #expect(try reversed.startParameter(tolerance: .standard) == expectedEnd)
        #expect(try reversed.endParameter(tolerance: .standard) == expectedStart)
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsTranslationsThatDoNotMatchSurfacePeriodicity() {
        let base = SurfaceParameterCurve.sphericalGreatCircle(
            cosine: .unitX,
            sine: .unitY,
            startParameter: 0.2,
            endParameter: 2.4
        )
        #expect(throws: KernelError.self) {
            try SurfaceParameterCurve.periodicTranslation(
                base: base,
                uShift: Double.pi,
                vShift: 0.0
            ).validate(on: sphere, tolerance: .standard)
        }
        #expect(throws: KernelError.self) {
            try SurfaceParameterCurve.periodicTranslation(
                base: base,
                uShift: 0.0,
                vShift: 2.0 * Double.pi
            ).validate(on: sphere, tolerance: .standard)
        }
    }
}
