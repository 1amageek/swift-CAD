public struct KernelError: Error, Codable, Equatable, Sendable {
    public let phase: KernelPhase
    public let code: KernelErrorCode
    public let featureID: FeatureID?
    public let subshapeID: SubshapeID?
    public let residual: Double?
    public let tolerance: ModelingTolerance?
    public let message: String

    public init(
        phase: KernelPhase,
        code: KernelErrorCode,
        featureID: FeatureID? = nil,
        subshapeID: SubshapeID? = nil,
        residual: Double? = nil,
        tolerance: ModelingTolerance? = nil,
        message: String
    ) {
        self.phase = phase
        self.code = code
        self.featureID = featureID
        self.subshapeID = subshapeID
        self.residual = residual
        self.tolerance = tolerance
        self.message = message
    }
}
