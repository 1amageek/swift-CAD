import Foundation
import CADCore
@testable import CADGeometry
import Testing

@Suite("General Cone-Cone Surface Intersection", .serialized)
struct GeneralConeConeSurfaceIntersectionTests {
    private let intersector = DefaultSurfaceSurfaceIntersector()
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func nonparallelAxesProduceTwoVerifiedClosedSplineCurves() throws {
        let first = referenceCone()
        let second = transverseCone()

        let intersections = try intersector.intersections(
            first: first,
            second: second,
            tolerance: tolerance
        )
        #expect(intersections.count == 2)
        for intersection in intersections {
            try verifyCurve(
                intersection,
                first: first,
                second: second
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func operandOrderPreservesDeterministicCurveGeometry() throws {
        let first = referenceCone()
        let second = transverseCone()
        let forward = try curves(intersector.intersections(
            first: first,
            second: second,
            tolerance: tolerance
        ))
        let reversed = try curves(intersector.intersections(
            first: second,
            second: first,
            tolerance: tolerance
        ))

        #expect(forward.count == reversed.count)
        for index in forward.indices {
            guard case let .closed(lower, upper) = forward[index].parameterDomain,
                  case let .closed(reversedLower, reversedUpper) = reversed[index].parameterDomain else {
                Issue.record("General cone-cone curves must remain closed after operand reversal.")
                continue
            }
            for sampleIndex in 0...16 {
                let fraction = Double(sampleIndex) / 16.0
                let firstPoint = try forward[index].point(
                    at: lower + (upper - lower) * fraction,
                    tolerance: tolerance
                )
                let secondPoint = try reversed[index].point(
                    at: reversedLower + (reversedUpper - reversedLower) * fraction,
                    tolerance: tolerance
                )
                #expect(firstPoint.isApproximatelyEqual(
                    to: secondPoint,
                    tolerance: tolerance.distance
                ))
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func partialAngularDomainsProduceVerifiedMixedSplineCurves() throws {
        let first = referenceCone()
        let second = Surface3D.analytic(.cone(
            apex: Point3D(x: 0.51, y: 0.0, z: 1.0),
            axis: .unitY,
            halfAngle: atan(0.375)
        ))

        let intersections = try intersector.intersections(
            first: first,
            second: second,
            tolerance: tolerance
        )
        let reversed = try intersector.intersections(
            first: second,
            second: first,
            tolerance: tolerance
        )
        let forwardCurves = try curves(intersections)
        let reversedCurves = try curves(reversed)

        #expect(intersections.count == 2)
        #expect(forwardCurves == reversedCurves)
        for intersection in intersections {
            try verifyCurve(
                intersection,
                first: first,
                second: second,
                expectedKind: .mixed
            )
        }
        for intersection in reversed {
            try verifyCurve(
                intersection,
                first: second,
                second: first,
                expectedKind: .mixed
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func apexContactReturnsTypedSingularGeometryDiagnostic() throws {
        let first = referenceCone()
        let second = Surface3D.analytic(.cone(
            apex: Point3D(x: 2.0, y: 0.0, z: 4.0),
            axis: .unitY,
            halfAngle: atan(0.375)
        ))

        do {
            _ = try intersector.intersections(
                first: first,
                second: second,
                tolerance: tolerance
            )
            Issue.record("Cone-apex contact must not produce a singular pcurve.")
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
        second: Surface3D,
        expectedKind: CurveSurfaceIntersectionKind = .transverse
    ) throws {
        guard case let .curve(result) = intersection,
              case .bSpline = result.curve,
              case let .closed(lower, upper) = result.curve.parameterDomain else {
            Issue.record("A regular general cone-cone intersection must produce a closed B-spline curve.")
            return
        }
        #expect(result.kind == expectedKind)
        #expect(result.maximumResidual <= tolerance.distance)
        try result.firstSurfaceParameterCurve.validate(
            on: first,
            tolerance: tolerance
        )
        try result.secondSurfaceParameterCurve.validate(
            on: second,
            tolerance: tolerance
        )

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

    private func referenceCone() -> Surface3D {
        .analytic(.cone(
            apex: .origin,
            axis: .unitZ,
            halfAngle: atan(0.5)
        ))
    }

    private func transverseCone() -> Surface3D {
        .analytic(.cone(
            apex: Point3D(x: 0.0, y: 0.0, z: 4.0),
            axis: .unitY,
            halfAngle: atan(0.375)
        ))
    }

    private func curves(
        _ intersections: [SurfaceSurfaceIntersection]
    ) throws -> [Curve3D] {
        try intersections.map { intersection in
            guard case let .curve(curve) = intersection else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "Expected a general cone-cone curve intersection."
                )
            }
            return curve.curve
        }
    }
}
