import Testing
import CADCore
@testable import CADGeometry
import Foundation

@Suite("Parallel-offset torus-torus surface intersection", .serialized)
struct ParallelOffsetTorusTorusSurfaceIntersectionTests {
    private let tolerance = ModelingTolerance.standard
    private let intersector = DefaultSurfaceSurfaceIntersector()

    @Test(.timeLimit(.minutes(1)))
    func strictFullDomainConfigurationProducesFourVerifiedProceduralCurves() throws {
        let axis = try tiltedAxis()
        let first = torus(center: .origin, axis: axis, minorRadius: 0.5)
        let second = torus(
            center: Point3D(
                x: axis.x * 0.25,
                y: 2.2,
                z: axis.z * 0.25
            ),
            axis: axis,
            minorRadius: 1.5
        )
        let intersections = try intersector.intersections(
            first: first,
            second: second,
            tolerance: tolerance
        )

        #expect(intersections.count == 4)
        for intersection in intersections {
            try verifyCurve(intersection, first: first, second: second)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func operandOrderPreservesDeterministicThreeDimensionalCurves() throws {
        let first = torus(center: .origin, axis: .unitZ, minorRadius: 0.5)
        let second = torus(
            center: Point3D(x: 2.2, y: 0.0, z: 0.0),
            axis: .unitZ,
            minorRadius: 1.5
        )
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
    func separatedParallelOffsetToriProduceExactEmptyIntersection() throws {
        let intersections = try intersector.intersections(
            first: torus(center: .origin, axis: .unitZ, minorRadius: 0.5),
            second: torus(
                center: Point3D(x: 10.0, y: 0.0, z: 0.0),
                axis: .unitZ,
                minorRadius: 1.5
            ),
            tolerance: tolerance
        )
        #expect(intersections.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func generatorTangencyReturnsTypedSingularGeometryDiagnostic() throws {
        do {
            _ = try intersector.intersections(
                first: torus(center: .origin, axis: .unitZ, minorRadius: 0.5),
                second: torus(
                    center: Point3D(x: 2.0, y: 0.0, z: 0.0),
                    axis: .unitZ,
                    minorRadius: 1.5
                ),
                tolerance: tolerance
            )
            Issue.record("A torus-torus generator tangency must not be approximated.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .singularGeometry)
            #expect(error.residual != nil)
            #expect(error.tolerance == tolerance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func proceduralTruthRoundTripsAndRetainsClosedDifferentials() throws {
        let first = torus(center: .origin, axis: .unitZ, minorRadius: 0.5)
        let second = torus(
            center: Point3D(x: 2.2, y: 0.0, z: 0.0),
            axis: .unitZ,
            minorRadius: 1.5
        )
        let intersections = try intersector.intersections(
            first: first,
            second: second,
            tolerance: tolerance
        )
        let intersection = try #require(intersections.first)
        guard case let .curve(result) = intersection,
              case let .analyticAnalytic(exact) = result.truth,
              case let .parallelTorusTorus(proceduralCurve) = exact.definition,
              case let .bSpline(derivedCurve) = result.derivedRepresentation.curve else {
            Issue.record("Expected certified parallel torus-torus truth with a derived B-spline cache.")
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
        #expect(start.position == end.position)
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
              case .parallelTorusTorus = exactTruth.definition,
              case .surfaceLift = result.curve,
              case let .bSpline(derivedCurve) = result.derivedRepresentation.curve,
              case let .closed(lower, upper) = result.curve.parameterDomain else {
            Issue.record("A strict parallel-offset torus pair must retain procedural truth and a derived B-spline cache.")
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
            #expect((curvePoint - firstPoint).length <= tolerance.distance)
            #expect((curvePoint - secondPoint).length <= tolerance.distance)
            #expect((curvePoint - derivedPoint).length <= tolerance.distance)
        }
    }

    private func torus(
        center: Point3D,
        axis: Vector3D,
        minorRadius: Double
    ) -> Surface3D {
        .analytic(.torus(
            center: center,
            axis: axis,
            majorRadius: 3.0,
            minorRadius: minorRadius
        ))
    }

    private func tiltedAxis() throws -> Vector3D {
        try Vector3D(x: 0.2, y: 0.0, z: 1.0).normalized(
            tolerance: tolerance.distance
        )
    }

    private func expectEquivalentGeometry(
        _ first: Curve3D,
        _ second: Curve3D
    ) throws {
        guard case let .closed(firstLower, firstUpper) = first.parameterDomain,
              case let .closed(secondLower, secondUpper) = second.parameterDomain else {
            Issue.record("Parallel torus-torus procedural curves must be closed.")
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
                    message: "Expected a parallel torus-torus curve intersection."
                )
            }
            return result.curve
        }
    }
}
