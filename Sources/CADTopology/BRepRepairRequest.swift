import CADCore

public struct BRepRepairRequest: Codable, Equatable, Sendable {
    public let actions: [BRepRepairAction]
    public let validationRequest: BRepValidationRequest

    public init(
        actions: [BRepRepairAction],
        validationRequest: BRepValidationRequest = .all
    ) {
        self.actions = actions
        self.validationRequest = validationRequest
    }

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
    }
}
