import Foundation
import CADCore
@testable import CADGeometry
import Testing

@Suite("General Cone-Torus Surface Intersection", .serialized)
struct GeneralConeTorusSurfaceIntersectionTests {
    private let intersector = DefaultSurfaceSurfaceIntersector()
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func tiltedWideConeProducesFourVerifiedClosedSplineCurves() throws {
        let cone = try coneSurface()
        let torus = torusSurface()

        let intersections = try intersector.intersections(
            first: cone,
            second: torus,
            tolerance: tolerance
        )

        #expect(intersections.count == 4)
        for intersection in intersections {
            try verifyCurve(intersection, first: cone, second: torus)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func operandOrderPreservesDeterministicThreeDimensionalCurves() throws {
        let cone = try coneSurface()
        let torus = torusSurface()

        let forward = try intersector.intersections(
            first: cone,
            second: torus,
            tolerance: tolerance
        )
        let reverse = try intersector.intersections(
            first: torus,
            second: cone,
            tolerance: tolerance
        )

        #expect(curves(forward) == curves(reverse))
    }

    @Test(.timeLimit(.minutes(1)))
    func apexContactReturnsTypedUnsupportedDiagnostic() throws {
        let axis = try tiltedAxis()
        let cone = Surface3D.analytic(.cone(
            apex: Point3D(x: 4.0, y: 0.0, z: 0.0),
            axis: axis,
            halfAngle: atan(6.0)
        ))

        do {
            _ = try intersector.intersections(
                first: cone,
                second: torusSurface(),
                tolerance: tolerance
            )
            Issue.record("Cone-torus apex contact must not produce a singular pcurve.")
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
        second: Surface3D
    ) throws {
        guard case let .curve(result) = intersection,
              case .bSpline = result.curve,
              case let .closed(lower, upper) = result.curve.parameterDomain else {
            Issue.record("A regular general cone-torus intersection must produce a closed B-spline curve.")
            return
        }
        #expect(result.kind == .transverse)
        #expect(result.maximumResidual <= tolerance.distance)
        try result.firstSurfaceParameterCurve.validate(on: first, tolerance: tolerance)
        try result.secondSurfaceParameterCurve.validate(on: second, tolerance: tolerance)

        for index in 0...16 {
            let parameter = lower + (upper - lower) * Double(index) / 16.0
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

    private func coneSurface() throws -> Surface3D {
        .analytic(.cone(
            apex: .origin,
            axis: try tiltedAxis(),
            halfAngle: atan(6.0)
        ))
    }

    private func torusSurface() -> Surface3D {
        .analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))
    }

    private func tiltedAxis() throws -> Vector3D {
        try Vector3D(x: 0.05, y: 0.0, z: 1.0).normalized(
            tolerance: tolerance.distance
        )
    }

    private func curves(
        _ intersections: [SurfaceSurfaceIntersection]
    ) -> [Curve3D] {
        intersections.compactMap { intersection in
            guard case let .curve(curve) = intersection else { return nil }
            return curve.curve
        }
    }
}
