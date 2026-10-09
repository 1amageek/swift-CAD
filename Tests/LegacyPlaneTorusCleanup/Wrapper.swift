@testable import CADGeometry
import CADCore

/// Exercises the copied production dispatcher with the same validated source pair.
public func planeTorus(origin: Point3D, normal: Vector3D, reversed: Bool,
    options: SurfaceSurfaceIntersectionOptions = .init()) throws -> [SurfaceSurfaceIntersection] {
    let tolerance = ModelingTolerance.standard
    let planeSurface = Surface3D.plane(Plane3D(origin: origin, normal: normal))
    let torusSurface = Surface3D.analytic(.torus(center: .origin, axis: .unitZ,
        majorRadius: 3, minorRadius: 1))
    try planeSurface.validate(tolerance: tolerance)
    try torusSurface.validate(tolerance: tolerance)
    guard case let .plane(plane) = CanonicalAnalyticSurface(planeSurface),
        case let .torus(torus) = CanonicalAnalyticSurface(torusSurface) else {
        throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
            message: "Cleanup proof requires the original plane and torus sources.")
    }
    return try PlaneTorusSurfaceIntersector().intersections(plane: plane, torus: torus,
        firstSurface: reversed ? torusSurface : planeSurface,
        secondSurface: reversed ? planeSurface : torusSurface,
        options: options, tolerance: tolerance)
}
