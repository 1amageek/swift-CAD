import CADCore

public struct StableSubshapeReference: Codable, Hashable, Sendable {
    public let subshapeID: SubshapeID
    public let geometrySignature: SubshapeGeometrySignature

    public init(
        subshapeID: SubshapeID,
        geometrySignature: SubshapeGeometrySignature
    ) {
        self.subshapeID = subshapeID
        self.geometrySignature = geometrySignature
    }

    public func validate() throws {
        guard subshapeID.isValid else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                subshapeID: subshapeID,
                tolerance: nil,
                message: "Stable subshape reference requires a valid identity."
            )
        }
        try geometrySignature.validate()
    }

    private enum CodingKeys: String, CodingKey {
        case subshapeID
        case geometrySignature
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.subshapeID, .geometrySignature], in: decoder)
        subshapeID = try container.decode(SubshapeID.self, forKey: .subshapeID)
        geometrySignature = try container.decode(
            SubshapeGeometrySignature.self,
            forKey: .geometrySignature
        )
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(subshapeID, forKey: .subshapeID)
        try container.encode(geometrySignature, forKey: .geometrySignature)
    }
}
