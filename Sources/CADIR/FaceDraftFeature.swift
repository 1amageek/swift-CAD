import CADCore
import CADTopology

public struct FaceDraftFeature: Codable, Hashable, Sendable {
    public var target: FaceDraftTargetReference
    public var faces: [StableSubshapeReference]
    public var neutralFace: StableSubshapeReference
    public var angle: CADExpression

    public init(
        target: FaceDraftTargetReference,
        faces: [StableSubshapeReference],
        neutralFace: StableSubshapeReference,
        angle: CADExpression
    ) {
        self.target = target
        self.faces = faces
        self.neutralFace = neutralFace
        self.angle = angle
    }

    public func validate() throws {
        try target.validate()
        guard faces.isEmpty == false else {
            throw FeatureEvaluationError.invalidGraph("Face Draft requires at least one face target.")
        }
        var seen = Set<StableSubshapeReference>()
        for face in faces {
            try face.validate()
            guard seen.insert(face).inserted else {
                throw FeatureEvaluationError.invalidGraph("Face Draft targets must be unique.")
            }
        }
        try neutralFace.validate()
        guard seen.contains(neutralFace) == false else {
            throw FeatureEvaluationError.invalidGraph("Face Draft neutral face must be distinct from target faces.")
        }
        try angle.validateLiteralQuantities()
    }

    private enum CodingKeys: String, CodingKey {
        case target
        case faces
        case neutralFace
        case angle
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.target, .faces, .neutralFace, .angle],
            in: decoder
        )
        target = try container.decode(FaceDraftTargetReference.self, forKey: .target)
        faces = try container.decode([StableSubshapeReference].self, forKey: .faces)
        neutralFace = try container.decode(StableSubshapeReference.self, forKey: .neutralFace)
        angle = try container.decode(CADExpression.self, forKey: .angle)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(faces, forKey: .faces)
        try container.encode(neutralFace, forKey: .neutralFace)
        try container.encode(angle, forKey: .angle)
    }
}

public struct FaceDraftTargetReference: Codable, Hashable, Sendable {
    public var featureID: FeatureID

    public init(featureID: FeatureID) {
        self.featureID = featureID
    }

    public func validate() throws {}

    private enum CodingKeys: String, CodingKey {
        case featureID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.featureID], in: decoder)
        featureID = try container.decode(FeatureID.self, forKey: .featureID)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(featureID, forKey: .featureID)
    }
}
