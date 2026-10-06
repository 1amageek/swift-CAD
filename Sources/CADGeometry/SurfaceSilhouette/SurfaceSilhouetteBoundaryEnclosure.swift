/// Original complete-interval boundary values and one-sided tangent bounds.
public struct SurfaceSilhouetteBoundaryEnclosure: Sendable {
    public let position: CoordinateEnclosure2D
    public let tangent: CoordinateEnclosure2D
    public let hasSmoothDerivatives: Bool

    init(position: CoordinateEnclosure2D, tangent: CoordinateEnclosure2D,
         hasSmoothDerivatives: Bool) {
        self.position = position; self.tangent = tangent
        self.hasSmoothDerivatives = hasSmoothDerivatives
    }
}
