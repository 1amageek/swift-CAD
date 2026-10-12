public enum KernelPhase: String, Hashable, Sendable, CaseIterable {
    case validation
    case geometry
    case topology
    case classification
    case evaluation
    case exchange
}

#if !hasFeature(Embedded)
extension KernelPhase: Codable {}
#endif
