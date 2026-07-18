import CADCore

public struct CurveMatchFeature: Codable, Hashable, Sendable {
    public let source: CurveOutputReference
    public let sourceEnd: CurveEndpointEnd
    public let target: CurveOutputReference
    public let targetEnd: CurveEndpointEnd
    public let targetOrientation: CurveFrameOrientation
    public let continuity: CurveContinuityLevel

    public init(
        source: CurveOutputReference,
        sourceEnd: CurveEndpointEnd,
        target: CurveOutputReference,
        targetEnd: CurveEndpointEnd,
        targetOrientation: CurveFrameOrientation = .forward,
        continuity: CurveContinuityLevel
    ) {
        self.source = source
        self.sourceEnd = sourceEnd
        self.target = target
        self.targetEnd = targetEnd
        self.targetOrientation = targetOrientation
        self.continuity = continuity
    }

    public func validate() throws {
        try source.validate()
        try target.validate()
        guard source != target else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                tolerance: nil,
                message: "Curve match source and target must be different curve outputs."
            )
        }
    }
}
