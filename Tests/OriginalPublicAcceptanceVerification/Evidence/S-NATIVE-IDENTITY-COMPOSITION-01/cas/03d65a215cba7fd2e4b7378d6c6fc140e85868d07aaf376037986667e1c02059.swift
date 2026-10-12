public struct Point2D: Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

#if !hasFeature(Embedded)
extension Point2D: Codable {}
#endif
