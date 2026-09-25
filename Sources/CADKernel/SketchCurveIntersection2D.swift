import CADCore

/// A certified intersection of two sketch curves, located by each curve's natural parameter
/// (see `SketchCurveGeometry2D`).
public struct SketchCurveIntersection2D: Sendable, Hashable {
    public var point: Point2D
    public var firstParameter: Double
    public var secondParameter: Double

    public init(point: Point2D, firstParameter: Double, secondParameter: Double) {
        self.point = point
        self.firstParameter = firstParameter
        self.secondParameter = secondParameter
    }
}
