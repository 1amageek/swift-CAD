import CADCore
@testable import CADGeometry
import Testing

struct OffsetSurfaceLiftDerivativeBoundsTests {
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
