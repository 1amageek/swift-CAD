import CADCore
@testable import CADGeometry
import Testing

struct OffsetSurfaceLiftDerivativeBoundsTests {
    @Test
    func narrowPullbackBoundsDoNotConstructAnInvalidShortImage() throws {
        let tolerance = ModelingTolerance(distance: 1e-6, angle: 1e-8, relative: 1e-9)
        let source = Surface3D.analytic(.sphere(center: .origin, radius: 2))
        let image = try OffsetSurface3D(source: source, distance: -0.2)
            .parameterCurvePullback(
                transporting: .affine(origin: Point2D(x: 0, y: 0.1),
                                     direction: Point2D(x: 1, y: 0),
                                     startParameter: 0.7, endParameter: 0.8),
                tolerance: tolerance
            )
        let lift = SurfaceLiftCurve3D(surface: source, parameterCurve: .offsetSurfaceImage(image))
        try lift.validate(tolerance: tolerance)
        let interval = try ScalarInterval(lower: 0.499999, upper: 0.500001)
        #expect(throws: GeometryError.self) {
            try image.subcurve(fromNormalizedFraction: interval.lower,
                               toNormalizedFraction: interval.upper, tolerance: tolerance)
        }
        let bounder = SurfaceLiftDifferentialBounder()
        let first = try #require(try bounder.firstDerivativeMagnitude(
            lift: lift, interval: interval, tolerance: tolerance))
        let second = try #require(try bounder.secondDerivativeMagnitude(
            lift: lift, interval: interval, tolerance: tolerance))
        let third = try #require(try bounder.thirdDerivativeMagnitude(
            lift: lift, interval: interval, tolerance: tolerance))
        #expect(first.isFinite && second.isFinite && third.isFinite)
        let box = try lift.boundingBox(over: interval, tolerance: tolerance)
        for fraction in [interval.lower, interval.midpoint, interval.upper] {
            let differential = try lift.differentialGeometry(
                atNormalizedFraction: fraction, tolerance: tolerance)
            #expect(differential.firstDerivative.length <= first)
            #expect(differential.secondDerivative.length <= second)
            #expect(box.contains(differential.position, tolerance: tolerance.distance))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func offsetBoundaryBoundsEncloseActualDerivatives() throws {
        let tolerance = ModelingTolerance.standard
        let patch = Surface3D.bSpline(.bilinearPatch(
            bottomLeft: .origin, bottomRight: Point3D(x: 0.1, y: 0, z: 0),
            topRight: Point3D(x: 0.1, y: 0.1, z: 0), topLeft: Point3D(x: 0, y: 0.1, z: 0)))
        let surface = Surface3D.procedural(.offset(.init(source: patch, distance: 0.004)))
        let lift = SurfaceLiftCurve3D(surface: surface,
            parameterCurve: .constantV(v: 0, uStart: 0, uEnd: 1))
        let bounder = SurfaceLiftDifferentialBounder()
        let ruled = Surface3D.procedural(.ruled(.init(
            startBoundary: .surfaceLift(.init(surface: patch, parameterCurve: lift.parameterCurve)),
            endBoundary: .surfaceLift(lift))))
        let ruledBounds = try DefaultSurfaceDifferentialEncloser().tessellationBounds(
            of: ruled, over: SurfaceParameterBox(u: ScalarInterval(lower: 0, upper: 1),
                v: ScalarInterval(lower: 0, upper: 1)), tolerance: tolerance)
        #expect(ruledBounds.tangentUMagnitudeUpperBound >= 0.1)
        #expect(ruledBounds.tangentVMagnitudeUpperBound >= 0.004)
        let collapsed = Surface3D.procedural(.ruled(.init(
            startBoundary: .surfaceLift(lift), endBoundary: .surfaceLift(lift))))
        #expect(throws: (any Error).self) {
            try DefaultSurfaceDifferentialEncloser().tessellationBounds(
                of: collapsed, over: SurfaceParameterBox(u: ScalarInterval(lower: 0, upper: 1),
                    v: ScalarInterval(lower: 0, upper: 1)), tolerance: tolerance)
        }
        for lower in [0.0, 0.25, 0.75] {
            let interval = try ScalarInterval(lower: lower, upper: lower + 0.25)
            let first = try #require(try bounder.firstDerivativeMagnitude(lift: lift, interval: interval, tolerance: tolerance))
            let second = try #require(try bounder.secondDerivativeMagnitude(lift: lift, interval: interval, tolerance: tolerance))
            let third = try #require(try bounder.thirdDerivativeMagnitude(lift: lift, interval: interval, tolerance: tolerance))
            #expect(first.isFinite && second.isFinite && third.isFinite)
            #expect(first >= 0.1 && second >= 0 && third >= 0)
            #expect(second < 1e-6)
            #expect(third < 1e-6)
            let jet = try DefaultCurveDifferentialEncloser().thirdOrderIntervalJet(
                of: .surfaceLift(lift), over: interval, tolerance: tolerance)
            #expect(jet.z.value.upper - jet.z.value.lower < 1e-6)
            for fraction in [interval.lower, interval.midpoint, interval.upper] {
                let differential = try lift.differentialGeometry(atNormalizedFraction: fraction, tolerance: tolerance)
                #expect(differential.firstDerivative.length <= first)
                #expect(differential.secondDerivative.length <= second)
            }
        }
        #expect(throws: (any Error).self) {
            try bounder.firstDerivativeMagnitude(lift: lift,
                interval: ScalarInterval(lower: -0.25, upper: 0.25), tolerance: tolerance)
        }
    }
}
