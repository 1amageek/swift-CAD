import CADCore
@testable import CADGeometry
import Foundation
import Testing

@Suite("General Cylinder-Cylinder Surface Intersection")
struct GeneralCylinderCylinderSurfaceIntersectionTests {
    private let intersector = DefaultSurfaceSurfaceIntersector()
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func unequalIntersectingAxesProduceTwoVerifiedSplineCurves() throws {
        let first = cylinder(origin: .origin, axis: .unitZ, radius: 2.0)
        let second = cylinder(origin: .origin, axis: .unitX, radius: 3.0)

        let intersections = try intersector.intersections(
            first: first,
            second: second,
            tolerance: tolerance
        )

        #expect(intersections.count == 2)
        for intersection in intersections {
            try verifyCurve(intersection, first: first, second: second)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func skewUnequalAxesProduceVerifiedDualPcurves() throws {
        let first = cylinder(
            origin: Point3D(x: 0.25, y: -0.5, z: 0.0),
            axis: .unitZ,
            radius: 2.25
        )
        let secondAxis = try Vector3D(x: 1.0, y: 0.25, z: 0.1).normalized(
            tolerance: tolerance.distance
        )
        let second = cylinder(
            origin: Point3D(x: -0.5, y: 0.75, z: 1.0),
            axis: secondAxis,
            radius: 1.5
        )

        let intersections = try intersector.intersections(
            first: first,
            second: second,
            tolerance: tolerance
        )

        #expect(intersections.isEmpty == false)
        for intersection in intersections {
            try verifyCurve(intersection, first: first, second: second)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func separatedSkewAxesProduceNoIntersection() throws {
        let intersections = try intersector.intersections(
            first: cylinder(origin: .origin, axis: .unitZ, radius: 1.0),
            second: cylinder(
                origin: Point3D(x: 0.0, y: 10.0, z: 0.0),
                axis: .unitX,
                radius: 1.0
            ),
            tolerance: tolerance
        )

        #expect(intersections.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func isolatedTangencyProducesVerifiedPoint() throws {
        let first = cylinder(origin: .origin, axis: .unitZ, radius: 1.0)
        let second = cylinder(
            origin: Point3D(x: 0.0, y: -2.0, z: 0.0),
            axis: .unitX,
            radius: 1.0
        )

        let intersections = try intersector.intersections(
            first: first,
            second: second,
            tolerance: tolerance
        )

        guard case let .point(point) = try #require(intersections.first) else {
            Issue.record("An isolated cylinder contact must produce a point.")
            return
        }
        #expect(intersections.count == 1)
        #expect(point.residual <= tolerance.distance)
        #expect(point.firstSurfaceParameter.residual <= tolerance.distance)
        #expect(point.secondSurfaceParameter.residual <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func operandOrderPreservesDeterministicThreeDimensionalCurves() throws {
        let first = cylinder(
            origin: Point3D(x: 0.0, y: 0.5, z: 0.25),
            axis: .unitZ,
            radius: 2.0
        )
        let second = cylinder(origin: .origin, axis: .unitX, radius: 2.75)

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
    func subdivisionExhaustionReturnsTypedResourceDiagnostic() throws {
        do {
            _ = try intersector.intersections(
                first: cylinder(origin: .origin, axis: .unitZ, radius: 20.0),
                second: cylinder(
                    origin: Point3D(x: 0.0, y: 2.0, z: 0.0),
                    axis: .unitX,
                    radius: 17.0
                ),
                options: SurfaceSurfaceIntersectionOptions(
                    maximumSubdivisionDepth: 0,
                    maximumIterations: 1,
                    maximumSeedCount: 1_024
                ),
                tolerance: tolerance
            )
            Issue.record("A zero-depth trace must not return an unverified curve.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .resourceLimitExceeded)
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
            Issue.record("A general cylinder intersection must produce a bounded B-spline curve.")
            return
        }
        #expect(result.maximumResidual <= tolerance.distance)
        try result.firstSurfaceParameterCurve.validate(on: first, tolerance: tolerance)
        try result.secondSurfaceParameterCurve.validate(on: second, tolerance: tolerance)

        for index in 0...32 {
            let fraction = Double(index) / 32.0
            let parameter = lower + (upper - lower) * fraction
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

    private func cylinder(origin: Point3D, axis: Vector3D, radius: Double) -> Surface3D {
        .analytic(.cylinder(origin: origin, axis: axis, radius: radius))
    }

    private func curves(_ intersections: [SurfaceSurfaceIntersection]) -> [Curve3D] {
        intersections.compactMap { intersection in
            guard case let .curve(curve) = intersection else { return nil }
            return curve.curve
        }
    }
}
