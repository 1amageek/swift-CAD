import CADCore

/// A sheet filling an opening of a target's open boundary, the loop through `boundarySeed`: a
/// surface built over the loop, or with `insertedSheet` (Plasticity's Insert Sheet, Trim to hole)
/// the part of that sheet the loop encloses, the loop's edges lying on it. With `guides`
/// (Plasticity's Patch Faces Multiple through guides) each guide curve, running between two
/// corners of the loop, divides the opening, and each part is filled as a face of its own, the
/// faces meeting along the guides. With `trimsToSheet` (Insert Sheet's Trim to sheet, inferred
/// with the user 2026-10-05) the inserted sheet is kept whole instead: its open boundary, lying on
/// the target around the opening, cuts the target back, and the fill is the target so trimmed and
/// the inserted sheet sewn into one sheet.
public struct SurfaceFillFeature: Codable, Hashable, Sendable {
    public let targetFeatureID: FeatureID
    public let boundarySeed: StableSubshapeReference
    /// The sheet trimmed to the opening, nil for a built fill.
    public let insertedSheet: FeatureID?
    /// Curves dividing the opening into faces, each between two of the loop's corners.
    public let guides: [CurveSectionReference]
    /// Whether the target is trimmed to the inserted sheet's boundary rather than the sheet to the opening.
    public let trimsToSheet: Bool

    public init(
        targetFeatureID: FeatureID,
        boundarySeed: StableSubshapeReference,
        insertedSheet: FeatureID? = nil,
        guides: [CurveSectionReference] = [],
        trimsToSheet: Bool = false
    ) {
        self.targetFeatureID = targetFeatureID
        self.boundarySeed = boundarySeed
        self.insertedSheet = insertedSheet
        self.guides = guides
        self.trimsToSheet = trimsToSheet
    }

    /// The features the fill consumes: its target, any inserted sheet and its guides.
    public var inputs: [FeatureInput] {
        var seen = Set<FeatureInput>()
        return ([FeatureInput(featureID: targetFeatureID, role: .target)]
            + (insertedSheet.map { [FeatureInput(featureID: $0, role: .body)] } ?? [])
            + guides.map { FeatureInput(featureID: $0.featureID, role: .guide) })
            .filter { seen.insert($0).inserted }
    }

    public func validate() throws {
        guard insertedSheet != targetFeatureID else {
            throw FeatureEvaluationError.invalidGraph("An inserted sheet is another sheet than the one with the opening.")
        }
        guard guides.isEmpty || insertedSheet == nil else {
            throw FeatureEvaluationError.invalidGraph("An inserted sheet fills an opening without guides.")
        }
        guard trimsToSheet == false || insertedSheet != nil else {
            throw FeatureEvaluationError.invalidGraph("Trim to sheet trims the opening's sheet to an inserted sheet.")
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
        case guides
        case trimsToSheet
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.targetFeatureID, .boundarySeed, .insertedSheet, .guides, .trimsToSheet], in: decoder)
        targetFeatureID = try container.decode(FeatureID.self, forKey: .targetFeatureID)
        boundarySeed = try container.decode(StableSubshapeReference.self, forKey: .boundarySeed)
        insertedSheet = try container.decodeIfPresent(FeatureID.self, forKey: .insertedSheet)
        guides = try container.decodeIfPresent([CurveSectionReference].self, forKey: .guides) ?? []
        trimsToSheet = try container.decodeIfPresent(Bool.self, forKey: .trimsToSheet) ?? false
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(targetFeatureID, forKey: .targetFeatureID)
        try container.encode(boundarySeed, forKey: .boundarySeed)
        try container.encodeIfPresent(insertedSheet, forKey: .insertedSheet)
        if guides.isEmpty == false { try container.encode(guides, forKey: .guides) }
        if trimsToSheet { try container.encode(trimsToSheet, forKey: .trimsToSheet) }
    }
}
