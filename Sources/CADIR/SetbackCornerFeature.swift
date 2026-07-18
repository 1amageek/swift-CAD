import CADCore

public struct SetbackCornerFeature: Codable, Hashable, Sendable {
    public let target: SetbackCornerTargetReference
    public let vertex: StableSubshapeReference
    public let radius: CADExpression

    public init(
        target: SetbackCornerTargetReference,
        vertex: StableSubshapeReference,
        radius: CADExpression
    ) {
        self.target = target
        self.vertex = vertex
        self.radius = radius
    }

    public func validate() throws {
        try target.validate()
        try vertex.validate()
        try radius.validateLiteralQuantities()
        guard case .vertex = vertex.geometrySignature else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                subshapeID: vertex.subshapeID,
                tolerance: nil,
                message: "Setback corner requires a stable vertex selection."
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case target
        case vertex
        case radius
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.target, .vertex, .radius], in: decoder)
        target = try container.decode(SetbackCornerTargetReference.self, forKey: .target)
        vertex = try container.decode(StableSubshapeReference.self, forKey: .vertex)
        radius = try container.decode(CADExpression.self, forKey: .radius)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(target, forKey: .target)
        try container.encode(vertex, forKey: .vertex)
        try container.encode(radius, forKey: .radius)
    }
}
