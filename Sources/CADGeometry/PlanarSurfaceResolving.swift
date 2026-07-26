import CADCore

struct ResolvedPlaneGeometry: Sendable {
    let origin: Point3D
    let normal: Vector3D
}

protocol PlanarSurfaceResolving: Sendable {
    func canonicalPlane(
        for surface: Surface3D
    ) -> ResolvedPlaneGeometry?

    func exactPlane(
        for surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> ResolvedPlaneGeometry?
}
