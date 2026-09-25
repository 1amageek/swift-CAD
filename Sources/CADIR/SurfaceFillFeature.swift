import CADCore

public struct SurfaceFillFeature: Codable, Hashable, Sendable {
    public let targetFeatureID: FeatureID
    public let boundarySeed: StableSubshapeReference

    public init(
        targetFeatureID: FeatureID,
        boundarySeed: StableSubshapeReference
    ) {
        self.targetFeatureID = targetFeatureID
        self.boundarySeed = boundarySeed
    }

    public func validate() throws {
        try boundarySeed.validate()
        guard boundarySeed.subshapeID.featureID == targetFeatureID,
              case .edge = boundarySeed.geometrySignature else {
            throw FeatureEvaluationError.invalidGraph(
                "Surface fill requires an edge reference owned by its target feature."
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case targetFeatureID
        case boundarySeed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.targetFeatureID, .boundarySeed], in: decoder)
        targetFeatureID = try container.decode(FeatureID.self, forKey: .targetFeatureID)
        boundarySeed = try container.decode(StableSubshapeReference.self, forKey: .boundarySeed)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(targetFeatureID, forKey: .targetFeatureID)
        try container.encode(boundarySeed, forKey: .boundarySeed)
    }
}
