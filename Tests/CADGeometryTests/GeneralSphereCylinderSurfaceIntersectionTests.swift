import CADCore
@testable import CADGeometry
import Testing

@Suite("General Sphere-Cylinder Surface Intersection")
struct GeneralSphereCylinderSurfaceIntersectionTests {
    private let intersector = DefaultSurfaceSurfaceIntersector()
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func offsetCylinderInsideSphereProducesTwoVerifiedSplineCurves() throws {
        let sphere = sphere(radius: 3.0)
        let cylinder = cylinder(axisOrigin: Point3D(x: 1.0, y: 0.0, z: 0.0), radius: 1.5)

        let intersections = try intersector.intersections(
            first: sphere,
            second: cylinder,
            tolerance: tolerance
        )

        #expect(intersections.count == 2)
        for intersection in intersections {
            try verifyCurve(
                intersection,
                first: sphere,
                second: cylinder,
                expectedKind: .transverse
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func partiallyIntersectingCylinderProducesOneMixedClosedCurve() throws {
        let sphere = sphere(radius: 2.0)
        let cylinder = cylinder(axisOrigin: Point3D(x: 2.0, y: 0.0, z: 0.0), radius: 1.0)

        let intersections = try intersector.intersections(
            first: sphere,
            second: cylinder,
            tolerance: tolerance
        )

        let intersection = try #require(intersections.first)
        #expect(intersections.count == 1)
        try verifyCurve(
            intersection,
            first: sphere,
            second: cylinder,
            expectedKind: .mixed
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func separatedCylinderProducesNoIntersection() throws {
        let intersections = try intersector.intersections(
            first: sphere(radius: 2.0),
            second: cylinder(
                axisOrigin: Point3D(x: 5.0, y: 0.0, z: 0.0),
                radius: 1.0
            ),
            tolerance: tolerance
        )

        #expect(intersections.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func subToleranceGapRemainsAnExactEmptyIntersection() throws {
        let gap = tolerance.distance * 0.5
        let intersections = try intersector.intersections(
            first: sphere(radius: 2.0),
            second: cylinder(
                axisOrigin: Point3D(x: 3.0 + gap, y: 0.0, z: 0.0),
                radius: 1.0
            ),
            tolerance: tolerance
        )

        #expect(intersections.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func externalTangencyProducesVerifiedPoint() throws {
        let sphere = sphere(radius: 2.0)
        let cylinder = cylinder(axisOrigin: Point3D(x: 3.0, y: 0.0, z: 0.0), radius: 1.0)

        let intersections = try intersector.intersections(
            first: sphere,
            second: cylinder,
            tolerance: tolerance
        )

        guard case let .point(point) = try #require(intersections.first) else {
            Issue.record("An externally tangent sphere and cylinder must produce one point.")
            return
        }
        #expect(intersections.count == 1)
        #expect(point.residual <= tolerance.distance)
        #expect(point.firstSurfaceParameter.residual <= tolerance.distance)
        #expect(point.secondSurfaceParameter.residual <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func operandOrderPreservesDeterministicThreeDimensionalCurves() throws {
        let sphere = sphere(radius: 3.0)
        let cylinder = cylinder(axisOrigin: Point3D(x: 1.0, y: 0.0, z: 0.0), radius: 1.5)

        let forward = try intersector.intersections(
            first: sphere,
            second: cylinder,
            tolerance: tolerance
        )
        let reverse = try intersector.intersections(
            first: cylinder,
            second: sphere,
            tolerance: tolerance
        )

        #expect(curves(forward) == curves(reverse))
    }

    @Test(.timeLimit(.minutes(1)))
    func arbitraryCylinderAxisProducesVerifiedDualPcurves() throws {
        let sphere = sphere(radius: 3.0)
        let axis = try Vector3D(x: 1.0, y: 0.3, z: 0.2).normalized(
            tolerance: tolerance.distance
        )
        let cylinder = cylinder(
            axisOrigin: Point3D(x: 0.0, y: 1.0, z: 0.0),
            axis: axis,
            radius: 1.5
        )

        let intersections = try intersector.intersections(
            first: sphere,
            second: cylinder,
            tolerance: tolerance
        )

        #expect(intersections.count == 2)
        for intersection in intersections {
            try verifyCurve(
                intersection,
                first: sphere,
                second: cylinder,
                expectedKind: .transverse
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func sphericalParameterPoleContactReturnsTypedDiagnostic() throws {
        do {
            _ = try intersector.intersections(
                first: sphere(radius: 2.0),
                second: cylinder(
                    axisOrigin: Point3D(x: 1.0, y: 0.0, z: 0.0),
                    radius: 1.0
                ),
                tolerance: tolerance
            )
            Issue.record("A spherical parameter-pole contact must not produce a singular pcurve.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .unsupportedCapability)
            #expect(error.residual != nil)
            #expect(error.tolerance == tolerance)
        }
    }

    private func verifyCurve(
        _ intersection: SurfaceSurfaceIntersection,
        first: Surface3D,
        second: Surface3D,
        expectedKind: CurveSurfaceIntersectionKind
    ) throws {
        guard case let .curve(result) = intersection,
              case .bSpline = result.curve,
              case let .closed(lower, upper) = result.curve.parameterDomain else {
            Issue.record("A general sphere-cylinder intersection must produce a bounded B-spline curve.")
            return
        }
        #expect(result.kind == expectedKind)
        #expect(result.maximumResidual <= tolerance.distance)
        try result.firstSurfaceParameterCurve.validate(on: first, tolerance: tolerance)
        try result.secondSurfaceParameterCurve.validate(on: second, tolerance: tolerance)

        for index in 0...16 {
            let parameter = lower + (upper - lower) * Double(index) / 16.0
            let curvePoint = try result.curve.point(at: parameter, tolerance: tolerance)
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
            #expect(curvePoint.isApproximatelyEqual(
                to: firstPoint,
                tolerance: tolerance.distance
            ))
            #expect(curvePoint.isApproximatelyEqual(
                to: secondPoint,
                tolerance: tolerance.distance
            ))
        }
    }

    private func sphere(radius: Double) -> Surface3D {
        .analytic(.sphere(center: .origin, radius: radius))
    }

    private func cylinder(
        axisOrigin: Point3D,
        axis: Vector3D = .unitZ,
        radius: Double
    ) -> Surface3D {
        .analytic(.cylinder(origin: axisOrigin, axis: axis, radius: radius))
    }

    private func curves(_ intersections: [SurfaceSurfaceIntersection]) -> [Curve3D] {
        intersections.compactMap { intersection in
            guard case let .curve(curve) = intersection else { return nil }
            return curve.curve
        }
    }
}
