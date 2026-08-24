import CADCore
import CADGeometry
import CADIR
@testable import CADModeling
import Synchronization
import Testing

@Suite("Evaluated curve path arc-length contract")
struct EvaluatedCurvePathArcLengthTests {
    private let tolerance = ModelingTolerance.standard

    @Test
    func bSplineDistanceFractionUsesCertifiedArcLengthInversion() throws {
        let spline = BSplineCurve3D(
            degree: 3,
            knots: [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 0.0, y: 8.0, z: 0.0),
                Point3D(x: 1.0, y: 8.0, z: 0.0),
                Point3D(x: 10.0, y: 8.0, z: 0.0),
            ]
        )
        let exactCurve = Curve3D.bSpline(spline)
        let displayParameters = [0.0, 0.25, 0.5, 0.75, 1.0]
        let evaluated = EvaluatedCurve(
            sourceFeatureID: FeatureID(),
            source: .generatedFeature,
            kind: .spline,
            points: try displayParameters.map {
                try exactCurve.point(at: $0, tolerance: tolerance)
            },
            exactCurve: exactCurve,
            exactParameterDomain: .closed(0.0, 1.0),
            exactPointParameters: displayParameters
        )
        let evaluator = EvaluatedCurvePathEvaluator(tolerance: tolerance)
        let samples = try evaluator.samples(
            for: evaluated,
            distanceFraction: 0.5
        )
        let endPoint = try #require(samples.last?.point)
        let parameterHalfPoint = try exactCurve.point(
            at: 0.5,
            tolerance: tolerance
        )
        let expectedParameter = try DefaultCurveArcLengthResolver()
            .parameterEnclosure(
                atArcLengthFraction: 0.5,
                of: exactCurve,
                over: ScalarInterval(lower: 0.0, upper: 1.0),
                tolerance: tolerance
            ).parameter
        let expectedPoint = try exactCurve.point(
            at: expectedParameter,
            tolerance: tolerance
        )
        let fullLength = try evaluator.length(of: evaluated)

        #expect((endPoint - expectedPoint).length <= tolerance.distance)
        #expect((endPoint - parameterHalfPoint).length > tolerance.distance * 100.0)
        #expect(abs((samples.last?.distance ?? 0.0) * 2.0 - fullLength) <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func reversedAnalyticCurvePreservesExactTraversal() throws {
        let pathTolerance = ModelingTolerance(
            distance: 1.0e-4,
            angle: 1.0e-6
        )
        let exactCurve = Curve3D.analytic(.ellipse(
            center: .origin,
            normal: .unitZ,
            majorAxis: .unitX,
            majorRadius: 5.0,
            minorRadius: 2.0
        ))
        let interval = try ScalarInterval(
            lower: 0.0,
            upper: Double.pi * 0.5
        )
        let lowerPoint = try exactCurve.point(
            at: interval.lower,
            tolerance: pathTolerance
        )
        let upperPoint = try exactCurve.point(
            at: interval.upper,
            tolerance: pathTolerance
        )
        let evaluated = EvaluatedCurve(
            sourceFeatureID: FeatureID(),
            source: .generatedFeature,
            kind: .spline,
            points: [lowerPoint, upperPoint],
            exactCurve: exactCurve,
            exactParameterDomain: .closed(interval.lower, interval.upper),
            exactPointParameters: [interval.lower, interval.upper]
        )
        let samples = try EvaluatedCurvePathEvaluator(
            tolerance: pathTolerance
        ).samples(
            for: [EvaluatedCurvePathSegment(
                curve: evaluated,
                isReversed: true
            )],
            distanceFraction: 0.25
        )
        let expectedParameter = try DefaultCurveArcLengthResolver()
            .parameterEnclosure(
                atArcLengthFraction: 0.75,
                of: exactCurve,
                over: interval,
                tolerance: pathTolerance
            ).parameter
        let expectedEnd = try exactCurve.point(
            at: expectedParameter,
            tolerance: pathTolerance
        )
        let expectedTangent = try exactCurve.differentialGeometry(
            at: expectedParameter,
            tolerance: pathTolerance
        ).tangent * -1.0
        let first = try #require(samples.first)
        let last = try #require(samples.last)

