#if L2_ISOLATED_VERIFICATION
import L0
import L1
import DI0
#endif

/// Lossless wrapper keeps DI0 out of the isolated root facade's public member types.
/// The shared checked scalar interval is the only retained storage and validator.
public struct ExactRealRootInterval<Value: Sendable>: Sendable {
    let domainInterval: ExactParameterInterval<Value>
    public var lower: ExactRealRootBound<Value> { .init(domainInterval.lower) }
    public var upper: ExactRealRootBound<Value> { .init(domainInterval.upper) }
    public var includesLower: Bool { domainInterval.includesLower }
    public var includesUpper: Bool { domainInterval.includesUpper }
    public var isEmpty: Bool { domainInterval.isEmpty }
    public var depth: ExactScalarDepth { domainInterval.depth }
    init(retaining interval: ExactParameterInterval<Value>) { domainInterval = interval }
}
