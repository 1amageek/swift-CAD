public enum KernelCapabilityStatus: String, Hashable, Sendable, CaseIterable {
    case planned
    case partial
    case supported
}

#if !hasFeature(Embedded)
extension KernelCapabilityStatus: Codable {}
#endif
