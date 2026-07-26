import CADCore

public struct SurfaceOperationTargetReference: Codable, Hashable, Sendable {
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
        try face.validate()
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

    private enum CodingKeys: String, CodingKey {
        case featureID
        case face
    }

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

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(featureID, forKey: .featureID)
        try container.encode(face, forKey: .face)
    }
}
