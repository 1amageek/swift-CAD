import CADCore
@testable import CADGeometry
import Foundation
import Testing

@Suite("Certified curve arc length")
struct CurveArcLengthResolverTests {
    private let tolerance = ModelingTolerance.standard

    @Test
    func lineLengthAndFractionAreExact() throws {
        let curve = Curve3D.line(Line3D(
            origin: .origin,
            direction: .unitX
        ))
        let interval = try ScalarInterval(lower: 2.0, upper: 12.0)
        let resolver = DefaultCurveArcLengthResolver()

        let length = try resolver.enclosure(
            of: curve,
            over: interval,
            tolerance: tolerance
        )
        let parameter = try resolver.parameterEnclosure(
            atArcLengthFraction: 0.25,
            of: curve,
            over: interval,
            tolerance: tolerance
        )

        #expect(length.lowerBound <= 10.0)
        #expect(length.upperBound >= 10.0)
        #expect(length.width <= 1.0e-12)
        #expect(parameter.parameterRange.lower == 4.5)
        #expect(parameter.parameterRange.upper == 4.5)
        #expect(parameter.spatialErrorUpperBound == 0.0)
    }

    @Test
    func circleLengthUsesAnalyticArcLength() throws {
        let curve = Curve3D.circle(Circle3D(
            center: .origin,
            normal: .unitZ,
            radius: 3.0
        ))
        let interval = try ScalarInterval(
            lower: 0.0,
            upper: Double.pi * 0.5
        )

        let length = try DefaultCurveArcLengthResolver().enclosure(
            of: curve,
            over: interval,
            tolerance: tolerance
        )

        let reference = 1.5 * Double.pi
        #expect(length.lowerBound <= reference)
        #expect(length.upperBound >= reference)
        #expect(length.width <= 1.0e-12)
    }

    @Test
    func nonlinearBSplineLengthEnclosesReferenceAndConverges() throws {
        let curve = Curve3D.bSpline(BSplineCurve3D(
            degree: 3,
            knots: [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 2.0, z: 0.0),
                Point3D(x: 3.0, y: -1.0, z: 0.0),
                Point3D(x: 4.0, y: 0.0, z: 0.0),
            ]
        ))
        let interval = try ScalarInterval(lower: 0.0, upper: 1.0)
        let enclosure = try DefaultCurveArcLengthResolver().enclosure(
            of: curve,
            over: interval,
            options: CurveArcLengthOptions(absoluteAccuracy: 1.0e-7),
            tolerance: tolerance
        )
        let reference = try highResolutionLength(
            curve: curve,
            interval: interval,
            segmentCount: 200_000
        )

        #expect(enclosure.width <= 1.0e-7)
        #expect(enclosure.lowerBound <= reference)
        #expect(enclosure.upperBound >= reference)
    }

    @Test
    func nonlinearBSplineArcLengthFractionDoesNotUseParameterFraction() throws {
        let curve = Curve3D.bSpline(BSplineCurve3D(
            degree: 3,
            knots: [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 0.0, y: 8.0, z: 0.0),
                Point3D(x: 1.0, y: 8.0, z: 0.0),
                Point3D(x: 10.0, y: 8.0, z: 0.0),
            ]
        ))
        let interval = try ScalarInterval(lower: 0.0, upper: 1.0)
        let result = try DefaultCurveArcLengthResolver().parameterEnclosure(
            atArcLengthFraction: 0.5,
            of: curve,
            over: interval,
            options: CurveArcLengthOptions(absoluteAccuracy: 5.0e-6),
            tolerance: tolerance
        )

        #expect(result.parameterRange.contains(0.5) == false)
        #expect(result.spatialErrorUpperBound <= 5.0e-6)
    }

    @Test(.timeLimit(.minutes(1)))
    func rationalQuadraticConvergesAtStrictModelingTolerance() throws {
        let strictTolerance = ModelingTolerance(
            distance: 1.0e-8,
            angle: 1.0e-10,
            relative: 1.0e-9
        )
        let curve = try rationalQuadraticCurve(tolerance: strictTolerance)
        let interval = try ScalarInterval(lower: 0.0, upper: 1.0)
        let parameterization = try DefaultCurveArcLengthResolver()
            .parameterization(
                of: curve,
                over: interval,
                tolerance: strictTolerance
            )
        let quarter = try parameterization.parameterEnclosure(
            atArcLengthFraction: 0.25
        )
        let reference = try highResolutionLength(
            curve: curve,
            interval: interval,
            segmentCount: 100_000,
            tolerance: strictTolerance
        )

        #expect(parameterization.lengthEnclosure.width <= strictTolerance.distance)
        #expect(abs(parameterization.lengthEnclosure.midpoint - reference) <= strictTolerance.distance)
        #expect(quarter.spatialErrorUpperBound <= strictTolerance.distance)
    }

    @Test
    func endpointFractionsCannotBypassCurveDomainValidation() throws {
        let curve = try rationalQuadraticCurve(tolerance: tolerance)
        let outsideDomain = try ScalarInterval(lower: -0.25, upper: 0.25)
        let resolver = DefaultCurveArcLengthResolver()

        #expect(throws: KernelError.self) {
            try resolver.parameterEnclosure(
                atArcLengthFraction: 0.0,
                of: curve,
                over: outsideDomain,
                tolerance: tolerance
            )
        }
        #expect(throws: KernelError.self) {
            try resolver.parameterEnclosure(
                atArcLengthFraction: 1.0,
                of: curve,
                over: outsideDomain,
                tolerance: tolerance
            )
        }
    }

    private func highResolutionLength(
        curve: Curve3D,
        interval: ScalarInterval,
        segmentCount: Int,
        tolerance: ModelingTolerance? = nil
    ) throws -> Double {
        let evaluationTolerance = tolerance ?? self.tolerance
        var previous = try curve.point(
            at: interval.lower,
            tolerance: evaluationTolerance
        )
        var result = 0.0
        for index in 1...segmentCount {
            let parameter = interval.lower
                + interval.width * Double(index) / Double(segmentCount)
            let point = try curve.point(
                at: parameter,
                tolerance: evaluationTolerance
            )
            result += (point - previous).length
            previous = point
        }
        return result
    }

    private func rationalQuadraticCurve(
        tolerance: ModelingTolerance
    ) throws -> Curve3D {
        let spline = BSplineCurve3D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 0.02, y: 0.0, z: 0.03),
                Point3D(x: 0.03, y: 0.0, z: 0.05),
            ],
            weights: [1.0, 0.75, 1.0]
        )
        try spline.validate(tolerance: tolerance)
        return .bSpline(spline)
    }
}
