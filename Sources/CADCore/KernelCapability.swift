public struct KernelCapability: Codable, Equatable, Hashable, Sendable {
    public let id: String
    public let operation: String
    public let status: KernelCapabilityStatus
    public let topology: KernelTopologyContract
    public let acceptedInputs: [String]
    public let exactOutputs: [String]
    public let failureCodes: [KernelErrorCode]
    public let tolerance: ModelingTolerance
    public let publicAPIs: [String]
    public let testFixtures: [String]

    public init(
        id: String,
        operation: String,
        status: KernelCapabilityStatus,
        topology: KernelTopologyContract,
        acceptedInputs: [String],
        exactOutputs: [String],
        failureCodes: [KernelErrorCode],
        tolerance: ModelingTolerance,
        publicAPIs: [String],
        testFixtures: [String]
    ) {
        self.id = id
        self.operation = operation
        self.status = status
        self.topology = topology
        self.acceptedInputs = acceptedInputs
        self.exactOutputs = exactOutputs
        self.failureCodes = failureCodes
        self.tolerance = tolerance
        self.publicAPIs = publicAPIs
        self.testFixtures = testFixtures
    }
}
