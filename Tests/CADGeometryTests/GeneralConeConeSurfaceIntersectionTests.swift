import Foundation
import CADCore
@testable import CADGeometry
import Testing

@Suite("General Cone-Cone Surface Intersection", .serialized)
struct GeneralConeConeSurfaceIntersectionTests {
    private let intersector = DefaultSurfaceSurfaceIntersector()
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func nonparallelAxesProduceTwoVerifiedClosedProceduralCurves() throws {
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
    func partialAngularDomainsProduceVerifiedMixedProceduralCurves() throws {
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
        #expect(forwardCurves.count == reversedCurves.count)
        for index in forwardCurves.indices {
            try expectEquivalentGeometry(
                forwardCurves[index],
                reversedCurves[index]
            )
        }
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
    func proceduralTruthRoundTripsAndRetainsBranchJoinDifferentials() throws {
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

        for intersection in intersections {
            guard case let .curve(result) = intersection,
                  case let .analyticAnalytic(exact) = result.truth,
                  case .coneCone = exact.definition,
                  case let .bSpline(derivedCurve) = result.derivedRepresentation.curve else {
                Issue.record("Expected certified cone-cone truth with a derived B-spline cache.")
                continue
            }
            let encoded = try JSONEncoder().encode(result)
            let decoded = try JSONDecoder().decode(
                SurfaceSurfaceIntersectionCurve.self,
                from: encoded
            )
            #expect(decoded == result)
            try decoded.validate(tolerance: tolerance)

            let exactFirstPcurve = exact.firstSurfaceParameterCurve
            let exactSecondPcurve = exact.secondSurfaceParameterCurve
            try exactFirstPcurve.validate(on: first, tolerance: tolerance)
            try exactSecondPcurve.validate(on: second, tolerance: tolerance)
            for fraction in [0.0, 0.0001, 0.25, 0.5, 0.5001, 0.75, 1.0] {
                let geometry = try result.curve.differentialGeometry(
                    at: fraction,
                    tolerance: tolerance
                )
                #expect(geometry.firstDerivative.length > tolerance.distance)
                let firstParameter = try exactFirstPcurve.parameter(
                    atNormalizedFraction: fraction,
                    tolerance: tolerance
                )
                let secondParameter = try exactSecondPcurve.parameter(
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
                let derivedPoint = try derivedCurve.point(
                    at: fraction,
                    tolerance: tolerance
                )
                #expect((geometry.position - firstPoint).length <= tolerance.distance)
                #expect((geometry.position - secondPoint).length <= tolerance.distance)
                #expect((geometry.position - derivedPoint).length <= tolerance.distance)
            }
            let start = try result.curve.differentialGeometry(
                at: 0.0,
                tolerance: tolerance
            )
            let end = try result.curve.differentialGeometry(
                at: 1.0,
                tolerance: tolerance
            )
            #expect((start.position - end.position).length <= tolerance.distance)
            #expect((start.firstDerivative - end.firstDerivative).length
                <= tolerance.relative * max(start.firstDerivative.length, 1.0))
            #expect((start.secondDerivative - end.secondDerivative).length
                <= tolerance.relative * max(start.secondDerivative.length, 1.0))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func isolatedNonApexTangenciesProduceVerifiedPoints() throws {
        let first = referenceCone()
        let second = Surface3D.analytic(.cone(
            apex: Point3D(x: 0.5436419397953523, y: 0.0, z: 1.0),
            axis: .unitY,
            halfAngle: atan(0.375)
        ))

        let forward = try intersector.intersections(
            first: first,
            second: second,
            tolerance: tolerance
        )
        let reversed = try intersector.intersections(
            first: second,
            second: first,
            tolerance: tolerance
        )
        let forwardPoints = try intersectionPoints(forward)
        let reversedPoints = try intersectionPoints(reversed)

        #expect(forward.count == 2)
        #expect(reversed.count == forward.count)
        for index in forwardPoints.indices {
            #expect(forwardPoints[index].isApproximatelyEqual(
                to: reversedPoints[index],
                tolerance: tolerance.distance
            ))
        }
        for intersection in forward {
            try verifyPoint(intersection, first: first, second: second)
        }
        for intersection in reversed {
            try verifyPoint(intersection, first: second, second: first)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func apexContactProducesTwoCertifiedGraphLoops() throws {
        let first = referenceCone()
        let second = Surface3D.analytic(.cone(
            apex: Point3D(x: 2.0, y: 0.0, z: 4.0),
            axis: .unitY,
            halfAngle: atan(0.375)
        ))
        let apex = Point3D(x: 2.0, y: 0.0, z: 4.0)

        for operands in [(first, second), (second, first)] {
            let intersections = try intersector.intersections(
                first: operands.0,
                second: operands.1,
                tolerance: tolerance
            )
            #expect(intersections.count == 2)
            var interiorPoints: [Point3D] = []
            for intersection in intersections {
                guard case let .curve(result) = intersection,
                      case let .analyticAnalytic(exact) = result.truth,
                      case let .coneCone(procedural) = exact.definition,
                      case .certifiedIntersection(.coneCone) = result.curve else {
                    Issue.record("A cone-cone apex contact must retain direct certified graph truth.")
                    continue
                }
                #expect(procedural.componentKind == .apexReducedAngularInterval)
                #expect(result.kind == .mixed)
                #expect(result.maximumResidual <= tolerance.distance)
                let decoded = try JSONDecoder().decode(
                    SurfaceSurfaceIntersectionCurve.self,
                    from: JSONEncoder().encode(result)
                )
                #expect(decoded == result)
                try decoded.validate(tolerance: tolerance)

                for fraction in [
                    0.0, 1.0e-8, 0.25, 0.5, 0.75, 1.0 - 1.0e-8, 1.0,
                ] {
                    let geometry = try result.curve.differentialGeometry(
                        at: fraction,
                        tolerance: tolerance
                    )
                    #expect(geometry.firstDerivative.length > tolerance.distance)
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
                    #expect(geometry.position.isApproximatelyEqual(
                        to: firstPoint,
                        tolerance: tolerance.distance
                    ))
                    #expect(geometry.position.isApproximatelyEqual(
                        to: secondPoint,
                        tolerance: tolerance.distance
                    ))
                    if fraction == 0.0 || fraction == 1.0 {
                        #expect(geometry.position.isApproximatelyEqual(
                            to: apex,
                            tolerance: tolerance.distance
                        ))
                    }
                    if fraction == 0.5 {
                        interiorPoints.append(geometry.position)
                    }
                }
            }
            #expect(interiorPoints.count == 2)
            #expect(interiorPoints[0].isApproximatelyEqual(
                to: interiorPoints[1],
                tolerance: tolerance.distance
            ) == false)
        }
    }

    private func verifyCurve(
        _ intersection: SurfaceSurfaceIntersection,
        first: Surface3D,
        second: Surface3D,
        expectedKind: CurveSurfaceIntersectionKind = .transverse
    ) throws {
        guard case let .curve(result) = intersection,
              case let .analyticAnalytic(exactTruth) = result.truth,
              case .coneCone = exactTruth.definition,
              case .surfaceLift = result.curve,
              case .bSpline = result.derivedRepresentation.curve,
              case let .closed(lower, upper) = result.curve.parameterDomain else {
            Issue.record("A regular general cone-cone intersection must retain procedural truth and a derived B-spline cache.")
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

    private func expectEquivalentGeometry(
        _ first: Curve3D,
        _ second: Curve3D
    ) throws {
        guard case let .closed(firstLower, firstUpper) = first.parameterDomain,
              case let .closed(secondLower, secondUpper) = second.parameterDomain else {
            Issue.record("General cone-cone procedural curves must be bounded and closed.")
            return
        }
        for sampleIndex in 0...16 {
            let fraction = Double(sampleIndex) / 16.0
            let firstPoint = try first.point(
                at: firstLower + (firstUpper - firstLower) * fraction,
                tolerance: tolerance
            )
            let secondPoint = try second.point(
                at: secondLower + (secondUpper - secondLower) * fraction,
                tolerance: tolerance
            )
            #expect(firstPoint.isApproximatelyEqual(
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

    private func verifyPoint(
        _ intersection: SurfaceSurfaceIntersection,
        first: Surface3D,
        second: Surface3D
    ) throws {
        guard case let .point(result) = intersection else {
            Issue.record("An isolated cone-cone tangency must produce a point.")
            return
        }
        #expect(result.residual <= tolerance.distance)
        let firstPoint = try first.point(
            u: result.firstSurfaceParameter.u,
            v: result.firstSurfaceParameter.v,
            tolerance: tolerance
        )
        let secondPoint = try second.point(
            u: result.secondSurfaceParameter.u,
            v: result.secondSurfaceParameter.v,
            tolerance: tolerance
        )
        let firstGeometry = try first.differentialGeometry(
            atU: result.firstSurfaceParameter.u,
            v: result.firstSurfaceParameter.v,
            tolerance: tolerance
        )
        let secondGeometry = try second.differentialGeometry(
            atU: result.secondSurfaceParameter.u,
            v: result.secondSurfaceParameter.v,
            tolerance: tolerance
        )
        #expect((result.point - firstPoint).length <= tolerance.distance)
        #expect((result.point - secondPoint).length <= tolerance.distance)
        #expect(firstGeometry.normal.cross(secondGeometry.normal).length <= tolerance.angle)
    }

    private func intersectionPoints(
        _ intersections: [SurfaceSurfaceIntersection]
    ) throws -> [Point3D] {
        try intersections.map { intersection in
            guard case let .point(point) = intersection else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "Expected an isolated general cone-cone contact point."
                )
            }
            return point.point
        }.sorted { first, second in
            [first.x, first.y, first.z].lexicographicallyPrecedes([
                second.x,
                second.y,
                second.z,
            ])
        }
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
