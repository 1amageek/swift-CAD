import CADCore
import CADTopology

/// Face outlines offset (Offset Face Loop): the outer loop of each chosen face is offset by
/// `distance` into the face, over the faces around it, or both ways, as `side` says, with corners
/// joined as `gapFill` says, and imprinted. Individually,
/// each face's own outline is offset; combined, the outline of the faces together is, so edges
/// between two chosen faces are not.
public struct FaceLoopOffsetFeature: Codable, Hashable, Sendable {
    public var target: PatternTargetReference
    public var faces: [StableSubshapeReference]
    public var distance: CADExpression
    public var side: FaceLoopOffsetSide
    public var gapFill: OffsetGapFill
    public var isIndividual: Bool

    public init(
        target: PatternTargetReference,
        faces: [StableSubshapeReference],
        distance: CADExpression,
        side: FaceLoopOffsetSide = .inward,
        gapFill: OffsetGapFill = .round,
        isIndividual: Bool = true
    ) {
        self.target = target
        self.faces = faces
        self.distance = distance
        self.side = side
        self.gapFill = gapFill
        self.isIndividual = isIndividual
    }

    public func validate() throws {
        try target.validate()
        guard faces.isEmpty == false else {
            throw FeatureEvaluationError.invalidGraph("Offset Face Loop needs at least one face.")
        }
        for face in faces { try face.validate() }
        guard Set(faces).count == faces.count else {
            throw FeatureEvaluationError.invalidGraph("Offset Face Loop's faces must be distinct.")
        }
        try distance.validateLiteralQuantities()
    }

    private enum CodingKeys: String, CodingKey {
        case target, faces, distance, side, gapFill, isIndividual
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.target, .faces, .distance, .side, .gapFill, .isIndividual], in: decoder)
        target = try container.decode(PatternTargetReference.self, forKey: .target)
        faces = try container.decode([StableSubshapeReference].self, forKey: .faces)
        distance = try container.decode(CADExpression.self, forKey: .distance)
        side = try container.decode(FaceLoopOffsetSide.self, forKey: .side)
        gapFill = try container.decode(OffsetGapFill.self, forKey: .gapFill)
        isIndividual = try container.decode(Bool.self, forKey: .isIndividual)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(faces, forKey: .faces)
        try container.encode(distance, forKey: .distance)
        try container.encode(side, forKey: .side)
        try container.encode(gapFill, forKey: .gapFill)
        try container.encode(isIndividual, forKey: .isIndividual)
    }
}

/// Where Offset Face Loop offsets a face's outline.
public enum FaceLoopOffsetSide: String, Codable, Hashable, Sendable {
    /// Into the face.
    case inward
    /// Over the faces around it.
    case outward
    /// Both ways, the same distance.
    case symmetric
}
