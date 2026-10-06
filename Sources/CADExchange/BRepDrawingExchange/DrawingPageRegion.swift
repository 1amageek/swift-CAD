import CADCore

/// Producer-assembled outer/inner section contours in final paper points.
public struct DrawingPageRegion: Sendable {
    public let identity: String
    public let loops: [[Point2D]]
    public let outer: [Bool]
    public init(identity: String, loops: [[Point2D]], outer: [Bool]) {
        self.identity = identity; self.loops = loops; self.outer = outer
    }
}
