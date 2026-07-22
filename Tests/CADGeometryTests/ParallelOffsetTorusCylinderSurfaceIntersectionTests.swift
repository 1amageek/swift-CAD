import CADCore
@testable import CADGeometry
import Foundation
import Testing

@Suite("Parallel-Offset Torus-Cylinder Surface Intersection")
struct ParallelOffsetTorusCylinderSurfaceIntersectionTests {
    private let intersector = DefaultSurfaceSurfaceIntersector()
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func cylinderInsideTubeBandProducesTwoVerifiedProceduralCurves() throws {
        let torus = torus(majorRadius: 3.0, minorRadius: 1.5)
        let cylinder = cylinder(axisOrigin: Point3D(x: 3.0, y: 0.0, z: 0.0), radius: 0.5)

        let intersections = try intersector.intersections(
            first: torus,
            second: cylinder,
            tolerance: tolerance
        )

        #expect(intersections.count == 2)
        for intersection in intersections {
            try verifyCurve(
                intersection,
                first: torus,
                second: cylinder,
                expectedKind: .transverse
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func partialTubeBandProducesOneMixedProceduralCurve() throws {
        let torus = torus(majorRadius: 3.0, minorRadius: 1.0)
        let cylinder = cylinder(axisOrigin: Point3D(x: 4.0, y: 0.0, z: 0.0), radius: 1.0)

        let intersections = try intersector.intersections(
            first: torus,
            second: cylinder,
            tolerance: tolerance
        )

        let intersection = try #require(intersections.first)
        #expect(intersections.count == 1)
        try verifyCurve(
            intersection,
            first: torus,
            second: cylinder,
            expectedKind: .mixed
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func tiltedParallelAxesRetainRotationInvariantProceduralCurves() throws {
        let axis = try Vector3D(x: 0.2, y: 0.3, z: 1.0).normalized(
            tolerance: tolerance.distance
        )
        let radial = try axis.cross(.unitX).normalized(
            tolerance: tolerance.distance
        )
        let torus = Surface3D.analytic(.torus(
            center: .origin,
            axis: axis,
            majorRadius: 3.0,
            minorRadius: 1.5
        ))
        let cylinder = Surface3D.analytic(.cylinder(
            origin: .origin + radial * 3.0,
            axis: axis,
            radius: 0.5
        ))

        let intersections = try intersector.intersections(
            first: torus,
            second: cylinder,
            tolerance: tolerance
        )

        #expect(intersections.count == 2)
        for intersection in intersections {
            try verifyCurve(
                intersection,
                first: torus,
                second: cylinder,
                expectedKind: .transverse
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func separatedCylinderProducesNoIntersection() throws {
        let intersections = try intersector.intersections(
            first: torus(majorRadius: 3.0, minorRadius: 1.0),
            second: cylinder(
                axisOrigin: Point3D(x: 8.0, y: 0.0, z: 0.0),
                radius: 0.5
            ),
            tolerance: tolerance
        )

        #expect(intersections.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func externalTangencyProducesVerifiedPoint() throws {
        let first = torus(majorRadius: 3.0, minorRadius: 1.0)
        let second = cylinder(
            axisOrigin: Point3D(x: 5.0, y: 0.0, z: 0.0),
            radius: 1.0
        )

        let intersections = try intersector.intersections(
            first: first,
            second: second,
            tolerance: tolerance
        )

        guard case let .point(point) = try #require(intersections.first) else {
            Issue.record("An externally tangent torus and cylinder must produce one point.")
            return
        }
        #expect(intersections.count == 1)
        #expect(point.residual <= tolerance.distance)
        #expect(point.firstSurfaceParameter.residual <= tolerance.distance)
        #expect(point.secondSurfaceParameter.residual <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func internalDoubleTangenciesProduceFourCertifiedRegularBranchesInBothOrders() throws {
        let torus = torus(majorRadius: 3.0, minorRadius: 1.0)
        let cylinder = cylinder(
            axisOrigin: Point3D(x: 3.0, y: 0.0, z: 0.0),
            radius: 1.0
        )
        let operandOrders = [
            (first: torus, second: cylinder),
            (first: cylinder, second: torus),
        ]

        for operands in operandOrders {
            let intersections = try intersector.intersections(
                first: operands.first,
                second: operands.second,
                tolerance: tolerance
            )
            #expect(intersections.count == 4)
            var negativeCount = 0
            var positiveCount = 0
            var endpointPoints: [Point3D] = []

            for intersection in intersections {
                guard case let .curve(result) = intersection,
                      case let .analyticAnalytic(exact) = result.truth,
                      case let .parallelTorusCylinder(procedural) = exact.definition,
                      case let .bSpline(derivedCurve) = result.derivedRepresentation.curve,
                      case let .closed(lower, upper) = result.curve.parameterDomain else {
                    Issue.record("An internal torus-cylinder tangency must retain certified procedural branches and derived B-spline caches.")
                    continue
                }
                switch procedural.componentKind {
                case .negativeInternalTangencyInterval:
                    negativeCount += 1
                case .positiveInternalTangencyInterval:
                    positiveCount += 1
                case .negativeFullBranch, .positiveFullBranch,
                     .boundedAngularInterval:
                    Issue.record("An internal double root must not use a simple-root component kind.")
                }
                #expect(result.kind == .mixed)
                #expect(result.maximumResidual <= tolerance.distance)
                let decoded = try JSONDecoder().decode(
                    SurfaceSurfaceIntersectionCurve.self,
                    from: JSONEncoder().encode(result)
                )
                #expect(decoded == result)

                for fraction in [0.0, 0.125, 0.5, 0.875, 1.0] {
                    let parameter = lower + (upper - lower) * fraction
                    let exactDifferential = try procedural.differential(
                        atNormalizedFraction: fraction,
                        tolerance: tolerance
                    )
                    #expect(exactDifferential.firstDerivative.length > tolerance.distance)
                    let curvePoint = try result.curve.point(
                        at: parameter,
                        tolerance: tolerance
                    )
                    let derivedPoint = try derivedCurve.point(
                        at: parameter,
                        tolerance: tolerance
                    )
                    let firstParameter = try result.firstSurfaceParameterCurve.parameter(
                        atCurveParameter: parameter,
                        curveDomain: result.curve.parameterDomain,
                        tolerance: tolerance
                    )
                    let secondParameter = try result.secondSurfaceParameterCurve.parameter(
                        atCurveParameter: parameter,
                        curveDomain: result.curve.parameterDomain,
                        tolerance: tolerance
                    )
                    let firstPoint = try operands.first.point(
                        u: firstParameter.u,
                        v: firstParameter.v,
                        tolerance: tolerance
                    )
                    let secondPoint = try operands.second.point(
                        u: secondParameter.u,
                        v: secondParameter.v,
                        tolerance: tolerance
                    )
                    #expect(curvePoint.isApproximatelyEqual(
                        to: exactDifferential.position,
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
                        endpointPoints.append(curvePoint)
                    }
                }
            }

            #expect(negativeCount == 2)
            #expect(positiveCount == 2)
            var uniqueEndpoints: [Point3D] = []
            for point in endpointPoints where uniqueEndpoints.contains(where: {
                $0.isApproximatelyEqual(to: point, tolerance: tolerance.distance)
            }) == false {
                uniqueEndpoints.append(point)
            }
            #expect(uniqueEndpoints.count == 2)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func isolatedAndMixedInternalTangencyIntervalsRetainRegularCertifiedEndpoints() throws {
        let torus = torus(majorRadius: 3.0, minorRadius: 1.0)
        let cases = [
            (
                cylinder: cylinder(
                    axisOrigin: Point3D(x: 2.75, y: 0.0, z: 0.0),
                    radius: 0.75
                ),
                expectedCurveCount: 2,
                expectedEndpointCount: 1
            ),
            (
                cylinder: cylinder(
                    axisOrigin: Point3D(x: 3.5, y: 0.0, z: 0.0),
                    radius: 1.5
                ),
                expectedCurveCount: 4,
                expectedEndpointCount: 3
            ),
        ]

        for configuration in cases {
            let intersections = try intersector.intersections(
                first: torus,
                second: configuration.cylinder,
                tolerance: tolerance
            )
            #expect(intersections.count == configuration.expectedCurveCount)
            var endpoints: [Point3D] = []

            for intersection in intersections {
                guard case let .curve(result) = intersection,
                      case let .analyticAnalytic(exact) = result.truth,
                      case let .parallelTorusCylinder(procedural) = exact.definition else {
                    Issue.record("An internal tangency interval must retain exact parallel torus-cylinder truth.")
                    continue
                }
                switch procedural.componentKind {
                case .negativeInternalTangencyInterval,
                     .positiveInternalTangencyInterval:
                    break
                case .negativeFullBranch, .positiveFullBranch,
                     .boundedAngularInterval:
                    Issue.record("A double-root endpoint must use an internal-tangency component kind.")
                }
                for fraction in [0.0, 1.0] {
                    let differential = try procedural.differential(
                        atNormalizedFraction: fraction,
                        tolerance: tolerance
                    )
                    #expect(differential.firstDerivative.length > tolerance.distance)
                    endpoints.append(differential.position)
                }
            }

            var uniqueEndpoints: [Point3D] = []
            for point in endpoints where uniqueEndpoints.contains(where: {
                $0.isApproximatelyEqual(to: point, tolerance: tolerance.distance)
            }) == false {
                uniqueEndpoints.append(point)
            }
            #expect(uniqueEndpoints.count == configuration.expectedEndpointCount)

            guard case let .curve(firstResult) = try #require(intersections.first),
                  case let .analyticAnalytic(exact) = firstResult.truth,
                  case let .parallelTorusCylinder(procedural) = exact.definition,
                  var payload = try JSONSerialization.jsonObject(
                    with: JSONEncoder().encode(procedural)
                  ) as? [String: Any] else {
                Issue.record("Expected an encoded internal-tangency certificate.")
                continue
            }
            payload["componentKind"] = "positiveFullBranch"
            #expect(throws: KernelError.self) {
                _ = try JSONDecoder().decode(
                    CertifiedParallelTorusCylinderIntersectionCurve.self,
                    from: JSONSerialization.data(withJSONObject: payload)
                )
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func operandOrderPreservesDeterministicThreeDimensionalCurves() throws {
        let torus = torus(majorRadius: 3.0, minorRadius: 1.5)
        let cylinder = cylinder(axisOrigin: Point3D(x: 3.0, y: 0.0, z: 0.0), radius: 0.5)

        let forward = try intersector.intersections(
            first: torus,
            second: cylinder,
            tolerance: tolerance
        )
        let reverse = try intersector.intersections(
            first: cylinder,
            second: torus,
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
        let torus = torus(majorRadius: 3.0, minorRadius: 1.0)
        let cylinder = cylinder(
            axisOrigin: Point3D(x: 4.0, y: 0.0, z: 0.0),
            radius: 1.0
        )
        let intersections = try intersector.intersections(
            first: torus,
            second: cylinder,
            tolerance: tolerance
        )

        #expect(intersections.count == 1)
        for intersection in intersections {
            guard case let .curve(result) = intersection,
                  case let .analyticAnalytic(exact) = result.truth,
                  case let .parallelTorusCylinder(proceduralCurve) = exact.definition,
                  case let .bSpline(derivedCurve) = result.derivedRepresentation.curve else {
                Issue.record("Expected certified parallel torus-cylinder truth with a derived B-spline cache.")
                continue
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

            let exactTorusPcurve = exact.firstSurfaceParameterCurve
            let exactCylinderPcurve = exact.secondSurfaceParameterCurve
            try exactTorusPcurve.validate(on: torus, tolerance: tolerance)
            try exactCylinderPcurve.validate(on: cylinder, tolerance: tolerance)
            for fraction in [0.0, 0.0001, 0.25, 0.4999, 0.5, 0.5001, 0.75, 1.0] {
                let geometry = try result.curve.differentialGeometry(
                    at: fraction,
                    tolerance: tolerance
                )
                #expect(geometry.firstDerivative.length > tolerance.distance)
                let torusParameter = try exactTorusPcurve.parameter(
                    atNormalizedFraction: fraction,
                    tolerance: tolerance
                )
                let cylinderParameter = try exactCylinderPcurve.parameter(
                    atNormalizedFraction: fraction,
                    tolerance: tolerance
                )
                let torusPoint = try torus.point(
                    u: torusParameter.u,
                    v: torusParameter.v,
                    tolerance: tolerance
                )
                let cylinderPoint = try cylinder.point(
                    u: cylinderParameter.u,
                    v: cylinderParameter.v,
                    tolerance: tolerance
                )
                let derivedPoint = try derivedCurve.point(
                    at: fraction,
                    tolerance: tolerance
                )
                #expect((geometry.position - torusPoint).length <= tolerance.distance)
                #expect((geometry.position - cylinderPoint).length <= tolerance.distance)
                #expect((geometry.position - derivedPoint).length <= tolerance.distance)
            }
            let finiteDifferenceStep = 1.0e-4
            for fraction in [0.125, 0.375, 0.625, 0.875] {
                let differential = try proceduralCurve.differential(
                    atNormalizedFraction: fraction,
                    tolerance: tolerance
                )
                let lowerPoint = try proceduralCurve.point(
                    atNormalizedFraction: fraction - finiteDifferenceStep,
                    tolerance: tolerance
                )
                let upperPoint = try proceduralCurve.point(
                    atNormalizedFraction: fraction + finiteDifferenceStep,
                    tolerance: tolerance
                )
                let finiteFirst = (upperPoint - lowerPoint)
                    / (2.0 * finiteDifferenceStep)
                let finiteSecond = (
                    (upperPoint - differential.position)
                        + (lowerPoint - differential.position)
                ) / (finiteDifferenceStep * finiteDifferenceStep)
                #expect((finiteFirst - differential.firstDerivative).length
                    <= 1.0e-6 * max(differential.firstDerivative.length, 1.0))
                #expect((finiteSecond - differential.secondDerivative).length
                    <= 1.0e-4 * max(differential.secondDerivative.length, 1.0))
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

    private func verifyCurve(
        _ intersection: SurfaceSurfaceIntersection,
        first: Surface3D,
        second: Surface3D,
        expectedKind: CurveSurfaceIntersectionKind
    ) throws {
        guard case let .curve(result) = intersection,
              case let .analyticAnalytic(exactTruth) = result.truth,
              case .parallelTorusCylinder = exactTruth.definition,
              case .surfaceLift = result.curve,
              case let .bSpline(derivedCurve) = result.derivedRepresentation.curve,
              case let .closed(lower, upper) = result.curve.parameterDomain else {
            Issue.record("A parallel-offset torus-cylinder intersection must retain procedural truth and a derived B-spline cache.")
            return
        }
        #expect(result.kind == expectedKind)
        #expect(result.maximumResidual <= tolerance.distance)
        try result.firstSurfaceParameterCurve.validate(on: first, tolerance: tolerance)
        try result.secondSurfaceParameterCurve.validate(on: second, tolerance: tolerance)

        for index in 0...16 {
            let parameter = lower + (upper - lower) * Double(index) / 16.0
            let curvePoint = try result.curve.point(at: parameter, tolerance: tolerance)
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

    private func torus(majorRadius: Double, minorRadius: Double) -> Surface3D {
        .analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: majorRadius,
            minorRadius: minorRadius
        ))
    }

    private func cylinder(axisOrigin: Point3D, radius: Double) -> Surface3D {
        .analytic(.cylinder(origin: axisOrigin, axis: .unitZ, radius: radius))
    }

    private func expectEquivalentGeometry(
        _ first: Curve3D,
        _ second: Curve3D
    ) throws {
        guard case let .closed(firstLower, firstUpper) = first.parameterDomain,
              case let .closed(secondLower, secondUpper) = second.parameterDomain else {
            Issue.record("Parallel torus-cylinder procedural curves must be bounded and closed.")
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
                    message: "Expected a parallel torus-cylinder curve intersection."
                )
            }
            return curve.curve
        }
    }
}
