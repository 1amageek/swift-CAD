public enum KernelErrorCode: String, Codable, Hashable, Sendable, CaseIterable {
    case invalidInput
    case missingReference
    case unsupportedCapability
    case ambiguousSelection
    case intersectionFailure
    case classificationFailure
    case topologyFailure
    case nonManifoldResult
    case resourceLimitExceeded
}
