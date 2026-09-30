import CADCore

/// Unwrap Face: one face of a body flattened into a sheet of its own in the world's XY plane,
/// centred on the origin, on the face's own parameters (so it serves as a Deform reference). The
/// body is left as it is.
public struct FaceUnwrapFeature: Codable, Hashable, Sendable {
    public var target: PatternTargetReference
    public var face: StableSubshapeReference

    public init(target: PatternTargetReference, face: StableSubshapeReference) {
        self.target = target
        self.face = face
    }

    public func validate() throws {
        try target.validate()
        try face.validate()
    }

    private enum CodingKeys: String, CodingKey {
        case target, face
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.target, .face], in: decoder)
        target = try container.decode(PatternTargetReference.self, forKey: .target)
        face = try container.decode(StableSubshapeReference.self, forKey: .face)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(face, forKey: .face)
    }

    /// The inputs the feature reads: the body it copies the face from.
    public var inputs: [FeatureInput] {
        [FeatureInput(featureID: target.featureID, role: .target)]
    }
}
