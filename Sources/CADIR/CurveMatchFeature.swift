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

    private enum CodingKeys: String, CodingKey {
        case source
        case sourceEnd
        case target
        case targetEnd
        case targetOrientation
        case continuity
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.source, .sourceEnd, .target, .targetEnd, .targetOrientation, .continuity],
            in: decoder
        )
        source = try container.decode(CurveOutputReference.self, forKey: .source)
        sourceEnd = try container.decode(CurveEndpointEnd.self, forKey: .sourceEnd)
        target = try container.decode(CurveOutputReference.self, forKey: .target)
        targetEnd = try container.decode(CurveEndpointEnd.self, forKey: .targetEnd)
        targetOrientation = try container.decode(
            CurveFrameOrientation.self,
            forKey: .targetOrientation
        )
        continuity = try container.decode(CurveContinuityLevel.self, forKey: .continuity)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(source, forKey: .source)
        try container.encode(sourceEnd, forKey: .sourceEnd)
        try container.encode(target, forKey: .target)
        try container.encode(targetEnd, forKey: .targetEnd)
        try container.encode(targetOrientation, forKey: .targetOrientation)
        try container.encode(continuity, forKey: .continuity)
    }
}
