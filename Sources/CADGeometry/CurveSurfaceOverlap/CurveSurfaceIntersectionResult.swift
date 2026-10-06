/// A complete result in the requested domains, separating points from continuous regions.
public struct CurveSurfaceIntersectionResult: Sendable {
    public let points: [CurveSurfaceIntersection]
    public let overlaps: [CurveSurfaceOverlap]

    init(points: [CurveSurfaceIntersection], overlaps: [CurveSurfaceOverlap]) {
        self.points = points
        self.overlaps = overlaps
    }
}
