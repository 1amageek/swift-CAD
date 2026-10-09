#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// An exact conjunct in the source graph, independent of any solver instruction set.
public struct OriginalParametricGraphCondition<F:ExactScalarArithmetic & ExactScalarOrdering>:Sendable {
    public enum Relation:Sendable { case equal,notEqual,positive,nonnegative }
    public let polynomial:ExactPolynomial<F>
    public let relation:Relation
    init(_ polynomial:ExactPolynomial<F>,_ relation:Relation) { self.polynomial=polynomial;self.relation=relation }
    func accepts(_ sign:ExactSign)->Bool {
        switch relation { case .equal:return sign == .zero
        case .notEqual:return sign != .zero
        case .positive:return sign == .positive
        case .nonnegative:return sign != .negative }
    }
}
