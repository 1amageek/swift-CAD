/// Rich SSI publication; native empty results retain complete exclusion authority.
public struct SurfaceSurfaceIntersectionResult: Sendable {
    /// Numerical representations of isolated components; full positive-dimensional coverage is retained separately.
    public let intersections: [SurfaceSurfaceIntersection]
    public let originalNativeRelations: OriginalNativeSurfaceSurfaceRelations?
    public let originalNativePoints: OriginalNativeSurfaceSurfacePoints?

    init(intersections: [SurfaceSurfaceIntersection],
        originalNativePoints: OriginalNativeSurfaceSurfacePoints? = nil,
        originalNativeRelations: OriginalNativeSurfaceSurfaceRelations? = nil) {
        self.intersections = intersections
        self.originalNativePoints = originalNativePoints
        self.originalNativeRelations = originalNativeRelations
    }

}
