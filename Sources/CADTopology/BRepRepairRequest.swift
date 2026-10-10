import CADCore

public struct BRepRepairRequest: Equatable, Sendable {
    public let actions: [BRepRepairAction]
    public let validationRequest: BRepValidationRequest

    public init(
        actions: [BRepRepairAction],
        validationRequest: BRepValidationRequest = .all
    ) {
        self.actions = actions
        self.validationRequest = validationRequest
    }

    #if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case actions
        case validationRequest
    }
    #endif

    #if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.actions, .validationRequest],
            in: decoder
        )
        self.init(
            actions: try container.decode([BRepRepairAction].self, forKey: .actions),
            validationRequest: try container.decode(
                BRepValidationRequest.self,
                forKey: .validationRequest
            )
        )
    }
    #endif

    #if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(actions, forKey: .actions)
        try container.encode(validationRequest, forKey: .validationRequest)
    }
    #endif

    public func validate(tolerance: ModelingTolerance) throws {
        try validationRequest.validate(tolerance: tolerance)
        guard actions.isEmpty == false,
              Set(actions).count == actions.count else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A B-rep repair request requires unique non-empty actions."
            )
        }
        let requestedScopes = Set(validationRequest.scopes)
        let requiredScopes = actions.reduce(into: Set<TopologyValidationScope>()) {
            $0.formUnion($1.requiredValidationScopes)
        }
        let missingScopes = requiredScopes.subtracting(requestedScopes)
        guard missingScopes.isEmpty else {
            throw KernelError(
                phase: .topology,
                code: .invalidInput,
                tolerance: tolerance,
                message: "B-rep repair validation is missing required scopes: \(missingScopes.map({ $0.rawValue }).sorted().joined(separator: ", "))."
            )
        }
    }
}

#if !hasFeature(Embedded)
extension BRepRepairRequest: Codable {}
#endif
