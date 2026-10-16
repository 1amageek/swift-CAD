import CADCore

protocol SurfaceNormalResolving: Sendable {
    func normal(
        at point: Point3D,
        on surface: Surface3D,
        u: Double,
        v: Double,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution
    ) throws -> Vector3D
}
