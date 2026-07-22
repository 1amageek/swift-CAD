import Testing
import CADCore
@testable import CADGeometry

@Suite("Parallel-offset torus-torus surface intersection", .serialized)
struct ParallelOffsetTorusTorusSurfaceIntersectionTests {
    private let tolerance = ModelingTolerance.standard
    private let intersector = DefaultSurfaceSurfaceIntersector()

    @Test(.timeLimit(.minutes(1)))
    func strictFullDomainConfigurationProducesFourVerifiedClosedCurves() throws {
        let axis = try tiltedAxis()
        let first = torus(center: .origin, axis: axis, minorRadius: 0.5)
        let second = torus(
            center: Point3D(
                x: axis.x * 0.25,
                y: 2.2,
                z: axis.z * 0.25
            ),
            axis: axis,
            minorRadius: 1.5
        )
        let intersections = try intersector.intersections(
            first: first,
            second: second,
            tolerance: tolerance
        )

        #expect(intersections.count == 4)
        for intersection in intersections {
            try verifyCurve(intersection, first: first, second: second)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func operandOrderPreservesDeterministicThreeDimensionalCurves() throws {
        let first = torus(center: .origin, axis: .unitZ, minorRadius: 0.5)
        let second = torus(
            center: Point3D(x: 2.2, y: 0.0, z: 0.0),
            axis: .unitZ,
            minorRadius: 1.5
        )
        let forward = try intersector.intersections(
            first: first,
            second: second,
            tolerance: tolerance
        )
        let reverse = try intersector.intersections(
            first: second,
            second: first,
            tolerance: tolerance
        )

        #expect(curves(forward) == curves(reverse))
    }

    @Test(.timeLimit(.minutes(1)))
    func separatedParallelOffsetToriProduceExactEmptyIntersection() throws {
        let intersections = try intersector.intersections(
            first: torus(center: .origin, axis: .unitZ, minorRadius: 0.5),
            second: torus(
                center: Point3D(x: 10.0, y: 0.0, z: 0.0),
                axis: .unitZ,
                minorRadius: 1.5
            ),
            tolerance: tolerance
        )
        #expect(intersections.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func generatorTangencyReturnsTypedSingularGeometryDiagnostic() throws {
        do {
            _ = try intersector.intersections(
                first: torus(center: .origin, axis: .unitZ, minorRadius: 0.5),
                second: torus(
                    center: Point3D(x: 2.0, y: 0.0, z: 0.0),
                    axis: .unitZ,
                    minorRadius: 1.5
                ),
                tolerance: tolerance
            )
            Issue.record("A torus-torus generator tangency must not be approximated.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .singularGeometry)
            #expect(error.residual != nil)
            #expect(error.tolerance == tolerance)
        }
    }

    private func verifyCurve(
        _ intersection: SurfaceSurfaceIntersection,
        first: Surface3D,
        second: Surface3D
    ) throws {
        guard case let .curve(result) = intersection,
              case .bSpline = result.curve,
              case let .closed(lower, upper) = result.curve.parameterDomain else {
            Issue.record("A strict parallel-offset torus pair must produce closed B-spline curves.")
            return
        }
        #expect(result.kind == .transverse)
        #expect(result.maximumResidual <= tolerance.distance)
        try result.firstSurfaceParameterCurve.validate(on: first, tolerance: tolerance)
        try result.secondSurfaceParameterCurve.validate(on: second, tolerance: tolerance)

        for index in 0...24 {
            let parameter = lower + (upper - lower) * Double(index) / 24.0
            let curvePoint = try result.curve.point(
                at: parameter,
                tolerance: tolerance
            )
            let firstUV = try result.firstSurfaceParameterCurve.parameter(
                atCurveParameter: parameter,
                curveDomain: result.curve.parameterDomain,
                tolerance: tolerance
            )
            let secondUV = try result.secondSurfaceParameterCurve.parameter(
                atCurveParameter: parameter,
                curveDomain: result.curve.parameterDomain,
                tolerance: tolerance
            )
            let firstPoint = try first.point(
                u: firstUV.u,
                v: firstUV.v,
                tolerance: tolerance
            )
            let secondPoint = try second.point(
                u: secondUV.u,
                v: secondUV.v,
                tolerance: tolerance
            )
            #expect((curvePoint - firstPoint).length <= tolerance.distance)
            #expect((curvePoint - secondPoint).length <= tolerance.distance)
        }
    }

    private func torus(
        center: Point3D,
        axis: Vector3D,
        minorRadius: Double
    ) -> Surface3D {
        .analytic(.torus(
            center: center,
            axis: axis,
            majorRadius: 3.0,
            minorRadius: minorRadius
        ))
    }

    private func tiltedAxis() throws -> Vector3D {
        try Vector3D(x: 0.2, y: 0.0, z: 1.0).normalized(
            tolerance: tolerance.distance
        )
    }

    private func curves(
        _ intersections: [SurfaceSurfaceIntersection]
    ) -> [Curve3D] {
        intersections.compactMap { intersection in
            guard case let .curve(result) = intersection else { return nil }
            return result.curve
        }
    }
}
