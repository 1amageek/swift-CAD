#if EXACT_DOMAIN_ISOLATED_VERIFICATION
import L0
#endif

public struct ExactParameterProduct<F: ExactScalarOrdering>: Sendable {
    let context: ExactParameterDomainContext<F>
    let storage: [ExactParameterSet<F>]
    public let depth: ExactScalarDepth
    public var axes: ArraySlice<ExactParameterSet<F>> { storage[...] }
    public var arity: Int { storage.count }
    public let isEmpty: Bool
    init(context: ExactParameterDomainContext<F>, storage: [ExactParameterSet<F>], depth: ExactScalarDepth, isEmpty: Bool) {
        self.context = context; self.storage = storage; self.depth = depth; self.isEmpty = isEmpty
    }
}
