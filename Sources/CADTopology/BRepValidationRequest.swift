import CADCore

public struct BRepValidationRequest: Equatable, Sendable {
    public let scopes: [TopologyValidationScope]

    public init(scopes: [TopologyValidationScope]) {
        self.scopes = scopes
    }

    public static let all = BRepValidationRequest(scopes: TopologyValidationScope.allCases)

    #if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case scopes
    }
    #endif

    #if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.scopes], in: decoder)
        self.init(scopes: try container.decode([TopologyValidationScope].self, forKey: .scopes))
    }
    #endif

    #if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(scopes, forKey: .scopes)
    }
    #endif

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        guard scopes.isEmpty == false,
              Set(scopes).count == scopes.count else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A B-rep validation request requires unique non-empty scopes."
            )
        }
    }
}

#if !hasFeature(Embedded)
extension BRepValidationRequest: Codable {}
#endif
