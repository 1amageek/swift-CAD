import CADCore

extension KernelCapabilities {
    static func feature(
        id: String,
        operation: String,
        topology: KernelTopologyContract,
        inputs: [String],
        outputs: [String],
        fixtures: [String],
        status: KernelCapabilityStatus = .partial,
        failureCodes: [KernelErrorCode] = [
            .invalidInput, .missingReference, .unsupportedCapability, .topologyFailure,
        ],
        additionalPublicAPIs: [String] = []
    ) -> KernelCapability {
        KernelCapability(
            id: id,
            operation: operation,
            status: status,
            topology: topology,
            acceptedInputs: inputs,
            exactOutputs: outputs,
            failureCodes: failureCodes,
            tolerance: .standard,
            publicAPIs: [
                "CADIR.FeatureRequest",
                "CADIR.CADCommand.appendFeature",
                "SwiftCAD.DocumentBuilder.\(operation)",
            ] + additionalPublicAPIs,
            testFixtures: fixtures
        )
    }
}
