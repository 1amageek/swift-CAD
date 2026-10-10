#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Sealed immutable coefficient owner; alone it does not identify a source.
public final class OriginalSourceAffineAction<F: ExactScalarArithmetic & ExactScalarOrdering>: Sendable {
    public let field: F
    public let evidenceDepth: ExactScalarDepth
    private let coefficients: [F.Value]
    init(field: F,coefficients: [F.Value],depth: ExactScalarDepth) {
        self.field = field;self.coefficients = coefficients;self.evidenceDepth = depth
    }
    public func admitted<A: ExactScalarAdmission & ~Copyable>(using a: inout A) throws(ExactScalarFailure) {
        try a.checkpoint();try a.admitDepth(value:evidenceDepth.value,coefficient:evidenceDepth.coefficient)
        for value in coefficients { try a.consumeWork(1);_ = try field.sign(of:value,using:&a) }
        try a.checkpoint()
    }
    public func coefficient<A: ExactScalarAdmission & ~Copyable>(row: Int,column: Int,using a: inout A) throws(ExactScalarFailure) -> F.Value {
        try a.checkpoint();try a.consumeWork(1)
        guard (0..<3).contains(row),(0..<4).contains(column) else { throw .invalidSource }
        let value = coefficients[row*4+column]
        try a.admitDepth(value:evidenceDepth.value,coefficient:evidenceDepth.coefficient)
        _ = try field.sign(of:value,using:&a)
        try a.checkpoint();return value
    }
}
