import CADCore
import CADTopology

public struct FaceKnifeFeature: Codable, Hashable, Sendable {
    public var target: FaceKnifeTargetReference
    public var face: StableSubshapeReference
    public var loop: [Point3D]

    public init(
        target: FaceKnifeTargetReference,
        face: StableSubshapeReference,
        loop: [Point3D]
    ) {
        self.target = target
        self.face = face
        self.loop = loop
    }

    public func validate() throws {
        try target.validate()
        try face.validate()
        guard loop.count >= 3 else {
            throw FeatureEvaluationError.invalidGraph("Face Knife requires at least three loop points.")
        }
        for point in loop {
            try point.validate()
        }
    }

    private enum CodingKeys: String, CodingKey {
        case target
        case face
        case loop
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.target, .face, .loop], in: decoder)
        target = try container.decode(FaceKnifeTargetReference.self, forKey: .target)
        face = try container.decode(StableSubshapeReference.self, forKey: .face)
        loop = try container.decode([Point3D].self, forKey: .loop)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(face, forKey: .face)
        try container.encode(loop, forKey: .loop)
    }
}

public struct FaceKnifeTargetReference: Codable, Hashable, Sendable {
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
