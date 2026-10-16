import CADCore
import CADGeometry

public struct SurfaceOperationTargetReference: Hashable, Sendable {
    public let featureID: FeatureID
    public let face: StableSubshapeReference

    public init(
        featureID: FeatureID,
        face: StableSubshapeReference
    ) {
        self.featureID = featureID
        self.face = face
    }

    public func validate() throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(using: &execution)
    }

    public func validate(using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try face.validate(using: &execution)
        guard case .face = face.geometrySignature else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                subshapeID: face.subshapeID,
                tolerance: nil,
                message: "Surface operation target must reference a face."
            )
        }
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case featureID
        case face
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.featureID, .face], in: decoder)
        featureID = try container.decode(FeatureID.self, forKey: .featureID)
        face = try container.decode(
            StableSubshapeReference.self,
            forKey: .face
        )
        try validate()
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(featureID, forKey: .featureID)
        try container.encode(face, forKey: .face)
    }
#endif
}

#if !hasFeature(Embedded)
extension SurfaceOperationTargetReference: Codable {}
#endif
