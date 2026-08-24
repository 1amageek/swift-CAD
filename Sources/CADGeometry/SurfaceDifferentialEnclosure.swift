public struct SurfaceDifferentialEnclosure: Codable, Equatable, Hashable, Sendable {
    public let position: CoordinateEnclosure3D
    public let tangentU: CoordinateEnclosure3D
    public let tangentV: CoordinateEnclosure3D
    public let secondDerivativeUU: CoordinateEnclosure3D
    public let secondDerivativeUV: CoordinateEnclosure3D
    public let secondDerivativeVV: CoordinateEnclosure3D

    public init(
        position: CoordinateEnclosure3D,
        tangentU: CoordinateEnclosure3D,
        tangentV: CoordinateEnclosure3D,
        secondDerivativeUU: CoordinateEnclosure3D,
        secondDerivativeUV: CoordinateEnclosure3D,
        secondDerivativeVV: CoordinateEnclosure3D
    ) {
        self.position = position
        self.tangentU = tangentU
        self.tangentV = tangentV
        self.secondDerivativeUU = secondDerivativeUU
        self.secondDerivativeUV = secondDerivativeUV
        self.secondDerivativeVV = secondDerivativeVV
    }
}
