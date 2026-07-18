public struct ModelingTolerance: Codable, Hashable, Sendable {
    public var distance: Double
    public var angle: Double
    public var relative: Double

    public init(
        distance: Double,
        angle: Double,
        relative: Double = 1.0e-9
    ) {
        self.distance = distance
        self.angle = angle
        self.relative = relative
    }

    public static let standard = ModelingTolerance(
        distance: 1.0e-6,
        angle: 1.0e-9,
        relative: 1.0e-9
    )

    public func validate() throws {
        guard distance.isFinite,
              distance > 0.0,
              angle.isFinite,
              angle > 0.0,
              relative.isFinite,
              relative > 0.0 else {
            throw GeometryError.invalidModelingTolerance(
                distance: distance,
                angle: angle,
                relative: relative
            )
        }
    }
}
