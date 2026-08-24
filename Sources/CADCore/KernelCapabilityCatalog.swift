public struct KernelCapabilityCatalog: Codable, Equatable, Sendable {
    public let capabilities: [KernelCapability]

    public init(capabilities: [KernelCapability] = []) {
        self.capabilities = capabilities
    }

    public func validate() throws {
        var identifiers = Set<String>()
        for capability in capabilities {
            guard capability.id.isEmpty == false,
                  capability.operation.isEmpty == false,
                  identifiers.insert(capability.id).inserted else {
                throw KernelError(
                    phase: .validation,
                    code: .invalidInput,
                    tolerance: nil,
                    message: "Capability identifiers must be non-empty and unique."
                )
            }
            guard capability.failureCodes.isEmpty == false else {
                throw KernelError(
                    phase: .validation,
                    code: .invalidInput,
                    tolerance: nil,
                    message: "Capability \(capability.id) must declare typed failure codes."
                )
            }
            guard capability.status != .supported
                    || !capability.failureCodes.contains(.unsupportedCapability) else {
                throw KernelError(
                    phase: .validation,
                    code: .invalidInput,
                    tolerance: nil,
                    message: "Supported capability \(capability.id) must not declare an unsupported public-input path."
                )
            }
            guard capability.topology != .notApplicable
                || capability.id.hasPrefix("GEO-") else {
                throw KernelError(
                    phase: .validation,
                    code: .invalidInput,
                    tolerance: nil,
                    message: "Capability \(capability.id) must declare its supported topology."
                )
            }
            guard capability.acceptedInputs.isEmpty == false,
                  capability.exactOutputs.isEmpty == false,
                  capability.publicAPIs.isEmpty == false,
                  capability.testFixtures.isEmpty == false else {
                throw KernelError(
                    phase: .validation,
                    code: .invalidInput,
                    tolerance: nil,
                    message: "Capability \(capability.id) must bind inputs, exact outputs, public APIs, and test fixtures."
                )
            }
            try validateUnique(capability.acceptedInputs, field: "acceptedInputs", capabilityID: capability.id)
            try validateUnique(capability.exactOutputs, field: "exactOutputs", capabilityID: capability.id)
            try validateUnique(capability.publicAPIs, field: "publicAPIs", capabilityID: capability.id)
            try validateUnique(capability.testFixtures, field: "testFixtures", capabilityID: capability.id)
            try capability.tolerance.validate()
        }
    }

    public func capability(id: String) -> KernelCapability? {
        capabilities.first { $0.id == id }
    }

    public func capabilities(operation: String) -> [KernelCapability] {
        capabilities.filter { $0.operation == operation }
    }

    public func requireRegistered(operation: String) throws -> KernelCapability {
        guard let capability = capabilities(operation: operation).first else {
            throw KernelError(
                phase: .validation,
                code: .unsupportedCapability,
                tolerance: nil,
                message: "No capability is registered for operation \(operation)."
            )
        }
        return capability
    }

    public func requireExecutable(operation: String) throws -> KernelCapability {
        let capability = try requireRegistered(operation: operation)
        guard capability.status != .planned else {
            throw KernelError(
                phase: .validation,
                code: .unsupportedCapability,
                tolerance: nil,
                message: "Operation \(operation) does not have an executable capability envelope."
            )
        }
        return capability
    }

    public func requireSupported(operation: String) throws -> KernelCapability {
        let capability = try requireRegistered(operation: operation)
        guard capability.status == .supported else {
            throw KernelError(
                phase: .validation,
                code: .unsupportedCapability,
                tolerance: nil,
                message: "Operation \(operation) has not satisfied its complete support contract."
            )
        }
        return capability
    }

    private func validateUnique(
        _ values: [String],
        field: String,
        capabilityID: String
    ) throws {
        guard values.allSatisfy({ $0.isEmpty == false }),
              Set(values).count == values.count else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                tolerance: nil,
                message: "Capability \(capabilityID) contains empty or duplicate \(field) entries."
            )
        }
    }
}
