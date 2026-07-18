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
                  case let .bSpline(curve) = value.curve,
                  case let .closed(lower, upper) = curve.domain else {
                Issue.record("A bounded hyperbolic branch must use a finite B-spline contract.")
                continue
            }
            #expect(value.kind == .transverse)
            #expect(value.maximumResidual <= tolerance.distance)
            endpoints.append(try curve.point(at: lower, tolerance: tolerance))
            endpoints.append(try curve.point(at: upper, tolerance: tolerance))
            for index in 0...16 {
                let parameter = lower
                    + (upper - lower) * Double(index) / 16.0
                let point = try curve.point(at: parameter, tolerance: tolerance)
                let planeUV = try value.firstSurfaceParameterCurve.parameter(
                    atCurveParameter: parameter,
                    curveDomain: curve.domain,
                    tolerance: tolerance
                )
                let coneUV = try value.secondSurfaceParameterCurve.parameter(
                    atCurveParameter: parameter,
                    curveDomain: curve.domain,
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
                  case let .bSpline(curve) = value.curve,
                  case let .closed(lower, upper) = curve.domain else {
                Issue.record("A bounded conic branch must use a finite B-spline contract.")
                continue
            }
            #expect(value.kind == .transverse)
            #expect(value.maximumResidual <= tolerance.distance)
            endpoints.append(try curve.point(at: lower, tolerance: tolerance))
            endpoints.append(try curve.point(at: upper, tolerance: tolerance))
            for index in 0...16 {
                let parameter = lower
                    + (upper - lower) * Double(index) / 16.0
                let point = try curve.point(at: parameter, tolerance: tolerance)
                let firstUV = try value.firstSurfaceParameterCurve.parameter(
                    atCurveParameter: parameter,
                    curveDomain: curve.domain,
                    tolerance: tolerance
                )
                let secondUV = try value.secondSurfaceParameterCurve.parameter(
                    atCurveParameter: parameter,
                    curveDomain: curve.domain,
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
