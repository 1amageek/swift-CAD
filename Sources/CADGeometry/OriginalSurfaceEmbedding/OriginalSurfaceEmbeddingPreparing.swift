import CADCore

package protocol OriginalSurfaceEmbeddingPreparing: Sendable {
    func prepare(surface: Surface3D, over domain: SurfaceParameterBox,
        options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> any OriginalSurfaceEmbeddingSession
}
