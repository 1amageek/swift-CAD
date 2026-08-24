public struct CurveDifferentialEnclosure: Codable, Equatable, Hashable, Sendable {
    public let position: CoordinateEnclosure3D
    public let firstDerivative: CoordinateEnclosure3D
    public let secondDerivative: CoordinateEnclosure3D

    public init(
        position: CoordinateEnclosure3D,
        firstDerivative: CoordinateEnclosure3D,
        secondDerivative: CoordinateEnclosure3D
    ) {
        self.position = position
        self.firstDerivative = firstDerivative
        self.secondDerivative = secondDerivative
    }
}
