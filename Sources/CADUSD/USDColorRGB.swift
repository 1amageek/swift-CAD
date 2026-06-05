public struct USDColorRGB: Sendable, Hashable {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }
}
