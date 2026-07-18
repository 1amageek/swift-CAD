import CADCore
@testable import CADGeometry
import Testing

@Suite("General Torus-Cylinder Surface Intersection")
struct GeneralTorusCylinderSurfaceIntersectionTests {
    private let intersector = DefaultSurfaceSurfaceIntersector()
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func tiltedCylinderProducesVerifiedClosedSplineCurves() throws {
        let torus = torusSurface()
        let cylinder = try tiltedCylinderSurface()

        let intersections = try intersector.intersections(
            first: torus,
            second: cylinder,
            tolerance: tolerance
        )

        #expect(intersections.count == 2)
        for intersection in intersections {
            try verifyCurve(intersection, first: torus, second: cylinder)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func operandOrderPreservesDeterministicThreeDimensionalCurves() throws {
        let torus = torusSurface()
        let cylinder = try tiltedCylinderSurface()

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

    @Test(.timeLimit(.minutes(1)))
    func separatedTiltedCylinderProducesExactEmptyIntersection() throws {
        let axis = try Vector3D(x: 0.08, y: 0.0, z: 1.0).normalized(
            tolerance: tolerance.distance
        )
        let intersections = try intersector.intersections(
            first: torusSurface(),
            second: .analytic(.cylinder(
                origin: Point3D(x: 10.0, y: 0.0, z: 0.0),
                axis: axis,
                radius: 1.0
            )),
            tolerance: tolerance
        )

        #expect(intersections.isEmpty)
    }

    private func verifyCurve(
        _ intersection: SurfaceSurfaceIntersection,
        first: Surface3D,
        second: Surface3D
    ) throws {
        guard case let .curve(result) = intersection,
              case .bSpline = result.curve,
              case let .closed(lower, upper) = result.curve.parameterDomain else {
            Issue.record("A regular non-parallel torus-cylinder intersection must produce a closed B-spline curve.")
            return
        }
        #expect(result.kind == .transverse)
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

    private func torusSurface() -> Surface3D {
        .analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))
    }

    private func tiltedCylinderSurface() throws -> Surface3D {
        let axis = try Vector3D(x: 0.08, y: 0.0, z: 1.0).normalized(
            tolerance: tolerance.distance
        )
        return .analytic(.cylinder(
            origin: .origin,
            axis: axis,
            radius: 3.0
        ))
    }

    private func curves(_ intersections: [SurfaceSurfaceIntersection]) -> [Curve3D] {
        intersections.compactMap { intersection in
            guard case let .curve(curve) = intersection else { return nil }
            return curve.curve
        }
    }
}
