public enum KernelPhase: String, Codable, Hashable, Sendable, CaseIterable {
    case validation
    case geometry
    case topology
    case classification
    case evaluation
    case exchange
}
