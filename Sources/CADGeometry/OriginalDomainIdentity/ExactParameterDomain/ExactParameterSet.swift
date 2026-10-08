#if EXACT_DOMAIN_ISOLATED_VERIFICATION
import L0
#endif

public struct ExactParameterSet<F: ExactScalarOrdering>: Sendable {
    let context: ExactParameterDomainContext<F>
    let storage: [ExactParameterInterval<F.Value>]
    public let depth: ExactScalarDepth
    /// COW-backed view retains endpoints; obtaining it does not materialize an array.
    public var intervals: ArraySlice<ExactParameterInterval<F.Value>> { storage[...] }
    public var isEmpty: Bool { storage.isEmpty }
    public var intervalCount: Int { storage.count }
    init(context: ExactParameterDomainContext<F>, storage: [ExactParameterInterval<F.Value>], depth: ExactScalarDepth) {
        self.context = context; self.storage = storage; self.depth = depth
    }
}
