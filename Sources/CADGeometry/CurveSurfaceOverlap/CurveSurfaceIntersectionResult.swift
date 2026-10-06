/// A complete result in the requested domains, separating points from continuous regions.
public struct CurveSurfaceIntersectionResult: Sendable {
    public let points: [CurveSurfaceIntersection]
    public let overlaps: [CurveSurfaceOverlap]

    /// Complete original native tuple coverage; nil for legacy source families.
    public let originalNativePoints: OriginalNativeCurveSurfacePoints?

    init(points: [CurveSurfaceIntersection], overlaps: [CurveSurfaceOverlap],
        originalNativePoints: OriginalNativeCurveSurfacePoints? = nil) {
        self.points = points
        self.overlaps = overlaps
        self.originalNativePoints = originalNativePoints
    }
}
