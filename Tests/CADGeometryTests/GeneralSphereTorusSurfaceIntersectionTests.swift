import Testing
import CADCore
import Foundation
@testable import CADGeometry

@Suite("General sphere-torus surface intersection", .serialized)
struct GeneralSphereTorusSurfaceIntersectionTests {
    private let tolerance = ModelingTolerance.standard
    private let intersector = DefaultSurfaceSurfaceIntersector()
    private let torus = Surface3D.analytic(.torus(
        center: .origin,
        axis: .unitZ,
        majorRadius: 3.0,
        minorRadius: 1.0
    ))

    @Test(.timeLimit(.minutes(1)))
    func radialAndAxialOffsetSphereProducesTwoVerifiedProceduralCurves() throws {
        let sphere = sphereSurface(center: Point3D(x: 0.5, y: 0.0, z: 0.25), radius: 3.0)
        let intersections = try intersector.intersections(
            first: sphere,
            second: torus,
            tolerance: tolerance
        )

        #expect(intersections.count == 2)
        try assertVerifiedClosedCurves(
            intersections,
            firstSurface: sphere,
            secondSurface: torus,
            expectedKind: .transverse
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func tiltedTorusAxisProducesRotationInvariantProceduralCurves() throws {
        let axis = try Vector3D(x: 0.2, y: 0.0, z: 1.0).normalized(
            tolerance: tolerance.distance
        )
        let tiltedTorus = Surface3D.analytic(.torus(
            center: .origin,
            axis: axis,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))
        let sphere = sphereSurface(
            center: Point3D(
                x: axis.x * 0.25,
                y: 0.5,
                z: axis.z * 0.25
            ),
            radius: 3.0
        )
        let intersections = try intersector.intersections(
            first: sphere,
            second: tiltedTorus,
            tolerance: tolerance
        )

        #expect(intersections.count == 2)
        try assertVerifiedClosedCurves(
            intersections,
            firstSurface: sphere,
            secondSurface: tiltedTorus,
            expectedKind: .transverse
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func partialAngularDomainProducesOneVerifiedMixedProceduralCurve() throws {
        let sphere = sphereSurface(center: Point3D(x: 0.5, y: 0.0, z: 0.0), radius: 2.0)
        let intersections = try intersector.intersections(
            first: sphere,
            second: torus,
            tolerance: tolerance
        )

        #expect(intersections.count == 1)
        try assertVerifiedClosedCurves(
            intersections,
            firstSurface: sphere,
            secondSurface: torus,
            expectedKind: .mixed
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func separatedSphereProducesNoIntersection() throws {
        let sphere = sphereSurface(center: Point3D(x: 10.0, y: 0.0, z: 0.0), radius: 1.0)
        let intersections = try intersector.intersections(
            first: sphere,
            second: torus,
            tolerance: tolerance
        )
        #expect(intersections.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func operandOrderPreservesDeterministicCurveGeometry() throws {
        let sphere = sphereSurface(center: Point3D(x: 0.5, y: 0.0, z: 0.25), radius: 3.0)
        let forward = try intersector.intersections(
            first: sphere,
            second: torus,
            tolerance: tolerance
        )
        let reversed = try intersector.intersections(
            first: torus,
            second: sphere,
            tolerance: tolerance
        )

        let forwardKeys = try curveKeys(for: forward)
        let reversedKeys = try curveKeys(for: reversed)
        #expect(forwardKeys == reversedKeys)
    }

    @Test(.timeLimit(.minutes(1)))
    func proceduralTruthRoundTripsAndRetainsBranchJoinDifferentials() throws {
        let sphere = sphereSurface(
            center: Point3D(x: 0.5, y: 0.0, z: 0.0),
            radius: 2.0
        )
        let intersections = try intersector.intersections(
            first: sphere,
            second: torus,
            tolerance: tolerance
        )

        #expect(intersections.count == 1)
        for intersection in intersections {
            guard case let .curve(result) = intersection,
                  case let .analyticAnalytic(exact) = result.truth,
                  case let .sphereTorus(proceduralCurve) = exact.definition,
                  case let .bSpline(derivedCurve) = result.derivedRepresentation.curve else {
                Issue.record("Expected certified sphere-torus truth with a derived B-spline cache.")
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

            let exactSpherePcurve = exact.firstSurfaceParameterCurve
            let exactTorusPcurve = exact.secondSurfaceParameterCurve
            try exactSpherePcurve.validate(on: sphere, tolerance: tolerance)
            try exactTorusPcurve.validate(on: torus, tolerance: tolerance)
            for fraction in [0.0, 0.0001, 0.25, 0.4999, 0.5, 0.5001, 0.75, 1.0] {
                let geometry = try result.curve.differentialGeometry(
                    at: fraction,
                    tolerance: tolerance
                )
                #expect(geometry.firstDerivative.length > tolerance.distance)
                let sphereParameter = try exactSpherePcurve.parameter(
                    atNormalizedFraction: fraction,
                    tolerance: tolerance
                )
                let torusParameter = try exactTorusPcurve.parameter(
                    atNormalizedFraction: fraction,
                    tolerance: tolerance
                )
                let spherePoint = try sphere.point(
                    u: sphereParameter.u,
                    v: sphereParameter.v,
                    tolerance: tolerance
                )
                let torusPoint = try torus.point(
                    u: torusParameter.u,
                    v: torusParameter.v,
                    tolerance: tolerance
                )
                let derivedPoint = try derivedCurve.point(
                    at: fraction,
                    tolerance: tolerance
                )
                #expect((geometry.position - spherePoint).length <= tolerance.distance)
                #expect((geometry.position - torusPoint).length <= tolerance.distance)
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
                let firstScale = max(differential.firstDerivative.length, 1.0)
                let secondScale = max(differential.secondDerivative.length, 1.0)
                #expect((finiteFirst - differential.firstDerivative).length
                    <= 1.0e-6 * firstScale)
                #expect((finiteSecond - differential.secondDerivative).length
                    <= 1.0e-4 * secondScale)
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
    func sphericalParameterPoleContactReturnsTypedDiagnostic() throws {
        let sphere = sphereSurface(center: Point3D(x: 4.0, y: 0.0, z: -1.0), radius: 1.0)
        do {
            _ = try intersector.intersections(
                first: sphere,
                second: torus,
                tolerance: tolerance
            )
            Issue.record("A sphere-torus curve through a spherical parameter pole must reject.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .singularGeometry)
            #expect(error.residual != nil)
            #expect(error.tolerance == tolerance)
        }
    }

    private func sphereSurface(center: Point3D, radius: Double) -> Surface3D {
        .analytic(.sphere(center: center, radius: radius))
    }

    private func assertVerifiedClosedCurves(
        _ intersections: [SurfaceSurfaceIntersection],
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        expectedKind: CurveSurfaceIntersectionKind
    ) throws {
        for intersection in intersections {
            guard case let .curve(value) = intersection,
                  case let .analyticAnalytic(exactTruth) = value.truth,
                  case .sphereTorus = exactTruth.definition,
                  case .surfaceLift = value.curve,
                  case let .bSpline(derivedCurve) = value.derivedRepresentation.curve,
                  case let .closed(lower, upper) = value.curve.parameterDomain else {
                Issue.record("General sphere-torus intersection must retain procedural truth and a derived B-spline cache.")
                continue
            }
            #expect(value.kind == expectedKind)
            #expect(value.maximumResidual <= tolerance.distance)
            let start = try value.curve.point(at: lower, tolerance: tolerance)
            let end = try value.curve.point(at: upper, tolerance: tolerance)
            #expect((start - end).length <= tolerance.distance)
            for index in 0...32 {
                let parameter = lower
                    + (upper - lower) * Double(index) / 32.0
                let point = try value.curve.point(at: parameter, tolerance: tolerance)
                let derivedPoint = try derivedCurve.point(
                    at: parameter,
                    tolerance: tolerance
                )
                let firstUV = try value.firstSurfaceParameterCurve.parameter(
                    atCurveParameter: parameter,
                    curveDomain: value.curve.parameterDomain,
                    tolerance: tolerance
                )
                let secondUV = try value.secondSurfaceParameterCurve.parameter(
                    atCurveParameter: parameter,
                    curveDomain: value.curve.parameterDomain,
                    tolerance: tolerance
                )
                let firstPoint = try firstSurface.point(
                    u: firstUV.u,
                    v: firstUV.v,
                    tolerance: tolerance
                )
                let secondPoint = try secondSurface.point(
                    u: secondUV.u,
                    v: secondUV.v,
                    tolerance: tolerance
                )
                #expect((point - derivedPoint).length <= tolerance.distance)
                #expect((point - firstPoint).length <= tolerance.distance)
                #expect((point - secondPoint).length <= tolerance.distance)
            }
        }
    }

    private func curveKeys(
        for intersections: [SurfaceSurfaceIntersection]
    ) throws -> [[[Double]]] {
        try intersections.compactMap { intersection -> [[Double]]? in
            guard case let .curve(value) = intersection,
                  case let .closed(lower, upper) = value.curve.parameterDomain else {
                return nil
            }
            return try (0..<16).map { index in
                let parameter = lower
                    + (upper - lower) * Double(index) / 16.0
                let point = try value.curve.point(at: parameter, tolerance: tolerance)
                return [point.x, point.y, point.z]
            }.sorted { lhs, rhs in
                lhs.lexicographicallyPrecedes(rhs)
            }
        }.sorted { lhs, rhs in
            lhs.lexicographicallyPrecedes(rhs, by: { left, right in
                left.lexicographicallyPrecedes(right)
            })
        }
    }
}
