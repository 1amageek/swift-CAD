import Foundation
import CADCore
@testable import CADGeometry
import Testing

@Suite("General Torus-Torus Surface Intersection", .serialized)
struct GeneralTorusTorusSurfaceIntersectionTests {
    private let intersector = DefaultSurfaceSurfaceIntersector()
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func tiltedOffsetRingToriProduceTwoVerifiedClosedSplineCurves() throws {
        let first = firstTorus()
        let second = try secondTorus()

        let intersections = try intersector.intersections(
            first: first,
            second: second,
            tolerance: tolerance
        )

        #expect(intersections.count == 2)
        for intersection in intersections {
            try verifyCurve(intersection, first: first, second: second)
        }

        let boundaryContacts = try DefaultCurveSurfaceIntersector().intersections(
            curve: .circle(Circle3D(
                center: .origin,
                normal: .unitZ,
                radius: 4.0
            )),
            surface: second,
            options: .init(),
            tolerance: tolerance
        )
        #expect(boundaryContacts.count == 2)
        for contact in boundaryContacts {
            var matched = false
            for intersection in intersections {
                guard case let .curve(curve) = intersection else { continue }
                do {
                    _ = try curve.curve.parameterProjection(
                        of: contact.point,
                        tolerance: tolerance
                    )
                    matched = true
                    break
                } catch let error as KernelError where error.code == .intersectionFailure {
                    continue
                }
            }
            #expect(matched)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func operandOrderPreservesDeterministicThreeDimensionalCurves() throws {
        let first = firstTorus()
        let second = try secondTorus()

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
    func meridianSingularityReturnsTypedDiagnostic() throws {
        let orthogonal = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitX,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))

        do {
            _ = try intersector.intersections(
                first: firstTorus(),
                second: orthogonal,
                tolerance: tolerance
            )
            Issue.record("A singular torus-torus meridian envelope must not be approximated.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(
                error.code == .unsupportedCapability
                    || error.code == .resourceLimitExceeded
                    || error.code == .singularSystem
            )
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
            Issue.record("A regular general torus-torus intersection must produce a closed B-spline curve.")
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

    private func firstTorus() -> Surface3D {
        .analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))
    }

    private func secondTorus() throws -> Surface3D {
        .analytic(.torus(
            center: Point3D(x: 1.2, y: 0.2, z: 0.5),
            axis: try Vector3D(x: 0.25, y: 0.1, z: 1.0).normalized(
                tolerance: tolerance.distance
            ),
            majorRadius: 3.4,
            minorRadius: 0.7
        ))
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
