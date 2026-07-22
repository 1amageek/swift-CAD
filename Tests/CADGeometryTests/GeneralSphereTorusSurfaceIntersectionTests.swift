import Testing
import CADCore
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
    func radialAndAxialOffsetSphereProducesTwoVerifiedClosedCurves() throws {
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
    func tiltedTorusAxisProducesRotationInvariantVerifiedCurves() throws {
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
    func partialAngularDomainProducesOneVerifiedMixedCurve() throws {
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
                  case let .bSpline(curve) = value.curve,
                  case let .closed(lower, upper) = curve.domain else {
                Issue.record("General sphere-torus intersection must produce bounded B-spline curves.")
                continue
            }
            #expect(value.kind == expectedKind)
            #expect(value.maximumResidual <= tolerance.distance)
            let start = try curve.point(at: lower, tolerance: tolerance)
            let end = try curve.point(at: upper, tolerance: tolerance)
            #expect((start - end).length <= tolerance.distance)
            for index in 0...32 {
                let parameter = lower
                    + (upper - lower) * Double(index) / 32.0
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
