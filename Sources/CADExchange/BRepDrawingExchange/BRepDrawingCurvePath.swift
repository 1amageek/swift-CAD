import CADCore
import CADGeometry

/// Unscaled original SI polyline with directed native parameter provenance.
public struct BRepDrawingCurvePath: Sendable {
    public struct Sample: Sendable {
        public let parameter: Double
        public let point: Point2D
    }
    public let curve: OrthographicProjectedCurve
    public let startParameter: Double
    public let endParameter: Double
    public let samples: [Sample]
}
