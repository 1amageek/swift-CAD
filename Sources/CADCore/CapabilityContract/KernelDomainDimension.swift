/// The aspect of an operation's input or result affected by a known condition.
public enum KernelDomainDimension: String, CaseIterable, Hashable, Sendable {
    case supportSurface
    case boundaryCurve
    case connection
    case degeneracy
    case parameterization
    case topology
    case transformation
    case geometricFidelity
    case representation
}

#if !hasFeature(Embedded)
extension KernelDomainDimension: Codable {}
#endif
