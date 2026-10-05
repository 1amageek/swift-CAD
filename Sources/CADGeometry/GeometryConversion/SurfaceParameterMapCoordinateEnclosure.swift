import CADCore

/// Complete second-order bounds for one original coordinate on a consumer UV box.
public struct SurfaceParameterMapCoordinateEnclosure: Sendable {
    public let value: ScalarInterval
    public let derivativeU: ScalarInterval
    public let derivativeV: ScalarInterval
    public let secondDerivativeUU: ScalarInterval
    public let secondDerivativeUV: ScalarInterval
    public let secondDerivativeVV: ScalarInterval

    public init(value: ScalarInterval, derivativeU: ScalarInterval,
        derivativeV: ScalarInterval, secondDerivativeUU: ScalarInterval,
        secondDerivativeUV: ScalarInterval, secondDerivativeVV: ScalarInterval) {
        self.value = value
        self.derivativeU = derivativeU
        self.derivativeV = derivativeV
        self.secondDerivativeUU = secondDerivativeUU
        self.secondDerivativeUV = secondDerivativeUV
        self.secondDerivativeVV = secondDerivativeVV
    }
}
