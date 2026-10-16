import CADCore
import CADGeometry

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
        var execution = try BRepModel.originalValidationExecution()
        try validate(tolerance: tolerance, using: &execution)
    }

    public func validate(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        try tolerance.validate()
        guard !scopes.isEmpty else { throw invalidRequest(tolerance: tolerance) }
        for index in scopes.indices {
            try execution.consumeWork(1)
            for previous in 0..<index {
                try execution.consumeWork(1)
                if scopes[index] == scopes[previous] { throw invalidRequest(tolerance: tolerance) }
            }
        }
    }

    private func invalidRequest(tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .topology, code: .invalidInput, tolerance: tolerance,
            message: "A B-rep validation request requires unique non-empty scopes.")
    }

}

#if !hasFeature(Embedded)
extension BRepValidationRequest: Codable {}
#endif
