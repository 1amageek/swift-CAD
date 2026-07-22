import Foundation
import CADCore
@testable import CADGeometry
import Testing

@Suite("General Torus-Torus Surface Intersection", .serialized)
struct GeneralTorusTorusSurfaceIntersectionTests {
    private let intersector = DefaultSurfaceSurfaceIntersector()
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func tiltedOffsetRingToriProduceTwoVerifiedClosedProceduralCurves() throws {
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

        let forwardCurves = try curves(forward)
        let reverseCurves = try curves(reverse)
        #expect(forwardCurves.count == reverseCurves.count)
        for (forwardCurve, reverseCurve) in zip(forwardCurves, reverseCurves) {
            try expectEquivalentGeometry(forwardCurve, reverseCurve)
        }
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
                error.code == .resourceLimitExceeded
                    || error.code == .singularSystem
                    || error.code == .singularGeometry
            )
            #expect(error.residual != nil)
            #expect(error.tolerance == tolerance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func proceduralTruthRoundTripsAndRetainsImplicitDifferentials() throws {
        let first = firstTorus()
        let second = try secondTorus()
        let intersections = try intersector.intersections(
            first: first,
            second: second,
            tolerance: tolerance
        )
        let intersection = try #require(intersections.first)
        guard case let .curve(result) = intersection,
              case let .analyticAnalytic(exact) = result.truth,
              case let .generalTorusTorus(proceduralCurve) = exact.definition,
              case let .bSpline(derivedCurve) = result.derivedRepresentation.curve else {
            Issue.record("Expected certified general torus-torus truth with a derived B-spline cache.")
            return
        }
        let encoded = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(
            SurfaceSurfaceIntersectionCurve.self,
            from: encoded
        )
        #expect(decoded == result)
        try decoded.validate(tolerance: tolerance)
        var unexpectedPayload = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        unexpectedPayload["unexpected"] = true
        let unexpectedData = try JSONSerialization.data(
            withJSONObject: unexpectedPayload
        )
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                SurfaceSurfaceIntersectionCurve.self,
                from: unexpectedData
            )
        }

        let firstPcurve = exact.firstSurfaceParameterCurve
        let secondPcurve = exact.secondSurfaceParameterCurve
        try firstPcurve.validate(on: first, tolerance: tolerance)
        try secondPcurve.validate(on: second, tolerance: tolerance)
        for fraction in [0.0, 0.125, 0.25, 0.5, 0.75, 0.875, 1.0] {
            let exactPoint = try proceduralCurve.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            let derivedPoint = try derivedCurve.point(
                at: fraction,
                tolerance: tolerance
            )
            let firstParameter = try firstPcurve.parameter(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            let secondParameter = try secondPcurve.parameter(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            let firstPoint = try first.point(
                u: firstParameter.u,
                v: firstParameter.v,
                tolerance: tolerance
            )
            let secondPoint = try second.point(
                u: secondParameter.u,
                v: secondParameter.v,
                tolerance: tolerance
            )
            #expect((exactPoint - derivedPoint).length <= tolerance.distance)
            #expect((exactPoint - firstPoint).length <= tolerance.distance)
            #expect((exactPoint - secondPoint).length <= tolerance.distance)
        }
        let step = 1.0e-4
        for fraction in [0.125, 0.375, 0.625, 0.875] {
            let differential = try proceduralCurve.differential(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            let lower = try proceduralCurve.point(
                atNormalizedFraction: fraction - step,
                tolerance: tolerance
            )
            let upper = try proceduralCurve.point(
                atNormalizedFraction: fraction + step,
                tolerance: tolerance
            )
            let finiteFirst = (upper - lower) / (2.0 * step)
            let finiteSecond = (
                (upper - differential.position)
                    + (lower - differential.position)
            ) / (step * step)
            #expect((finiteFirst - differential.firstDerivative).length
                <= 1.0e-6 * max(differential.firstDerivative.length, 1.0))
            #expect((finiteSecond - differential.secondDerivative).length
                <= 1.0e-4 * max(differential.secondDerivative.length, 1.0))
        }
        let start = try proceduralCurve.differential(
            atNormalizedFraction: 0.0,
            tolerance: tolerance
        )
        let end = try proceduralCurve.differential(
            atNormalizedFraction: 1.0,
            tolerance: tolerance
        )
        #expect((start.position - end.position).length <= tolerance.distance)
        #expect((start.firstDerivative - end.firstDerivative).length
            <= tolerance.relative * max(start.firstDerivative.length, 1.0))
        #expect((start.secondDerivative - end.secondDerivative).length
            <= tolerance.relative * max(start.secondDerivative.length, 1.0))
    }

    private func verifyCurve(
        _ intersection: SurfaceSurfaceIntersection,
        first: Surface3D,
        second: Surface3D
    ) throws {
        guard case let .curve(result) = intersection,
              case let .analyticAnalytic(exactTruth) = result.truth,
              case .generalTorusTorus = exactTruth.definition,
              case .surfaceLift = result.curve,
              case let .bSpline(derivedCurve) = result.derivedRepresentation.curve,
              case let .closed(lower, upper) = result.curve.parameterDomain else {
            Issue.record("A regular general torus-torus intersection must retain procedural truth and a derived B-spline cache.")
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
            let derivedPoint = try derivedCurve.point(
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
            #expect(curvePoint.isApproximatelyEqual(
                to: derivedPoint,
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

    private func expectEquivalentGeometry(
        _ first: Curve3D,
        _ second: Curve3D
    ) throws {
        guard case let .closed(firstLower, firstUpper) = first.parameterDomain,
              case let .closed(secondLower, secondUpper) = second.parameterDomain else {
            Issue.record("General torus-torus procedural curves must be closed.")
            return
        }
        for index in 0...16 {
            let fraction = Double(index) / 16.0
            let firstPoint = try first.point(
                at: firstLower + (firstUpper - firstLower) * fraction,
                tolerance: tolerance
            )
            let secondPoint = try second.point(
                at: secondLower + (secondUpper - secondLower) * fraction,
                tolerance: tolerance
            )
            #expect((firstPoint - secondPoint).length <= tolerance.distance)
        }
    }

    private func curves(
        _ intersections: [SurfaceSurfaceIntersection]
    ) throws -> [Curve3D] {
        try intersections.map { intersection in
            guard case let .curve(result) = intersection else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "Expected a general torus-torus curve intersection."
                )
            }
            return result.curve
        }
    }
}
