/// Rich SSI publication; native empty results retain complete exclusion authority.
public struct SurfaceSurfaceIntersectionResult: Sendable {
    public let intersections: [SurfaceSurfaceIntersection]
    public let originalNativePoints: OriginalNativeSurfaceSurfacePoints?

    init(intersections: [SurfaceSurfaceIntersection],
        originalNativePoints: OriginalNativeSurfaceSurfacePoints? = nil) {
        self.intersections = intersections
        self.originalNativePoints = originalNativePoints
    }
}
