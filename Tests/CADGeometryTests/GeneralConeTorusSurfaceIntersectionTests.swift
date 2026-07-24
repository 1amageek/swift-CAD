import Foundation
import CADCore
@testable import CADGeometry
import Testing

@Suite("General Cone-Torus Surface Intersection", .serialized)
struct GeneralConeTorusSurfaceIntersectionTests {
    private let intersector = DefaultSurfaceSurfaceIntersector()
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(3)))
    func tiltedWideConeProducesFourVerifiedClosedProceduralCurves() throws {
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

    @Test(.timeLimit(.minutes(4)))
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

        let forwardCurves = curves(forward)
        let reverseCurves = curves(reverse)
        #expect(forwardCurves.count == reverseCurves.count)
        for (forwardCurve, reverseCurve) in zip(forwardCurves, reverseCurves) {
            try expectEquivalentGeometry(forwardCurve, reverseCurve)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func apexContactProducesThreeCertifiedFactoredCubicComponents() throws {
        let axis = try tiltedAxis()
        let cone = Surface3D.analytic(.cone(
            apex: Point3D(x: 4.0, y: 0.0, z: 0.0),
            axis: axis,
            halfAngle: atan(6.0)
        ))
        let torus = torusSurface()

        for operands in [(cone, torus), (torus, cone)] {
            let intersections = try intersector.intersections(
                first: operands.0,
                second: operands.1,
                tolerance: tolerance
            )
            #expect(intersections.count == 3)
            for intersection in intersections {
                guard case let .curve(result) = intersection,
                      case let .analyticAnalytic(exact) = result.truth,
                      case let .generalConeTorus(procedural) = exact.definition,
                      case .certifiedIntersection(.coneTorus) = result.curve,
                      procedural.apexReduction != nil else {
                    Issue.record("A cone-torus apex contact must retain exact factored-cubic truth.")
                    continue
                }
                #expect(result.kind == .mixed)
                #expect(result.maximumResidual <= tolerance.distance)
                let data = try JSONEncoder().encode(result)
                let decoded = try JSONDecoder().decode(
                    SurfaceSurfaceIntersectionCurve.self,
                    from: data
                )
                #expect(decoded == result)
                try decoded.validate(tolerance: tolerance)

                for fraction in [0.0, 0.125, 0.25, 0.5, 0.75, 0.875, 1.0] {
                    let point = try result.curve.point(
                        at: fraction,
                        tolerance: tolerance
                    )
                    let differential = try result.curve.differentialGeometry(
                        at: fraction,
                        tolerance: tolerance
                    )
                    #expect(differential.position.isApproximatelyEqual(
                        to: point,
                        tolerance: tolerance.distance
                    ))
                    #expect(differential.firstDerivative.length > tolerance.distance)
                    let firstUV = try result.firstSurfaceParameterCurve.parameter(
                        atNormalizedFraction: fraction,
                        tolerance: tolerance
                    )
                    let secondUV = try result.secondSurfaceParameterCurve.parameter(
                        atNormalizedFraction: fraction,
                        tolerance: tolerance
                    )
                    let firstPoint = try operands.0.point(
                        u: firstUV.u,
                        v: firstUV.v,
                        tolerance: tolerance
                    )
                    let secondPoint = try operands.1.point(
                        u: secondUV.u,
                        v: secondUV.v,
                        tolerance: tolerance
                    )
                    #expect(point.isApproximatelyEqual(
                        to: firstPoint,
                        tolerance: tolerance.distance
                    ))
                    #expect(point.isApproximatelyEqual(
                        to: secondPoint,
                        tolerance: tolerance.distance
                    ))
                }
            }
        }
    }

    @Test(.timeLimit(.minutes(3)))
    func proceduralTruthRoundTripsAndRetainsImplicitDifferentials() throws {
        let cone = try coneSurface()
        let torus = torusSurface()
        let intersections = try intersector.intersections(
            first: cone,
            second: torus,
            tolerance: tolerance
        )

        let intersection = try #require(intersections.first)
        guard case let .curve(result) = intersection,
              case let .analyticAnalytic(exact) = result.truth,
              case let .generalConeTorus(proceduralCurve) = exact.definition,
              case let .bSpline(derivedCurve) = result.derivedRepresentation.curve else {
            Issue.record("Expected certified general cone-torus truth with a derived B-spline cache.")
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

        let exactConePcurve = exact.firstSurfaceParameterCurve
        let exactTorusPcurve = exact.secondSurfaceParameterCurve
        try exactConePcurve.validate(on: cone, tolerance: tolerance)
        try exactTorusPcurve.validate(on: torus, tolerance: tolerance)
        for fraction in [0.0, 0.125, 0.25, 0.5, 0.75, 0.875, 1.0] {
            let exactPoint = try proceduralCurve.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            let derivedPoint = try derivedCurve.point(
                at: fraction,
                tolerance: tolerance
            )
            let coneParameter = try exactConePcurve.parameter(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            let torusParameter = try exactTorusPcurve.parameter(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            let conePoint = try cone.point(
                u: coneParameter.u,
                v: coneParameter.v,
                tolerance: tolerance
            )
            let torusPoint = try torus.point(
                u: torusParameter.u,
                v: torusParameter.v,
                tolerance: tolerance
            )
            #expect((exactPoint - derivedPoint).length <= tolerance.distance)
            #expect((exactPoint - conePoint).length <= tolerance.distance)
            #expect((exactPoint - torusPoint).length <= tolerance.distance)
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
        #expect(start.position == end.position)
        #expect((start.firstDerivative - end.firstDerivative).length
            <= tolerance.relative * max(start.firstDerivative.length, 1.0))
        #expect((start.secondDerivative - end.secondDerivative).length
            <= tolerance.relative * max(start.secondDerivative.length, 1.0))
    }

    @Test(.timeLimit(.minutes(2)))
    func rotatedAxesRetainCertifiedBranchGeometry() throws {
        let torusAxis = try Vector3D(x: 0.2, y: 0.3, z: 1.0).normalized(
            tolerance: tolerance.distance
        )
        let radial = try torusAxis.cross(.unitX).normalized(
            tolerance: tolerance.distance
        )
        let coneAxis = try (torusAxis + radial * 0.05).normalized(
            tolerance: tolerance.distance
        )
        let cone = Surface3D.analytic(.cone(
            apex: Point3D(x: 0.5, y: -0.25, z: 0.75),
            axis: coneAxis,
            halfAngle: atan(6.0)
        ))
        let torus = Surface3D.analytic(.torus(
            center: Point3D(x: 0.5, y: -0.25, z: 0.75),
            axis: torusAxis,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))
        let curve = try CertifiedGeneralConeTorusIntersectionCurve(
            coneSurface: cone,
            torusSurface: torus,
            branchIndex: 0,
            tolerance: tolerance
        )

        #expect(curve.branchCount == 4)
        for fraction in [0.0, 0.125, 0.25, 0.5, 0.75, 0.875, 1.0] {
            let point = try curve.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            let coneProjection = try cone.parameterProjection(
                of: point,
                tolerance: tolerance
            )
            let torusProjection = try torus.parameterProjection(
                of: point,
                tolerance: tolerance
            )
            #expect(coneProjection.residual <= curve.maximumResidualUpperBound)
            #expect(torusProjection.residual <= curve.maximumResidualUpperBound)
        }
    }

    private func verifyCurve(
        _ intersection: SurfaceSurfaceIntersection,
        first: Surface3D,
        second: Surface3D
    ) throws {
        guard case let .curve(result) = intersection,
              case let .analyticAnalytic(exactTruth) = result.truth,
              case .generalConeTorus = exactTruth.definition,
              case .surfaceLift = result.curve,
              case let .bSpline(derivedCurve) = result.derivedRepresentation.curve,
              case let .closed(lower, upper) = result.curve.parameterDomain else {
            Issue.record("A regular general cone-torus intersection must retain procedural truth and a derived B-spline cache.")
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

    private func expectEquivalentGeometry(
        _ first: Curve3D,
        _ second: Curve3D
    ) throws {
        guard case let .closed(firstLower, firstUpper) = first.parameterDomain,
              case let .closed(secondLower, secondUpper) = second.parameterDomain else {
            Issue.record("General cone-torus procedural curves must be closed.")
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
}
