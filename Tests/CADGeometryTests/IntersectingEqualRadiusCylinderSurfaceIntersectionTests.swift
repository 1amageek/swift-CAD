import CADCore
@testable import CADGeometry
import Foundation
import Testing

@Suite("Intersecting Equal-Radius Cylinder Surface Intersection")
struct IntersectingEqualRadiusCylinderSurfaceIntersectionTests {
    private let intersector = DefaultSurfaceSurfaceIntersector()
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func orthogonalAxesProduceTwoVerifiedMixedContactEllipses() throws {
        let first = cylinder(
            origin: Point3D(x: 0.0, y: 0.0, z: 3.0),
            axis: .unitZ,
            radius: 2.0
        )
        let second = cylinder(
            origin: Point3D(x: -2.0, y: 0.0, z: 0.0),
            axis: .unitX,
            radius: 2.0
        )

        let intersections = try intersector.intersections(
            first: first,
            second: second,
            tolerance: tolerance
        )

        #expect(intersections.count == 2)
        for intersection in intersections {
            guard case let .curve(result) = intersection,
                  case let .analytic(.ellipse(center, _, _, majorRadius, minorRadius)) = result.curve else {
                Issue.record("Intersecting equal-radius cylinders must produce exact ellipses.")
                continue
            }
            #expect(result.kind == .mixed)
            #expect(center.isApproximatelyEqual(to: .origin, tolerance: tolerance.distance))
            #expect(abs(majorRadius - 2.0 * sqrt(2.0)) <= tolerance.distance)
            #expect(abs(minorRadius - 2.0) <= tolerance.distance)
            #expect(result.maximumResidual <= tolerance.distance)
            let positiveContact = try result.curve.parameterProjection(
                of: Point3D(x: 0.0, y: 2.0, z: 0.0),
                tolerance: tolerance
            )
            let negativeContact = try result.curve.parameterProjection(
                of: Point3D(x: 0.0, y: -2.0, z: 0.0),
                tolerance: tolerance
            )
            #expect(positiveContact.residual <= tolerance.distance)
            #expect(negativeContact.residual <= tolerance.distance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func operandOrderPreservesDeterministicCurveGeometry() throws {
        let first = cylinder(origin: .origin, axis: .unitZ, radius: 1.5)
        let second = cylinder(origin: .origin, axis: .unitX, radius: 1.5)

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
