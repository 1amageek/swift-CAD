/// Declared inputs and known limitations of one registered operation.
/// This value documents coverage; it is not a per-shape admission certificate.
public struct KernelCapabilityDomain: Equatable, Sendable {
    public let capability: KernelCapability
    public let knownLimitations: [KernelDomainLimitation]

    public init(capability: KernelCapability, knownLimitations: [KernelDomainLimitation]) {
        self.capability = capability
        self.knownLimitations = knownLimitations
    }

    public func limitations(affecting dimension: KernelDomainDimension) -> [KernelDomainLimitation] {
        knownLimitations.filter { $0.dimensions.contains(dimension) }
    }
}

#if !hasFeature(Embedded)
extension KernelCapabilityDomain: Codable {}
#endif
