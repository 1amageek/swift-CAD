import CADCore
import CADTopology

public struct FaceDeleteFeature: Codable, Hashable, Sendable {
    public var target: FaceDeleteTargetReference
    public var faces: [StableSubshapeReference]

    public init(
        target: FaceDeleteTargetReference,
        faces: [StableSubshapeReference]
    ) {
        self.target = target
        self.faces = faces
    }

    public func validate() throws {
        try target.validate()
        guard faces.isEmpty == false else {
            throw FeatureEvaluationError.invalidGraph("Face Delete requires at least one face target.")
        }
        var seen = Set<StableSubshapeReference>()
        for face in faces {
            try face.validate()
            guard seen.insert(face).inserted else {
                throw FeatureEvaluationError.invalidGraph("Face Delete targets must be unique.")
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case target
        case faces
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.target, .faces], in: decoder)
        target = try container.decode(FaceDeleteTargetReference.self, forKey: .target)
        faces = try container.decode([StableSubshapeReference].self, forKey: .faces)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(faces, forKey: .faces)
    }
}

public struct FaceDeleteTargetReference: Codable, Hashable, Sendable {
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
