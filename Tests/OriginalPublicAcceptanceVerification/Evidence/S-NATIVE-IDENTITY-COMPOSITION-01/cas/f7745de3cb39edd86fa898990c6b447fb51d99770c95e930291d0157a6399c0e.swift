#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Exact original O+D*t, valid on the entire real authored coordinate.
public struct OriginalWholeLinearLawReceipt<S: OriginalLinearSourceReading,F: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: Sendable {
    public let source: OriginalSourceBinding<S>
    public let field: F
    public let origin: [F.Value]
    public let direction: [F.Value]
    init(source: OriginalSourceBinding<S>,field: F,origin: [F.Value],direction: [F.Value]) {
        self.source = source; self.field = field; self.origin = origin; self.direction = direction
    }
    public func position<A: ExactScalarAdmission & ~Copyable>(at t: F.Value,limits: OriginalSourceIssuanceLimits,
        using a: inout A) throws(OriginalSourceIssuanceFailure) -> [F.Value] {
        do {
            try a.checkpoint(); try source.require(limits)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:3,of:F.Value.self))
            var result: [F.Value] = []; result.reserveCapacity(3)
            for i in 0..<3 { try a.consumeWork(1); result.append(try field.adding(origin[i],field.multiplying(direction[i],t,using:&a),using:&a)) }
            try a.checkpoint(); return result
        } catch { throw .init(preserving:error) }
    }
}
