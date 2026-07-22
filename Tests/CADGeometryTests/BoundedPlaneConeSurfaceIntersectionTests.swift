import Foundation
import Testing
import CADCore
@testable import CADGeometry

@Suite("Bounded plane-cone surface intersection", .serialized)
struct BoundedPlaneConeSurfaceIntersectionTests {
    private let tolerance = ModelingTolerance.standard
    private let intersector = DefaultBoundedSurfaceSurfaceIntersector()

    @Test(.timeLimit(.minutes(1)))
    func boundedHyperbolaProducesVerifiedBranchesAndDualPcurves() throws {
        let plane = Surface3D.plane(Plane3D(
            origin: Point3D(x: 1.0, y: 0.0, z: 0.0),
            normal: .unitX
        ))
        let cone = Surface3D.analytic(.cone(
            apex: .origin,
            axis: .unitZ,
            halfAngle: Double.pi / 6.0
        ))
        let boundaryPoints = [
            hyperbolaPoint(parameter: -0.8, branch: 1.0),
            hyperbolaPoint(parameter: 0.8, branch: 1.0),
            hyperbolaPoint(parameter: -0.5, branch: -1.0),
            hyperbolaPoint(parameter: 0.5, branch: -1.0),
        ]

        let intersections = try #require(try intersector.intersections(
            first: plane,
            second: cone,
            boundaryPoints: boundaryPoints,
            tolerance: tolerance
        ))
        #expect(intersections.count == 2)
        var endpoints: [Point3D] = []
        for intersection in intersections {
            guard case let .curve(value) = intersection,
                  case let .analyticAnalytic(exact) = value.truth,
                  case .boundedPlaneCone = exact.definition,
                  case let .surfaceLift(curve) = value.curve,
                  case let .bSpline(derivedCurve) = value.derivedRepresentation.curve,
                  case let .closed(lower, upper) = value.curve.parameterDomain else {
                Issue.record("A bounded hyperbolic branch must retain exact procedural truth and a derived B-spline cache.")
                continue
            }
            #expect(value.kind == .transverse)
            #expect(value.maximumResidual <= tolerance.distance)
            endpoints.append(try curve.point(atNormalizedFraction: lower, tolerance: tolerance))
            endpoints.append(try curve.point(atNormalizedFraction: upper, tolerance: tolerance))
            for index in 0...16 {
                let parameter = lower
                    + (upper - lower) * Double(index) / 16.0
                let point = try value.curve.point(at: parameter, tolerance: tolerance)
                let derivedPoint = try derivedCurve.point(
                    at: parameter,
                    tolerance: tolerance
                )
                let planeUV = try value.firstSurfaceParameterCurve.parameter(
                    atCurveParameter: parameter,
                    curveDomain: value.curve.parameterDomain,
                    tolerance: tolerance
                )
                let coneUV = try value.secondSurfaceParameterCurve.parameter(
                    atCurveParameter: parameter,
                    curveDomain: value.curve.parameterDomain,
                    tolerance: tolerance
                )
                let planePoint = try plane.point(
                    u: planeUV.u,
                    v: planeUV.v,
                    tolerance: tolerance
                )
                let conePoint = try cone.point(
                    u: coneUV.u,
                    v: coneUV.v,
                    tolerance: tolerance
                )
                #expect((point - planePoint).length <= tolerance.distance)
                #expect((point - conePoint).length <= tolerance.distance)
                #expect((point - derivedPoint).length <= tolerance.distance)
            }
        }
        for boundaryPoint in boundaryPoints {
            #expect(endpoints.contains {
                ($0 - boundaryPoint).length <= tolerance.distance
            })
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func boundedHyperbolaIsStableWhenOperandOrderIsReversed() throws {
        let plane = Surface3D.plane(Plane3D(
            origin: Point3D(x: 1.0, y: 0.0, z: 0.0),
            normal: .unitX
        ))
        let cone = Surface3D.analytic(.cone(
            apex: .origin,
            axis: .unitZ,
            halfAngle: Double.pi / 6.0
        ))
        let boundaryPoints = [
            hyperbolaPoint(parameter: -0.8, branch: 1.0),
            hyperbolaPoint(parameter: 0.8, branch: 1.0),
        ]
        let forward = try #require(try intersector.intersections(
            first: plane,
            second: cone,
            boundaryPoints: boundaryPoints,
            tolerance: tolerance
        ))
        let reversed = try #require(try intersector.intersections(
            first: cone,
            second: plane,
            boundaryPoints: Array(boundaryPoints.reversed()),
            tolerance: tolerance
        ))

        let forwardEndpoints = try endpointKeys(for: forward)
        let reversedEndpoints = try endpointKeys(for: reversed)
        #expect(forwardEndpoints == reversedEndpoints)
    }

    @Test(.timeLimit(.minutes(1)))
    func boundedParabolaProducesVerifiedDualPcurves() throws {
        let halfAngle = Double.pi / 6.0
        let normal = try Vector3D(
            x: cos(halfAngle),
            y: 0.0,
            z: -sin(halfAngle)
        ).normalized(tolerance: tolerance.distance)
        let plane = Surface3D.plane(Plane3D(
            origin: Point3D(
                x: -normal.x,
                y: -normal.y,
                z: -normal.z
            ),
            normal: normal
        ))
        let cone = Surface3D.analytic(.cone(
            apex: .origin,
            axis: .unitZ,
            halfAngle: halfAngle
        ))
        let boundaryPoints = [
            parabolaPoint(parameter: -1.2),
            parabolaPoint(parameter: 1.2),
        ]
        let intersections = try #require(try intersector.intersections(
            first: plane,
            second: cone,
            boundaryPoints: boundaryPoints,
            tolerance: tolerance
        ))
        #expect(intersections.count == 1)
        try assertVerified(
            intersections,
            firstSurface: plane,
            secondSurface: cone,
            expectedEndpoints: boundaryPoints
        )

        let reversed = try #require(try intersector.intersections(
            first: cone,
            second: plane,
            boundaryPoints: Array(boundaryPoints.reversed()),
            tolerance: tolerance
        ))
        let forwardEndpoints = try endpointKeys(for: intersections)
        let reversedEndpoints = try endpointKeys(for: reversed)
        #expect(forwardEndpoints == reversedEndpoints)
    }

    @Test(.timeLimit(.minutes(1)))
    func boundedHyperbolaProvesEmptyWithoutACompleteFaceBoundary() throws {
        let plane = Surface3D.plane(Plane3D(
            origin: Point3D(x: 1.0, y: 0.0, z: 0.0),
            normal: .unitX
        ))
        let cone = Surface3D.analytic(.cone(
            apex: .origin,
            axis: .unitZ,
            halfAngle: Double.pi / 6.0
        ))
        let intersections = try #require(try intersector.intersections(
            first: plane,
            second: cone,
            boundaryPoints: [hyperbolaPoint(parameter: 0.0, branch: 1.0)],
            tolerance: tolerance
        ))
        #expect(intersections.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func boundedConicTruthRoundTripsAndRetainsExactDifferentials() throws {
        let plane = Surface3D.plane(Plane3D(
            origin: Point3D(x: 1.0, y: 0.0, z: 0.0),
            normal: .unitX
        ))
        let cone = Surface3D.analytic(.cone(
            apex: .origin,
            axis: .unitZ,
            halfAngle: Double.pi / 6.0
        ))
        let intersections = try #require(try intersector.intersections(
            first: plane,
            second: cone,
            boundaryPoints: [
                hyperbolaPoint(parameter: -0.8, branch: 1.0),
                hyperbolaPoint(parameter: 0.8, branch: 1.0),
            ],
            tolerance: tolerance
        ))
        let intersection = try #require(intersections.first)
        guard case let .curve(result) = intersection,
              case let .analyticAnalytic(exact) = result.truth,
              case let .boundedPlaneCone(proceduralCurve) = exact.definition,
              case let .bSpline(derivedCurve) = result.derivedRepresentation.curve else {
            Issue.record("Expected bounded plane-cone procedural truth with a derived B-spline cache.")
            return
        }

        let encoded = try JSONEncoder().encode(proceduralCurve)
        let decoded = try JSONDecoder().decode(
            CertifiedBoundedPlaneConeIntersectionCurve.self,
            from: encoded
        )
        #expect(decoded == proceduralCurve)
        try decoded.validate(tolerance: tolerance)
        var unexpectedPayload = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        unexpectedPayload["unexpected"] = true
        let unexpectedData = try JSONSerialization.data(withJSONObject: unexpectedPayload)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(
                CertifiedBoundedPlaneConeIntersectionCurve.self,
                from: unexpectedData
            )
        }

        let bounds = try proceduralCurve.boundingBox(tolerance: tolerance)
        for fraction in [0.0, 0.125, 0.5, 0.875, 1.0] {
            let exactPoint = try proceduralCurve.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            let derivedPoint = try derivedCurve.point(
                at: fraction,
                tolerance: tolerance
            )
            #expect(bounds.contains(exactPoint, tolerance: tolerance.distance))
            #expect((exactPoint - derivedPoint).length <= tolerance.distance)
        }

        let step = 1.0e-4
        for fraction in [0.125, 0.375, 0.625, 0.875] {
            let geometry = try proceduralCurve.differential(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            let lower = try proceduralCurve.point(
                atNormalizedFraction: fraction - step,
                tolerance: tolerance
            )
            let center = try proceduralCurve.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            let upper = try proceduralCurve.point(
                atNormalizedFraction: fraction + step,
                tolerance: tolerance
            )
            let finiteFirst = (upper - lower) / (2.0 * step)
            let finiteSecond = ((upper - center) - (center - lower)) / (step * step)
            #expect((geometry.position - center).length <= tolerance.distance)
            #expect((geometry.firstDerivative - finiteFirst).length <= 1.0e-5)
            #expect((geometry.secondDerivative - finiteSecond).length <= 1.0e-5)
        }
    }

    private func hyperbolaPoint(parameter: Double, branch: Double) -> Point3D {
        Point3D(
            x: 1.0,
            y: sinh(parameter),
            z: branch * sqrt(3.0) * cosh(parameter)
        )
    }

    private func parabolaPoint(parameter: Double) -> Point3D {
        Point3D(
            x: sqrt(3.0) * parameter * parameter / 4.0 - 1.0 / sqrt(3.0),
            y: parameter,
            z: 1.0 + 3.0 * parameter * parameter / 4.0
        )
    }

    private func assertVerified(
        _ intersections: [SurfaceSurfaceIntersection],
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        expectedEndpoints: [Point3D]
    ) throws {
        var endpoints: [Point3D] = []
        for intersection in intersections {
            guard case let .curve(value) = intersection,
                  case let .analyticAnalytic(exact) = value.truth,
                  case .boundedPlaneCone = exact.definition,
                  case .surfaceLift = value.curve,
                  case let .bSpline(derivedCurve) = value.derivedRepresentation.curve,
                  case let .closed(lower, upper) = value.curve.parameterDomain else {
                Issue.record("A bounded conic branch must retain exact procedural truth and a derived B-spline cache.")
                continue
            }
            #expect(value.kind == .transverse)
            #expect(value.maximumResidual <= tolerance.distance)
            endpoints.append(try value.curve.point(at: lower, tolerance: tolerance))
            endpoints.append(try value.curve.point(at: upper, tolerance: tolerance))
            for index in 0...16 {
                let parameter = lower
                    + (upper - lower) * Double(index) / 16.0
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
                #expect((point - firstPoint).length <= tolerance.distance)
                #expect((point - secondPoint).length <= tolerance.distance)
                #expect((point - derivedPoint).length <= tolerance.distance)
            }
        }
        for expectedEndpoint in expectedEndpoints {
            #expect(endpoints.contains {
                ($0 - expectedEndpoint).length <= tolerance.distance
            })
        }
    }

    private func endpointKeys(
        for intersections: [SurfaceSurfaceIntersection]
    ) throws -> [[Double]] {
        try intersections.flatMap { intersection -> [Point3D] in
            guard case let .curve(value) = intersection,
                  case let .closed(lower, upper) = value.curve.parameterDomain else {
                return []
            }
            return [
                try value.curve.point(at: lower, tolerance: tolerance),
                try value.curve.point(at: upper, tolerance: tolerance),
            ]
        }.map { [$0.x, $0.y, $0.z] }.sorted { lhs, rhs in
            lhs.lexicographicallyPrecedes(rhs)
        }
    }
}
