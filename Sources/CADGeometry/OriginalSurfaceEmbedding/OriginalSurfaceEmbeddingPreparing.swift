import CADCore

package protocol OriginalSurfaceEmbeddingPreparing: Sendable {
    func prepare(surface: Surface3D, over domain: SurfaceParameterBox,
        options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance,
        maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        maximumAlgebraicDepth: Int?, consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?) throws -> any OriginalSurfaceEmbeddingSession

    func prepare(surface: Surface3D, over domain: SurfaceParameterBox,
        options: SurfaceSurfaceIntersectionOptions, tolerance: ModelingTolerance,
        admission: GeometryConversionAdmission) throws -> any OriginalSurfaceEmbeddingSession
}