        #expect(samples.count > 2)
        #expect(first.point.isApproximatelyEqual(
            to: upperPoint,
            tolerance: pathTolerance.distance
        ))
        #expect(last.point.isApproximatelyEqual(
            to: expectedEnd,
            tolerance: pathTolerance.distance
        ))
        #expect(last.tangent.dot(expectedTangent) >= 1.0 - pathTolerance.angle)
    }

    @Test(.timeLimit(.minutes(1)))
    func preparedRigidImagePathSamplesCanonicalGeometry() throws {
        let spline = BSplineCurve3D(
            degree: 3,
            knots: [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0],
            controlPoints: [
                .origin,
                Point3D(x: 0.0, y: 4.0, z: 0.0),
                Point3D(x: 2.0, y: 6.0, z: 0.0),
                Point3D(x: 8.0, y: 6.0, z: 0.0),
            ]
        )
        let transform = try RigidTransform3D.rotated(
            around: .origin,
            direction: .unitZ,
            angle: Double.pi * 0.5,
            tolerance: tolerance
        )
        let exactCurve = Curve3D.rigidImage(try RigidImageCurve3D(
            source: .bSpline(spline),
            transform: transform,
            tolerance: tolerance
        ))
        let endpoints = try [0.0, 1.0].map {
            try exactCurve.point(at: $0, tolerance: tolerance)
        }
        let evaluated = EvaluatedCurve(
            sourceFeatureID: FeatureID(),
            source: .generatedFeature,
            kind: .spline,
            points: endpoints,
            exactCurve: exactCurve,
            exactParameterDomain: .closed(0.0, 1.0),
            exactPointParameters: [0.0, 1.0]
        )
        let evaluator = EvaluatedCurvePathEvaluator(tolerance: tolerance)
        let prepared = try evaluator.prepare(evaluated)
        let sample = try evaluator.sample(
            at: prepared.totalLength * 0.5,
            on: prepared
        )
        let expectedParameter = try DefaultCurveArcLengthResolver()
            .parameterEnclosure(
                atArcLengthFraction: 0.5,
                of: exactCurve,
                over: ScalarInterval(lower: 0.0, upper: 1.0),
                tolerance: tolerance
            ).parameter
        let expected = try exactCurve.differentialGeometry(
            at: expectedParameter,
            tolerance: tolerance
        )
        let chordMidpoint = endpoints[0] + (endpoints[1] - endpoints[0]) * 0.5

        #expect((sample.point - expected.position).length <= tolerance.distance)
        #expect(sample.tangent.dot(expected.tangent) >= 1.0 - tolerance.angle)
        #expect((sample.point - chordMidpoint).length > tolerance.distance * 100.0)
    }

    @Test(.timeLimit(.minutes(1)))
    func preparedPeriodicPathPreservesEvaluatedStartPhase() throws {
        let circle = Circle3D(
            center: .origin,
            normal: .unitZ,
            radius: 2.0
        )
        let exactCurve = Curve3D.circle(circle)
        let start = Double.pi * 0.5
        let end = start + Double.pi * 2.0
        let pointParameters = [
            start,
            start + Double.pi * 0.5,
            start + Double.pi,
            start + Double.pi * 1.5,
            end,
        ]
        let points = try pointParameters.map {
            try exactCurve.point(at: $0, tolerance: tolerance)
        }
        let evaluated = EvaluatedCurve(
            sourceFeatureID: FeatureID(),
            source: .generatedFeature,
            kind: .circle,
            points: points,
            isClosed: true,
            exactCurve: exactCurve,
            exactPointParameters: pointParameters
        )
        let evaluator = EvaluatedCurvePathEvaluator(tolerance: tolerance)
        let prepared = try evaluator.prepare(evaluated)
        let origin = try evaluator.sample(at: 0.0, on: prepared)
        let quarter = try evaluator.sample(
            at: prepared.totalLength * 0.25,
            on: prepared
        )
        let expectedQuarter = try exactCurve.differentialGeometry(
            at: start + Double.pi * 0.5,
            tolerance: tolerance
        )

        #expect(origin.point.isApproximatelyEqual(
            to: points[0],
            tolerance: tolerance.distance
        ))
        #expect(quarter.point.isApproximatelyEqual(
            to: expectedQuarter.position,
            tolerance: tolerance.distance
        ))
        #expect(quarter.tangent.dot(expectedQuarter.tangent) >= 1.0 - tolerance.angle)
    }

    @Test(.timeLimit(.minutes(1)))
    func reversedPeriodicRigidImageUsesCanonicalArcLengthPath() throws {
        let source = Curve3D.circle(Circle3D(
            center: Point3D(x: 1.0, y: -2.0, z: 0.0),
            normal: .unitZ,
            radius: 3.0
        ))
        let transform = try RigidTransform3D.rotated(
            around: .origin,
            direction: .unitY,
            angle: Double.pi * 0.25,
            tolerance: tolerance
        )
        let exactCurve = Curve3D.rigidImage(try RigidImageCurve3D(
            source: source,
            transform: transform,
            tolerance: tolerance
        ))
        let start = Double.pi * 0.5
        let parameters = [
            start,
            start + Double.pi * 0.5,
            start + Double.pi,
            start + Double.pi * 1.5,
            start + Double.pi * 2.0,
        ]
        let points = try parameters.map {
            try exactCurve.point(at: $0, tolerance: tolerance)
        }
        let evaluated = EvaluatedCurve(
            sourceFeatureID: FeatureID(),
            source: .generatedFeature,
            kind: .circle,
            points: points,
            isClosed: true,
            exactCurve: exactCurve,
            exactPointParameters: parameters
        )
        let evaluator = EvaluatedCurvePathEvaluator(tolerance: tolerance)
        let samples = try evaluator.samples(
            for: [EvaluatedCurvePathSegment(
                curve: evaluated,
                isReversed: true
            )],
            distanceFraction: 0.25
        )
        let first = try #require(samples.first)
        let last = try #require(samples.last)
        let expectedLast = try exactCurve.differentialGeometry(
            at: start + Double.pi * 1.5,
            tolerance: tolerance
        )

        #expect(first.point.isApproximatelyEqual(
            to: points[0],
            tolerance: tolerance.distance
        ))
        #expect(last.point.isApproximatelyEqual(
            to: expectedLast.position,
            tolerance: tolerance.distance
        ))
        #expect(last.tangent.dot(-expectedLast.tangent) >= 1.0 - tolerance.angle)
        #expect(abs(last.distance - Double.pi * 1.5) <= tolerance.distance)
    }

    @available(macOS 15.0, *)
    @Test(.timeLimit(.minutes(1)))
    func preparedChainReusesOneCertifiedParameterization() throws {
        let pathTolerance = ModelingTolerance(
            distance: 1.0e-3,
            angle: 1.0e-6
        )
        let exactCurve = Curve3D.analytic(.ellipse(
            center: .origin,
            normal: .unitZ,
            majorAxis: .unitX,
            majorRadius: 4.0,
            minorRadius: 2.0
        ))
        let parameters = [0.0, Double.pi * 0.5]
        let evaluated = EvaluatedCurve(
            sourceFeatureID: FeatureID(),
            source: .generatedFeature,
            kind: .spline,
            points: try parameters.map {
                try exactCurve.point(at: $0, tolerance: pathTolerance)
            },
            exactCurve: exactCurve,
            exactParameterDomain: .closed(parameters[0], parameters[1]),
            exactPointParameters: parameters
        )
        let resolver = CountingCurveArcLengthResolver()
        let evaluator = EvaluatedCurvePathEvaluator(
            tolerance: pathTolerance,
            arcLengthResolver: resolver
        )
        let chain = try evaluator.prepare([
            EvaluatedCurvePathSegment(curve: evaluated),
        ])

        for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
            _ = try evaluator.sample(
                at: chain.totalLength * fraction,
                on: chain
            )
        }

        #expect(resolver.parameterizationCallCount == 1)
    }
}

