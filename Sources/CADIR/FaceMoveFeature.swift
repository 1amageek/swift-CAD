import CADCore
import CADGeometry

public struct FaceMoveFeature: Hashable, Sendable {
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
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(tolerance: tolerance, using: &execution)
    }

    public func validate(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try target.validate()
        try face.validate(using: &execution)
        try translation.validate(tolerance: tolerance, using: &execution)

        try execution.checkpoint()
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case target
        case face
        case translation
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.target, .face, .translation], in: decoder)
        target = try container.decode(FaceMoveTargetReference.self, forKey: .target)
        face = try container.decode(StableSubshapeReference.self, forKey: .face)
        translation = try container.decode(DirectMoveVector.self, forKey: .translation)
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: CADIRPersistenceValidation.tolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(face, forKey: .face)
        try container.encode(translation, forKey: .translation)
    }
#endif
}

#if !hasFeature(Embedded)
extension FaceMoveFeature: Codable {}
#endif
