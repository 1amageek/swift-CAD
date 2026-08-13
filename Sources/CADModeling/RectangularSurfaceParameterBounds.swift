public struct RectangularSurfaceParameterBounds: Hashable, Sendable {
    public let lowerU: Double
    public let upperU: Double
    public let lowerV: Double
    public let upperV: Double

    public init(
        lowerU: Double,
        upperU: Double,
        lowerV: Double,
        upperV: Double
    ) {
        self.lowerU = lowerU
        self.upperU = upperU
        self.lowerV = lowerV
        self.upperV = upperV
    }
}
