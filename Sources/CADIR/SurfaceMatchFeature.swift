import CADCore

public struct SurfaceMatchFeature: Codable, Hashable, Sendable {
    public let source: SurfaceOperationTargetReference
    public let target: SurfaceOperationTargetReference
    public let sourceParameter: SurfaceParameter
    public let targetParameter: SurfaceParameter
    public let normalAlignment: SurfaceNormalAlignment
    public let continuity: SurfaceContinuityLevel

    public init(
        source: SurfaceOperationTargetReference,
        target: SurfaceOperationTargetReference,
        sourceParameter: SurfaceParameter,
        targetParameter: SurfaceParameter,
        normalAlignment: SurfaceNormalAlignment = .aligned,
        continuity: SurfaceContinuityLevel
    ) {
        self.source = source
        self.target = target
        self.sourceParameter = sourceParameter
        self.targetParameter = targetParameter
        self.normalAlignment = normalAlignment
        self.continuity = continuity
    }

    public func validate() throws {
        try source.validate()
        try target.validate()
        guard source.featureID != target.featureID else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                tolerance: nil,
                message: "Surface match source and target must be different sheet features."
            )
        }
        guard sourceParameter.u.isFinite,
              sourceParameter.v.isFinite,
              targetParameter.u.isFinite,
              targetParameter.v.isFinite else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                tolerance: nil,
                message: "Surface match parameters must be finite."
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case source
        case target
        case sourceParameter
        case targetParameter
        case normalAlignment
        case continuity
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.source, .target, .sourceParameter, .targetParameter, .normalAlignment, .continuity],
            in: decoder
        )
        source = try container.decode(SurfaceOperationTargetReference.self, forKey: .source)
        target = try container.decode(SurfaceOperationTargetReference.self, forKey: .target)
        sourceParameter = try container.decode(SurfaceParameter.self, forKey: .sourceParameter)
        targetParameter = try container.decode(SurfaceParameter.self, forKey: .targetParameter)
        normalAlignment = try container.decode(SurfaceNormalAlignment.self, forKey: .normalAlignment)
        continuity = try container.decode(SurfaceContinuityLevel.self, forKey: .continuity)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(source, forKey: .source)
        try container.encode(target, forKey: .target)
        try container.encode(sourceParameter, forKey: .sourceParameter)
        try container.encode(targetParameter, forKey: .targetParameter)
        try container.encode(normalAlignment, forKey: .normalAlignment)
        try container.encode(continuity, forKey: .continuity)
    }
}
