import CADCore
@testable import CADGeometry
import Foundation
import Testing

@Suite("General Sphere-Cylinder Surface Intersection")
struct GeneralSphereCylinderSurfaceIntersectionTests {
    private let intersector = DefaultSurfaceSurfaceIntersector()
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func offsetCylinderInsideSphereProducesTwoVerifiedProceduralCurves() throws {
        let sphere = sphere(radius: 3.0)
        let cylinder = cylinder(axisOrigin: Point3D(x: 1.0, y: 0.0, z: 0.0), radius: 1.5)

        let intersections = try intersector.intersections(
            first: sphere,
            second: cylinder,
            tolerance: tolerance
        )

        #expect(intersections.count == 2)
        for intersection in intersections {
            try verifyCurve(
                intersection,
                first: sphere,
                second: cylinder,
                expectedKind: .transverse
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func partiallyIntersectingCylinderProducesOneMixedClosedCurve() throws {
        let sphere = sphere(radius: 2.0)
        let cylinder = cylinder(axisOrigin: Point3D(x: 2.0, y: 0.0, z: 0.0), radius: 1.0)

        let intersections = try intersector.intersections(
            first: sphere,
            second: cylinder,
            tolerance: tolerance
        )

        let intersection = try #require(intersections.first)
        #expect(intersections.count == 1)
        try verifyCurve(
            intersection,
            first: sphere,
            second: cylinder,
            expectedKind: .mixed
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func separatedCylinderProducesNoIntersection() throws {
        let intersections = try intersector.intersections(
            first: sphere(radius: 2.0),
            second: cylinder(
                axisOrigin: Point3D(x: 5.0, y: 0.0, z: 0.0),
                radius: 1.0
            ),
            tolerance: tolerance
        )

        #expect(intersections.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func subToleranceGapRemainsAnExactEmptyIntersection() throws {
        let gap = tolerance.distance * 0.5
        let intersections = try intersector.intersections(
            first: sphere(radius: 2.0),
            second: cylinder(
                axisOrigin: Point3D(x: 3.0 + gap, y: 0.0, z: 0.0),
                radius: 1.0
            ),
            tolerance: tolerance
        )

        #expect(intersections.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func externalTangencyProducesVerifiedPoint() throws {
        let sphere = sphere(radius: 2.0)
        let cylinder = cylinder(axisOrigin: Point3D(x: 3.0, y: 0.0, z: 0.0), radius: 1.0)

        let intersections = try intersector.intersections(
            first: sphere,
            second: cylinder,
            tolerance: tolerance
        )

        guard case let .point(point) = try #require(intersections.first) else {
            Issue.record("An externally tangent sphere and cylinder must produce one point.")
            return
        }
        #expect(intersections.count == 1)
        #expect(point.residual <= tolerance.distance)
        #expect(point.firstSurfaceParameter.residual <= tolerance.distance)
        #expect(point.secondSurfaceParameter.residual <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func operandOrderPreservesDeterministicThreeDimensionalCurves() throws {
        let sphere = sphere(radius: 3.0)
        let cylinder = cylinder(axisOrigin: Point3D(x: 1.0, y: 0.0, z: 0.0), radius: 1.5)

        let forward = try intersector.intersections(
            first: sphere,
            second: cylinder,
            tolerance: tolerance
        )
        let reverse = try intersector.intersections(
            first: cylinder,
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
    func arbitraryCylinderAxisProducesVerifiedDualPcurves() throws {
        let sphere = sphere(radius: 3.0)
        let axis = try Vector3D(x: 1.0, y: 0.3, z: 0.2).normalized(
            tolerance: tolerance.distance
        )
        let cylinder = cylinder(
            axisOrigin: Point3D(x: 0.0, y: 1.0, z: 0.0),
            axis: axis,
            radius: 1.5
        )

        let intersections = try intersector.intersections(
            first: sphere,
            second: cylinder,
            tolerance: tolerance
        )

        #expect(intersections.count == 2)
        for intersection in intersections {
            try verifyCurve(
                intersection,
                first: sphere,
                second: cylinder,
                expectedKind: .transverse
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func proceduralTruthRoundTripsAndRetainsBranchJoinDifferentials() throws {
        let sphere = sphere(radius: 2.0)
        let cylinder = cylinder(
            axisOrigin: Point3D(x: 2.0, y: 0.0, z: 0.0),
            radius: 1.0
        )
        let intersections = try intersector.intersections(
            first: sphere,
            second: cylinder,
            tolerance: tolerance
        )

        for intersection in intersections {
            guard case let .curve(result) = intersection,
                  case let .analyticAnalytic(exact) = result.truth,
                  case .sphereCylinder = exact.definition,
                  case let .bSpline(derivedCurve) = result.derivedRepresentation.curve else {
                Issue.record("Expected certified sphere-cylinder truth with a derived B-spline cache.")
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
            try exactSecondPcurve.validate(on: cylinder, tolerance: tolerance)
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
                let firstPoint = try sphere.point(
                    u: firstParameter.u,
                    v: firstParameter.v,
                    tolerance: tolerance
                )
                let secondPoint = try cylinder.point(
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
    func sphericalParameterPoleContactsProduceCertifiedOpenBranchesInBothOrders() throws {
        let sphere = sphere(radius: 2.0)
        let cylinder = cylinder(
            axisOrigin: Point3D(x: 1.0, y: 0.0, z: 0.0),
            radius: 1.0
        )
        let operandOrders = [
            (first: sphere, second: cylinder),
            (first: cylinder, second: sphere),
        ]

        for operands in operandOrders {
            let intersections = try intersector.intersections(
                first: operands.first,
                second: operands.second,
                tolerance: tolerance
            )
            #expect(intersections.count == 4)
            var endpoints: [Point3D] = []
            var poleEndpointCount = 0

            for intersection in intersections {
                guard case let .curve(result) = intersection,
                      case let .analyticAnalytic(exact) = result.truth,
                      case let .sphereCylinder(procedural) = exact.definition,
                      case let .bSpline(derived) = result.derivedRepresentation.curve,
                      case let .closed(lower, upper) = result.curve.parameterDomain else {
                    Issue.record("A spherical-pole intersection must retain exact open sphere-cylinder truth and a derived B-spline cache.")
                    continue
                }
                switch procedural.componentKind {
                case .negativeOpenAngularInterval,
                     .positiveOpenAngularInterval:
                    break
                case .negativeFullBranch, .positiveFullBranch,
                     .boundedAngularInterval:
                    Issue.record("A spherical-pole graph edge must use an open angular component.")
                }
                #expect(result.kind == .mixed)
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
                invalidPayload["componentKind"] = "positiveFullBranch"
                #expect(throws: KernelError.self) {
                    _ = try JSONDecoder().decode(
                        CertifiedSphereCylinderIntersectionCurve.self,
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
                        if abs(abs(curvePoint.z) - 2.0) <= tolerance.distance {
                            poleEndpointCount += 1
                        }
                    }
                }
            }

            #expect(poleEndpointCount == 4)
            var uniqueEndpoints: [Point3D] = []
            for point in endpoints where uniqueEndpoints.contains(where: {
                $0.isApproximatelyEqual(to: point, tolerance: tolerance.distance)
            }) == false {
                uniqueEndpoints.append(point)
            }
            #expect(uniqueEndpoints.count == 3)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rootFreeBranchCrossingOneSphericalPoleRetainsTheOtherClosedBranch() throws {
        let sphere = sphere(radius: 2.0)
        let axis = try Vector3D(
            x: 0.5,
            y: 0.0,
            z: sqrt(3.0) * 0.5
        ).normalized(tolerance: tolerance.distance)
        let cylinder = cylinder(
            axisOrigin: Point3D(
                x: -sqrt(3.0) * 0.25,
                y: 0.0,
                z: 0.25
            ),
            axis: axis,
            radius: 0.5
        )

        for operands in [
            (first: sphere, second: cylinder),
            (first: cylinder, second: sphere),
        ] {
            let intersections = try intersector.intersections(
                first: operands.first,
                second: operands.second,
                tolerance: tolerance
            )
            #expect(intersections.count == 2)
            var openCount = 0
            var fullCount = 0

            for intersection in intersections {
                guard case let .curve(result) = intersection,
                      case let .analyticAnalytic(exact) = result.truth,
                      case let .sphereCylinder(procedural) = exact.definition else {
                    Issue.record("A root-free spherical-pole crossing must retain exact sphere-cylinder truth.")
                    continue
                }
                #expect(result.kind == .transverse)
                switch procedural.componentKind {
                case .positiveOpenAngularInterval:
                    openCount += 1
                    var invalidPayload = try #require(
                        JSONSerialization.jsonObject(
                            with: JSONEncoder().encode(procedural)
                        ) as? [String: Any]
                    )
                    invalidPayload["componentKind"] = "positiveFullBranch"
                    #expect(throws: KernelError.self) {
                        _ = try JSONDecoder().decode(
                            CertifiedSphereCylinderIntersectionCurve.self,
                            from: JSONSerialization.data(
                                withJSONObject: invalidPayload
                            )
                        )
                    }
                    let start = try procedural.differential(
                        atNormalizedFraction: 0.0,
                        tolerance: tolerance
                    )
                    let end = try procedural.differential(
                        atNormalizedFraction: 1.0,
                        tolerance: tolerance
                    )
                    let northPole = Point3D(x: 0.0, y: 0.0, z: 2.0)
                    #expect(start.position.isApproximatelyEqual(
                        to: northPole,
                        tolerance: tolerance.distance
                    ))
                    #expect(end.position.isApproximatelyEqual(
                        to: northPole,
                        tolerance: tolerance.distance
                    ))
                    #expect(start.firstDerivative.length > tolerance.distance)
                    #expect(end.firstDerivative.length > tolerance.distance)
                case .negativeFullBranch:
                    fullCount += 1
                case .negativeOpenAngularInterval, .positiveFullBranch,
                     .boundedAngularInterval:
                    Issue.record("Only the positive root-free branch should be split at the north pole.")
                }
                for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
                    let point = try procedural.point(
                        atNormalizedFraction: fraction,
                        tolerance: tolerance
                    )
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
            #expect(openCount == 1)
            #expect(fullCount == 1)
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
              case .sphereCylinder = exactTruth.definition,
              case .surfaceLift = result.curve,
              case .bSpline = result.derivedRepresentation.curve,
              case let .closed(lower, upper) = result.curve.parameterDomain else {
            Issue.record("A general sphere-cylinder intersection must retain procedural truth and a derived B-spline cache.")
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

    private func cylinder(
        axisOrigin: Point3D,
        axis: Vector3D = .unitZ,
        radius: Double
    ) -> Surface3D {
        .analytic(.cylinder(origin: axisOrigin, axis: axis, radius: radius))
    }

    private func expectEquivalentGeometry(
        _ first: Curve3D,
        _ second: Curve3D
    ) throws {
        guard case let .closed(firstLower, firstUpper) = first.parameterDomain,
              case let .closed(secondLower, secondUpper) = second.parameterDomain else {
            Issue.record("General sphere-cylinder procedural curves must be bounded and closed.")
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
                    message: "Expected a general sphere-cylinder curve intersection."
                )
            }
            return curve.curve
        }
    }
}
