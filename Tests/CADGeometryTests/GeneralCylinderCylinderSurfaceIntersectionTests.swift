import CADCore
@testable import CADGeometry
import Foundation
import Testing

@Suite("General Cylinder-Cylinder Surface Intersection")
struct GeneralCylinderCylinderSurfaceIntersectionTests {
    private let intersector = DefaultSurfaceSurfaceIntersector()
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func unequalIntersectingAxesProduceTwoVerifiedProceduralCurves() throws {
        let first = cylinder(origin: .origin, axis: .unitZ, radius: 2.0)
        let second = cylinder(origin: .origin, axis: .unitX, radius: 3.0)

        let intersections = try intersector.intersections(
            first: first,
            second: second,
            tolerance: tolerance
        )

        #expect(intersections.count == 2)
        for intersection in intersections {
            try verifyCurve(intersection, first: first, second: second)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func skewUnequalAxesProduceVerifiedDualPcurves() throws {
        let first = cylinder(
            origin: Point3D(x: 0.25, y: -0.5, z: 0.0),
            axis: .unitZ,
            radius: 2.25
        )
        let secondAxis = try Vector3D(x: 1.0, y: 0.25, z: 0.1).normalized(
            tolerance: tolerance.distance
        )
        let second = cylinder(
            origin: Point3D(x: -0.5, y: 0.75, z: 1.0),
            axis: secondAxis,
            radius: 1.5
        )

        let intersections = try intersector.intersections(
            first: first,
            second: second,
            tolerance: tolerance
        )

        #expect(intersections.isEmpty == false)
        for intersection in intersections {
            try verifyCurve(intersection, first: first, second: second)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func separatedSkewAxesProduceNoIntersection() throws {
        let intersections = try intersector.intersections(
            first: cylinder(origin: .origin, axis: .unitZ, radius: 1.0),
            second: cylinder(
                origin: Point3D(x: 0.0, y: 10.0, z: 0.0),
                axis: .unitX,
                radius: 1.0
            ),
            tolerance: tolerance
        )

        #expect(intersections.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func isolatedTangencyProducesVerifiedPoint() throws {
        let first = cylinder(origin: .origin, axis: .unitZ, radius: 1.0)
        let second = cylinder(
            origin: Point3D(x: 0.0, y: -2.0, z: 0.0),
            axis: .unitX,
            radius: 1.0
        )

        let intersections = try intersector.intersections(
            first: first,
            second: second,
            tolerance: tolerance
        )

        guard case let .point(point) = try #require(intersections.first) else {
            Issue.record("An isolated cylinder contact must produce a point.")
            return
        }
        #expect(intersections.count == 1)
        #expect(point.residual <= tolerance.distance)
        #expect(point.firstSurfaceParameter.residual <= tolerance.distance)
        #expect(point.secondSurfaceParameter.residual <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func operandOrderPreservesDeterministicThreeDimensionalCurves() throws {
        let first = cylinder(
            origin: Point3D(x: 0.0, y: 0.5, z: 0.25),
            axis: .unitZ,
            radius: 2.0
        )
        let second = cylinder(origin: .origin, axis: .unitX, radius: 2.75)

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
    func proceduralTruthRoundTripsAndRetainsBranchJoinDifferentials() throws {
        let first = cylinder(
            origin: Point3D(x: 0.25, y: -0.5, z: 0.0),
            axis: .unitZ,
            radius: 2.25
        )
        let secondAxis = try Vector3D(x: 1.0, y: 0.25, z: 0.1).normalized(
            tolerance: tolerance.distance
        )
        let second = cylinder(
            origin: Point3D(x: -0.5, y: 0.75, z: 1.0),
            axis: secondAxis,
            radius: 1.5
        )
        let intersections = try intersector.intersections(
            first: first,
            second: second,
            tolerance: tolerance
        )

        for intersection in intersections {
            guard case let .curve(result) = intersection,
                  case let .analyticAnalytic(exact) = result.truth,
                  case .cylinderCylinder = exact.definition,
                  case let .bSpline(derivedCurve) = result.derivedRepresentation.curve else {
                Issue.record("Expected certified cylinder-cylinder truth with a derived B-spline cache.")
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
    func subdivisionExhaustionReturnsTypedResourceDiagnostic() throws {
        do {
            _ = try intersector.intersections(
                first: cylinder(origin: .origin, axis: .unitZ, radius: 20.0),
                second: cylinder(
                    origin: Point3D(x: 0.0, y: 2.0, z: 0.0),
                    axis: .unitX,
                    radius: 17.0
                ),
                options: SurfaceSurfaceIntersectionOptions(
                    maximumSubdivisionDepth: 0,
                    maximumIterations: 1,
                    maximumSeedCount: 1_024
                ),
                tolerance: tolerance
            )
            Issue.record("A zero-depth trace must not return an unverified curve.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .resourceLimitExceeded)
            #expect(error.residual != nil)
            #expect(error.tolerance == tolerance)
        }
    }

    private func verifyCurve(
        _ intersection: SurfaceSurfaceIntersection,
        first: Surface3D,
        second: Surface3D
    ) throws {
        guard case let .curve(result) = intersection,
              case let .analyticAnalytic(exactTruth) = result.truth,
              case .cylinderCylinder = exactTruth.definition,
              case .surfaceLift = result.curve,
              case .bSpline = result.derivedRepresentation.curve,
              case let .closed(lower, upper) = result.curve.parameterDomain else {
            Issue.record("A general cylinder intersection must retain procedural truth and a derived B-spline cache.")
            return
        }
        #expect(result.maximumResidual <= tolerance.distance)
        try result.firstSurfaceParameterCurve.validate(on: first, tolerance: tolerance)
        try result.secondSurfaceParameterCurve.validate(on: second, tolerance: tolerance)

        for index in 0...32 {
            let fraction = Double(index) / 32.0
            let parameter = lower + (upper - lower) * fraction
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

    private func cylinder(origin: Point3D, axis: Vector3D, radius: Double) -> Surface3D {
        .analytic(.cylinder(origin: origin, axis: axis, radius: radius))
    }

    private func expectEquivalentGeometry(
        _ first: Curve3D,
        _ second: Curve3D
    ) throws {
        guard case let .closed(firstLower, firstUpper) = first.parameterDomain,
              case let .closed(secondLower, secondUpper) = second.parameterDomain else {
            Issue.record("General cylinder-cylinder procedural curves must be bounded and closed.")
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
                    message: "Expected a general cylinder-cylinder curve intersection."
                )
            }
            return curve.curve
        }
    }
}
