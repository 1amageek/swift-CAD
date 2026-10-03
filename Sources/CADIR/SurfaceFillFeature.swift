import CADCore

/// A sheet filling an opening of a target's open boundary, the loop through `boundarySeed`: a
/// surface built over the loop, or with `insertedSheet` (Plasticity's Insert Sheet, Trim to hole)
/// the part of that sheet the loop encloses, the loop's edges lying on it.
public struct SurfaceFillFeature: Codable, Hashable, Sendable {
    public let targetFeatureID: FeatureID
    public let boundarySeed: StableSubshapeReference
    /// The sheet trimmed to the opening, nil for a built fill.
    public let insertedSheet: FeatureID?

    public init(
        targetFeatureID: FeatureID,
        boundarySeed: StableSubshapeReference,
        insertedSheet: FeatureID? = nil
    ) {
        self.targetFeatureID = targetFeatureID
        self.boundarySeed = boundarySeed
        self.insertedSheet = insertedSheet
    }

    /// The features the fill consumes: its target and any inserted sheet.
    public var inputs: [FeatureInput] {
        [FeatureInput(featureID: targetFeatureID, role: .target)]
            + (insertedSheet.map { [FeatureInput(featureID: $0, role: .body)] } ?? [])
    }

    public func validate() throws {
        guard insertedSheet != targetFeatureID else {
            throw FeatureEvaluationError.invalidGraph("An inserted sheet is another sheet than the one with the opening.")
        }
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
        case insertedSheet
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.targetFeatureID, .boundarySeed, .insertedSheet], in: decoder)
        targetFeatureID = try container.decode(FeatureID.self, forKey: .targetFeatureID)
        boundarySeed = try container.decode(StableSubshapeReference.self, forKey: .boundarySeed)
        insertedSheet = try container.decodeIfPresent(FeatureID.self, forKey: .insertedSheet)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(targetFeatureID, forKey: .targetFeatureID)
        try container.encode(boundarySeed, forKey: .boundarySeed)
        try container.encodeIfPresent(insertedSheet, forKey: .insertedSheet)
    }
}
