import CADCore

package struct ResolvedPlaneGeometry: Sendable {
    package let origin: Point3D
    package let normal: Vector3D
}

package protocol PlanarSurfaceResolving: Sendable {
    func canonicalPlane(
        for surface: Surface3D
    ) -> ResolvedPlaneGeometry?

    func exactPlane(
        for surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> ResolvedPlaneGeometry?
}
