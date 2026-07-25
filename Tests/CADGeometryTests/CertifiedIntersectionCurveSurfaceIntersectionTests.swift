import Foundation
import CADCore
@testable import CADGeometry
import Testing

@Suite("Certified intersection curve-surface intersection")
struct CertifiedIntersectionCurveSurfaceIntersectionTests {
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func sphereConeSupportsReducedPlaneIntersections() throws {
        let sphere = Surface3D.analytic(.sphere(
            center: .origin,
            radius: 1.0
        ))
        let cone = Surface3D.analytic(.cone(
            apex: Point3D(x: 1.0, y: 0.0, z: 0.0),
            axis: .unitZ,
            halfAngle: atan(0.5)
        ))

        let curve = try certifiedCurve(first: sphere, second: cone)
        try verifySourceCoincidence(
            curve: curve,
            sourceSurfaces: [sphere, cone]
        )
        try verifyReducedPlaneIntersections(curve: curve)
        try verifyUnsupportedNonPlaneSurface(curve: curve)
    }

    @Test(.timeLimit(.minutes(1)))
    func coneConeSupportsReducedPlaneIntersections() throws {
        let first = Surface3D.analytic(.cone(
            apex: .origin,
            axis: .unitZ,
            halfAngle: atan(0.5)
        ))
        let second = Surface3D.analytic(.cone(
            apex: Point3D(x: 2.0, y: 0.0, z: 4.0),
            axis: .unitY,
            halfAngle: atan(0.375)
        ))

        let curve = try certifiedCurve(first: first, second: second)
        try verifySourceCoincidence(
            curve: curve,
            sourceSurfaces: [first, second]
        )
        try verifyReducedPlaneIntersections(curve: curve)
        try verifyUnsupportedNonPlaneSurface(curve: curve)
    }

    @Test(.timeLimit(.minutes(1)))
    func coneCylinderSupportsReducedPlaneIntersections() throws {
        let cone = Surface3D.analytic(.cone(
            apex: .origin,
            axis: .unitZ,
            halfAngle: atan(0.5)
        ))
        let cylinder = Surface3D.analytic(.cylinder(
            origin: Point3D(x: 1.0, y: 0.0, z: 0.0),
            axis: .unitY,
            radius: 1.0
        ))

        let curve = try certifiedCurve(first: cone, second: cylinder)
        try verifySourceCoincidence(
            curve: curve,
            sourceSurfaces: [cone, cylinder]
        )
        try verifyReducedPlaneIntersections(curve: curve)
        try verifyUnsupportedNonPlaneSurface(curve: curve)
    }

