/// The cause family used to interpret a kernel failure across operation boundaries.
/// A category describes a reported failure; it does not establish geometric validity.
public enum KernelFailureCategory: String, Hashable, Sendable, CaseIterable {
    case invalidInput
    case missingReference
    case unsupportedDomain
    case ambiguity
    case constraintFailure
    case singularity
    case numericalIndeterminacy
    case nonDiscreteResult
    case emptyResult
    case invalidTopology
    case resourceExhaustion
    case cancelled
    case ioFailure
    case dependencyUnavailable
    case externalFailure
    case securityRefusal
    case unclassified
}

#if !hasFeature(Embedded)
extension KernelFailureCategory: Codable {}
#endif
