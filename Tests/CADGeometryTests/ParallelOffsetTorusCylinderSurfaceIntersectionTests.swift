import CADCore
@testable import CADGeometry
import Testing

@Suite("Parallel-Offset Torus-Cylinder Surface Intersection")
struct ParallelOffsetTorusCylinderSurfaceIntersectionTests {
    private let intersector = DefaultSurfaceSurfaceIntersector()
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func cylinderInsideTubeBandProducesTwoVerifiedSplineCurves() throws {
        let torus = torus(majorRadius: 3.0, minorRadius: 1.5)
        let cylinder = cylinder(axisOrigin: Point3D(x: 3.0, y: 0.0, z: 0.0), radius: 0.5)

        let intersections = try intersector.intersections(
            first: torus,
            second: cylinder,
            tolerance: tolerance
        )

        #expect(intersections.count == 2)
        for intersection in intersections {
            try verifyCurve(
                intersection,
                first: torus,
                second: cylinder,
                expectedKind: .transverse
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func partialTubeBandProducesOneMixedClosedCurve() throws {
        let torus = torus(majorRadius: 3.0, minorRadius: 1.0)
        let cylinder = cylinder(axisOrigin: Point3D(x: 4.0, y: 0.0, z: 0.0), radius: 1.0)

        let intersections = try intersector.intersections(
            first: torus,
            second: cylinder,
            tolerance: tolerance
        )

        let intersection = try #require(intersections.first)
        #expect(intersections.count == 1)
        try verifyCurve(
            intersection,
            first: torus,
            second: cylinder,
            expectedKind: .mixed
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func separatedCylinderProducesNoIntersection() throws {
        let intersections = try intersector.intersections(
            first: torus(majorRadius: 3.0, minorRadius: 1.0),
            second: cylinder(
                axisOrigin: Point3D(x: 8.0, y: 0.0, z: 0.0),
                radius: 0.5
            ),
            tolerance: tolerance
        )

        #expect(intersections.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func externalTangencyProducesVerifiedPoint() throws {
        let first = torus(majorRadius: 3.0, minorRadius: 1.0)
        let second = cylinder(
            axisOrigin: Point3D(x: 5.0, y: 0.0, z: 0.0),
            radius: 1.0
        )

        let intersections = try intersector.intersections(
            first: first,
            second: second,
            tolerance: tolerance
        )

        guard case let .point(point) = try #require(intersections.first) else {
            Issue.record("An externally tangent torus and cylinder must produce one point.")
            return
        }
        #expect(intersections.count == 1)
        #expect(point.residual <= tolerance.distance)
        #expect(point.firstSurfaceParameter.residual <= tolerance.distance)
        #expect(point.secondSurfaceParameter.residual <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func operandOrderPreservesDeterministicThreeDimensionalCurves() throws {
        let torus = torus(majorRadius: 3.0, minorRadius: 1.5)
        let cylinder = cylinder(axisOrigin: Point3D(x: 3.0, y: 0.0, z: 0.0), radius: 0.5)

        let forward = try intersector.intersections(
            first: torus,
            second: cylinder,
            tolerance: tolerance
        )
        let reverse = try intersector.intersections(
            first: cylinder,
            second: torus,
            tolerance: tolerance
        )

        #expect(curves(forward) == curves(reverse))
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
            Issue.record("A parallel-offset torus-cylinder intersection must produce a bounded B-spline curve.")
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

    private func torus(majorRadius: Double, minorRadius: Double) -> Surface3D {
        .analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: majorRadius,
            minorRadius: minorRadius
        ))
    }

    private func cylinder(axisOrigin: Point3D, radius: Double) -> Surface3D {
        .analytic(.cylinder(origin: axisOrigin, axis: .unitZ, radius: radius))
    }

    private func curves(_ intersections: [SurfaceSurfaceIntersection]) -> [Curve3D] {
        intersections.compactMap { intersection in
            guard case let .curve(curve) = intersection else { return nil }
            return curve.curve
        }
    }
}
