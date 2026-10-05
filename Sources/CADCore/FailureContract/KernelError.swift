public struct KernelError: Error, Equatable, Sendable {
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
        tolerance: ModelingTolerance?,
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

    public var category: KernelFailureCategory { code.category }

    public static func unsupportedEvaluation(
        featureID: FeatureID? = nil,
        subshapeID: SubshapeID? = nil,
        residual: Double? = nil,
        tolerance: ModelingTolerance,
        message: String
    ) -> KernelError {
        KernelError(
            phase: .evaluation,
            code: .unsupportedCapability,
            featureID: featureID,
            subshapeID: subshapeID,
            residual: residual,
            tolerance: tolerance,
            message: message
        )
    }
}

#if !hasFeature(Embedded)
extension KernelError: Codable {}
#endif
