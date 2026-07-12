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
                    message: "Capability identifiers must be non-empty and unique."
                )
            }
            guard capability.failureCodes.isEmpty == false else {
                throw KernelError(
                    phase: .validation,
                    code: .invalidInput,
                    message: "Capability \(capability.id) must declare typed failure codes."
                )
            }
            try capability.tolerance.validate()
        }
    }

    public func capability(id: String) -> KernelCapability? {
        capabilities.first { $0.id == id }
    }

    public func capabilities(operation: String) -> [KernelCapability] {
        capabilities.filter { $0.operation == operation }
    }

    public func require(operation: String) throws -> KernelCapability {
        let genericOperations: Set<String> = [
            "sketch", "revolve", "sweep", "loft", "polySpline", "bSplineSurface",
            "faceLoopOffset", "edgeOffset", "faceKnife", "faceDelete", "faceDraft",
            "bridgeCurve", "curveEdit", "curveOffset", "curveTrim",
        ]
        guard let capability = capabilities(operation: operation).first
            ?? (genericOperations.contains(operation) ? capabilities(operation: "featureOperation").first : nil) else {
            throw KernelError(
                phase: .validation,
                code: .unsupportedCapability,
                message: "No capability is registered for operation \(operation)."
            )
        }
        guard capability.status != .planned else {
            throw KernelError(
                phase: .validation,
                code: .unsupportedCapability,
                message: "Operation \(operation) is not available in the current kernel."
            )
        }
        return capability
    }
}
