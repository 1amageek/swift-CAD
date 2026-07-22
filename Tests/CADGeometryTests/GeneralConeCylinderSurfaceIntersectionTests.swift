import Foundation
import CADCore
@testable import CADGeometry
import Testing

@Suite("General Cone-Cylinder Surface Intersection", .serialized)
struct GeneralConeCylinderSurfaceIntersectionTests {
    private let intersector = DefaultSurfaceSurfaceIntersector()
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func transverseAxesProduceTwoVerifiedClosedSplineCurves() throws {
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
    func parallelOffsetAxesProduceTwoVerifiedClosedSplineCurves() throws {
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
    func angularDomainSplitsProduceVerifiedMixedSplineCurves() throws {
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

        #expect(curves(forward) == curves(reverse))
    }

    @Test(.timeLimit(.minutes(1)))
    func coneApexContactReturnsTypedDiagnostic() throws {
        do {
            _ = try intersector.intersections(
                first: cone(),
                second: cylinder(
                    origin: Point3D(x: 1.0, y: 0.0, z: 0.0),
                    axis: .unitY,
                    radius: 1.0
                ),
                tolerance: tolerance
            )
            Issue.record("A cone-apex contact must not produce a singular pcurve.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .singularGeometry)
            #expect(error.residual != nil)
            #expect(error.tolerance == tolerance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cylinderGeneratorParallelToConeRulingReturnsTypedSingularity() throws {
        let halfAngle = atan(0.5)
        let rulingDirection = Vector3D(
            x: sin(halfAngle),
            y: 0.0,
            z: cos(halfAngle)
        )

        do {
            _ = try intersector.intersections(
                first: cone(halfAngle: halfAngle),
                second: cylinder(
                    origin: Point3D(x: 0.0, y: 0.0, z: 4.0),
                    axis: rulingDirection,
                    radius: 1.0
                ),
                tolerance: tolerance
            )
            Issue.record("A ruling-parallel cylinder generator must return a singular diagnostic.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .singularSystem)
            #expect(error.residual != nil)
            #expect(error.tolerance == tolerance)
        }
    }

    private func verifyCurve(
        _ intersection: SurfaceSurfaceIntersection,
        first: Surface3D,
        second: Surface3D,
        expectedKind: CurveSurfaceIntersectionKind
    ) throws {
        guard case let .curve(result) = intersection,
              case .bSpline = result.curve,
              case let .closed(lower, upper) = result.curve.parameterDomain else {
            Issue.record("A regular general cone-cylinder intersection must produce a bounded B-spline curve.")
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

    private func curves(_ intersections: [SurfaceSurfaceIntersection]) -> [Curve3D] {
        intersections.compactMap { intersection in
            guard case let .curve(curve) = intersection else { return nil }
            return curve.curve
        }
    }
}
