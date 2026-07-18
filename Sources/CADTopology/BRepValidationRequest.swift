import CADCore

public struct BRepValidationRequest: Codable, Equatable, Sendable {
    public let scopes: [TopologyValidationScope]

    public init(scopes: [TopologyValidationScope]) {
        self.scopes = scopes
    }

    public static let all = BRepValidationRequest(scopes: TopologyValidationScope.allCases)

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
