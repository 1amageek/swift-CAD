import CADCore

/// Fillet Shell's variable point: the fillet's radius (or distance) at a fraction of its edge's
/// length from its start; the radius follows the natural cubic spline through the points and the
/// edge's ends.
public struct FilletVariablePoint: Codable, Hashable, Sendable {
    public let position: Double
    public let radius: CADExpression

    public init(position: Double, radius: CADExpression) {
        self.position = position
        self.radius = radius
    }
}
