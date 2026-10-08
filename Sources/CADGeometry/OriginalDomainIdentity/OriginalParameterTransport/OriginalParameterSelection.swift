#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

public struct OriginalParameterSelection<Source: Sendable, F: ExactScalarArithmetic & ExactScalarOrdering>: Sendable {
    public let frame: OriginalParameterFrame<Source,F>
    let storage: [ExactParameterSet<F>]
    public var axes: ArraySlice<ExactParameterSet<F>> { storage[...] }
    public var arity: Int { storage.count }
    public let isEmpty: Bool
    init<A: ExactScalarAdmission & ~Copyable>(frame: OriginalParameterFrame<Source,F>,
        axes: [ExactParameterSet<F>], using admission: inout A) throws(ExactScalarFailure) {
        var empty = false
        for axis in axes { try admission.consumeWork(1); empty = empty || axis.isEmpty }
        self.frame = frame; storage = axes; isEmpty = empty
    }
}
