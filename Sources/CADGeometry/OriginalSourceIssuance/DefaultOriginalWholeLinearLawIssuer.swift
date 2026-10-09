#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

public struct DefaultOriginalWholeLinearLawIssuer<S: OriginalLinearSourceReading,F: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting>: OriginalWholeLinearLawIssuing {
    public typealias Source = S
    public typealias Field = F
    public init() {}
    public func issue<A: ExactScalarAdmission & ~Copyable>(source: borrowing OriginalSourceBinding<S>,field: borrowing F,
        limits: OriginalSourceIssuanceLimits,using a: inout A) throws(OriginalSourceIssuanceFailure) -> OriginalWholeLinearLawReceipt<S,F> {
        do {
            try a.checkpoint(); try source.require(limits)
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:6,of:F.Value.self))
            var origin: [F.Value] = [],direction: [F.Value] = []; origin.reserveCapacity(3); direction.reserveCapacity(3)
            var nonzero = false
            for axis in 0..<3 {
                try a.consumeWork(2)
                origin.append(try field.binary64(exactly:source.original.originCoordinate(in:axis),using:&a))
                let d = try field.binary64(exactly:source.original.directionCoordinate(in:axis),using:&a)
                if try field.sign(of:d,using:&a) != .zero { nonzero = true }; direction.append(d)
            }
            guard nonzero else { throw OriginalSourceIssuanceFailure.invalidSource }
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:1,of:OriginalWholeLinearLawReceipt<S,F>.self))
            let receipt = OriginalWholeLinearLawReceipt(source:copy source,field:copy field,origin:origin,direction:direction)
            try a.checkpoint(); return receipt
        } catch { throw .init(preserving:error) }
    }
}
