import Foundation
import CADCore
@testable import CADGeometry
import Testing

@Suite("Certified intersection curve-surface intersection")
struct CertifiedIntersectionCurveSurfaceIntersectionTests {
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func sphereConeSourceSurfacesReportContinuousCoincidence() throws {
        let sphere = Surface3D.analytic(.sphere(
            center: .origin,
            radius: 1.0
        ))
        let cone = Surface3D.analytic(.cone(
            apex: Point3D(x: 1.0, y: 0.0, z: 0.0),
            axis: .unitZ,
            halfAngle: atan(0.5)
        ))

        try verifySourceCoincidenceAndThirdSurfaceFailure(
            curve: certifiedCurve(first: sphere, second: cone),
            sourceSurfaces: [sphere, cone]
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func coneConeSourceSurfacesReportContinuousCoincidence() throws {
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

        try verifySourceCoincidenceAndThirdSurfaceFailure(
            curve: certifiedCurve(first: first, second: second),
            sourceSurfaces: [first, second]
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func coneCylinderSourceSurfacesReportContinuousCoincidence() throws {
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

        try verifySourceCoincidenceAndThirdSurfaceFailure(
            curve: certifiedCurve(first: cone, second: cylinder),
            sourceSurfaces: [cone, cylinder]
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func coneTorusSourceSurfacesReportContinuousCoincidence() throws {
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

        try verifySourceCoincidenceAndThirdSurfaceFailure(
            curve: certifiedCurve(first: cone, second: torus),
            sourceSurfaces: [cone, torus]
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func parallelTorusSourceSurfacesReportContinuousCoincidence() throws {
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

        try verifySourceCoincidenceAndThirdSurfaceFailure(
            curve: certifiedCurve(first: first, second: second),
            sourceSurfaces: [first, second]
        )
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

    private func verifySourceCoincidenceAndThirdSurfaceFailure(
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

        do {
            _ = try intersector.intersections(
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
}
