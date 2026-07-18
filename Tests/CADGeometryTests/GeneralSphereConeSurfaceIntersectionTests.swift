import Foundation
import CADCore
@testable import CADGeometry
import Testing

@Suite("General Sphere-Cone Surface Intersection", .serialized)
struct GeneralSphereConeSurfaceIntersectionTests {
    private let intersector = DefaultSurfaceSurfaceIntersector()
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func offsetConeInsideSphereProducesTwoVerifiedSplineCurves() throws {
        let sphere = sphere(radius: 3.0)
        let cone = cone(apex: Point3D(x: 1.0, y: 0.0, z: -4.0))

        let intersections = try intersector.intersections(
            first: sphere,
            second: cone,
            tolerance: tolerance
        )

        #expect(intersections.count == 2)
        for intersection in intersections {
            try verifyCurve(intersection, first: sphere, second: cone)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func separatedConeProducesNoIntersection() throws {
        let intersections = try intersector.intersections(
            first: sphere(radius: 1.0),
            second: cone(apex: Point3D(x: 8.0, y: 0.0, z: -4.0)),
            tolerance: tolerance
        )

        #expect(intersections.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func operandOrderPreservesDeterministicThreeDimensionalCurves() throws {
        let sphere = sphere(radius: 3.0)
        let cone = cone(apex: Point3D(x: 1.0, y: 0.0, z: -4.0))

        let forward = try intersector.intersections(
            first: sphere,
            second: cone,
            tolerance: tolerance
        )
        let reverse = try intersector.intersections(
            first: cone,
            second: sphere,
            tolerance: tolerance
        )

        #expect(curves(forward) == curves(reverse))
    }

    private func verifyCurve(
        _ intersection: SurfaceSurfaceIntersection,
        first: Surface3D,
        second: Surface3D
    ) throws {
        guard case let .curve(result) = intersection,
              case .bSpline = result.curve,
              case let .closed(lower, upper) = result.curve.parameterDomain else {
            Issue.record("A general sphere-cone intersection must produce a bounded B-spline curve.")
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

    private func sphere(radius: Double) -> Surface3D {
        .analytic(.sphere(center: .origin, radius: radius))
    }

    private func cone(apex: Point3D) -> Surface3D {
        .analytic(.cone(
            apex: apex,
            axis: .unitZ,
            halfAngle: atan(0.5)
        ))
    }

    private func curves(_ intersections: [SurfaceSurfaceIntersection]) -> [Curve3D] {
        intersections.compactMap { intersection in
            guard case let .curve(curve) = intersection else { return nil }
            return curve.curve
        }
    }
}
