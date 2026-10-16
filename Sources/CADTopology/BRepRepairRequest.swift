import CADCore
import CADGeometry

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
        var execution = try BRepModel.originalValidationExecution()
        try validate(tolerance: tolerance, using: &execution)
    }

    public func validate(tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws {
        try validationRequest.validate(tolerance: tolerance, using: &execution)
        guard !actions.isEmpty else {
            throw KernelError(phase: .topology, code: .invalidInput, tolerance: tolerance,
                message: "A B-rep repair request requires unique non-empty actions.")
        }
        for index in actions.indices {
            try execution.consumeWork(1)
            for previous in 0..<index {
                try execution.consumeWork(1)
                guard actions[index] != actions[previous] else {
                    throw KernelError(phase: .topology, code: .invalidInput, tolerance: tolerance,
                        message: "A B-rep repair request requires unique non-empty actions.")
                }
            }
        }
        let scopes = try OriginalParameterQueryStorage.values(count: 7, using: &execution) { execution in
            TopologyValidationScope.allCases
        }
        var missing: [String] = []
        for scope in scopes {
            let required = try OriginalParameterQueryStorage.contains(actions, using: &execution) { action, execution in action.requires(scope) }
            let present = try OriginalParameterQueryStorage.contains(validationRequest.scopes, using: &execution) { selected, execution in selected == scope }
            if required && !present { try OriginalParameterQueryStorage.append(scope.rawValue, to: &missing, using: &execution) }
        }
        guard missing.isEmpty else {
            try OriginalParameterQueryStorage.sort(&missing, using: &execution) { first, second, execution in
                try execution.consumeWork(first.utf8.count)
                try execution.consumeWork(second.utf8.count)
                return first < second
            }
            let prefix = "B-rep repair validation is missing required scopes: "
            var bytes = prefix.utf8.count
            for (index, value) in missing.enumerated() {
                let increment = value.utf8.count.addingReportingOverflow(index == 0 ? 0 : 2)
                let total = bytes.addingReportingOverflow(increment.partialValue)
                guard !increment.overflow, !total.overflow else { throw ExactScalarFailure.countOverflow }
                bytes = total.partialValue
            }
            let total = bytes.addingReportingOverflow(1)
            guard !total.overflow else { throw ExactScalarFailure.countOverflow }
            try execution.retainStorage(bytes: total.partialValue)
            try execution.consumeWork(total.partialValue)
            var message = String()
            message.reserveCapacity(total.partialValue)
            message.append(prefix)
            for (index, value) in missing.enumerated() {
                if index > 0 { message.append(", ") }
                message.append(value)
            }
            message.append(".")
            throw KernelError(phase: .topology, code: .invalidInput, tolerance: tolerance, message: message)
        }
    }

}

#if !hasFeature(Embedded)
extension BRepRepairRequest: Codable {}
#endif
