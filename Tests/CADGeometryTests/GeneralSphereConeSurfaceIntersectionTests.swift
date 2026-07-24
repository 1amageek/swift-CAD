import Foundation
import CADCore
@testable import CADGeometry
import Testing

@Suite("General Sphere-Cone Surface Intersection", .serialized)
struct GeneralSphereConeSurfaceIntersectionTests {
    private let intersector = DefaultSurfaceSurfaceIntersector()
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func offsetConeInsideSphereProducesTwoVerifiedProceduralCurves() throws {
        let sphere = sphere(radius: 3.0)
        let cone = cone(apex: Point3D(x: 1.0, y: 0.0, z: -4.0))

        let intersections = try intersector.intersections(
            first: sphere,
            second: cone,
            tolerance: tolerance
        )

        #expect(intersections.count == 2)
        for intersection in intersections {
            try verifyCurve(
                intersection,
                first: sphere,
                second: cone,
                expectedKind: .transverse
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func partiallyIntersectingConeProducesOneMixedClosedCurve() throws {
        let sphere = sphere(radius: 2.0)
        let cone = cone(apex: Point3D(x: 2.0, y: 0.0, z: -4.0))

        let intersections = try intersector.intersections(
            first: sphere,
            second: cone,
            tolerance: tolerance
        )

        let intersection = try #require(intersections.first)
        #expect(intersections.count == 1)
        try verifyCurve(
            intersection,
            first: sphere,
            second: cone,
            expectedKind: .mixed
        )
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

        let forwardCurves = try curves(forward)
        let reverseCurves = try curves(reverse)
        #expect(forwardCurves.count == reverseCurves.count)
        for (forwardCurve, reverseCurve) in zip(forwardCurves, reverseCurves) {
            try expectEquivalentGeometry(forwardCurve, reverseCurve)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func proceduralTruthRoundTripsAndRetainsBranchJoinDifferentials() throws {
        let sphere = sphere(radius: 2.0)
        let cone = cone(apex: Point3D(x: 2.0, y: 0.0, z: -4.0))
        let intersections = try intersector.intersections(
            first: sphere,
            second: cone,
            tolerance: tolerance
        )

        for intersection in intersections {
            guard case let .curve(result) = intersection,
                  case let .analyticAnalytic(exact) = result.truth,
                  case .sphereCone = exact.definition,
                  case let .bSpline(derivedCurve) = result.derivedRepresentation.curve else {
                Issue.record("Expected certified sphere-cone truth with a derived B-spline cache.")
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
            try exactFirstPcurve.validate(on: sphere, tolerance: tolerance)
            try exactSecondPcurve.validate(on: cone, tolerance: tolerance)
            for fraction in [0.0, 0.0001, 0.25, 0.4999, 0.5, 0.5001, 0.75, 1.0] {
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
                let firstPoint = try sphere.point(
                    u: firstParameter.u,
                    v: firstParameter.v,
                    tolerance: tolerance
                )
                let secondPoint = try cone.point(
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
    func coneApexContactProducesTwoCertifiedGraphLoops() throws {
        let sphere = sphere(radius: 1.0)
        let cone = cone(apex: Point3D(x: 1.0, y: 0.0, z: 0.0))
        let apex = Point3D(x: 1.0, y: 0.0, z: 0.0)

        for operands in [(sphere, cone), (cone, sphere)] {
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
                      case let .sphereCone(procedural) = exact.definition,
                      case .certifiedIntersection(.sphereCone) = result.curve else {
                    Issue.record("A cone-apex contact must retain direct certified sphere-cone graph truth.")
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

                for fraction in [0.0, 1.0e-8, 0.25, 0.5, 0.75, 1.0 - 1.0e-8, 1.0] {
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

    @Test(.timeLimit(.minutes(1)))
    func sphericalPoleContactsProduceCertifiedOpenBranchesInBothOrders() throws {
        let sphere = sphere(radius: 2.0)
        let cone = cone(apex: Point3D(x: 1.0, y: 0.0, z: 0.0))

        for operands in [(first: sphere, second: cone), (first: cone, second: sphere)] {
            let intersections = try intersector.intersections(
                first: operands.first,
                second: operands.second,
                tolerance: tolerance
            )
            #expect(intersections.count == 2)
            var endpoints: [Point3D] = []
            var openCount = 0

            for intersection in intersections {
                guard case let .curve(result) = intersection,
                      case let .analyticAnalytic(exact) = result.truth,
                      case let .sphereCone(procedural) = exact.definition,
                      case let .bSpline(derived) = result.derivedRepresentation.curve,
                      case let .closed(lower, upper) = result.curve.parameterDomain else {
                    Issue.record("A spherical-pole intersection must retain exact open sphere-cone truth and a derived B-spline cache.")
                    continue
                }
                let invalidFullKind: String
                switch procedural.componentKind {
                case .negativeOpenAngularInterval:
                    invalidFullKind = "negativeFullBranch"
                    openCount += 1
                case .positiveOpenAngularInterval:
                    invalidFullKind = "positiveFullBranch"
                    openCount += 1
                case .negativeFullBranch, .positiveFullBranch,
                     .boundedAngularInterval, .apexReducedAngularInterval:
                    invalidFullKind = "positiveFullBranch"
                    Issue.record("A spherical-pole graph edge must use an open angular component.")
                }
                #expect(result.kind == .transverse)
                #expect(result.maximumResidual <= tolerance.distance)
                let decoded = try JSONDecoder().decode(
                    SurfaceSurfaceIntersectionCurve.self,
                    from: JSONEncoder().encode(result)
                )
                #expect(decoded == result)
                var invalidPayload = try #require(
                    JSONSerialization.jsonObject(
                        with: JSONEncoder().encode(procedural)
                    ) as? [String: Any]
                )
                invalidPayload["componentKind"] = invalidFullKind
                #expect(throws: KernelError.self) {
                    _ = try JSONDecoder().decode(
                        CertifiedSphereConeIntersectionCurve.self,
                        from: JSONSerialization.data(withJSONObject: invalidPayload)
                    )
                }

                for fraction in [
                    0.0, 1.0e-8, 0.125, 0.5, 0.875, 1.0 - 1.0e-8, 1.0,
                ] {
                    let parameter = lower + (upper - lower) * fraction
                    let geometry = try procedural.differential(
                        atNormalizedFraction: fraction,
                        tolerance: tolerance
                    )
                    #expect(geometry.firstDerivative.length > tolerance.distance)
                    let curvePoint = try result.curve.point(
                        at: parameter,
                        tolerance: tolerance
                    )
                    let derivedPoint = try derived.point(
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
                    let firstPoint = try operands.first.point(
                        u: firstUV.u,
                        v: firstUV.v,
                        tolerance: tolerance
                    )
                    let secondPoint = try operands.second.point(
                        u: secondUV.u,
                        v: secondUV.v,
                        tolerance: tolerance
                    )
                    #expect(curvePoint.isApproximatelyEqual(
                        to: geometry.position,
                        tolerance: tolerance.distance
                    ))
                    #expect(curvePoint.isApproximatelyEqual(
                        to: derivedPoint,
                        tolerance: tolerance.distance
                    ))
                    #expect(curvePoint.isApproximatelyEqual(
                        to: firstPoint,
                        tolerance: tolerance.distance
                    ))
                    #expect(curvePoint.isApproximatelyEqual(
                        to: secondPoint,
                        tolerance: tolerance.distance
                    ))
                    if fraction == 0.0 || fraction == 1.0 {
                        endpoints.append(curvePoint)
                        #expect(abs(abs(curvePoint.z) - 2.0) <= tolerance.distance)
                    }
                }
            }

            #expect(openCount == 2)
            var uniqueEndpoints: [Point3D] = []
            for point in endpoints where uniqueEndpoints.contains(where: {
                $0.isApproximatelyEqual(to: point, tolerance: tolerance.distance)
            }) == false {
                uniqueEndpoints.append(point)
            }
            #expect(uniqueEndpoints.count == 2)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func boundedComponentCrossingSphericalPoleProducesCompleteOpenGraph() throws {
        let sphere = sphere(radius: 2.0)
        let cone = cone(apex: Point3D(x: 3.0, y: 0.0, z: -4.0))

        for operands in [(first: sphere, second: cone), (first: cone, second: sphere)] {
            let intersections = try intersector.intersections(
                first: operands.first,
                second: operands.second,
                tolerance: tolerance
            )
            #expect(intersections.count == 3)
            var endpoints: [Point3D] = []
            var poleEndpointCount = 0

            for intersection in intersections {
                guard case let .curve(result) = intersection,
                      case let .analyticAnalytic(exact) = result.truth,
                      case let .sphereCone(procedural) = exact.definition else {
                    Issue.record("A bounded spherical-pole crossing must retain exact sphere-cone graph edges.")
                    continue
                }
                switch procedural.componentKind {
                case .negativeOpenAngularInterval,
                     .positiveOpenAngularInterval:
                    break
                case .negativeFullBranch, .positiveFullBranch,
                     .boundedAngularInterval, .apexReducedAngularInterval:
                    Issue.record("Every edge of a pole-split bounded component must be open.")
                }
                #expect(result.kind == .mixed)
                for fraction in [0.0, 1.0e-8, 0.25, 0.5, 0.75, 1.0 - 1.0e-8, 1.0] {
                    let geometry = try procedural.differential(
                        atNormalizedFraction: fraction,
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
                    let firstPoint = try operands.first.point(
                        u: firstUV.u,
                        v: firstUV.v,
                        tolerance: tolerance
                    )
                    let secondPoint = try operands.second.point(
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
                        endpoints.append(geometry.position)
                        if abs(geometry.position.z - 2.0) <= tolerance.distance {
                            poleEndpointCount += 1
                        }
                    }
                }
            }

            #expect(poleEndpointCount == 2)
            var uniqueEndpoints: [Point3D] = []
            for point in endpoints where uniqueEndpoints.contains(where: {
                $0.isApproximatelyEqual(to: point, tolerance: tolerance.distance)
            }) == false {
                uniqueEndpoints.append(point)
            }
            #expect(uniqueEndpoints.count == 3)
        }
    }

    private func verifyCurve(
        _ intersection: SurfaceSurfaceIntersection,
        first: Surface3D,
        second: Surface3D,
        expectedKind: CurveSurfaceIntersectionKind
    ) throws {
        guard case let .curve(result) = intersection,
              case let .analyticAnalytic(exactTruth) = result.truth,
              case .sphereCone = exactTruth.definition,
              case .surfaceLift = result.curve,
              case .bSpline = result.derivedRepresentation.curve,
              case let .closed(lower, upper) = result.curve.parameterDomain else {
            Issue.record("A general sphere-cone intersection must retain procedural truth and a derived B-spline cache.")
            return
        }
        #expect(result.kind == expectedKind)
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

    private func expectEquivalentGeometry(
        _ first: Curve3D,
        _ second: Curve3D
    ) throws {
        guard case let .closed(firstLower, firstUpper) = first.parameterDomain,
              case let .closed(secondLower, secondUpper) = second.parameterDomain else {
            Issue.record("General sphere-cone procedural curves must be bounded and closed.")
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

    private func curves(
        _ intersections: [SurfaceSurfaceIntersection]
    ) throws -> [Curve3D] {
        try intersections.map { intersection in
            guard case let .curve(curve) = intersection else {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    tolerance: tolerance,
                    message: "Expected a general sphere-cone curve intersection."
                )
            }
            return curve.curve
        }
    }
}