@available(macOS 15.0, *)
private final class CountingCurveArcLengthResolver: CurveArcLengthResolving, Sendable {
    private let callCount = Mutex(0)
    private let base = DefaultCurveArcLengthResolver()

    var parameterizationCallCount: Int {
        callCount.withLock { $0 }
    }

    func enclosure(
        of curve: Curve3D,
        over interval: ScalarInterval,
        options: CurveArcLengthOptions,
        tolerance: ModelingTolerance
    ) throws -> CurveArcLengthEnclosure {
        try base.enclosure(
            of: curve,
            over: interval,
            options: options,
            tolerance: tolerance
        )
    }

    func parameterEnclosure(
        atArcLengthFraction fraction: Double,
        of curve: Curve3D,
        over interval: ScalarInterval,
        options: CurveArcLengthOptions,
        tolerance: ModelingTolerance
    ) throws -> CurveArcLengthParameterEnclosure {
        try base.parameterEnclosure(
            atArcLengthFraction: fraction,
            of: curve,
            over: interval,
            options: options,
            tolerance: tolerance
        )
    }

    func parameterization(
        of curve: Curve3D,
        over interval: ScalarInterval,
        options: CurveArcLengthOptions,
        tolerance: ModelingTolerance
    ) throws -> any CurveArcLengthParameterization {
        callCount.withLock { $0 += 1 }
        return try base.parameterization(
            of: curve,
            over: interval,
            options: options,
            tolerance: tolerance
        )
    }
}
