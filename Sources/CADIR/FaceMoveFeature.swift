import CADCore

public struct FaceMoveFeature: Codable, Hashable, Sendable {
    public let target: FaceMoveTargetReference
    public let face: StableSubshapeReference
    public let translation: DirectMoveVector

    public init(
        target: FaceMoveTargetReference,
        face: StableSubshapeReference,
        translation: DirectMoveVector
    ) {
        self.target = target
        self.face = face
        self.translation = translation
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try target.validate()
        try face.validate()
        try translation.validate(tolerance: tolerance)
    }

    private enum CodingKeys: String, CodingKey {
        case target
        case face
        case translation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.target, .face, .translation], in: decoder)
        target = try container.decode(FaceMoveTargetReference.self, forKey: .target)
        face = try container.decode(StableSubshapeReference.self, forKey: .face)
        translation = try container.decode(DirectMoveVector.self, forKey: .translation)
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(face, forKey: .face)
        try container.encode(translation, forKey: .translation)
    }
}
