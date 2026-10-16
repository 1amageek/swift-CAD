import CADCore
import CADGeometry

public struct StableSubshapeReference: Hashable, Sendable {
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
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(using: &execution)
    }

    public func validate(using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        guard subshapeID.isValid else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                subshapeID: subshapeID,
                tolerance: nil,
                message: "Stable subshape reference requires a valid identity."
            )
        }
        try geometrySignature.validate(using: &execution)
    }

    /// Pays for the stored equality/hash payload without validating or changing it.
    func chargeStructuralComparison(using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        for _ in subshapeID.role.utf8 { try execution.consumeWork(1) }
        try geometrySignature.chargeStructuralComparison(using: &execution)
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case subshapeID
        case geometrySignature
    }
#endif

#if !hasFeature(Embedded)
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
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(subshapeID, forKey: .subshapeID)
        try container.encode(geometrySignature, forKey: .geometrySignature)
    }
#endif
}

#if !hasFeature(Embedded)
extension StableSubshapeReference: Codable {}
#endif
