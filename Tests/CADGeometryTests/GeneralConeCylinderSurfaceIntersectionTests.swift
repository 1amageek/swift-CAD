import Foundation
import CADCore
@testable import CADGeometry
import Testing

@Suite("General Cone-Cylinder Surface Intersection", .serialized)
struct GeneralConeCylinderSurfaceIntersectionTests {
    private let intersector = DefaultSurfaceSurfaceIntersector()
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func transverseAxesProduceTwoVerifiedProceduralCurves() throws {
        let cone = cone()
        let cylinder = cylinder(
            origin: Point3D(x: 0.0, y: 0.0, z: 4.0),
            axis: .unitY,
            radius: 1.0
        )

        let intersections = try intersector.intersections(
            first: cone,
            second: cylinder,
            tolerance: tolerance
        )

        #expect(intersections.count == 2)
        for intersection in intersections {
            try verifyCurve(
                intersection,
                first: cone,
                second: cylinder,
                expectedKind: .transverse
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func parallelOffsetAxesProduceTwoVerifiedProceduralCurves() throws {
        let cone = cone()
        let cylinder = cylinder(
            origin: Point3D(x: 1.0, y: 0.0, z: 0.0),
            axis: .unitZ,
            radius: 0.5
        )

        let intersections = try intersector.intersections(
            first: cone,
            second: cylinder,
            tolerance: tolerance
        )

        #expect(intersections.count == 2)
        for intersection in intersections {
            try verifyCurve(
                intersection,
                first: cone,
                second: cylinder,
                expectedKind: .transverse
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func angularDomainSplitsProduceVerifiedMixedProceduralCurves() throws {
        let cone = cone()
        let cylinder = cylinder(
            origin: Point3D(x: 0.0, y: 0.0, z: 1.5),
            axis: .unitY,
            radius: 1.0
        )

        let intersections = try intersector.intersections(
            first: cone,
            second: cylinder,
            tolerance: tolerance
        )

        #expect(intersections.count == 2)
        for intersection in intersections {
            try verifyCurve(
                intersection,
                first: cone,
                second: cylinder,
                expectedKind: .mixed
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func separatedCylinderProducesNoIntersection() throws {
        let intersections = try intersector.intersections(
            first: cone(),
            second: cylinder(
                origin: Point3D(x: 10.0, y: 0.0, z: 0.0),
                axis: .unitY,
                radius: 1.0
            ),
            tolerance: tolerance
        )

        #expect(intersections.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func operandOrderPreservesDeterministicThreeDimensionalCurves() throws {
        let cone = cone()
        let cylinder = cylinder(
            origin: Point3D(x: 0.0, y: 0.0, z: 4.0),
            axis: .unitY,
            radius: 1.0
        )

        let forward = try intersector.intersections(
            first: cone,
            second: cylinder,
            tolerance: tolerance
        )
        let reverse = try intersector.intersections(
            first: cylinder,
            second: cone,
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
        let cone = cone()
        let cylinder = cylinder(
            origin: Point3D(x: 0.0, y: 0.0, z: 1.5),
            axis: .unitY,
            radius: 1.0
        )
        let intersections = try intersector.intersections(
            first: cone,
            second: cylinder,
            tolerance: tolerance
        )

        for intersection in intersections {
            guard case let .curve(result) = intersection,
                  case let .analyticAnalytic(exact) = result.truth,
                  case .coneCylinder = exact.definition,
                  case let .bSpline(derivedCurve) = result.derivedRepresentation.curve else {
                Issue.record("Expected certified cone-cylinder truth with a derived B-spline cache.")
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
            try exactFirstPcurve.validate(on: cone, tolerance: tolerance)
            try exactSecondPcurve.validate(on: cylinder, tolerance: tolerance)
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
                let firstPoint = try cone.point(
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
    func coneApexContactProducesTwoCertifiedGraphLoops() throws {
        let cone = cone()
        let cylinder = cylinder(
            origin: Point3D(x: 1.0, y: 0.0, z: 0.0),
            axis: .unitY,
            radius: 1.0
        )

        for operands in [(cone, cylinder), (cylinder, cone)] {
            let intersections = try intersector.intersections(
                first: operands.0,
                second: operands.1,
                tolerance: tolerance
            )
            #expect(intersections.count == 2)
            var componentKinds:
                Set<CertifiedConeCylinderIntersectionCurve.ComponentKind> = []
            for intersection in intersections {
                guard case let .curve(result) = intersection,
                      case let .analyticAnalytic(exact) = result.truth,
                      case let .coneCylinder(procedural) = exact.definition else {
                    Issue.record("A cone-cylinder apex contact must retain certified graph truth.")
                    continue
                }
                componentKinds.insert(procedural.componentKind)
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
                            to: .origin,
                            tolerance: tolerance.distance
                        ))
                    }
                }
            }
            #expect(componentKinds == [
                .apexLowerNodeInterval,
                .apexUpperNodeInterval,
            ])
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cylinderGeneratorParallelToConeRulingProducesCertifiedLinearLoop() throws {
        let halfAngle = atan(0.5)
        let rulingDirection = Vector3D(
            x: sin(halfAngle),
            y: 0.0,
            z: cos(halfAngle)
        )

        let cone = cone(halfAngle: halfAngle)
        let cylinder = cylinder(
            origin: Point3D(x: 0.0, y: 0.0, z: 4.0),
            axis: rulingDirection,
            radius: 1.0
        )

        for operands in [(cone, cylinder), (cylinder, cone)] {
            let intersections = try intersector.intersections(
                first: operands.0,
                second: operands.1,
                tolerance: tolerance
            )
            #expect(intersections.count == 1)
            let intersection = try #require(intersections.first)
            guard case let .curve(result) = intersection,
                  case let .analyticAnalytic(exact) = result.truth,
                  case let .coneCylinder(procedural) = exact.definition else {
                Issue.record("A ruling-parallel cone-cylinder loop must retain certified linear truth.")
                continue
            }
            #expect(procedural.componentKind == .rulingParallelLinear)
            #expect(result.kind == .transverse)
            #expect(result.maximumResidual <= tolerance.distance)
            let decoded = try JSONDecoder().decode(
                SurfaceSurfaceIntersectionCurve.self,
                from: JSONEncoder().encode(result)
            )
            #expect(decoded == result)
            try decoded.validate(tolerance: tolerance)

            for fraction in [0.0, 0.125, 0.25, 0.5, 0.75, 0.875, 1.0] {
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
            }
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
              case .coneCylinder = exactTruth.definition,
              case .surfaceLift = result.curve,
              case .bSpline = result.derivedRepresentation.curve,
              case let .closed(lower, upper) = result.curve.parameterDomain else {
            Issue.record("A regular general cone-cylinder intersection must retain procedural truth and a derived B-spline cache.")
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

    private func cone(halfAngle: Double = atan(0.5)) -> Surface3D {
        .analytic(.cone(
            apex: .origin,
            axis: .unitZ,
            halfAngle: halfAngle
        ))
    }

    private func cylinder(
        origin: Point3D,
        axis: Vector3D,
        radius: Double
    ) -> Surface3D {
        .analytic(.cylinder(origin: origin, axis: axis, radius: radius))
    }

    private func expectEquivalentGeometry(
        _ first: Curve3D,
        _ second: Curve3D
    ) throws {
        guard case let .closed(firstLower, firstUpper) = first.parameterDomain,
              case let .closed(secondLower, secondUpper) = second.parameterDomain else {
            Issue.record("General cone-cylinder procedural curves must be bounded and closed.")
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
                    message: "Expected a general cone-cylinder curve intersection."
                )
            }
            return curve.curve
        }
    }
}