    @Test(.timeLimit(.minutes(1)))
    func coneTorusSupportsReducedPlaneIntersections() throws {
        let coneAxis = try Vector3D(
            x: 0.05,
            y: 0.0,
            z: 1.0
        ).normalized(tolerance: tolerance.distance)
        let cone = Surface3D.analytic(.cone(
            apex: Point3D(x: 4.0, y: 0.0, z: 0.0),
            axis: coneAxis,
            halfAngle: atan(6.0)
        ))
        let torus = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))

        let curve = try certifiedCurve(first: cone, second: torus)
        try verifySourceCoincidence(
            curve: curve,
            sourceSurfaces: [cone, torus]
        )
        try verifyReducedPlaneIntersections(curve: curve)
        try verifyUnsupportedNonPlaneSurface(curve: curve)
    }

    @Test(.timeLimit(.minutes(1)))
    func parallelTorusRetainsExplicitThirdPlaneFailure() throws {
        let first = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 0.5
        ))
        let second = Surface3D.analytic(.torus(
            center: Point3D(x: 1.99, y: 0.0, z: 0.0),
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.5
        ))

        let curve = try certifiedCurve(first: first, second: second)
        try verifySourceCoincidence(
            curve: curve,
            sourceSurfaces: [first, second]
        )
        try verifyUnsupportedPlane(curve: curve)
    }

    private func certifiedCurve(
        first: Surface3D,
        second: Surface3D
    ) throws -> Curve3D {
        let intersections = try DefaultSurfaceSurfaceIntersector().intersections(
            first: first,
            second: second,
            tolerance: tolerance
        )
        for intersection in intersections {
            guard case let .curve(result) = intersection,
                  case .certifiedIntersection = result.curve else {
                continue
            }
            return result.curve
        }
        throw KernelError(
            phase: .geometry,
            code: .intersectionFailure,
            tolerance: tolerance,
            message: "The test fixture did not produce a certified intersection curve."
        )
    }

    private func verifySourceCoincidence(
        curve: Curve3D,
        sourceSurfaces: [Surface3D]
    ) throws {
        let intersector = DefaultCurveSurfaceIntersector()
        for surface in sourceSurfaces {
            do {
                _ = try intersector.intersections(
                    curve: curve,
                    surface: surface,
                    options: .init(),
                    tolerance: tolerance
                )
                Issue.record("A source-surface intersection must be non-discrete.")
            } catch let error as KernelError {
                #expect(error.phase == .geometry)
                #expect(error.code == .nonDiscreteIntersection)
                #expect(error.tolerance == tolerance)
            }
        }
    }

    private func verifyReducedPlaneIntersections(
        curve: Curve3D
    ) throws {
        try verifyRecoveredParameters(curve: curve)

        let expectedParameter = 0.3125
        let expectedGeometry = try curve.differentialGeometry(
            at: expectedParameter,
            tolerance: tolerance
        )
        let plane = Surface3D.analytic(.plane(
            origin: expectedGeometry.position,
            normal: try expectedGeometry.tangent.normalized(
                tolerance: tolerance.distance
            )
        ))
        let curveRange = try ScalarInterval(
            lower: expectedParameter - 0.05,
            upper: expectedParameter + 0.05
        )
        let intersections = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: plane,
            options: .init(curveRange: curveRange),
            tolerance: tolerance
        )
        let expectedIntersection = try #require(
            intersections.min {
                ($0.point - expectedGeometry.position).length
                    < ($1.point - expectedGeometry.position).length
            }
        )
        #expect(
            (expectedIntersection.point - expectedGeometry.position).length
                <= tolerance.distance
        )
        #expect(
            abs(expectedIntersection.curveParameter - expectedParameter)
                <= tolerance.relative * 64.0
        )
        #expect(expectedIntersection.kind == .transverse)

        for intersection in intersections {
            #expect(curveRange.contains(intersection.curveParameter))
            #expect(intersection.residual <= tolerance.distance)
            let curvePoint = try curve.point(
                at: intersection.curveParameter,
                tolerance: tolerance
            )
            #expect(
                (curvePoint - intersection.point).length
                    <= tolerance.distance
            )
            let surfacePoint = try plane.point(
                u: intersection.surfaceU,
                v: intersection.surfaceV,
                tolerance: tolerance
            )
            #expect(
                (surfacePoint - intersection.point).length
                    <= tolerance.distance
            )
        }

        let tangentPlane = Surface3D.analytic(.plane(
            origin: expectedGeometry.position,
            normal: try expectedGeometry.curvatureVector.normalized(
                tolerance: tolerance.distance
            )
        ))
        let tangentIntersections =
            try DefaultCurveSurfaceIntersector().intersections(
                curve: curve,
                surface: tangentPlane,
                options: .init(curveRange: curveRange),
                tolerance: tolerance
            )
        let expectedTangent = try #require(
            tangentIntersections.min {
                ($0.point - expectedGeometry.position).length
                    < ($1.point - expectedGeometry.position).length
            }
        )
        #expect(
            (expectedTangent.point - expectedGeometry.position).length
                <= tolerance.distance
        )
        #expect(
            abs(expectedTangent.curveParameter - expectedParameter)
                <= tolerance.relative * 64.0
        )
        #expect(expectedTangent.kind == .tangent)

        let bounds = try certifiedBoundingBox(curve: curve)
        let emptyPlane = Surface3D.analytic(.plane(
            origin: Point3D(
                x: bounds.maximum.x + max(bounds.size.length, 1.0) + 1.0,
                y: bounds.center.y,
                z: bounds.center.z
            ),
            normal: .unitX
        ))
        let empty = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: emptyPlane,
            options: .init(),
            tolerance: tolerance
        )
        #expect(empty.isEmpty)
    }

    private func verifyRecoveredParameters(
        curve: Curve3D
    ) throws {
        guard case let .certifiedIntersection(certifiedCurve) = curve else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "The test requires a certified intersection curve."
            )
        }
        let resolver = DefaultCertifiedIntersectionParameterResolver()
        for expectedParameter in [0.0, 0.125, 0.3125, 0.5, 0.8125, 1.0] {
            let expectedPoint = try certifiedCurve.point(
                atNormalizedFraction: expectedParameter,
                tolerance: tolerance
            )
            let recovered = try resolver.normalizedParameters(
                of: expectedPoint,
                on: certifiedCurve,
                restrictedTo: nil,
                tolerance: tolerance
            )
            #expect(recovered.contains {
                abs($0 - expectedParameter) <= tolerance.relative * 64.0
            })
            for parameter in recovered {
                let recoveredPoint = try certifiedCurve.point(
                    atNormalizedFraction: parameter,
                    tolerance: tolerance
                )
                #expect(
                    (recoveredPoint - expectedPoint).length
                        <= tolerance.distance
                )
            }
        }
    }

    private func verifyUnsupportedNonPlaneSurface(
        curve: Curve3D
    ) throws {
        let thirdSurface = Surface3D.analytic(.sphere(
            center: Point3D(x: 100.0, y: 100.0, z: 100.0),
            radius: 1.0
        ))
        do {
            _ = try DefaultCurveSurfaceIntersector().intersections(
                curve: curve,
                surface: thirdSurface,
                options: .init(),
                tolerance: tolerance
            )
            Issue.record("A non-plane third-surface path must remain explicitly unsupported.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .unsupportedCapability)
            #expect(error.tolerance == tolerance)
        }
    }

    private func verifyUnsupportedPlane(curve: Curve3D) throws {
        do {
            _ = try DefaultCurveSurfaceIntersector().intersections(
                curve: curve,
                surface: .analytic(.plane(
                    origin: Point3D(x: 0.0, y: 0.0, z: 100.0),
                    normal: .unitZ
                )),
                options: .init(),
                tolerance: tolerance
            )
            Issue.record("A third-surface path must remain explicitly unsupported.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .unsupportedCapability)
            #expect(error.tolerance == tolerance)
        }
    }

    private func certifiedBoundingBox(
        curve: Curve3D
    ) throws -> BoundingBox3D {
        guard case let .certifiedIntersection(certifiedCurve) = curve else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "The test requires a certified intersection curve."
            )
        }
        switch certifiedCurve {
        case let .sphereCone(curve):
            return try curve.boundingBox(tolerance: tolerance)
        case let .coneCone(curve):
            return try curve.boundingBox(tolerance: tolerance)
        case let .coneCylinder(curve):
            return try curve.boundingBox(tolerance: tolerance)
        case let .coneTorus(curve):
            return try curve.boundingBox(tolerance: tolerance)
        case let .parallelTorusTorus(curve):
            return try curve.boundingBox(tolerance: tolerance)
        }
    }
}
