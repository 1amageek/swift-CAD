/// Whole-parameter screen bounds and the retained original spatial enclosure.
public struct OrthographicCurveEnclosure: Sendable {
    public let position: CoordinateEnclosure2D
    public let firstDerivative: CoordinateEnclosure2D
    public let secondDerivative: CoordinateEnclosure2D
    public let original: CurveDifferentialEnclosure

    public init(position: CoordinateEnclosure2D, firstDerivative: CoordinateEnclosure2D,
        secondDerivative: CoordinateEnclosure2D, original: CurveDifferentialEnclosure) {
        self.position = position
        self.firstDerivative = firstDerivative
        self.secondDerivative = secondDerivative
        self.original = original
    }
}
