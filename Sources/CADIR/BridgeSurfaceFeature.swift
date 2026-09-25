import CADCore

public struct BridgeSurfaceFeature: Codable, Sendable, Hashable {
    public enum EndOrientation: String, Codable, Sendable, Hashable {
        case forward
        case reversed
    }

    public let startBoundary: StableSubshapeReference
    public let endBoundary: StableSubshapeReference
    public let endOrientation: EndOrientation

    public init(
        startBoundary: StableSubshapeReference,
        endBoundary: StableSubshapeReference,
        endOrientation: EndOrientation = .forward
    ) {
        self.startBoundary = startBoundary
        self.endBoundary = endBoundary
        self.endOrientation = endOrientation
    }

    private enum CodingKeys: String, CodingKey {
        case startBoundary
        case endBoundary
        case endOrientation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.startBoundary, .endBoundary, .endOrientation],
            in: decoder
        )
        startBoundary = try container.decode(StableSubshapeReference.self, forKey: .startBoundary)
        endBoundary = try container.decode(StableSubshapeReference.self, forKey: .endBoundary)
        endOrientation = try container.decode(
            EndOrientation.self,
            forKey: .endOrientation
        )
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(startBoundary, forKey: .startBoundary)
        try container.encode(endBoundary, forKey: .endBoundary)
        try container.encode(endOrientation, forKey: .endOrientation)
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try startBoundary.validate()
        try endBoundary.validate()
        guard startBoundary.subshapeID != endBoundary.subshapeID,
              case .edge = startBoundary.geometrySignature,
              case .edge = endBoundary.geometrySignature else {
            throw FeatureEvaluationError.invalidGraph(
                "Bridge surface requires two distinct edge references."
            )
        }
    }

    public var targetFeatureID: FeatureID { startBoundary.subshapeID.featureID }

    public var sourceInputs: [FeatureInput] {
        let first = FeatureInput(featureID: targetFeatureID, role: .target)
        let secondID = endBoundary.subshapeID.featureID
        return secondID == targetFeatureID
            ? [first]
            : [first, FeatureInput(featureID: secondID, role: .target)]
    }
}
