import CADCore
@testable import CADGeometry
import Foundation
import Testing

@Suite("General Torus-Cylinder Surface Intersection")
struct GeneralTorusCylinderSurfaceIntersectionTests {
    private let intersector = DefaultSurfaceSurfaceIntersector()
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(2)))
    func tiltedCylinderProducesVerifiedClosedProceduralCurves() throws {
        let torus = torusSurface()
        let cylinder = try tiltedCylinderSurface()

        let intersections = try intersector.intersections(
            first: torus,
            second: cylinder,
            tolerance: tolerance
        )

        #expect(intersections.count == 2)
        for intersection in intersections {
            try verifyCurve(intersection, first: torus, second: cylinder)
        }
    }

    // Deterministic operand-order tracing runs near two minutes under
    // full-suite load in unoptimized builds.
    @Test(.timeLimit(.minutes(4)))
    func operandOrderPreservesDeterministicThreeDimensionalCurves() throws {
        let torus = torusSurface()
        let cylinder = try tiltedCylinderSurface()

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

        let forwardCurves = curves(forward)
        let reverseCurves = curves(reverse)
        #expect(forwardCurves.count == reverseCurves.count)
        for (forwardCurve, reverseCurve) in zip(forwardCurves, reverseCurves) {
            try expectEquivalentGeometry(forwardCurve, reverseCurve)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func separatedTiltedCylinderProducesExactEmptyIntersection() throws {
        let axis = try Vector3D(x: 0.08, y: 0.0, z: 1.0).normalized(
            tolerance: tolerance.distance
        )
        let intersections = try intersector.intersections(
            first: torusSurface(),
            second: .analytic(.cylinder(
                origin: Point3D(x: 10.0, y: 0.0, z: 0.0),
                axis: axis,
                radius: 1.0
            )),
            tolerance: tolerance
        )

        #expect(intersections.isEmpty)
    }

    @Test(.timeLimit(.minutes(2)))
    func rotatedAxesRetainRotationInvariantProceduralCurves() throws {
        let torusAxis = try Vector3D(x: 0.2, y: 0.3, z: 1.0).normalized(
            tolerance: tolerance.distance
        )
        let radial = try torusAxis.cross(.unitX).normalized(
            tolerance: tolerance.distance
        )
        let cylinderAxis = try (torusAxis + radial * 0.08).normalized(
            tolerance: tolerance.distance
        )
        let torus = Surface3D.analytic(.torus(
            center: Point3D(x: 0.5, y: -0.25, z: 0.75),
            axis: torusAxis,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))
        let cylinder = Surface3D.analytic(.cylinder(
            origin: Point3D(x: 0.5, y: -0.25, z: 0.75),
            axis: cylinderAxis,
            radius: 3.0
        ))

        let intersections = try intersector.intersections(
            first: torus,
            second: cylinder,
            tolerance: tolerance
        )

        #expect(intersections.count == 2)
        for intersection in intersections {
            try verifyCurve(intersection, first: torus, second: cylinder)
        }
    }

    // Procedural truth round-trips run near two minutes under full-suite
    // load in unoptimized builds.
    @Test(.timeLimit(.minutes(4)))
    func proceduralTruthRoundTripsAndRetainsImplicitDifferentials() throws {
        let torus = torusSurface()
        let cylinder = try tiltedCylinderSurface()
        let intersections = try intersector.intersections(
            first: torus,
            second: cylinder,
            tolerance: tolerance
        )

        #expect(intersections.count == 2)
        for intersection in intersections {
            guard case let .curve(result) = intersection,
                  case let .analyticAnalytic(exact) = result.truth,
                  case let .generalTorusCylinder(proceduralCurve) = exact.definition,
                  case let .bSpline(derivedCurve) = result.derivedRepresentation.curve else {
                Issue.record("Expected certified general torus-cylinder truth with a derived B-spline cache.")
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
            for fraction in [0.0, 0.125, 0.25, 0.5, 0.75, 0.875, 1.0] {
                let exactPoint = try proceduralCurve.point(
                    atNormalizedFraction: fraction,
                    tolerance: tolerance
                )
                let derivedPoint = try derivedCurve.point(
                    at: fraction,
                    tolerance: tolerance
                )
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
                #expect((exactPoint - derivedPoint).length <= tolerance.distance)
                #expect((exactPoint - torusPoint).length <= tolerance.distance)
                #expect((exactPoint - cylinderPoint).length <= tolerance.distance)
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
    }

    private func verifyCurve(
        _ intersection: SurfaceSurfaceIntersection,
        first: Surface3D,
        second: Surface3D
    ) throws {
        guard case let .curve(result) = intersection,
              case let .analyticAnalytic(exactTruth) = result.truth,
              case .generalTorusCylinder = exactTruth.definition,
              case .surfaceLift = result.curve,
              case let .bSpline(derivedCurve) = result.derivedRepresentation.curve,
              case let .closed(lower, upper) = result.curve.parameterDomain else {
            Issue.record("A regular non-parallel torus-cylinder intersection must retain procedural truth and a derived B-spline cache.")
            return
        }
        #expect(result.kind == .transverse)
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

    private func torusSurface() -> Surface3D {
        .analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))
    }

    private func tiltedCylinderSurface() throws -> Surface3D {
        let axis = try Vector3D(x: 0.08, y: 0.0, z: 1.0).normalized(
            tolerance: tolerance.distance
        )
        return .analytic(.cylinder(
            origin: .origin,
            axis: axis,
            radius: 3.0
        ))
    }

    private func curves(_ intersections: [SurfaceSurfaceIntersection]) -> [Curve3D] {
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
            Issue.record("General torus-cylinder procedural curves must be closed.")
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
