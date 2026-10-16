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

    func exactPlane(for surface: Surface3D, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> ResolvedPlaneGeometry?
}

extension PlanarSurfaceResolving {
    // FIXME(INCOMPLETE_IMPLEMENTATION): Injected plane resolvers must implement
    // original source resolution under the caller execution before exact-plane
    // consumers may use this admitted witness.
    package func exactPlane(for surface: Surface3D, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> ResolvedPlaneGeometry? {
        try execution.checkpoint()
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "This plane resolver has no direct original source witness.")
    }
}
